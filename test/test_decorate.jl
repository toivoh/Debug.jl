include("debug.jl")

module TestDecorate
export @syms
using Base, Debug, Debug.AST, Debug.Analysis

macro assert_fails(ex)
    quote
        if (try; $(esc(ex)); true; catch e; false; end)
            error($("@assert_fails: $ex didn't fail!"))
        end
    end
end

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

reconstruct(node::Union(Leaf,Sym,Line)) = node.ex
reconstruct(ex::Expr) = expr(ex.head, {reconstruct(arg) for arg in ex.args})
function reconstruct(block::Block)
    env = block.env
    for arg in block.args
        if isa(arg, Leaf{BlockEnv})
            if !(env.defined == arg.ex.defined)
                error("env.defined = $(env.defined) != $(arg.ex.defined)")
            end
            just_assigned = env.assigned - env.defined
            if !(just_assigned == arg.ex.assigned)
                error("just_assigned = $(just_assigned) != $(arg.ex.assigned)")
            end
#            @assert env.defined == arg.ex.defined
#            @assert (env.assigned - env.defined) == arg.ex.assigned 
        end
    end
    expr(:block, {reconstruct(arg) for arg in block.args})
end

function test_decorate(code)
    dcode = analyze(code)
    rcode = reconstruct(dcode)
    @assert rcode == code
end

#code, dcode, rcode = test_decorate(quote
test_decorate(quote
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
end)


# ---- scoping tests ----------------------------------------------------------

# symbol defining/assigning constructs
test_decorate(quote
    $(@syms)
    let
        $(@syms d1 d2 d3 d4 d5 [a1 a2 a3 a4])
        # define
        global d1, d2=3, d3::Int, d4::String = "foo"
        local d5::Float64 = 3    
        # assign
        a1 = 5
        a2, a3::Integer = 6, 7
        a4::Int = 23
        # neither
        y
        v[i] = x
        z += 2
    end
end)

# while
test_decorate(quote
    $(@syms [i])
    i=1
    while ($(@syms [i]); i < 3) # condition evaluated in outside scope
        $(@syms j [i z])
        i=i+1
        local j=i^2
        z = i-j
    end
end)

# try
test_decorate(quote
    try
        $(@syms x)    
        local x
    catch e
        $(@syms e [y])
        y = 2
    end
end)

# for
test_decorate(quote
    $(@syms [a])
    for x=(a=11; 1:n)
        $(@syms x [x2])
        x2 = x^2
        push(z, x2)       
    end
end)

# let
test_decorate(quote
    $(@syms [a])
    let x, y=3, z::Int, u::Int=11, v=(a=11; 23)
        $(@syms x y z u v)
    end
end)

# comprehensions
test_decorate(quote
    let
        $(@syms [a])
        [($(@syms x y); x*y+z) for x=($(@syms [a]); 1:5), y=(a=5; 1:3)]
    end
    let
        $(@syms [a])
        {($(@syms x y); x*y+z) for x=($(@syms [a]); 1:5), y=(a=5; 1:3)}
    end
    let
        $(@syms [a b])
        (b=5;Int)[($(@syms x); x+z) for x=($(@syms [a b]); a=5; 1:5)]
    end
end)

# dict comprehensions
test_decorate(quote
    let
        $(@syms [a])
        [($(@syms x y); x*y=>z) for x=($(@syms [a]); 1:5), y=(a=5; 1:3)]
    end
    let
        $(@syms [a])
        {($(@syms x y); x*y=>z) for x=($(@syms [a]); 1:5), y=(a=5; 1:3)}
    end
    let
        $(@syms [a b])
        (b=5;Int=>Int)[($(@syms x); x=>z) for x=($(@syms [a b]); a=5; 1:5)]
    end
end)

# functions
test_decorate(quote
    $(@syms [f1 f2 f3 f4])
    function f1(x, y::(w=3; Int), args...)
        $(@syms x y args [z w])
        z = x*y
    end
    f2(x, y::(w=3; Int), args::Int...) = begin
        $(@syms x y args [z w])
        z = x*y
    end
    f3 = function(x, y::(w=3; Int), args...)
        $(@syms x y args [z w])
        z = x*y
    end
    f4 = (x, y::(w=3; Int), args...)->begin
        $(@syms x y args [z w])
        z = x*y
    end
end)

# functions with type parameters
test_decorate(quote
    $(@syms [f g])
    function f{S,T<:Int}(x::S, y::T)
        $(@syms S T x y)
        (x, y)
    end
    g{S,T<:Int}(x::S, y::T) = begin
        $(@syms S T x y)
        (x, y)
    end
end)


# test that the right hand sides below are really evaluated inside the scope
@assert_fails eval(:(typealias P{Real} Real))
@assert_fails eval(:(abstract  Q{Real} <: Real))
@assert_fails eval(:(type      R{Real} <: Real; end))

# typealias, abstract
test_decorate(quote
    $(@syms T1 T2 T3)
    abstract T1
    abstract T2 <: Q
    typealias T3 T1    
end)

# type
test_decorate(quote
    $(@syms T [a])
    type T<:(a=3; Integer)
        $(@syms c T)
        x::Int
        y::Int
        c(x,y) = begin
            $(@syms x y)
            new(x,y)
        end
        function T(x)
            $(@syms x)
            c(x,2x)
        end
    end
end)

# types with type parameters
test_decorate(quote
    $(@syms P Q)
    type P{T}
        $(@syms T)
        x::T
    end
    type Q{S,T} <: Associative{S,T}
        $(@syms S T)
        x::T
    end
end)

# abstract/typealias with type parameters
test_decorate(quote
    $(@syms A X)
    abstract A{S,T} <: B{($(@syms A X); Int)}
    typealias X{Q<:Associative{Int,Int},R<:Real} Dict{($(@syms Q R); Int),Int}
end)

end # module
