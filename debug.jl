
module Debug
using Base
import Base.promote_rule
import Base.ref, Base.assign, Base.has
export trap, instrument, analyze, @debug, Scope, graft, debug_eval, @show
export Leaf, Line, Sym, Block

macro show(ex)
    quote
        print($(string(ex,"\t= ")))
        show($(esc(ex)))
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

const dict_comprehension        = symbol("dict-comprehension")
const typed_comprehension       = symbol("typed-comprehension")
const typed_dict                = symbol("typed-dict")
const typed_dict_comprehension  = symbol("typed-dict-comprehension")

const untyped_comprehensions = [:comprehension, dict_comprehension]
const typed_comprehensions =   [typed_comprehension, typed_dict_comprehension]


# ---- analyze ----------------------------------------------------------------

## Env: analysis-time scope ##
type Env
    parent::Union(Env,Nothing)
    defined::Set{Symbol}
    assigned::Set{Symbol}
    processed::Bool  # todo: better way to handle assigned pass?
end
child(env) = Env(env, Set{Symbol}(), Set{Symbol}(), false)
function has(env::Env, sym::Symbol) 
    has(env.defined, sym) || (isa(env.parent, Env) && has(env.parent, sym))
end

# -- Extended AST nodes that can be produced by decorate in addition to Expr --
type Block;    args::Vector; env::Env;          end # :block with Env
type Sym;      ex::Symbol;   env::Env;          end # Symbol with Env
type Leaf{T};  ex::T;                           end # Unexpanded node
type Line{T};  ex::T; line::Int; file::String;  end
Line{T}(ex::T, line, file) = Line{T}(ex, line, string(file))
Line{T}(ex::T, line)       = Line{T}(ex, line, "")
get_head(ex::Block) = :block
get_head(ex::Expr)  = ex.head

# ---- decorate() node visit states ----
abstract State
abstract SimpleState <: State
promote_rule{S<:State,T<:State}(::Type{S},::Type{T}) = State

type Def      <: SimpleState;  env::Env;  end  # definition, e.g. inside local
type Lhs      <: SimpleState;  env::Env;  end  # e.g. to the left of =
type Rhs      <: SimpleState;  env::Env;  end  # plain evaluation
type Typ      <: SimpleState;  env::Env;  end  # inside type. todo: better way?
# Sig: :call/:curly node in e.g. function f(x) ... / f(x) = ...
type Sig      <: State;  s::SimpleState; inner::Env;  end
# SplitDef: Def with different scopes for left and right side, e.g.
# let x_inner = y_outer
# type T_outer{S_inner} <: Q
type SplitDef <: State;  ls::Env;        rs::Env;     end

# decorate and propagate source file info among Line's
function analyze(ex)
    node = decorate(Rhs(child(nothing)), ex)
    set_source!(node, "")
    node
end

# ---- decorate: rewrite AST to include scoping info ----
function decorate(states::Vector, args::Vector) 
    {decorate(s, arg) for (s, arg) in zip(states, args)}
end
decorate(states::Vector, ex::Expr) = expr(ex.head, decorate(states, ex.args))

decorate(s::State,       ex)                 = Leaf(ex)
decorate(s::SimpleState, ex::LineNumberNode) = Line(ex, ex.line)
decorate(s::SimpleState, ex::SymbolNode)     = decorate(s, ex.name)
decorate(s::Def, ex::Symbol) = (add(s.env.defined,  ex); Sym(ex,s.env))
decorate(s::Lhs, ex::Symbol) = (add(s.env.assigned, ex); Sym(ex,s.env))
decorate(s::SimpleState, ex::Symbol) = Sym(ex,s.env)

decorate(s::SplitDef, ex) = decorate(Def(s.ls), ex)
function decorate(s::SplitDef, ex::Expr)
    head, nargs = ex.head, length(ex.args)
    if     head === :(=);   decorate([Def(s.ls), Rhs(s.rs)],                ex)
    elseif head === :(<:);  decorate([s,         Rhs(s.rs)],                ex)
    elseif head === :curly; decorate([s,         fill(Def(s.rs), nargs-1)], ex)
    else                    decorate(Def(s.ls), ex)
    end
end

function decorate(s::Sig, ex::Expr)
    @assert contains([:call, :curly], ex.head)
    if is_expr(ex.args[1], :curly) first = s;
    else; first = (isa(s.s,Def) ? s.s : Lhs(s.s.env));
    end
    states = [first, fill(Def(s.inner), length(ex.args)-1)]
    decorate(states, ex)
end

function decorate(s::Typ, ex::Expr)
    head, args = ex.head, ex.args
    if contains([:function, :(=)], head) && is_expr(args[1], :call)
        decorate(Def(s.env), ex)
    else
        # This will disable all scoping, defining and assigning
        # in the body of the type not caused by method definitions.
        # Todo: How should e.g. a while loop in a type body be treated?
        states = fill(s, length(args))
        if head === :block; Block(decorate(states, args), s.env)
        else                decorate(states, ex)
        end
    end
end

function argstates(state::SimpleState, head, args)
    e, nargs = state.env, length(args)
    if contains([:function, :(=)], head) && is_expr(args[1], :call)
        inner = child(e)
        [Sig(state, inner), Rhs(inner)]
    elseif contains([:function, :(->)], head)
        inner = child(e); [Def(inner), Rhs(inner)]
        
    elseif contains([:global, :local], head); fill(Def(e), nargs)
    elseif head === :while;                [Rhs(e), Rhs(child(e))]
    elseif head === :try; ec = child(e);   [Rhs(child(e)), Def(ec),Rhs(ec)]
    elseif head === :for; inner = child(e);[SplitDef(inner,e), Rhs(inner)]
    elseif contains([untyped_comprehensions, :let], head); inner = child(e); 
        [Rhs(inner), fill(SplitDef(inner,e), nargs-1)]
    elseif contains(typed_comprehensions, head); inner = child(e)
        [Rhs(e), Rhs(inner), fill(SplitDef(inner,e), nargs-2)]
        
    elseif head === :(=);   [(isa(state,Def) ? state : Lhs(e)), Rhs(e)]
    elseif head === :(<:);  [(isa(state,Def) ? state : Rhs(e)), Rhs(e)]
    elseif head === :tuple; fill(state,  nargs)
    elseif head === :ref;   fill(Rhs(e), nargs)
    elseif head === :(...); [state]
    elseif head === :(::) && nargs == 1; [Rhs(e)]
    elseif head === :(::) && nargs == 2; [state, Rhs(e)]

    # I'm guessing abstract and typealias wrap their args in one scope,
    # except the actual name to be defined
    elseif head === :abstract;  inner=child(e); [SplitDef(e,inner)]
    elseif head === :type;      inner=child(e); [SplitDef(e,inner), Typ(inner)]
    elseif head === :typealias; inner=child(e); [SplitDef(e,inner), Rhs(inner)]

    else fill(Rhs(e), nargs)
    end
end

function decorate(state::SimpleState, ex::Expr)
    head, args  = ex.head, ex.args
    if head === :line;                                 return Line(ex, args...)
    elseif contains([:quote, :top, :macrocall], head); return Leaf(ex)
    end

    states = argstates(state, head, args)
    if head === :block; Block(decorate(states, args), state.env)
    else                decorate(states, ex)
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

instrument(ex) = add_traps((nothing,quot(NoScope())), analyze(ex))

add_traps(env, node::Union(Leaf,Sym,Line)) = node.ex
function add_traps(env, ex::Expr)
    expr(ex.head, {add_traps(env, arg) for arg in ex.args})
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
function add_traps(env, ex::Block)
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
        push(code, add_traps(env, arg))
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
