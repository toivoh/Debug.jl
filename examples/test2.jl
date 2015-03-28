
module TestInteractive
using Debug

println(Debug.UI.helptext)
println()
println("Type an expression to evaluate it in the current scope.")

@debug begin
    function sumpow(n::Int, p::Int = 1)
        @bp
        if n <= 0; return 0; end
        n^p + sumpow(n-1, p)
    end
    sumpow(10)
end

end # module
