
#   Debug.AST:
# ==============
# Extensions to the julia AST format shared by decorate, instrument, and graft

module AST
using Base
import Base.has, Base.show

export Env, LocalEnv, NoEnv, child, add_assigned, add_defined
export LocNode, PLeaf, SymNode, BlockNode
export Loc
export headof, argsof, argof, nargsof, envof, exof
export Ex, Node, ExNode, Leaf
export is_trap


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

abstract Node

type ExNode{T} <: Node
    parent::Union(ExNode, Nothing)
    format::T
    args::Vector{Node}

    ExNode(format::T, args) = new(nothing, format, Node[args...])
    ExNode(args...) = ExNode(T(args[1:end-1]...), args[end])
end
ExNode{T}(format::T, args) = ExNode{T}(format, args)

typealias Ex Union(Expr, ExNode)

type Block;  env::Env;  end
typealias BlockNode ExNode{Block}

type Leaf{T} <: Node
    parent::Union(ExNode, Nothing)
    format::T

    Leaf(format::T) = new(nothing, format)
    Leaf(args...)   = new(nothing, T(args...))
end
Leaf{T}(format::T) = Leaf{T}(format)

type Plain;  ex; end
type Sym;    ex::Symbol; env::Env;  end
type Loc{T}  ex::T; line::Int; file::String;  end
Loc{T}(ex::T, line, file) = Loc{T}(ex, line, string(file))
Loc{T}(ex::T, line)       = Loc{T}(ex, line, "")

typealias PLeaf   Leaf{Plain}
typealias SymNode Leaf{Sym}
typealias LocNode Leaf{Loc}

parentof(ex::Node) = ex.parent

headof(ex::Expr)           = ex.head
headof(ex::ExNode{Symbol}) = ex.format
headof(ex::BlockNode)      = :block

argsof(ex::Ex) = ex.args
nargsof(ex)  = length(argsof(ex))
argof(ex, k) = argsof(ex)[k]

envof(node::Union(ExNode, Leaf)) = envof(node.format)
envof(fmt::Union(Block, Sym))    = fmt.env

exof(node::Leaf) = exof(node.format)
exof(fmt::Union(Plain, Sym, Loc)) = fmt.ex

is_trap(ex)        = false
is_trap(::LocNode) = true

end # module
