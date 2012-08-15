
load("debug.jl")

module TestDebugEval
import Base.*
import Debug.*


@debug function f(n)
    x = 0  # this must be line #10
    for k=1:n
        x += k
    end
    x = x*x
    let y=2x
        y
    end
    try
        error("throw something")
    catch e
        x
    end
end

function debug_hook(line::Int, file, scope::Scope) 
    print(line, ":")

    if (line == 11) debug_eval(scope, :(x += 1)) end

    if (line >  10) debug_eval(scope, :(print("\tx = ", x))) end
    if (line == 12) debug_eval(scope, :(print("\tk = ", k))) end
    if (line == 16) debug_eval(scope, :(print("\ty = ", y))) end
    if (line == 21) debug_eval(scope, :(print("\te = ", e))) end
    println()
end

f(3)

end
