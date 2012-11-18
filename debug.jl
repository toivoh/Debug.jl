
module Debug
using Base
import Base.promote_rule
import Base.ref, Base.assign, Base.has
export trap, instrument, analyze, @debug, Scope, graft, debug_eval

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
const typed_dict          = symbol("typed-dict")


function replicate_last{T}(v::Vector{T}, n)
    if n < length(v)-1; error("replicate_last: cannot shrink v more!"); end
    [v[1:end-1], fill(v[end], n+1-length(v))]
end


# ---- analyze ----------------------------------------------------------------

type Env
    parent::Union(Env,Nothing)
    defined::Set{Symbol}
    assigned::Set{Symbol}
    processed::Bool
end
child(env) = Env(env, Set{Symbol}(), Set{Symbol}(), false)
function has(env::Env, sym::Symbol) 
    has(env.defined, sym) || (isa(env.parent, Env) && has(env.parent, sym))
end

type Block
    args::Vector
    env::Env
end
get_head(ex::Block) = :block
get_head(ex::Expr)  = ex.head

type Leaf{T};  ex::T;                           end
type Sym;      ex::Symbol; env::Env;            end
type Line{T};  ex::T; line::Int; file::String;  end
Line{T}(ex::T, line, file) = Line{T}(ex, line, string(file))
Line{T}(ex::T, line)       = Line{T}(ex, line, "")

abstract State
abstract SimpleState <: State
type Def <: SimpleState;  env::Env;  end
type Lhs <: SimpleState;  env::Env;  end
type Rhs <: SimpleState;  env::Env;  end
type SplitDef <: State;  ls::Env; rs::Env;  end
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
analyze1(s::SimpleState, ex::SymbolNode)     = analyze1(s, ex.name)
analyze1(s::Def, ex::Symbol) = (add(s.env.defined,  ex); Sym(ex,s.env))
analyze1(s::Lhs, ex::Symbol) = (add(s.env.assigned, ex); Sym(ex,s.env))
analyze1(s::SimpleState, ex::Symbol) = Sym(ex,s.env)

analyze1(s::SplitDef, ex) = analyze1(Def(s.ls), ex)
function analyze1(s::SplitDef, ex::Expr)
    if (ex.head === :(=)) analyze1([Def(s.ls), Rhs(s.rs)], ex)
    else                  analyze1(Def(s.ls), ex)
    end
end

function argstates(state::SimpleState, head, args)
    e, nargs = state.env, length(args)
    if contains([:function, :(=)], head) && is_expr(args[1], :call)
        inner = child(e)
        {[Lhs(e), fill(Def(inner), length(args[1].args)-1)],Rhs(inner)}
    elseif contains([:function, :(->)], head)
        inner = child(e); [Def(inner), Rhs(inner)]
        
    elseif contains([:global, :local], head); fill(Def(e), nargs)
    elseif head === :while;                [Rhs(e), Rhs(child(e))]
    elseif head === :try; ec = child(e);   [Rhs(child(e)), Def(ec),Rhs(ec)]
    elseif head === :for; inner = child(e);[SplitDef(inner,e), Rhs(inner)]
    elseif contains([:let, :comprehension], head); inner = child(e); 
        [Rhs(inner), fill(SplitDef(inner,e), nargs-1)]
    elseif head === typed_comprehension; inner = child(e)
        [Rhs(inner), Rhs(inner), fill(SplitDef(inner,e), nargs-2)]
        
    elseif head === :(=);   [(isa(state,Def) ? state : Lhs(e)), Rhs(e)]
    elseif head === :tuple; fill(state,  nargs)
    elseif head === :ref;   fill(Rhs(e), nargs)
    elseif head === doublecolon && nargs == 1; [Rhs(e)]
    elseif head === doublecolon && nargs == 2; [state, Rhs(e)]
    else fill(Rhs(e), nargs)
    end
end

function analyze1(state::SimpleState, ex::Expr)
    head,  args  = ex.head, ex.args
    if head === :line; return Line(ex, ex.args...)
    elseif contains([:quote, :top, :macrocall, :type], head); return Leaf(ex)
    end

    states = argstates(state, head, args)
    if head === :block; Block(analyze1(states, args), state.env)
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


# ---- Scope: runtime symbol table with getters and setters -------------------

abstract Scope

type NoScope <: Scope; end
has(scope::NoScope, sym::Symbol) = false

type LocalScope <: Scope
    parent::Scope
    syms::Dict
end

function has(scope::LocalScope, sym::Symbol)
    has(scope.syms, sym) || has(scope.parent, sym)
end
function get_entry(scope::LocalScope, sym::Symbol)
    has(scope.syms, sym) ? scope.syms[sym] : get_entry(scope.parent, sym)
end

get_getter(scope::LocalScope, sym::Symbol) = get_entry( scope, sym)[1]
get_setter(scope::LocalScope, sym::Symbol) = get_entry( scope, sym)[2]
ref(   scope::LocalScope,     sym::Symbol) = get_getter(scope, sym)()
assign(scope::LocalScope, x,  sym::Symbol) = get_setter(scope, sym)(x)

function code_getset(sym::Symbol)
    val = gensym(string(sym))
    :( ()->$sym, $val->($sym=$val) )
end
function code_scope(scope::Symbol, parent, syms)
    pairs = {expr(:(=>), quot(sym), code_getset(sym)) for sym in syms}
    :(local $scope = $(quot(LocalScope))($parent, $(expr(typed_dict, 
        :($(quot(Symbol))=>$(quot((Function,Function)))), pairs...))))
end


# ---- instrument -------------------------------------------------------------

instrument(ex) = instrument_((nothing,quot(NoScope())), analyze(ex))

instrument_(env, node::Union(Leaf,Sym,Line)) = node.ex
function instrument_(env, ex::Expr)
    expr(ex.head, {instrument_(env, arg) for arg in ex.args})
end
collect_syms!(syms::Set{Symbol}, ::Nothing, outer) = nothing
function collect_syms!(syms::Set{Symbol}, s::Env, outer)
    if is(s, outer); return; end
    collect_syms!(syms, s.parent, outer)
    if !s.processed
        if isa(s.parent, Env)
            s.defined  = s.defined | (s.assigned - s.parent.assigned)
            s.assigned = s.defined | s.parent.assigned
        else
            s.defined  = s.defined | s.assigned
            s.assigned = s.defined
        end
    end
    add_each(syms, s.defined)
end
function instrument_(env, ex::Block)
    syms = Set{Symbol}()
    collect_syms!(syms, ex.env, env[1])
    
    code = {}
    if isempty(syms)
        env = (ex.env, env[2])
    else
        name = gensym("env")
        push(code, code_scope(name, env[2], syms))
        env = (ex.env, name)
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


# ---- @debug -----------------------------------------------------------------

macro debug(ex)
    globalvar = esc(gensym("globalvar"))
    quote
        $globalvar = false
        try
            global $globalvar
            $globalvar = true
        end
        if !$globalvar
            error("@debug: must be applied in global scope!")
        end
        $(esc(instrument(ex)))
    end
end


# ---- debug_eval -------------------------------------------------------------

const updating_ops = {
 :+= => :+,   :-= => :-,  :*= => :*,  :/= => :/,  ://= => ://, :.//= => :.//,
:.*= => :.*, :./= => :./, :\= => :\, :.\= => :.\,  :^= => :^,   :.^= => :.^,
 :%= => :%,   :|= => :|,  :&= => :&,  :$= => :$,  :<<= => :<<,  :>>= => :>>,
 :>>>= => :>>>}

graft(s::Scope, ex) = ex
function graft(s::Scope, ex::Sym)
    sym = ex.ex
    if has(ex.env, sym) || !has(s, sym); sym
    else expr(:call, get_getter(s, sym))
    end
end
function graft(s::Scope, ex::Union(Expr, Block))
    head, args = get_head(ex), ex.args
    if head == :(=)
        lhs, rhs = args
        if isa(lhs, Sym)
            rhs = graft(s, rhs)
            sym = lhs.ex
            if has(lhs.env, sym) || !has(s, sym); return :($sym = $rhs)
            else return expr(:call, get_setter(s, sym), rhs)
            end
        elseif is_expr(lhs, :tuple)
            tup = esc(gensym("tuple"))
            return graft(s, expr(:block, 
                 :( $tup  = $rhs     ),
                {:( $dest = $tup[$k] ) for (k,dest)=enumerate(lhs.args)}...))
        elseif is_expr(lhs, :ref) || is_expr(lhs, :escape)  # pass down
        else error("graft: not implemented: $ex")       
        end  
    elseif has(updating_ops, head) # Translate updating ops, e g x+=1 ==> x=x+1
        op = updating_ops[head]
        return graft(s, :( $(args[1]) = ($op)($(args[1]), $(args[2])) ))
    elseif head === :escape 
        return ex.args[1]  # bypasses substitution
    end        
    expr(head, {graft(s,arg) for arg in args})
end
graft(s::Scope, node::Union(Leaf,Line)) = node.ex

#debug_eval(scope::Scope, ex) = eval(graft(scope, ex))
function debug_eval(scope::Scope, ex)
     ex2 = graft(scope, analyze(ex))
    # @show ex2
     eval(ex2)
#    eval(graft(scope, ex)) # doesn't work?
end

end # module
