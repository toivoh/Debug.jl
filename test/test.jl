
load("debug.jl")

module TestDebugEval
import Base.*
import Debug.*


@debug function f(n)
    x = 0       # line 10
    for k=1:n   # line 11
        x += k  # line 12
    end         # line 13
    x = x*x     # line 14
end

function debug_hook(line::Int, file, scope::Scope)
    print(line, ":")

    if (line == 11) debug_eval(scope, :(x += 1)) end

    if (line >  10) debug_eval(scope, :(print("\tx = ", x))) end
    if (line == 12) debug_eval(scope, :(print("\tk = ", k))) end
    println()
end

f(3)

end
