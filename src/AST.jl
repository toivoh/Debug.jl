
#   Debug.AST:
# ==============
# Extensions to the julia AST format shared by decorate, instrument, and graft

module AST
using Base
import Base.has, Base.show

export Env, LocalEnv, NoEnv, child, add_assigned, add_defined
export Node, ExNode, Leaf
export Trap, Loc, Sym, Block


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
    head::T
    args::Vector{Node}    

    ExNode(head, args) = new(nothing, head, Node[args...])
end
ExNode{T}(head::T, args) = ExNode{T}(head, args)

type Leaf{T} <: Node
    parent::Union(ExNode, Nothing)
    value::T

    Leaf(value) = new(value)
end
Leaf{T}(value::T) = Leaf{T}(value)

# Additional head types
type Block;  env::Env;  end

# Leaf types
abstract Trap

type Sym;  ex::Symbol; env::Env;  end # Symbol with Env
type Loc{T} <: Trap;  ex::T; line::Int; file::String;  end # Trap location

# abstract Trap  # nodes that should invoke trap(node, scope)

# type Block;           args::Vector; env::Env;          end # :block with Env
# type Sym;             ex::Symbol;   env::Env;          end # Symbol with Env
# type Leaf{T};         ex::T;                           end # Unexpanded node
# type Loc{T} <: Trap;  ex::T; line::Int; file::String;  end # Trap location
# Loc{T}(ex::T, line, file) = Loc{T}(ex, line, string(file))
# Loc{T}(ex::T, line)       = Loc{T}(ex, line, "")
# get_head(ex::Block) = :block
# get_head(ex::Expr)  = ex.head

end # module
