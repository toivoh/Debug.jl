
#   Debug.AST:
# ==============
# Extensions to the julia AST format shared by decorate, instrument, and graft

module AST
using Base
import Base.has, Base.show

export Env, LocalEnv, NoEnv, child, add_assigned, add_defined
export Node, ExNode, Leaf, PLeaf
export Block, Trap, Loc, Sym, Plain, toex


# ---- Env: analysis-time scope -----------------------------------------------

abstract Env
type NoEnv    <: Env; end
type LocalEnv <: Env
    source
    parent::Env
    defined::Set{Symbol}
    assigned::Set{Symbol}
end
child(source, env::Env) = LocalEnv(source, env, Set{Symbol}(), Set{Symbol}())

function show(io::IO, env::LocalEnv) 
    print(io, "LocalEnv(,$(env.parent),$(env.defined),$(env.assigned))")
end

has(env::NoEnv,    sym::Symbol) = false
has(env::LocalEnv, sym::Symbol) = has(env.defined,sym) || has(env.parent,sym)

add_defined( ::Env, ::Symbol) = nothing
add_assigned(::Env, ::Symbol) = nothing
add_defined( env::LocalEnv, sym::Symbol) = add(env.defined,  sym)
add_assigned(env::LocalEnv, sym::Symbol) = add(env.assigned, sym)


# ---- Extended AST nodes that can be produced by decorate() ------------------

# Additional ExNode head types
type Block;  env::Env;  end

toex(head::Symbol, args) = expr(head,   args...)
toex(head::Block,  args) = expr(:block, args...)

# Leaf head types
abstract Trap

type Plain; end # Plain leaf
type Sym;  env::Env;  end # Symbol with Env
type Loc <: Trap;  line::Int; file::String;  end # Trap location
Loc(line, file) = Loc(line, string(file))
Loc(line)       = Loc(line, "")


abstract Node

# node with args
type ExNode{H} <: Node
    parent::Union(ExNode, Nothing)
    head::H
    args::Vector{Node}    

    ExNode(head, args) = new(nothing, head, Node[args...])
end
ExNode{T}(head::T, args) = ExNode{T}(head, args)

type Leaf{H,T} <: Node
    parent::Union(ExNode, Nothing)
    head::H
    ex::T

    Leaf(head, ex) = new(nothing, head, ex)
end
Leaf{H,T}(head::H, ex::T) = Leaf{H,T}(head, ex)
Leaf(ex)                  = Leaf(Plain(), ex)

typealias PLeaf{T} Leaf{Plain,T}

end # module
