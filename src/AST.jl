
#   Debug.AST:
# ==============
# Extensions to the julia AST format shared by decorate, instrument, and graft

module AST
using Base
import Base.has, Base.show, Base.isequal

export Env, LocalEnv, NoEnv, child, add_assigned, add_defined
export LocNode, PLeaf, SymNode
export Trap, Loc, Plain
export headof, argsof, argof, nargsof
export parentof, envof, exof, valueof
export Ex, Node, ExNode
export is_emittable
export ExValue


export isblocknode

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

abstract Trap

type Plain;   ex; end
type Loc;     ex; line::Int; file::String;  end
Loc(ex, line, file) = Loc(ex, line, string(file))
Loc(ex, line)       = Loc(ex, line, "")

type Node{T}
    value::T
    parent::Union(Node, Nothing)
    state
    loc::Loc
    
    function set_args_parent(node::Node)
        if T <: ExValue
            for arg in argsof(node)
                set_parent(arg, node)
            end            
        end
        node
    end

    Node(value::T)        = set_args_parent(new(value, nothing))
    Node(value::T, state) = set_args_parent(new(value, nothing, state))
end
Node{T}(value::T, args...) = Node{T}(value, args...)

type ExValue
    head::Symbol
    args::Vector{Node}

    ExValue(head::Symbol, args) = new(head, Node[args...])
end

typealias ExNode Node{ExValue}


typealias Ex Union(Expr, ExNode)

isequal(x::Node, y::Node) = isequal(x.value, y.value)


typealias PLeaf   Node{Plain}
typealias SymNode Node{Symbol}
typealias LocNode Node{Loc}

show(io::IO, ex::Node) = (print(io,"Node("); show(io,ex.value); print(io,")"))

function set_parent(ex::Node, parent::Node)
    if parentof(ex) === nothing; ex.parent = parent
    else; error("$ex already has a parent!")
    end
end
parentof(ex::Node) = ex.parent

headof(ex::Expr)      = ex.head
headof(ex::ExNode)    = valueof(ex).head

argsof(ex::Expr)                     = ex.args
argsof(ex::ExNode) = valueof(ex).args
nargsof(ex)  = length(argsof(ex))
argof(ex, k) = argsof(ex)[k]

envof(node::Node) = node.state.env # will only work for SimpleState:s

exof(node::Node) = exof(valueof(node))
exof(node::SymNode) = valueof(node)
exof(node::Ex)   = error("Not applicable!")
exof(value::Union(Plain, Loc)) = value.ex

valueof(node::Node) = node.value

is_emittable(ex) = true


isblocknode(::Any) = false
isblocknode(node::ExNode) = (headof(node) === :block)

end # module
