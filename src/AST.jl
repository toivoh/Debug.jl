
#   Debug.AST:
# ==============
# Extensions to the julia AST format shared by decorate, instrument, and graft

module AST
using Base
import Base.has

export Env, LocalEnv, NoEnv, child, add_assigned, add_defined
export Leaf, Loc, Sym, Block
export get_head


# ---- Env: analysis-time scope -----------------------------------------------

abstract Env
type NoEnv    <: Env; end
type LocalEnv <: Env
    parent::Env
    defined::Set{Symbol}
    assigned::Set{Symbol}
end
child(env::Env) = LocalEnv(env, Set{Symbol}(), Set{Symbol}())

has(env::NoEnv,    sym::Symbol) = false
has(env::LocalEnv, sym::Symbol) = has(env.defined,sym) || has(env.parent,sym)

add_defined( ::Env, ::Symbol) = nothing
add_assigned(::Env, ::Symbol) = nothing
add_defined( env::LocalEnv, sym::Symbol) = add(env.defined,  sym)
add_assigned(env::LocalEnv, sym::Symbol) = add(env.assigned, sym)


# ---- Extended AST nodes that can be produced by decorate() ------------------
type Block;    args::Vector; env::Env;          end # :block with Env
type Sym;      ex::Symbol;   env::Env;          end # Symbol with Env
type Leaf{T};  ex::T;                           end # Unexpanded node
type Loc{T};   ex::T; line::Int; file::String;  end
Loc{T}(ex::T, line, file) = Loc{T}(ex, line, string(file))
Loc{T}(ex::T, line)       = Loc{T}(ex, line, "")
get_head(ex::Block) = :block
get_head(ex::Expr)  = ex.head


end # module