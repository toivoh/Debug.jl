include(find_in_path("Debug.jl"))

module TestDebugEval
using Base, Debug

firstline = -1
trap(node::BlockNode, scope::Scope) = nothing
function trap(node::Node, scope::Scope) 
    global firstline = (firstline == -1) ? node.loc.line : firstline
    line = node.loc.line - firstline + 1
    print(line, ":")

    if (line == 2); debug_eval(scope, :(x += 1)) end
    if (line == 7); debug_eval(scope, :((y,z) = (z,y))) end

    if (line >  1); print("\tx = ", debug_eval(scope, :x)) end
    if (line == 3); print("\tk = ", debug_eval(scope, :k)) end
    if (line >  5)  
        print("\ty = ", debug_eval(scope, :y))
        print("\tz = ", debug_eval(scope, :z))
    end
    println()
end

@debug trap function f(n)
    x = 0       # line 1
    for k=1:n   # line 2
        x += k  # line 3
    end         # line 4
    y, z = 1:2  # line 5
    x = x*x     # line 6
    x           # line 7
end


f(3)

end
