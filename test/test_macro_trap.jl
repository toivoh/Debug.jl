module TestMacroTrap
using Debug
import Debug.Node, Debug.@instrument, Debug.Scope, Debug.BPNode

trap(::Node, ::Scope) = nothing
function trap(::BPNode, scope::Scope)
    @assert scope[:z] == 3
    scope[:z] = 4
end

macro m()
    esc(quote
        @bp
    end)
end

@instrument trap let
    z = 3
    @m
    @assert z == 4
end

end # module