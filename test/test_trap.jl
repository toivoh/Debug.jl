module TestTrap
using Debug
import Debug.Scope, Debug.Node, Debug.@instrument

firstline = -1
function trap(node::Node, scope::Scope)
    global firstline = (firstline == -1) ? node.loc.line : firstline
    line = node.loc.line - firstline + 1

    print(line, ":")
    if (line >  1); print("\tx = ", scope[:x]) end
    if (line == 3); print("\tk = ", scope[:k]) end
    println()
end

@instrument trap function f(n)
    x = 0       # line 1
    for k=1:n   # line 2
        x += k  # line 3
    end         # line 4
    x = x*x     # line 5
    x           # line 6
end


f(3)


errtrap(node, scope) = @assert false
@instrument trap @notrap begin; @bp; x=1; end

# #71
@debug begin
   serialize(IOBuffer(), @notrap ()->1)
end

@notrap z=5
@assert z == 5

end
