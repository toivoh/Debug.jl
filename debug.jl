
module Debug
using Base
export trap, instrument, analyze

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


# ---- analyze ----------------------------------------------------------------

type Scope
    parent::Union(Scope,Nothing)
#    defined::Set{Symbol}
#    assigned::Set{Symbol}
    
#    Scope(parent) = new(parent, Set{Symbol}(), Set{Symbol}())
end
child(s::Scope) = Scope(s)

type Node
    head::Symbol
    args::Vector
    scope::Scope
    Node(head, args, scope) = new(head, args, scope)
    Node(head, args)        = new(head, args)
end
type Leaf{T};  ex::T;                           end
type Line{T};  ex::T; line::Int; file::String;  end
Line{T}(ex::T, line, file) = Line{T}(ex, line, string(file))
Line{T}(ex::T, line)       = Line{T}(ex, line, "")

analyze(ex) = (node = analyze1(Scope(nothing),ex); set_source!(node, ""); node)

analyze1(s::Scope, ex)                 = Leaf(ex)
analyze1(s::Scope, ex::LineNumberNode) = Line(ex, ex.line, "")
function analyze1(s::Scope, ex::Expr)
    head, args = ex.head, ex.args
    if head === :line; return Line(ex, ex.args...)
    elseif contains([:quote, :top, :macrocall, :type], head); return Leaf(ex)
    end    
    if head === :while
        newargs = {analyze1(s, args[1]), analyze1(child(s), args[2])}
    elseif head === :try
        stry, scatch = child(s), child(s)
        newargs = {analyze1(stry, args[1]),
            analyze1(scatch, args[2]), analyze1(scatch, args[3])}
    elseif head === :for
        inner = child(s)
        newargs = {analyze1_split(inner, s, args[1]), analyze1(inner, args[2])}
    else
        newargs = {analyze1(s, arg) for arg in args}
    end
    Node(head, newargs, s)
end

analyze1_split(ls, rs::Scope, ex) = analyze1(ls, ex)
function analyze1_split(ls, rs::Scope, ex::Expr)
    if ex.head === :(=)
        Node(:(=), {analyze1(ls, ex.args[1]), analyze1(rs, ex.args[2])})
    else
        analyze1(ls, ex)
    end
end

set_source!(ex,       file::String) = nothing
set_source!(ex::Line, file::String) = (ex.file = file)
function set_source!(ex::Node, file::String)
    for arg in ex.args
        if isa(arg, Line) && arg.file != ""; file = arg.file; end
        set_source!(arg, file)
    end
end


# ---- instrument -------------------------------------------------------------

instrument(ex) = instrument_(analyze(ex))

instrument_(node::Union(Leaf,Line)) = node.ex
function instrument_(ex::Node)
    head, args = ex.head, ex.args
    if head === :block
        code = {}
        for arg in args
            push(code, instrument_(arg))
            if isa(arg, Line)
                push(code, :($(quot(trap))($(arg.line), $(quot(arg.file)))) )
            end
        end
        expr(head, code)
    else
        expr(head, {instrument_(arg) for arg in args})
    end
end

end # module
