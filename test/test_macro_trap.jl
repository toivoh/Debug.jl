include(find_in_path("Debug.jl"))

module TestMacroTrap
using Base, Debug

trap(::Loc, ::Scope) = nothing
function trap(::BreakPoint, scope::Scope)
    @assert scope[:z] == 3
    scope[:z] = 4
end

macro m()
    esc(quote
        @bp
    end)
end

@debug trap let
    z = 3
    @m
    @assert z == 4
end

end # module