
module TestInteractive
using Debug

println(Debug.UI.helptext)
println()
println("Type an expression to evaluate it in the current scope.")

@debug begin
    function myfunc2(x::Matrix)
        @bp
        for i=1:size(x,1), j=1:size(x,2)
            println("x[$i,$j] = $(x[i,j])");
        end
    end
    myfunc2([1 2; 3 4])
end

end # module
