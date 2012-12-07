include(find_in_path("Debug.jl"))

module TestInteractive
using Base, Debug

println("Commands:")
println("--------")
println("s: step into")
println("n: step over any enclosed scope")
println("o: step out from the current scope")
println("c: continue to next breakpoint")
println("q: quit")
println()
println("Type an expression to evaluate it in the current scope.")

@debug let
    x, y = 0, 1
    @bp
    go_on = true
    while go_on
        println("$x, $y")
        @bp
        x, y = y, x+y
    end
end

end # module
