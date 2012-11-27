include("debug.jl")

module TestInteractive
using Base
import Debug.@debug

@debug let
    x, y = 0, 1
    go_on = true
    while go_on
        println("$x, $y")
        x, y = y, x+y
    end
end

end # module
