
load("debug.jl")

module TestCollect
import Base.*
import Debug.*

code = :(function f(n)
    x = 0
    for k=1:n
        x += k
        println("k = ", k)
    end
    x = x*x
end)

println(getdefs(code), '\n')

end
