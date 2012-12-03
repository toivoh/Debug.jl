
#   Debug.AST:
# ==============
# Extensions to the julia AST format shared by decorate, instrument, and graft

module AST
using Base
import Base.has, Base.show

export Env, LocalEnv, NoEnv, child, add_assigned, add_defined
export LocNode, PLeaf, SymNode, BlockNode
export Trap, Loc, Block
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

    function ExNode(format::T, args)
        ex = new(nothing, format, Node[args...])
        for arg in ex.args; set_parent(arg, ex); end
        ex
    end
    ExNode(args...) = ExNode(T(args[1:end-1]...), args[end])
end
ExNode{T}(format::T, args) = ExNode{T}(format, args)
function show(io::IO, ex::ExNode) 
    print(io, "ExNode("); 
    show(io, ex.format); print(io, ", ")
    show(io, ex.args);   print(io, ")")
end

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


abstract Trap

type Plain;           ex; end
type Sym;             ex::Symbol; env::Env;  end
type Loc{T} <: Trap;  ex::T; line::Int; file::String;  end
Loc{T}(ex::T, line, file) = Loc{T}(ex, line, string(file))
Loc{T}(ex::T, line)       = Loc{T}(ex, line, "")

typealias PLeaf   Leaf{Plain}
typealias SymNode Leaf{Sym}
typealias LocNode Leaf{Loc}

show(io::IO, ex::Leaf) = (print(io,"Leaf("); show(io,ex.format); print(io,")"))
function show(io::IO, ex::PLeaf) 
    print(io,"PLeaf("); show(io,ex.format.ex); print(io,")")
end

function set_parent(ex::Union(ExNode, Leaf), parent::Node)
    if parentof(ex) === nothing; ex.parent = parent
    else; error("$ex already has a parent!")
    end
end
parentof(ex::Union(ExNode, Leaf)) = ex.parent

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

is_trap(ex)                 = false
is_trap{T<:Trap}(::Leaf{T}) = true

end # module
