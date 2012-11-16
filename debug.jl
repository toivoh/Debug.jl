
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
   defined::Set{Symbol}
   assigned::Set{Symbol}
    
   Scope(parent) = new(parent, Set{Symbol}(), Set{Symbol}())
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

typealias Pos Symbol
const DEF = :def
const LHS = :lhs
const RHS = :rhs

analyze(ex) = (node = analyze1(Scope(nothing),RHS,ex); set_source!(node, ""); node)

analyze1(s::Scope, pos::Pos, exs::Vector) = {analyze1(s,pos,ex) for ex in exs}
analyze1(s::Scope, pos::Pos, ex)                 = Leaf(ex)
analyze1(s::Scope, pos::Pos, ex::LineNumberNode) = Line(ex, ex.line, "")
function analyze1(s::Scope, pos::Pos, ex::Symbol)
    if     pos == DEF; add(s.defined,  ex)
    elseif pos == LHS; add(s.assigned, ex)
    end
    Leaf(ex)
end
function analyze1(s::Scope, pos::Pos, ex::Expr)
    head, args = ex.head, ex.args

    # non-Node results
    if head === :line; return Line(ex, ex.args...)
    elseif contains([:quote, :top, :macrocall, :type], head); return Leaf(ex)
    end    

    # special cases
    if contains([:function, :(=)], head) && is_expr(args[1], :call)
        inner     = child(s)
        sig, body = args
        return Node(head, {Node(:call, { analyze1(s,     LHS, sig.args[1]), 
                                   analyze1(inner, DEF, sig.args[2:end])... }),
                           analyze1(inner, RHS, body)}, s)
    elseif head === :for
        inner = child(s)
        return Node(:for, {analyze1_split(inner, s, args[1]), 
                           analyze1(inner, RHS, args[2])}, s)
    elseif contains([:let, :comprehension], head)
        return Node(head, analyze1_letargs(s, child(s), args), s)
    elseif head === typed_comprehension
        inner = child(s)        
        return Node(head, {analyze1(inner, RHS, args[1]),
                           analyze1_letargs(s, inner, args[2:end])...}, s)
    end

    nargs = length(args)
    sp = begin
        if     head === :while; [(s,RHS), (child(s),RHS)]
        elseif head === :try; sc = child(s); [(child(s),RHS),(sc,DEF),(sc,RHS)]
        elseif head === :(->); inner = child(s); [(inner,DEF), (inner,RHS)]
        elseif contains([:global, :local], head); fill((s,DEF), nargs)
        elseif head === :(=); [(s,(pos==DEF) ? DEF : LHS), (s,RHS)]
        elseif head === doublecolon && nargs == 1; [(s,RHS)]
        elseif head === doublecolon && nargs == 2; [(s,pos), (s,RHS)]
        elseif head === :tuple; fill((s,pos), nargs)
        elseif head === :ref;   fill((s,RHS), nargs)
        elseif head === :function; inner = child(s); [(inner,DEF), (inner,RHS)]
        else fill((s,RHS), nargs)
        end
    end
    Node(head, {analyze1(sa, pos, arg) for ((sa,pos),arg) in zip(sp,args)}, s)
end

function analyze1_letargs(outer::Scope, inner::Scope, args::Vector)
    return {analyze1(inner, RHS, args[1])
            {analyze1_split(inner, outer, arg) for arg in args[2:end]}...}
end

analyze1_split(ls, rs::Scope, ex) = analyze1(ls, DEF, ex)
function analyze1_split(ls, rs::Scope, ex::Expr)
    if ex.head === :(=)
        Node(:(=), {analyze1(ls,DEF,ex.args[1]), analyze1(rs,RHS,ex.args[2])})
    else
        analyze1(ls, DEF, ex)
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

instrument(ex) = instrument_((nothing,quot(nothing)), analyze(ex))

instrument_(env, node::Union(Leaf,Line)) = node.ex
function instrument_(env, ex::Node)
    head, args = ex.head, ex.args
    if head === :block
        code = {}
        outer_scope, outer_name = env
        s = ex.scope
        syms = Set{Symbol}()
        while !is(s, outer_scope)
            add_each(syms, s.defined)
            add_each(syms, s.assigned)
            s = s.parent
        end
        if isempty(syms)
            env = (ex.scope, outer_name)
        else
            name = gensym("scope")
            push(code, :( $name = {$({quot(sym) for sym in syms}...)} ))
            env = (ex.scope, name)
        end

        for arg in args
            push(code, instrument_(env, arg))
            if isa(arg, Line)
                push(code, :($(quot(trap))($(arg.line), $(quot(arg.file)),
                             $(env[2]))) )
            end
        end
        expr(head, code)
    else
        expr(head, {instrument_(env, arg) for arg in args})
    end
end

end # module
