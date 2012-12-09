include(find_in_path("Debug.jl"))

module TestInteractive
using Base, Debug

println(Debug.UI.helptext)
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
