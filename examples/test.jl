
module TestInteractive
using Debug

println(Debug.UI.helptext)
println()
println("Type an expression to evaluate it in the current scope.")

@debug begin
    function test()
        x, y = 0, 1
        @bp
        go_on = true
        while go_on
            println("$x, $y")
            @bp x > 100
            x, y = y, x+y
        end
    end
    test()
end

end # module
