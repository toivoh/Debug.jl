
load("debug.jl")

module TestDebugEval
import Base.*
import Debug.*

macro assign(lhs, rhs)
    esc(quote
        ($lhs) = ($rhs)   # f_line - 5
    end)
end

const f_line = 15 # line number of the next line:
@debug function f(n) # this must be line number f_line
    x = 0     # line number f_line + 1
    for k=1:n                      # 2
        x += k                     # 3
    end                            # 4
    x = x*x                        # 5
    let y=2x                       # 6
        y                          # 7
    end                            # 8
    try                            # 9
        error("throw something")   #10
    catch e                        #11
        x                          #12
    end                            #13
    [begin x^2 end for x=1:3]      #14
    g = (x, y)->begin              #15
        x = -1                     #16
        a, b = 1, 2                #17
        x                          #18
    end                            #19
    g(n, n)                        #20
    @assign w x/2                  #21
    x                              #22    
end

function debug_hook(line::Int, file, scope::Scope)
    line -= f_line
    print(line, ":")

    if (line ==  2) debug_eval(scope, :(x += 1)) end

    if (line !=  1) debug_eval(scope, :(print("\tx = ", x))) end
    if (line ==  3) debug_eval(scope, :(print("\tk = ", k))) end
    if (line ==  7) debug_eval(scope, :(print("\ty = ", y))) end
    if (line == 12) debug_eval(scope, :(print("\te = ", e))) end
    if (line >  15) debug_eval(scope, :(print("\tg = ", g))) end
    if (16 <= line <= 18) debug_eval(scope, :(print("\ty = ", y))) end
    if (line == 18) debug_eval(scope, :(print("\ta = ", a, "\tb = ", b, ))) end
#    if (line >  21) debug_eval(scope, :(print("\tw = ", w))) end
    println()
end

f(3)

end
