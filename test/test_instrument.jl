include("debug.jl")

module TestInstrument
using Base, Debug, Debug.Analysis
import Debug.trap

trap(line, file, scope) = println("trap: line = $line, file = $(repr(file))")

code = quote
    function()
        for i=1:3
            println(i)
        end
    end
end

icode = Debug.instrument(quot(trap), code)
println(icode, '\n')

eval(icode)()

println(Debug.instrument(quot(trap), quote
    global g1::String, g2
    local l
    i::Int = 1
    v = [1,2]
    while i<=3
        z,w = i+1,i+2
        println(z)
        i = i+1
        v[1] = i
    end
    for i = 1:5
        println(i)
    end
    try
        x = 5
    catch e
        println(e)
    end
    function f(x, ::Int, y::Float)
        x
    end
    f(x, ::Int, y::Float) = x
    f2 = function(x, ::Int, y::Float)
        x
    end
    g = (a,b)->begin
        z=a*b
    end
    let q::Int=i, r
        s=q
    end
    [begin
         x
     end for x=1:3,y=1:5]
    Int[begin
         x
     end for x=1:3]
end))

end
