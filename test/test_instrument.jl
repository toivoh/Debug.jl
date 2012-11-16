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

code2 = quote
    i = 1
    while i <= 3
        println(i)
        i += 1
    end 
end

acode = analyze(code2)
#showall(acode.args[4].args[2].args)

end
