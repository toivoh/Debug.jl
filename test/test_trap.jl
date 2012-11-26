include("debug.jl")

module TestTrap
using Base, Debug
import Debug.trap



@debug function f(n)
    x = 0  # this must be line #10
    for k=1:n
        x += k
    end
    x = x*x
    x
end

function trap(line::Int, file, scope::Scope) 
    print(line, ":")
    if (line > 10) print("\tx = ", scope[:x]) end
    if (line == 12) print("\tk = ", scope[:k]) end
    println()
end

f(3)

end
