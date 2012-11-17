
module Debug
using Base
import Base.promote_rule
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
end
child(s) = Scope(s, Set{Symbol}(), Set{Symbol}())

type Block
    args::Vector
    scope::Scope
end
type Leaf{T};  ex::T;                           end
type Line{T};  ex::T; line::Int; file::String;  end
Line{T}(ex::T, line, file) = Line{T}(ex, line, string(file))
Line{T}(ex::T, line)       = Line{T}(ex, line, "")

abstract State
abstract SimpleState <: State
type Def <: SimpleState;  scope::Scope;  end
type Lhs <: SimpleState;  scope::Scope;  end
type Rhs <: SimpleState;  scope::Scope;  end
type SplitDef <: State;  ls::Scope; rs::Scope;  end
promote_rule{S<:State,T<:State}(::Type{S},::Type{T}) = State

function analyze(ex)
    node = analyze1(Rhs(child(nothing)), ex)
    set_source!(node, "")
    node
end

function analyze1(states::Vector, args::Vector) 
    {analyze1(s, arg) for (s, arg) in zip(states, args)}
end
analyze1(states::Vector, ex) = expr(ex.head, analyze1(states, ex.args))
analyze1(s::State,       ex)                 = Leaf(ex)
analyze1(s::SimpleState, ex::LineNumberNode) = Line(ex, ex.line)
analyze1(s::Def, ex::Symbol) = (add(s.scope.defined,  ex); Leaf(ex))
analyze1(s::Lhs, ex::Symbol) = (add(s.scope.assigned, ex); Leaf(ex))

analyze1(s::SplitDef, ex) = analyze1(Def(s.ls), ex)
function analyze1(s::SplitDef, ex::Expr)
    if (ex.head === :(=)) analyze1([Def(s.ls), Rhs(s.rs)], ex)
    else                  analyze1(Def(s.ls), ex)
    end
end

function argstates(state::SimpleState, head, args)
    s, nargs = state.scope, length(args)
    if contains([:function, :(=)], head) && is_expr(args[1], :call)
        inner = child(s)
        {[Lhs(s), fill(Def(inner), length(args[1].args)-1)],Rhs(inner)}
    elseif contains([:function, :(->)], head)
        inner = child(s); [Def(inner), Rhs(inner)]
        
    elseif contains([:global, :local], head); fill(Def(s), nargs)
    elseif head === :while;                [Rhs(s), Rhs(child(s))]
    elseif head === :try; sc = child(s);   [Rhs(child(s)), Def(sc),Rhs(sc)]
    elseif head === :for; inner = child(s);[SplitDef(inner,s), Rhs(inner)]
    elseif contains([:let, :comprehension], head); inner = child(s); 
        [Rhs(inner), fill(SplitDef(inner,s), nargs-1)]
    elseif head === typed_comprehension; inner = child(s)
        [Rhs(inner), Rhs(inner), fill(SplitDef(inner,s), nargs-2)]
        
    elseif head === :(=);   [(isa(state,Def) ? state : Lhs(s)), Rhs(s)]
    elseif head === :tuple; fill(state,  nargs)
    elseif head === :ref;   fill(Rhs(s), nargs)
    elseif head === doublecolon && nargs == 1; [Rhs(s)]
    elseif head === doublecolon && nargs == 2; [state, Rhs(s)]
    else fill(Rhs(s), nargs)
    end
end

function analyze1(state::SimpleState, ex::Expr)
    head,  args  = ex.head, ex.args
    if head === :line; return Line(ex, ex.args...)
    elseif contains([:quote, :top, :macrocall, :type], head); return Leaf(ex)
    end

    states = argstates(state, head, args)
    if head === :block; Block(analyze1(states, args), state.scope)
    else                analyze1(states, ex)
    end
end

set_source!(ex,       file::String) = nothing
set_source!(ex::Line, file::String) = (ex.file = file)
function set_source!(ex::Union(Expr,Block), file::String)
    for arg in ex.args
        if isa(arg, Line) && arg.file != ""; file = arg.file; end
        set_source!(arg, file)
    end
end


# ---- instrument -------------------------------------------------------------

instrument(ex) = instrument_((nothing,quot(nothing)), analyze(ex))

instrument_(env, node::Union(Leaf,Line)) = node.ex
function instrument_(env, ex::Expr)
    expr(ex.head, {instrument_(env, arg) for arg in ex.args})
end
function instrument_(env, ex::Block)
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
    
    for arg in ex.args
        push(code, instrument_(env, arg))
        if isa(arg, Line)
            push(code, :($(quot(trap))($(arg.line), $(quot(arg.file)),
                                       $(env[2]))) )
        end
    end
    expr(:block, code)
end

end # module
