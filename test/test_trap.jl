include(find_in_path("Debug.jl"))

module TestTrap
using Base, Debug

firstline = -1
function trap(node::Node, scope::Scope)
    if isblocknode(node); return; end
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

end
