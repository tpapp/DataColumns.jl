#### Implementing the interface of Tables.jl

Tables.istable(::Type{<:FunctionalTable}) = true

Tables.rowaccess(::Type{<:FunctionalTable}) = true

Tables.rows(ft::FunctionalTable) = ft

Tables.schema(ft::FunctionalTable) = Tables.Schema(keys(ft), map(eltype, values(ft.columns)))

Tables.columnaccess(::Type{<:FunctionalTable}) = true

Tables.columns(ft::FunctionalTable) = columns(ft; vector = true, mutable = true)
