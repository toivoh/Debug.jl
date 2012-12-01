include(find_in_path("Debug.jl"))

module TestMacroTrap
using Base, Debug

function trap(loc::LocNode, scope::Scope)
    if loc.line == 15
        @assert scope[:z] == 3
        scope[:z] = 4
    end
end

macro m()
    esc(quote
        z  # must be line 15!
    end)
end

@debug trap let
    z = 3
    @m
    @assert z == 4
end

end # module