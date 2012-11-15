
load("debug.jl")

module TestInstrument
using Base, Debug
import Debug.trap

trap(line, file) = println("trap: line = $line, file = $(repr(file))")

code = quote
    function()
        for i=1:3
            println(i)
        end
    end
end

icode = instrument(code)
println(icode)

eval(icode)()


tcode = translate(code)
mark_scope!(tcode, NoScope())

end
