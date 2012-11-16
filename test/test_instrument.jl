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

acode2 = analyze(code2)
showall(acode2.args[4].args[2].args); println()

code3 = quote
    for i = 1:3
        println(i)
    end 
end

acode3 = analyze(code3)
println("\nacode3:")
showall(acode3.args[2].args)

code4 = :(
    function f(x::begin; Int; end)
        x^2
    end
)

acode4 = analyze(code4)
println("\n\nacode4:")
showall(acode4.args[1].args[2].args)

end
