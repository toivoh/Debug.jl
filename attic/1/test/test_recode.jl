
load("debug.jl")

module TestRecode
import Base.*
import Debug.*

code = :(function f(n)
    x = 0
    for k=1:n
        x += k
        println("k = ", k)
    end
    x = x*x
    let y=x
        z=2y
    end
    try
        error()
        x=1
    catch e
        n=2
        x
    end
end)

println(getdefs(code))

println()
println(code_debug(code))

end
