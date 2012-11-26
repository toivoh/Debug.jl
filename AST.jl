
#   Debug.AST:
# ==============
# Extensions to the julia AST format shared by decorate, instrument, and graft

module AST
using Base
import Base.has

export Env, child
export Leaf, Line, Sym, Block
export get_head


# ---- Env: analysis-time scope -----------------------------------------------
type Env
    parent::Union(Env,Nothing)
    defined::Set{Symbol}
    assigned::Set{Symbol}
    processed::Bool  # todo: better way to handle assigned pass?
end
child(env) = Env(env, Set{Symbol}(), Set{Symbol}(), false)
function has(env::Env, sym::Symbol) 
    has(env.defined, sym) || (isa(env.parent, Env) && has(env.parent, sym))
end


# ---- Extended AST nodes that can be produced by decorate() ------------------
type Block;    args::Vector; env::Env;          end # :block with Env
type Sym;      ex::Symbol;   env::Env;          end # Symbol with Env
type Leaf{T};  ex::T;                           end # Unexpanded node
type Line{T};  ex::T; line::Int; file::String;  end
Line{T}(ex::T, line, file) = Line{T}(ex, line, string(file))
Line{T}(ex::T, line)       = Line{T}(ex, line, "")
get_head(ex::Block) = :block
get_head(ex::Expr)  = ex.head


end # module