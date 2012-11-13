
load("debug.jl")

module TestAnalysis
using Base, Debug


code = quote
    for i=1:3
        println(i)
    end
end

#translated = translate(code)
#println(translated)

println(argpositions(:(for i=5;end)))
println(argpositions(:{x for x=1:5,y=1:3}))

end
