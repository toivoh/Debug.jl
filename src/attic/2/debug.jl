
module Debug
using Base
export instrument, trap, translate, argpositions, LHS, RHS, DEF

macro show(ex)
    quote
        print($(string(ex,"\t=")))
        show($ex)
    end
end


trap(args...) = error("No debug trap installed for ", typeof(args))

# ---- Helpers ----------------------------------------------------------------

quot(ex) = expr(:quote, ex)

is_expr(ex, head::Symbol) = (isa(ex, Expr) && (ex.head == head))
is_expr(ex, head::Symbol, n::Int) = is_expr(ex, head) && length(ex.args) == n

is_linenumber(ex::LineNumberNode) = true
is_linenumber(ex::Expr)           = is(ex.head, :line)
is_linenumber(ex)                 = false

get_linenumber(ex::Expr)           = ex.args[1]
get_linenumber(ex::LineNumberNode) = ex.line


# ----- Analysis --------------------------------------------------------------

abstract Head
type Exp <: Head
    head::Symbol
end
toast(head::Exp, args) = expr(head.head, args...)

type Leaf <: Head
    value
end
toast(head::Leaf, args) = (@assert length(args)==0; head.value)

type Node{T<:Head}
    head::T
    args::Vector{Node}
end
Node{T<:Head}(head::T)       = Node{T}(head, Node[])
Node{T<:Head}(head::T, args) = Node{T}(head, Node[args...])

function translate(ex::Expr)
    if contains([:line, :quote, :top, :macrocall], ex.head); Node(Leaf(ex));
    else; Node(Exp(ex.head), {translate(arg) for arg in ex.args})
    end
end
translate(ex) = Node(Leaf(ex))





typealias Position Symbol
const DEF = :def
const LHS = :lhs
const RHS = :rhs

const doublecolon = symbol("::")
const typed_comprehension = symbol("typed-comprehension")
const comprehensions = [:comprehension, typed_comprehension]

# ---- argpositions: give the Position of each node arg -----------------------

argpositions(ex::Expr) = argpositions(ex, RHS)
argpositions(ex::Expr, pos::Position) = argpositions(ex.head, ex.args, pos)

function argpositions(head::Symbol, args::Vector, pos::Position)
    nargs = length(args)
    positions = argpositions(head, nargs, pos)
    npos = length(positions)

    if     nargs < npos; error("Too few args for $head")
    elseif nargs > npos; [positions, fill(positions[end], nargs-npos)]
    else positions
    end    
end

function argpositions(head::Symbol, nargs::Int, pos::Position)
    @assert contains([RHS,LHS,DEF], pos)
    if pos == RHS
        if     head === :(=);  [LHS, RHS]
        elseif head === :for;  [DEF, RHS]
        elseif head === :let;  [RHS, DEF]
        elseif head === :try;  [RHS, DEF, RHS]

        elseif contains([:global, :local], head); [DEF]
        elseif head === :comprehension;           [RHS, DEF]
        elseif head === typed_comprehension;      [RHS, RHS, DEF]

        elseif head === :abstract;  [DEF]
        elseif head === :type;      [DEF, DEF]
        elseif head === :typealias; [DEF, RHS]
        elseif head === :function;  [DEF, RHS]
        elseif head === :(->);      [DEF, RHS]

        else [RHS]
        end
    else
        if     head === doublecolon; nargs == 2 ? [pos, RHS] : [RHS]
        elseif head === :tuple; [pos]
        elseif head === :call;  [LHS, DEF]
        elseif head === :ref;   [RHS]
        else
            error("Don't know how to handle $head in pos $pos")
        end        
    end
end

# ---- enscope ----------------------------------------------------------------

type Env
    parent::Union{nothing, Env}
    defined::Set{Symbol}
    assigned::Set{Symbol}
end
Env() = Env(nothing, Set{Symbol}(), Set{Symbol}())

enscope(ex) = enscope(Env(), ex, RHS)
enscope(env::Env, ex, pos::Position) = ex

function enscope(ex::Expr, pos::Position)
    
    argpos = argpositions(ex, pos)
    
end



# ---- old ----

type NodeData
    pos::Position
    NodeData() = new()
end

abstract Node
type INode <: Node
    head::Symbol
    args::Vector
    data::NodeData

    INode(head, args) = new(head, args, NodeData())
end
type LeafNode <: Node
    value
    data::NodeData

    LeafNode(value) = new(value, NodeData())
end

function translate(ex::Expr)
    if contains([:line, :quote, :top, :macrocall], ex.head); LeafNode(ex);
    else; INode(ex.head, {translate(arg) for arg in ex.args})
    end
end
translate(ex) = LeafNode(ex)


mark_pos!(nodes, s::Position) = (for node in nodes; mark_pos!(node, s); end)
function mark_pos!(node::Node, pos::Position)
    node.pos = pos
    mark_args_pos!(node, pos)
end

mark_args_pos!(::LeafNode, ::Position) = nothing
function mark_args_pos!(node::INode, pos::Position)
    head, args = node.head, node.args
    if pos == RHS
        if head === :(=)
            mark_pos!(args[1], LHS)
            mark_pos!(args[2], RHS)
        elseif contains([:global, :local], head)
            mark_pos!(args, DEF)
        elseif contains([:function, :for, :(->)], head)
            mark_pos!(args[1], DEF)
            mark_pos!(args[2], RHS)
        elseif head === :let
            mark_pos!(args[2:end], DEF)
            mark_pos!(args[1], RHS)
        elseif head == :try
            mark_pos!(args[[1,3]], RHS)
            mark_pos!(args[2], DEF)
        elseif contains([:abstract, :type, :typealias], head)
            mark_pos!(args[1], DEF)
        elseif contains(comprehensions, head)
            if head === typed_comprehension
                mark_pos!(args[1], RHS)
                args = args[2:end]
            end
            mark_pos!(args[1], RHS)
            mark_pos!(args[2:end], DEF)
        else
            mark_pos!(args, RHS)
        end
    elseif contains([LHS, DEF], pos)
        if head === doublecolon
            mark_pos!(args[1], pos)
            mark_pos!(args[2], RHS)
        elseif head === :tuple
            mark_pos!(args, pos)
        elseif head === :call
            mark_pos!(args[1], LHS)
            mark_pos!(args[2:end], DEF)            
        elseif head === :getindex
            mark_pos!(args, RHS)
        else
            error("Don't know how to handle $node in pos $pos")
        end
    else
        error()
    end
end


# ---- instrument -------------------------------------------------------------

type Context
    line::Int
    file::String
end
Context() = Context(0, "")

instrument(ex) = instrument(Context(), ex)

instrument(c::Context, ex) = ex
function instrument(c::Context, ex::Expr)
    head, args = ex.head, ex.args
    if contains([:line, :quote, :top, :macrocall, :type], head)
        ex
    elseif head === :block
        code = {}
        for arg in args
            if is_linenumber(arg)
                c.line = get_linenumber(arg)
                if is_expr(arg, :line, 2); c.file = arg.args[2]; end
                
                push(code, arg)
            else
                push(code, :($(quot(trap))($(c.line), $(quot(c.file)))) )
                push(code, instrument(arg))
            end
        end
        expr(head, code)
    else
        expr(head, {instrument(arg) for arg in args})
    end
end

end # module