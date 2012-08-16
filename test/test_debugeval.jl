
load("debug.jl")

module TestDebugEval
import Base.*
import Debug.*


@debug function f(n)
    x = 0      # this must be line #10
    for k=1:n                      #11
        x += k                     #12
    end                            #13
    x = x*x                        #14
    let y=2x                       #15
        y                          #16
    end                            #17
    try                            #18
        error("throw something")   #19
    catch e                        #20
        x                          #21
    end                            #22
    g = x->begin                   #23
        x = -1                     #24
        x                          #25
    end                            #26
    g(n)                           #27
    x                              #28
end

function debug_hook(line::Int, file, scope::Scope) 
    print(line, ":")

    if (line == 11) debug_eval(scope, :(x += 1)) end

    if (line >  10) debug_eval(scope, :(print("\tx = ", x))) end
    if (line == 12) debug_eval(scope, :(print("\tk = ", k))) end
    if (line == 16) debug_eval(scope, :(print("\ty = ", y))) end
    if (line == 21) debug_eval(scope, :(print("\te = ", e))) end
    if (line >  23) debug_eval(scope, :(print("\tg = ", g))) end
    println()
end

f(3)

end
