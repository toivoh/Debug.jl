
#   Debug.AST:
# ==============
# Extensions to the julia AST format shared by decorate, instrument, and graft

module AST
using Base
import Base.has, Base.show, Base.isequal

export Env, LocalEnv, NoEnv, child, add_assigned, add_defined
export LocNode, PLeaf, SymNode, BlockNode
export Trap, Loc, Block, Sym, Plain
export headof, argsof, argof, nargsof
export parentof, envof, exof, valueof
export Ex, Node, ExNode, Leaf
export is_emittable
export ExValue

export exnode, leaf

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
type Sym;     ex::Symbol; env::Env;  end
type Loc;     ex; line::Int; file::String;  end
Loc(ex, line, file) = Loc(ex, line, string(file))
Loc(ex, line)       = Loc(ex, line, "")


if 0==1 ###################################################################

type Node{T}
    value::T
    parent::Union(Node, Nothing)
    loc::Loc
    state
    
    Node(value::T) = new(value, nothing)
end
Node{T}(value::T) = Node{T}(value)

type ExValue{T}
    format::T
    args::Vector{Node}

    ExValue(format::T, args) = new(format, Node[args...])
end
ExValue{T}(format::T, args) = ExValue{T}(format, args)

type Block;  env::Env;  end

typealias BlockNode Node{ExValue{Block}}
typealias ExNode Union(Node{ExValue{Symbol}}, BlockNode)


typealias Ex Union(Expr, ExNode)

isequal(x::Node, y::Node) = isequal(x.value, y.value)


typealias PLeaf   Node{Plain}
typealias SymNode Node{Sym}
typealias LocNode Node{Loc}

show(io::IO, ex::Node) = (print(io,"Node("); show(io,ex.value); print(io,")"))

function set_parent(ex::Node, parent::Node)
    if parentof(ex) === nothing; ex.parent = parent
    else; error("$ex already has a parent!")
    end
end
parentof(ex::Node) = ex.parent

headof(ex::Expr)      = ex.head
headof(ex::ExNode)    = valueof(ex).format
headof(ex::BlockNode) = :block

argsof(ex::Expr)                     = ex.args
argsof(ex::Union(ExNode, BlockNode)) = valueof(ex).args
nargsof(ex)  = length(argsof(ex))
argof(ex, k) = argsof(ex)[k]

#envof(node::Union(ExNode, Leaf)) = envof(node.format)
envof(node::BlockNode) = envof(valueof(node).format)
envof(node::SymNode)   = envof(valueof(node))
envof(fmt::Union(Block, Sym)) = fmt.env

exof(node::Node) = exof(valueof(node))
exof(node::Ex)   = error("Not applicable!")
exof(fmt::Union(Plain, Sym, Loc)) = fmt.ex

valueof(node::Node) = node.value

is_emittable(ex) = true



exnode(value::ExValue) = Node(value)
typealias Leaf{T} Node{T}

leaf(value) = Node(value)

else ######################################################################



abstract Node

type ExNode{T} <: Node
    format::T
    args::Vector{Node}

    parent::Union(ExNode, Nothing)
    loc::Loc
    state

    function ExNode(format::T, args)
        ex = new(format, Node[args...], nothing) #, undef, undef
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

type ExValue{T}
    format::T
    args::Vector{Node}

    ExValue(format::T, args) = new(format, Node[args...])
end
ExValue{T}(format::T, args) = ExValue{T}(format, args)

typealias Ex Union(Expr, ExNode)

type Block;  env::Env;  end
typealias BlockNode ExNode{Block}

type Leaf{T} <: Node
    format::T

    parent::Union(ExNode, Nothing)
    loc::Loc
    state

    Leaf(format::T) = new(format, nothing)     #, undef, undef
    Leaf(args...)   = new(T(args...), nothing) #, undef, undef
end
Leaf{T}(format::T) = Leaf{T}(format)

isequal(x::Leaf, y::Leaf) = isequal(x.format, y.format)


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

valueof(node::Leaf)   = node.format
valueof(node::ExNode) = ExValue(node.format, node.args)

is_emittable(ex) = true


exnode(value::ExValue) = ExNode(value.format, value.args)

leaf(value) = Leaf(value)

end ############################################################


end # module
