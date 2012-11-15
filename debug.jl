
module Debug
using Base
export trap, instrument, translate, propagate!, NoScope

macro show(ex)
    quote
        print($(string(ex,"\t=")))
        show($ex)
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
    if n < length(v); error("replicate_last: cannot shrink v!"); end
    [v, fill(v[end], n-length(v))]
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
    file::String
    ex
end
#is_expr(node::Node{Exp}, head::Symbol) = node.head.head == head
toAST(head::Head,  args) = (@assert length(args)==0; toAST(head))
toAST(head::Exp,   args) = expr(head.head, args...)
toAST(head::Block, args) = expr(:block, args...)
toAST(head::Leaf)        = head.value
toAST(head::LineNumber)  = head.ex


translate(ex) = translate("", ex)
translate(file::String, ex) = Node(Leaf(ex))
function translate(file::String, ex::Expr)
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

# ---- Scope analysis ---------------------------------------------------------

function argtraits(node::Node, trait)
    traits = argtraits(node.head, trait)
    if length(traits) == 0; fill(trait, length(node.args))
    else                    replicate_last(traits, length(node.args))
    end
end
function propagate!(n::Node, trait)
    for (arg, t) in zip(n.args, argtraits(n, trait)); propagate!(arg, t); end
end


type NoScope    <: Scope; end
type LocalScope <: Scope
    parent::Scope
    defined::Set{Symbol}
    assigned::Set{Symbol}
end
child(s::Scope) = LocalScope(s, Set{Symbol}(), Set{Symbol}())

argtraits(head::Head, s::Scope) = []
function argtraits(head::Exp, s::Scope)
    if head === :while; [s, child(s)]
    elseif contains([:(->), :comprehension, :typed_comprehension], head); [s]
    elseif head === :try; scatch = child(s); [child(s), scatch, scatch]
    else []
    end
end


# ---- instrument -------------------------------------------------------------

instrument(ex) = instrument(translate(ex))

instrument(n::Node) = toAST(n.head, {instrument(arg) for arg in n.args})
function instrument(node::Node{Block})
    code = {}
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
