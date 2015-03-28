module TestLocalEval
using Base.Test
using Debug

@test_throws ErrorException @localscope

@debug function f(x)
    y = x+3
    (let y = -5, w = 4; y = -5; @localscope; end), @localscope
end

@debug_analyze function g(x)
    y = x+3
    (let y = -5, w = 4; y = -5; @localscope; end), @localscope
end

for func in [f, g]
    global z = 5

    si, so = func(11)
    @test so[:x] === 11 === si[:x]
    @test so[:y] === 14
    @test si[:y] === -5
    @test si[:w] === 4
    @test debug_eval(so, :(x, y, z, x*z)) === (11, 14, 5, 55)

    so[:x], so[:y], z = 1,2,3
    @test so[:x] === 1
    @test so[:y] === 2
    @test si[:y] === -5
    @test debug_eval(so, :(x, y, z, y*z)) === (1, 2, 3, 6)

    symso, symsi = Set(keys(so)), Set(keys(si))
    @test symso == Set([:x, :y])
    @test symsi == Set([:x, :y, :w])
end

end # module
