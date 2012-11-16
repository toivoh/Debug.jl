load("debug.jl")

module TestInstrument
using Base, Debug
import Debug.trap

trap(line, file, scope) = println("trap: line = $line, file = $(repr(file))")

code = quote
    function()
        for i=1:3
            println(i)
        end
    end
end

icode = instrument(code)
println(icode, '\n')

eval(icode)()

println(instrument(quote
    global g1, g2
    local l
    i = 1
    while i<=3
        z = i+1
        println(z)
        i += 1
    end
    try
        x = 5
    catch e
        println(e)
    end
end))

end
