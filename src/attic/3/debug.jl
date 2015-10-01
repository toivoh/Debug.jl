
module Debug
using Base
export trap, instrument, translate, propagate!, NoScope, RHS, LHS, DEF, analyze
import Base.promote_rule

macro show(ex)
    quote
        print($(string(ex,"\t= ")))
        show($ex)
        println()
    end
end


trap(args...) = error("No debug trap installed for ", typeof(args))


# ---- Helpers ----------------------------------------------------------------

quot(ex) = expr(:quote, ex)

is_expr(ex,       head::Symbol)   = false
is_expr(ex::Expr, head::Symbol)   = ex.head == head
is_expr(ex, head::Symbol, n::Int) = is_expr(ex, head) && length(ex.args) == n

is_linenumber(ex::LineNumberNode) = true
is_linenumber(ex::Expr)           = is(ex.head, :line)
is_linenumber(ex)                 = false

is_file_linenumber(ex)            = is_expr(ex, :line, 2)

get_linenumber(ex::Expr)           = ex.args[1]
get_linenumber(ex::LineNumberNode) = ex.line
get_sourcefile(ex::Expr)           = string(ex.args[2])

const doublecolon = symbol("::")
const typed_comprehension = symbol("typed-comprehension")


function replicate_last{T}(v::Vector{T}, n)
    if n < length(v)-1; error("replicate_last: cannot shrink v more!"); end
    [v[1:end-1], fill(v[end], n+1-length(v))]
end


# ---- translate --------------------------------------------------------------

abstract Scope

abstract Head
type Node{T<:Head}
    head::T
    args::Vector
    scope::Scope

    Node(head::T, args::Vector) = new(head, args)
end
Node{T<:Head}(head::T)       = Node{T}(head, Node[])
Node{T<:Head}(head::T, args) = Node{T}(head, Node[args...])


type Exp        <: Head;  head::Symbol;  end
type Block      <: Head; end
type Leaf{T}    <: Head;  value::T;      end
type LineNumber <: Head
    line::Int
    file::AbstractString
    ex
end
#is_expr(node::Node{Exp}, head::Symbol) = node.head.head == head
toAST(head::Head,  args) = (@assert length(args)==0; toAST(head))
toAST(head::Exp,   args) = expr(head.head, args...)
toAST(head::Block, args) = expr(:block, args...)
toAST(head::Leaf)        = head.value
toAST(head::LineNumber)  = head.ex


translate(ex) = translate("", ex)
translate(file::AbstractString, ex) = Node(Leaf(ex))
function translate(file::AbstractString, ex::Expr)
    head, args = ex.head, ex.args
    if is_expr(ex, :block)
        Node(Block(), { begin
                if is_file_linenumber(arg); file = get_sourcefile(arg); end
                translate(file, arg)
             end for arg in args })
    elseif contains([:quote, :top, :macrocall, :type], head); Node(Leaf(ex))
    elseif is_linenumber(ex); Node(LineNumber(get_linenumber(ex), file, ex))
    else Node(Exp(head), {translate(file, arg) for arg in args})
    end
end

# ---- Analysis ---------------------------------------------------------------

function argtraits(node::Node, trait)
    traits = argtraits(node.head, length(node.args), trait)
    if length(traits) == 0; fill(trait, length(node.args))
    else                    replicate_last(traits, length(node.args))
    end
end
argtraits(head::Head, nargs::Int, trait) = argtraits(head, trait)
argtraits(head::Head, trait)             = []
function propagate!(n::Node, trait)
    apply_trait!(n, trait)
    for (arg, t) in zip(n.args, argtraits(n, trait)); propagate!(arg, t); end
end

# ---- Scopes ----
type NoScope    <: Scope; end
add_defined( scope::NoScope, s::Symbol) = nothing
add_assigned(scope::NoScope, s::Symbol) = nothing

type LocalScope <: Scope
    parent::Scope
    defined::Set{Symbol}
    assigned::Set{Symbol}
end
add_defined( scope::LocalScope, s::Symbol) = add(scope.defined,  s)
add_assigned(scope::LocalScope, s::Symbol) = add(scope.assigned, s)

promote_rule{S<:Scope,T<:Scope}(::Type{S}, ::Type{T}) = Scope
child(s::Scope) = LocalScope(s, Set{Symbol}(), Set{Symbol}())


function argtraits(h::Exp, s::Scope)
    head = h.head
    if head === :while; [s, child(s)]
    elseif contains([:(->), :comprehension, :typed_comprehension], head); [s]
    elseif head === :try; scatch = child(s); [child(s), scatch, scatch]
    else []
    end
end
apply_trait!(node::Node, s::Scope) = (node.scope = s)

# ---- Position ----
typealias Position Symbol
const DEF = :def
const LHS = :lhs
const RHS = :rhs

function argtraits(h::Exp, nargs::Int, pos::Position)
    head = h.head
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
        elseif head === :(=);   [pos, RHS]
        elseif head === :tuple; [pos]
        elseif head === :call;  [LHS, DEF]
        elseif head === :ref;   [RHS]
        else
            error("Don't know how to handle $head in pos $pos")
        end        
    end    
end

apply_trait!(node::Node, pos::Position) = Nothin
function apply_trait!(node::Node{Leaf{Symbol}}, pos::Position)
    if     pos == DEF; add_defined( node.scope, node.head.value)
    elseif pos == LHS; add_assigned(node.scope, node.head.value)
    end
end

# ---- instrument -------------------------------------------------------------

function analyze(ex)
    node = translate(ex)
    propagate!(node, NoScope())
    propagate!(node, RHS)
    node
end

instrument(ex) = instrument(analyze(ex))

instrument(n::Node) = toAST(n.head, {instrument(arg) for arg in n.args})
function instrument(node::Node{Block})
    code = {}
    push(code, quot(node.scope))
    for arg in node.args
        push(code, instrument(arg))
        h = arg.head
        if isa(h, LineNumber)
            push(code, :($(quot(trap))($(h.line), $(quot(h.file)))) )
        end
    end
    expr(:block, code)
end

end # module
