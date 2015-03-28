module TestLocalEval
using Base.Test
using Debug

@test_throws ErrorException @localscope

@debug function f(x)
    y = x+3
    @localscope
end

@debug_analyze function g(x)
    y = x+3
    @localscope
end

for func in [f, g]
    global z = 5

    s = func(11)
    @test s[:x] === 11
    @test s[:y] === 14
    @test debug_eval(s, :(x, y, z, x*z)) === (11, 14, 5, 55)

    s[:x], s[:y], z = 1,2,3
    @test s[:x] === 1
    @test s[:y] === 2
    @test debug_eval(s, :(x, y, z, y*z)) === (1, 2, 3, 6)

    syms = Set(keys(s))
    @test syms == Set([:x, :y])
end

end # module
