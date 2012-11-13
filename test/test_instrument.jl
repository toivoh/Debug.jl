
load("debug.jl")
using Debug

code = quote
    for i=1:3
        println(i)
    end
end

icode = instrument(code)
println(icode)

debug_hook() = println("debug_hook called")
eval(icode)
