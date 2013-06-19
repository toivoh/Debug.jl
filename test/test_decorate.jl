module TestDecorate
export @syms, @noenv, @test_decorate
using Debug.AST, Debug.Meta, Debug.Analysis

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
        Node(BlockEnv([],[]))
    elseif is_expr(args[end], :hcat) || is_expr(args[end], :vcat)
        Node(BlockEnv(args[1:end-1], args[end].args))
    else
        Node(BlockEnv(args, []))
    end
end
macro noenv()
    Node(NoEnv())
end

rebuild(node::Union(Node{BlockEnv},Node{NoEnv})) = node
function rebuild(node::Node)
    if isblocknode(node)
        env = envof(node)
        for arg in argsof(node)
            if isa(arg, Node{BlockEnv})
                benv = valueof(arg)
                if !(env.defined == benv.defined)
                    error("env.defined = $(env.defined) != $(benv.defined)")
                end
                just_assigned = setdiff(env.assigned, env.defined)
                if !(just_assigned == benv.assigned)
                    error("just_assigned = $(just_assigned) != $(benv.assigned)")
                end
            elseif isa(arg, Node{NoEnv})
                @assert isa(env, NoEnv)
            end
        end
        Expr(:block, {rebuild(arg) for arg in argsof(node)}...)
    elseif isa(node, ExNode)
        Expr(headof(node), {rebuild(arg) for arg in argsof(node)}...)
    else
        exof(node)
    end
end

function test_decorate(code)
    ecode = macroexpand(code)
    dcode = analyze(NoEnv(), ecode, false)
    rcode = rebuild(dcode)
    @assert rcode == ecode
end
macro test_decorate(ex)
    quote
        test_decorate($(quot(ex)))
    end
end

@test_decorate let
    @syms [f]
    function f(x::Int)
        @syms x [y]
        y = 0
        while x > 0
            @syms [x y]
            x -= y
            y += 1
        end
        y
    end
end

@assert_fails @test_decorate let
    @syms
    local x = 3
end
@assert_fails @test_decorate let
    @syms
    x = 3
end
@assert_fails @test_decorate let
    @syms x
end
@assert_fails @test_decorate let
    @syms [x]
end

@assert_fails @test_decorate let
    @noenv
end
@assert_fails @test_decorate begin
    @syms
end


# ---- scoping tests ----------------------------------------------------------

# symbol defining/assigning constructs
@test_decorate let
    @syms
    let
        @syms d1 d2 d3 d4 d5 [a1 a2 a3 a4 a5]
        # define
        global d1, d2=3, d3::Int, d4::String = "foo"
        local d5::Float64 = 3    
        # assign
        a1 = 5
        a2, a3::Integer = 6, 7
        a4::Int = 23
        a5 += 2
        # neither
        y
        v[i] = x
    end
end

# while
@test_decorate let
    @syms [i]
    i=1
    while (@syms [i]; i < 3) # condition evaluated in outside scope
        @syms j [i z]
        i=i+1
        local j=i^2
        z = i-j
    end
end

# try
@test_decorate let
    try
        @syms x
        local x
    catch e
        @syms e [y]
        y = 2
    end
    try
        @syms x
        local x
    catch e
        @syms e [y]
        y = 2
    finally
        @syms z
        local z
    end
end

# for
@test_decorate let
    @syms [a]
    for x=(a=11; 1:n)
        @syms x [x2]
        x2 = x^2
        push!(z, x2)       
    end
end

# let
@test_decorate let
    @syms [a]
    let x, y=3, z::Int, u::Int=11, v=(a=11; 23)
        @syms x y z u v
    end
end

# comprehensions
@test_decorate let
    let
        @syms [a]
        [(@syms x y; x*y+z) for x=(@syms [a]; 1:5), y=(a=5; 1:3)]
    end
    let
        @syms [a]
        {(@syms x y; x*y+z) for x=(@syms [a]; 1:5), y=(a=5; 1:3)}
    end
    let
        @syms [a b]
        (b=5;Int)[(@syms x; x+z) for x=(@syms [a b]; a=5; 1:5)]
    end
end

# dict comprehensions
@test_decorate let
    let
        @syms [a]
        [(@syms x y; x*y=>z) for x=(@syms [a]; 1:5), y=(a=5; 1:3)]
    end
    let
        @syms [a]
        {(@syms x y; x*y=>z) for x=(@syms [a]; 1:5), y=(a=5; 1:3)}
    end
    let
        @syms [a b]
        (b=5;Int=>Int)[(@syms x; x=>z) for x=(@syms [a b]; a=5; 1:5)]
    end
end

# functions
@test_decorate let
    @syms [f1 f2 f3 f4]
    function f1(x, y::(w=3; Int), args...)
        @syms x y args [z w]
        z = x*y
    end
    f2(x, y::(w=3; Int), args::Int...) = begin
        @syms x y args [z w]
        z = x*y
    end
    f3 = function(x, y::(w=3; Int), args...)
        @syms x y args [z w]
        z = x*y
    end
    f4 = (x, y::(w=3; Int), args...)->begin
        @syms x y args [z w]
        z = x*y
    end
end

# functions with type parameters
@test_decorate let
    @syms [f g]
    function f{S,T<:Int}(x::S, y::T)
        @syms S T x y
        (x, y)
    end
    g{S,T<:Int}(x::S, y::T) = begin
        @syms S T x y
        (x, y)
    end
end


# test that the right hand sides below are really evaluated inside the scope
@assert_fails eval(:(typealias P{Real} Real))
@assert_fails eval(:(abstract  Q{Real} <: Real))
@assert_fails eval(:(type      R{Real} <: Real; end))

# typealias, abstract
@test_decorate let
    @syms T1 T2 T3
    abstract T1
    abstract T2 <: Q
    typealias T3 T1    
end

# type
@test_decorate let
    @syms T [a]
    type T<:(a=3; Integer)
        @syms c T
        x::Int
        y::Int
        c(x,y) = begin
            @syms x y
            new(x,y)
        end
        function T(x)
            @syms x
            c(x,2x)
        end
    end
end

# types with type parameters
@test_decorate let
    @syms P Q
    type P{T}
        @syms T
        x::T
    end
    type Q{S,T} <: Associative{S,T}
        @syms S T
        x::T
    end
end

# abstract/typealias with type parameters
@test_decorate let
    @syms A X
    abstract A{S,T} <: B{(@syms A X; Int)}
    typealias X{Q<:Associative{Int,Int},R<:Real} Dict{(@syms Q R; Int),Int}
end

# global/local scope
@test_decorate begin
    @noenv
    begin
        @noenv        
    end
    for x=(@noenv; 1:3)
        @syms x
    end
    let y=(@noenv; 1)
        @syms y
    end
end

end # module
