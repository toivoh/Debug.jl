include(find_in_path("Debug.jl"))

module TestDebugEval
using Base, Debug

trap(args...) = nothing


@debug trap function f(n)
    x = 0       # line 10
    for k=1:n   # line 11
        x += k  # line 12
    end         # line 13
    y, z = 1:2  # line 14
    x = x*x     # line 15
    x           # line 16
end

function trap(line::Int, file, scope::Scope) 
    print(line, ":")

    if (line == 11) debug_eval(scope, :(x += 1)) end
    if (line == 16) debug_eval(scope, :((y,z) = (z,y))) end

    if (line > 10)  print("\tx = ", debug_eval(scope, :x)) end
    if (line == 12) print("\tk = ", debug_eval(scope, :k)) end
    if (line > 14)  
        print("\ty = ", debug_eval(scope, :y))
        print("\tz = ", debug_eval(scope, :z))
    end
    println()
end

f(3)

end
