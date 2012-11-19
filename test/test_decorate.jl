load("debug.jl")

module TestDebugEval
export @syms
using Base, Debug

type BlockEnv
    defined ::Set{Symbol}
    assigned::Set{Symbol}

    BlockEnv(d, a) = new(Set{Symbol}(d...), Set{Symbol}(a...))
end

macro syms(args...)
    if length(args) == 0
        BlockEnv([],[])
    elseif Debug.is_expr(args[end], :hcat) || Debug.is_expr(args[end], :vcat)
        BlockEnv(args[1:end-1], args[end].args)
    else
        BlockEnv(args, [])
    end
end

code = quote
    $(@syms [f])
    function f(x::Int)
        $(@syms x [y])
        y = 0
        while x > 0
            $(@syms)
            x -= y
            y += 1
        end
        y
    end
end

reconstruct(node::Union(Leaf,Sym,Line)) = node.ex
reconstruct(ex::Expr) = expr(ex.head, {reconstruct(arg) for arg in ex.args})
function reconstruct(block::Block)
    env = block.env
    for arg in block.args
        if isa(arg, Leaf{BlockEnv})
            @assert env.defined == arg.ex.defined
            @assert (env.assigned - env.defined) == arg.ex.assigned 
        end
    end
    expr(:block, {reconstruct(arg) for arg in block.args})
end

dcode = analyze(code)
rcode = reconstruct(dcode)

@assert rcode == code

end
