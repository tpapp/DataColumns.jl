"""
Type for keys, used internally.
"""
const Keys = Tuple{Vararg{Symbol}}

"""
$(SIGNATURES)

Test that `keys` are valid keys of the second argument.
"""
validkeys(keys::Keys, ftkeys::Keys) = keys ⊆ ftkeys

"""
$(SIGNATURES)

Check that `keys` are valid for `obj`.

!!! NOTE
    Extend `validkeys` for other `obj`, not this method.
"""
function checkvalidkeys(keys::Keys, obj)
    @argcheck validkeys(keys, obj) "Some keys $(keys) which are not valid for this object."
end

"""
$(SIGNATURES)

Check that `drop ⊆ ftkeys`, then return `ftkeys ∖ drop`.
"""
function dropkeys(ftkeys::Keys, drop::Keys)
    checkvalidkeys(drop, ftkeys)
    tuple(setdiff(ftkeys, drop)...)
end

"""
$(SIGNATURES)

Test if a collection of element type `T` can contain a new element `elt` without *any* loss
of precision.
"""
@inline cancontain(T, elt::S) where {S} = S <: T || T ≡ promote_type(S, T)

@inline cancontain(T::Type{<:Integer}, elt::Integer) where {S <: Integer} =
    typemin(T) ≤ elt ≤ typemax(T)

@inline cancontain(T::Type{<:AbstractFloat}, elt::Integer) =
    (m = Integer(maxintfloat(T)); -m ≤ elt ≤ m)

"""
$(SIGNATURES)

Convert the argument to a narrower type if possible without losing precision.

!!! note
    This function is not type stable, use only when new container types are determined.
"""
@inline narrow(x) = x

@inline function narrow(x::Integer)
    intype(T) = typemin(T) ≤ x ≤ typemax(T)
    if intype(Bool)
        Bool(x)
    elseif intype(Int8)
        Int8(x)
    elseif intype(Int16)
        Int16(x)
    elseif intype(Int32)
        Int32(x)
    elseif intype(Int64)
        Int64(x)
    else
        x
    end
end

"""
$(SIGNATURES)

Append `elt` to `v`, allocating a new vector and copying the contents.

Type of new collection is calculated using `promote_type`.
"""
function append1(v::Vector{T}, elt::S) where {T,S}
    U = promote_type(T, S)
    w = Vector{U}(undef, length(v) + 1)
    copyto!(w, v)
    w[end] = elt
    w
end

"""
$(SIGNATURES)

Splits a named tuple in two, based on the names in `splitter`.

Returns two `NamedTuple`s; the first one is ordered as `splitter`, the second one with the
remaining values as in the original argument.

```jldoctest
julia> split_namedtuple(NamedTuple{(:a, :c)}, (c = 1, b = 2, a = 3, d = 4))
((a = 3, c = 1), (b = 2, d = 4))
```
"""
@inline split_namedtuple(splitter::Type{<:NamedTuple}, nt::NamedTuple) =
    splitter(nt), Base.structdiff(nt, splitter)
