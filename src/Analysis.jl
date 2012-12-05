
#   Debug.Analysis:
# ===================
# Scoping analysis used to support instrument and graft

module Analysis
using Base, AST, Meta
import Base.promote_rule

export analyze


# ---- Helpers ----------------------------------------------------------------

is_linenumber(ex::LineNumberNode) = true
is_linenumber(ex::Ex)             = is(headof(ex), :line)
is_linenumber(ex)                 = false

is_file_linenumber(ex)            = is_expr(ex, :line, 2)

get_linenumber(ex::Ex)             = argof(ex,1)
get_linenumber(ex::LineNumberNode) = ex.line
get_sourcefile(ex::Ex)             = string(argof(ex,2))

const dict_comprehension        = symbol("dict-comprehension")
const typed_comprehension       = symbol("typed-comprehension")
const typed_dict_comprehension  = symbol("typed-dict-comprehension")

const untyped_comprehensions = [:comprehension, dict_comprehension]
const typed_comprehensions =   [typed_comprehension, typed_dict_comprehension]


# ---- wrap(): add scoping info to AST ------------------------------------
# Rewrites AST, exchanging Expr:s and leaves for Node:s.
# Adds scope info, classifies nodes, etc.

abstract State
promote_rule{S<:State,T<:State}(::Type{S},::Type{T}) = State

abstract SimpleState <: State
type Def <: SimpleState;  env::Env;  end  # definition, e.g. inside local
type Lhs <: SimpleState;  env::Env;  end  # e.g. to the left of =
type Rhs <: SimpleState;  env::Env;  end  # plain evaluation

# TypeEnv: Env used in a type block to throw away non-method definitions 
type TypeEnv <: Env
    env::LocalEnv
end
raw(env::TypeEnv) = env.env
raw(env::Env)     = env

function wrap(states::Vector, args::Vector) 
    {wrap(s, arg) for (s, arg) in zip(states, args)}
end
wrap(s::SimpleState, ex::SymbolNode) = wrap(s, ex.name)
wrap(s::State, ex) = enwrap(s, decorate(s,ex))

enwrap(s::State, node::Node) = node
enwrap(s::State, value::ExValue) = ExNode(value.format, value.args)
enwrap(s::State, value) = Leaf(value)


decorate(states::Vector, ex::Ex) = ExValue(headof(ex), wrap(states,argsof(ex)))

decorate(s::State,       ex)                 = isa(ex, Node) ? ex : Plain(ex)
decorate(s::SimpleState, ex::LineNumberNode) = Loc(ex, ex.line)
decorate(s::Def, ex::Symbol) = (add_defined( s.env,ex); Sym(ex,raw(s.env)))
decorate(s::Lhs, ex::Symbol) = (add_assigned(s.env,ex); Sym(ex,raw(s.env)))
decorate(s::SimpleState, ex::Symbol) = Sym(ex,raw(s.env))

# SplitDef: Def with different scopes for left and right side, e.g.
# let x_inner = y_outer   or   type T_outer{S_inner} <: Q_outer
type SplitDef <: State;
    ls::Env;
    rs::Env;
end
decorate(s::SplitDef, ex) = decorate(Def(s.ls), ex)
function decorate(s::SplitDef, ex::Ex)
    head, nargs = headof(ex), nargsof(ex)
    if     head === :(=);   decorate([Def(s.ls), Rhs(s.rs)],                ex)
    elseif head === :(<:);  decorate([s,         Rhs(s.ls)],                ex)
    elseif head === :curly; decorate([s,         fill(Def(s.rs), nargs-1)], ex)
    else                    decorate(Def(s.ls), ex)
    end
end

# Sig: (part of) function signature in function f(x) ... / f(x) = ...
type Sig  <: State; 
    s::SimpleState;  # state with outer Env, to define/assign f
    inner::Env;      # Env inside the method
end
function decorate(s::Sig, ex::Ex)
    @assert contains([:call, :curly], headof(ex))
    if is_expr(argof(ex,1), :curly);first = s
    else;                           first = (isa(s.s,Def) ? s.s : Lhs(s.s.env))
    end
    states = [first, fill(Def(s.inner), nargsof(ex)-1)]
    decorate(states, ex)
end

# return a Vector of visit states for each arg of an expr(head, args)
function argstates(state::SimpleState, ex)
    head, args = headof(ex), argsof(ex)
    e, nargs = state.env, length(args)

    if contains([:function, :(=)], head) && is_expr(args[1], :call)
        if isa(e, TypeEnv); return argstates(Def(raw(e)), ex); end
        c = child(ex, e); [Sig(state, c), Rhs(c)]
    elseif contains([:function, :(->)], head)
        c = child(ex, e); [Def(c),        Rhs(c)]
        
    elseif contains([:global, :local], head); fill(Def(e), nargs)
    elseif head === :while;              [Rhs(e),        Rhs(child(ex, e))]
    elseif head === :try; cc = child(ex,e); [Rhs(child(ex,e)), Def(cc),Rhs(cc)]
    elseif head === :for; c = child(ex, e);  [SplitDef(c,e), Rhs(c)]
    elseif contains([untyped_comprehensions, :let], head); c = child(ex, e); 
        [Rhs(c), fill(SplitDef(c,e), nargs-1)]
    elseif contains(typed_comprehensions, head); c = child(ex, e)
        [Rhs(e), Rhs(c), fill(SplitDef(c,e), nargs-2)]
        
    elseif head === :(=);   [(isa(state,Def) ? state : Lhs(e)), Rhs(e)]
    elseif head === :(<:);  [(isa(state,Def) ? state : Rhs(e)), Rhs(e)]
    elseif head === :tuple; fill(state,  nargs)
    elseif head === :ref;   fill(Rhs(e), nargs)
    elseif head === :(...); [state]
    elseif head === :(::) && nargs == 1; [Rhs(e)]
    elseif head === :(::) && nargs == 2; [state, Rhs(e)]

    # I'm guessing abstract and typealias wrap their args in one scope,
    # except the actual name to be defined
    elseif head === :abstract; c=child(ex, e); [SplitDef(e,c)]
    elseif head === :type;     c=child(ex, e); [SplitDef(e,c), Rhs(TypeEnv(c))]
    elseif head === :typealias;c=child(ex, e); [SplitDef(e,c), Rhs(c)]

    else fill(Rhs(e), nargs)
    end
end

function decorate(state::SimpleState, ex::Ex)
    head, args  = headof(ex), argsof(ex)
    if head === :line;                     return Loc(ex, args...)
    elseif contains([:quote, :top], head); return Plain(ex)
    elseif head === :macrocall; return decorate(state, macroexpand(ex))
    end

    states = argstates(state, ex)
    ExValue(head===:block ? Block(raw(state.env)) : head, wrap(states,args))
end

# ---- post-decoration processing ---------------------------------------------

## set_source!(): propagate source file info ##
function set_source!(ex::LocNode, locex, line, file)
    ex.format.file = file
    ex.loc = ex.format
end
set_source!(ex::Leaf, locex, line, file) = (ex.loc = Loc(locex, line, file))
function set_source!(ex::ExNode, locex, line, file)
    ex.loc = Loc(locex, line, file)
    locex  = nothing
    for arg in argsof(ex)
        if isa(arg, LocNode) 
            line = arg.format.line
            if arg.format.file != "";  file = arg.format.file;  end
        end
        set_source!(arg, locex, line, file)
        locex = isa(arg, LocNode) ? exof(arg) : nothing
    end
end

## postprocess_env!: find defined symbols among assigned ##
# todo: Make child links for Env so that this doesn't have to go through the
# nodes?
postprocess_env!(envs::Set{LocalEnv}, ex) = nothing
function postprocess_env!(envs::Set{LocalEnv}, ex::SymNode)
    postprocess_env!(envs,envof(ex))
end
function postprocess_env!(envs::Set{LocalEnv}, ex::Ex)
    if isa(ex, BlockNode); postprocess_env!(envs, envof(ex)); end
    for arg in argsof(ex); postprocess_env!(envs, arg);    end
end

postprocess_env!(envs::Set{LocalEnv}, ::NoEnv) = nothing
function postprocess_env!(envs::Set{LocalEnv}, env::LocalEnv)
    if has(envs, env); return; end
    add(envs, env)
    p = env.parent
    p_assigned = isa(p, LocalEnv) ? p.assigned : Set{None}()
    env.defined  = env.defined | (env.assigned - p_assigned)
    env.assigned = env.defined | p_assigned
end

# ---- analyze(): wrap and then propagate source file info among LocNode's

analyze(ex, process_envs::Bool) = analyze(Rhs(NoEnv()), ex, process_envs)
analyze(env::Env, ex, process_envs::Bool) = analyze(Rhs(env), ex, process_envs)
function analyze(s::State, ex, process_envs::Bool)
    node = wrap(s, ex)
    set_source!(node, nothing, -1, "")
    if process_envs; postprocess_env!(Set{LocalEnv}(), node); end
    node
end

end # module
