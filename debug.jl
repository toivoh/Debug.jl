
module Debug
using Base
export instrument, trap, translate, argstates, LHS, RHS, DEF

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

typealias State Symbol
const DEF = :def
const LHS = :lhs
const RHS = :rhs


type NodeData
    state::State
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


mark_state!(nodes, s::State) = (for node in nodes; mark_state!(node, s); end)
function mark_state!(node::Node, state::State)
    node.state = state
    mark_args_state!(node, state)
end

const doublecolon = symbol("::")
const typed_comprehension = symbol("typed-comprehension")
const comprehensions = [:comprehension, typed_comprehension]

argstates(ex::Expr) = argstates(ex, RHS)
argstates(ex::Expr, state::State) = argstates(ex.head, ex.args, state)

function argstates(head::Symbol, args::Vector, state::State)
    nargs = length(args)
    states = argstates(head, nargs, state)
    nstates = length(states)

    if     nargs < nstates; error("Too few args for $head")
    elseif nargs > nstates; [states, fill(states[end], nargs-nstates)]
    else states
    end    
end

function argstates(head::Symbol, nargs::Int, state::State)
    @assert contains([RHS,LHS,DEF], state)
    if state == RHS
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
        if     head === doublecolon; nargs == 2 ? [state, RHS] : [RHS]
        elseif head === :tuple; [state]
        elseif head === :call;  [LHS, DEF]
        elseif head === :ref;   [RHS]
        else
            error("Don't know how to handle $head in state $state")
        end        
    end
end

mark_args_state!(::LeafNode, ::State) = nothing
function mark_args_state!(node::INode, state::State)
    head, args = node.head, node.args
    if state == RHS
        if head === :(=)
            mark_state!(args[1], LHS)
            mark_state!(args[2], RHS)
        elseif contains([:global, :local], head)
            mark_state!(args, DEF)
        elseif contains([:function, :for, :(->)], head)
            mark_state!(args[1], DEF)
            mark_state!(args[2], RHS)
        elseif head === :let
            mark_state!(args[2:end], DEF)
            mark_state!(args[1], RHS)
        elseif head == :try
            mark_state!(args[[1,3]], RHS)
            mark_state!(args[2], DEF)
        elseif contains([:abstract, :type, :typealias], head)
            mark_state!(args[1], DEF)
        elseif contains(comprehensions, head)
            if head === typed_comprehension
                mark_state!(args[1], RHS)
                args = args[2:end]
            end
            mark_state!(args[1], RHS)
            mark_state!(args[2:end], DEF)
        else
            mark_state!(args, RHS)
        end
    elseif contains([LHS, DEF], state)
        if head === doublecolon
            mark_state!(args[1], state)
            mark_state!(args[2], RHS)
        elseif head === :tuple
            mark_state!(args, state)
        elseif head === :call
            mark_state!(args[1], LHS)
            mark_state!(args[2:end], DEF)            
        elseif head === :ref
            mark_state!(args, RHS)
        else
            error("Don't know how to handle $node in state $state")
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