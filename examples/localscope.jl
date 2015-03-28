using Debug
@debug_analyze function f(x)
    outer = @localscope
    local inner
    pos = "outer"
    let pos = "inner"
        y = x
        inner = @localscope
    end
    (outer, inner)
end

outer, inner = f(5)

@show keys(outer) keys(inner)

println()
@show outer[:x] inner[:x]     # x is the same variable in both scopes
@show outer[:pos] inner[:pos] # pos refers to different variables in inner and outer

println("\nSetting `inner[:x] = 3`:")
inner[:x] = 3             # assigns to the single x variable
@show outer[:x] inner[:x] # both values have been updated

println()
@show debug_eval(inner, :(x*x)) # evaluate an expression in the inner scope
