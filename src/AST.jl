
#   Debug.AST:
# ==============
# Extensions to the julia AST format shared by decorate, instrument, and graft

module AST
import Base.haskey, Base.show, Base.isequal, Base.promote_rule

export Env, LocalEnv, NoEnv, child
export State, SimpleState, Def, Lhs, Rhs, Nonsyntax
export empty_symbol
export Loc, Plain, ExValue, Location
export Node, ExNode, PLeaf, SymNode, LocNode
export is_emittable, is_evaluable
export parentof, valueof, envof, exof
export Event, Enter, Leave


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

haskey(env::NoEnv,    sym::Symbol) = false
haskey(env::LocalEnv, sym::Symbol) = (sym in env.defined) || haskey(env.parent,sym)

add_defined( ::Env, ::Symbol) = nothing
add_assigned(::Env, ::Symbol) = nothing
add_defined( env::LocalEnv, sym::Symbol) = push!(env.defined,  sym)
add_assigned(env::LocalEnv, sym::Symbol) = push!(env.assigned, sym)


# ---- State: Context for a Node ----------------------------------------------

abstract State
promote_rule{S<:State,T<:State}(::Type{S},::Type{T}) = State

abstract SimpleState <: State
type Def <: SimpleState;  env::Env;  end  # definition, e.g. inside local
type Lhs <: SimpleState;  env::Env;  end  # e.g. to the left of =
type Rhs <: SimpleState;  env::Env;  end  # plain evaluation

type Nonsyntax <: State; end


# ---- Node: decorated AST node format ----------------------------------------

const empty_symbol = symbol("")

type Loc;   ex; line::Int; file::Symbol;  end
Loc(ex, line)       = Loc(ex, line, empty_symbol)

type Node{T}
    value::T
    parent::Union(Node, Nothing)
    introduces_scope::Bool
    state::State
    loc::Loc    
    
    function adopt_args!(node::Node)
        if T <: ExValue
            for arg in node.value.args
                set_parent(arg, node)
            end            
        end
        node
    end

    Node(value::T)                 = adopt_args!(new(value,nothing,false))
    Node(value::T, s::State)       = adopt_args!(new(value,nothing,false,s))
    Node(value::T,s::State,l::Loc) = adopt_args!(new(value,nothing,false,s,l))
end
Node{T}(value::T, args...) = Node{T}(value, args...)

isequal(x::Node, y::Node)  = isequal(x.value, y.value)
==(x::Node, y::Node)       = isequal(x.value, y.value)
show(io::IO, ex::Node) = (print(io,"Node("); show(io,ex.value); print(io,")"))

function set_parent(ex::Node, parent::Node)
    if parentof(ex) === nothing; ex.parent = parent
    else; error("$ex already has a parent!")
    end
end

## Types for Node.value ##

type Plain; ex; end
type Location;  end
type ExValue
    head::Symbol
    args::Vector{Node}

    ExValue(head::Symbol, args) = new(head, Node[args...])
end

typealias ExNode  Node{ExValue}
typealias PLeaf   Node{Plain}
typealias SymNode Node{Symbol}
typealias LocNode Node{Location}

# override for node types that should not be emitted
is_emittable(ex) = true

is_evaluable(ex) = is_emittable(ex)
is_evaluable(::Node{Location}) = false
is_evaluable(::LocNode) = false

## Accessors for Node:s ##

parentof(node::Node) = node.parent
valueof( node::Node) = node.value
envof(   node::Node) = node.state.env # will only work for SimpleState:s

exof(node::SymNode) = valueof(node)
exof(node::LocNode) = node.loc.ex
exof(node::Node)    = exof(valueof(node))
exof(value::Union(Plain, Loc)) = value.ex


# ---- Events -----------------------------------------------------------------

abstract Event{T<:Node}

type Enter{T<:Node} <: Event{T};  node::Node;  end
type Leave{T<:Node} <: Event{T};  node::Node;  end

Enter{T<:Node}(node::T) = Enter{T}(node)
Leave{T<:Node}(node::T) = Leave{T}(node)

end # module
