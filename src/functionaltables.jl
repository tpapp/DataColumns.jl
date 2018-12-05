export FunctionalTable, columns, ordering, rename

"""
$(TYPEDEF)

# Internal notes

- Use accessors `length`, `colums`, and `ordering` to access the fields, property accessors
  are forwarded to `columns`.

- The only inner constructor is the one where both the length and the ordering is trusted
  (and thus unchecked). Outer constructors should first wrap the ordering rule, then
  compute/verify length.
"""
struct FunctionalTable{C <: NamedTuple, O <: TableOrdering}
    len::Int
    columns::C
    ordering::O
    function FunctionalTable(trust_length::TrustLength, columns::C, ordering_rule::R
                             ) where {C <: NamedTuple, R <: TrustOrdering}
        @unpack ordering = ordering_rule
        checkvalidkeys(orderkey.(ordering), keys(columns))
        new{C, typeof(ordering)}(trust_length.len, columns, ordering)
    end
end

####
#### Outer constructors from FunctionalTable or NamedTuple
####

function FunctionalTable(ft::FunctionalTable,
                         ordering_rule::OrderingRule{K} = VerifyOrdering()) where K
    new_ordering = ordering_rule.ordering
    K ≡ :trust && return FunctionalTable(TrustLength(length(ft)), columns(ft), ordering_rule)
    rule = is_prefix(new_ordering, ordering(ft)) ? TrustOrdering(new_ordering) : ordering_rule
    FunctionalTable(TrustLength(length(ft)), columns(ft), rule)
end

function FunctionalTable(len::TrustLength, columns::NamedTuple,
                         ordering_rule::VerifyOrdering = VerifyOrdering(()))
    ft = FunctionalTable(len, columns, TrustOrdering(ordering_rule))
    @argcheck issorted(ft; lt = (a, b) -> isless_ordering(ordering(ft), a, b))
    ft
end

function FunctionalTable(len::TrustLength, columns::NamedTuple, ::TryOrdering)
    error("not implemented yet, maybe open an issue?")
end

function FunctionalTable(len::Integer, columns::NamedTuple, ordering_rule::OrderingRule)
    @argcheck all(column -> length(column) == len, values(columns))
    FunctionalTable(TrustLength(len), columns, ordering_rule)
end

function FunctionalTable(columns::NamedTuple, ordering_rule::OrderingRule)
    @argcheck !isempty(columns) "At least one column is needed to determine length."
    len = length(first(columns))
    @argcheck all(column -> length(column) == len, Base.tail(values(columns)))
    FunctionalTable(TrustLength(len), columns, ordering_rule)
end

FunctionalTable(len::Integer) =
    FunctionalTable(TrustLength(len), NamedTuple(), TrustOrdering())

####
#### accessors for fields and property overloading
####

"""
$(SIGNATURES)

Return the columns in a `NamedTuple`.

Each column is an iterable, but not necessarily an `<: AbstractVector`.

!!! note
    **Never mutate columns obtained by this method**, as that will violate invariants
    assumed by the implementation. Use `map(collect, columns(ft))` or similar to obtain
    mutable vectors.
"""
columns(ft::FunctionalTable) = getfield(ft, :columns)

"""
$(SIGNATURES)

Return the ordering of the table, which is a tuple of `ColumnOrdering` objects.
"""
ordering(ft::FunctionalTable) = getfield(ft, :ordering)

Base.propertynames(ft::FunctionalTable) = propertynames(columns(ft))

Base.getproperty(ft::FunctionalTable, key::Symbol) = getproperty(columns(ft), key)

Base.keys(ft::FunctionalTable) = keys(columns(ft))

Base.pairs(ft::FunctionalTable) = pairs(columns(ft))

Base.values(ft::FunctionalTable) = values(columns(ft))

####
#### Iteration interface and constructor
####

Base.IteratorSize(::FunctionalTable) = Base.HasLength()

Base.length(ft::FunctionalTable) = getfield(ft, :len)

Base.IteratorEltype(::FunctionalTable) = Base.HasEltype()

Base.eltype(ft::FunctionalTable) =
    NamedTuple{keys(ft), Tuple{map(eltype, values(ft))...}}

"""
$(SIGNATURES)

Create a `FunctionalTable` from an iterable that returns `NamedTuple`s.

Returned values need to have the same names (but not necessarily types).

`ordering_rule` specifies sorting. The `VerifyOrdering` (default), `TrustOrdering`, and
`TryOrdering`  constructors take a tuple of a tuple of `:key` or `:key => reverse` elements.

`cfg` determines sink configuration for collecting elements of the columns, see
[`SinkConfig`](@ref).
"""
function FunctionalTable(itr, ordering_rule::OrderingRule = TrustOrdering();
                         cfg::SinkConfig = SINKCONFIG)
    FunctionalTable(collect_columns(cfg, itr, ordering_rule)...)
end

function Base.iterate(ft::FunctionalTable, states...)
    ys = map(iterate, columns(ft), states...)
    any(isequal(nothing), ys) && return nothing
    map(first, ys), map(last, ys)
end

"""
Shows this many values from each column in a `FunctionalTable`.
"""
const SHOWROWS = 5

function _showcolcontents(io::IO, itr)
    elts = collect(Iterators.take(itr, SHOWROWS + 1))
    print(io, eltype(itr), "[")
    for (i, elt) in enumerate(elts)
        i > 1 && print(io, ", ")
        i > SHOWROWS ? print(io, "…") : show(io, elt)
    end
    print(io, "]")
end

function Base.show(io::IO, ft::FunctionalTable)
    print(io, "FunctionalTable of $(length(ft)) rows, ", ordering_repr(ordering(ft)))
    ioc = IOContext(io, :compact => true)
    for (key, col) in pairs(columns(ft))
        println(ioc)
        print(ioc, "    ", key, " = ")
        _showcolcontents(ioc, col)
    end
end

"""
$(SIGNATURES)

With a tuple of symbols returns `FunctionalTable` with a subset of the columns.

With a single symbol, return that column (an iterable).

`[drop = spec]` will keep *all but* the given columns, where `spec` is a `Tuple` of
`Symbol`s.

# Example

```julia
ft[(:a, :b)]
ft[:a]
ft[drop = (:a, :b)]
 ```
"""
function Base.getindex(ft::FunctionalTable, keep::Keys)
    FunctionalTable(TrustLength(length(ft)), NamedTuple{keep}(columns(ft)),
                    TrustOrdering(select_ordering(ordering(ft), keep)))
end

Base.getindex(ft::FunctionalTable, key::Symbol) = columns(ft)[key]

Base.getindex(ft::FunctionalTable; drop::Keys) = getindex(ft, dropkeys(keys(ft), drop))

"""
$(SIGNATURES)

Rename the columns of a `FunctionalTable`. `changes`, which is an `AbstractDict` or anything
that supports `pairs` and can be collected into one, maps column names to new names.

When `strict` (the default), the keys of the dictionary are checked to be a subset of
existing keys, otherwise superfluous keys are ignored.

# Example

```julia
rename(ft, Dict(:a => :a2, :b => :μ))
rename(ft, (a = :a2, b = :μ))   # same, using NamedTuple
```
"""
function rename(ft::FunctionalTable, changes::AbstractDict{Symbol, Symbol}; strict = true)
    strict && @argcheck keys(changes) ⊆ keys(columns(ft))
    change(key) = changes[key]
    newkeys = map(change, keys(columns(ft)))
    newordering = map(o -> ColumnOrdering{change(orderkey(o)), orderrev(o)}(), ordering(ft))
    FunctionalTable(TrustLength(length(ft)), NamedTuple{newkeys}(values(columns(ft))), TrustOrdering(newordering))
end

rename(ft::FunctionalTable, @nospecialize changes; strict = true) =
    rename(ft, Dict(pairs(changes)); strict = strict)

"""
$(SIGNATURES)

Rename the columns of a `FunctionalTable` using a function that maps symbols to symbols.

# Example

```julia
rename(key -> Symbol(String(key) * "-mean"), ft) # add "-mean" to each name
```
"""
rename(f, ft::FunctionalTable) =
    rename(ft, Dict(k => f(k) for k in keys(ft)); strict = false)

"""
$(SIGNATURES)

Convenience wrapper for `rename(::FunctionalTable, ::AbstractDict)` which constructs the
change dictionary from pairs. Non-existent keys always error.

```julia
rename(ft, :a => :a2, :b => :μ)
```
"""
rename(ft::FunctionalTable, pairs::Pair{Symbol, Symbol}...) =
    rename(ft, Dict(pairs); strict = true)

"""
$(SIGNATURES)

Merge two `FunctionalTable`s.

When `replace == true`, columns in the first one are replaced by second one, otherwise an
error is thrown if column names overlap.

The second table can be specified as a `NamedTuple` of columns.
"""
function Base.merge(a::FunctionalTable, b::FunctionalTable; replace = false)
    @argcheck length(a) == length(b)
    if !replace
        dup = tuple((keys(a) ∩ keys(b))...)
        @argcheck isempty(dup) "Duplicate columns $(dup). Use `replace = true`."
    end
    FunctionalTable(TrustLength(length(a)), merge(columns(a), columns(b)),
                    TrustOrdering(merge_ordering(ordering(a), keys(b))))
end

"""
$(SIGNATURES)
"""
Base.map(f, ft::FunctionalTable; cfg = SINKCONFIG) = FunctionalTable(imap(f, ft); cfg = cfg)

"""
$(SIGNATURES)

Map `ft` using `f` by rows, then `merge` the two. See [`map(f, ::FunctionalTable)`](@ref).

`cfg` is passed to `map`, `replace` governs replacement of overlapping columns in `merge`.
"""
function Base.merge(f, ft::FunctionalTable; cfg = SINKCONFIG, replace = false)
    merge(ft, map(f, ft; cfg = cfg); replace = replace)
end

Base.merge(ft::FunctionalTable, newcolumns::NamedTuple; replace = false) =
    merge(ft, FunctionalTable(newcolumns); replace = replace)

Base.filter(f, ft::FunctionalTable; cfg = SINKCONFIG) =
    FunctionalTable(Iterators.filter(f, ft), TrustOrdering(ordering(ft)))

"""
$(SIGNATURES)

A `FunctionalTable` of the first `n` rows.

Useful for previews and data exploration.
"""
function Base.first(ft::FunctionalTable, n::Integer; cfg::SinkConfig = SINKVECTORS)
    FunctionalTable(TrustLength(min(length(ft), n)),
                    map(col -> collect_column(cfg, Iterators.take(col, n)), columns(ft)),
                    TrustOrdering(ordering(ft)))
end
