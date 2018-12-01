module FunctionalTables

using ArgCheck: @argcheck
using DocStringExtensions: SIGNATURES, TYPEDEF
using Parameters: @unpack
using IterTools: @ifsomething, imap
import Tables

include("utilities.jl")
include("ordering.jl")
include("columns.jl")
include("functionaltables.jl")
include("tables-interface.jl")
include("sort.jl")
include("by.jl")

end # module
