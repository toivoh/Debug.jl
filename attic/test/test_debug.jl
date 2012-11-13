
load("debug.jl")

module TestDebug
import Base.*
import Debug.*


@debug function f(n)
    x = 0  # this must be line #10
    for k=1:n
        x += k
    end
    x = x*x
    x
end

function debug_hook(line::Int, file, scope::Scope) 
    print(line, ":")
    if (line > 10) print("\tx = ", scope[:x]) end
    if (line == 12) print("\tk = ", scope[:k]) end
    println()
end

f(3)

end
