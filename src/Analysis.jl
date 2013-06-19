
#   Debug.Analysis:
# ===================
# Scoping analysis used to support instrument and graft

module Analysis
using Debug.AST, Debug.Meta

export analyze


# ---- Helpers ----------------------------------------------------------------

is_linenumber(ex::LineNumberNode) = true
is_linenumber(ex::Ex)             = is(headof(ex), :line)
is_linenumber(ex)                 = false

is_file_linenumber(ex)            = is_expr(ex, :line, 2)

get_linenumber(ex::Ex)             = argof(ex,1)
get_linenumber(ex::LineNumberNode) = ex.line


# ---- wrap(): add scoping info to AST ------------------------------------
# Rewrites AST, exchanging Expr:s and leaves for Node:s.
# Adds scope info, classifies nodes, etc.

# TypeEnv: Env used in a type block to throw away non-method definitions 
type TypeEnv <: Env
    env::LocalEnv
end
raw(env::TypeEnv) = env.env
raw(env::Env)     = env

raw(s::State) = s
raw{T<:SimpleState}(s::T) = T(raw(s.env))


function wrap(states::Vector, args::Vector) 
    {wrap(s, arg) for (s, arg) in zip(states, args)}
end
wrap(s::SimpleState, ex::SymbolNode) = wrap(s, ex.name)
wrap(s::State, ex) = enwrap(s, decorate(s,ex))

# SplitDef: Def with different scopes for left and right side, e.g.
# let x_inner = y_outer   or   type T_outer{S_inner} <: Q_outer
type SplitDef <: State;
    ls::Env;
    rs::Env;
end
wrap(s::SplitDef, ex) = wrap(Def(s.ls), ex)
function wrap(s::SplitDef, ex::Ex)
    head, nargs = headof(ex), nargsof(ex)
    if     head === :(=);   enwrap(s, decorate([Def(s.ls), Rhs(s.rs)], ex))
    elseif head === :(<:);  enwrap(s, decorate([s,         Rhs(s.ls)], ex))
    elseif head === :curly; enwrap(s, decorate([s, fill(Def(s.rs), nargs-1)], ex))
    else                    wrap(Def(s.ls), ex)
    end
end

enwrap(s::State, value)    = Node(value, raw(s))
enwrap(s::State, loc::Loc) = Node(Location(), raw(s), loc)


## decorate: does most of the work for wrap ##

decorate(states::Vector, ex::Ex) = ExValue(headof(ex), wrap(states,argsof(ex)))

decorate(s::State, ex) = isa(ex, Node) ? valueof(ex) : Plain(ex) # wrap/unwrap
decorate(s::SimpleState, ex::LineNumberNode) = Loc(ex, ex.line)

decorate(s::Def,         ex::Symbol) = (AST.add_defined( s.env, ex); ex)
decorate(s::Lhs,         ex::Symbol) = (AST.add_assigned(s.env, ex); ex)
decorate(s::SimpleState, ex::Symbol) = ex

decorate(::Nonsyntax, ex::Ex) = Plain(ex)

# Sig: (part of) function signature in function f(x) ... / f(x) = ...
type Sig <: State; 
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

const updating_ops = {
 :+= => :+,   :-= => :-,  :*= => :*,  :/= => :/,  ://= => ://, :.//= => :.//,
:.*= => :.*, :./= => :./, :\= => :\, :.\= => :.\,  :^= => :^,   :.^= => :.^,
 :%= => :%,   :|= => :|,  :&= => :&,  :$= => :$,  :<<= => :<<,  :>>= => :>>,
 :>>>= => :>>>}

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
    elseif head === :try
        cc = child(ex,e); states = [Rhs(child(ex,e)), Def(cc),Rhs(cc)]
        nargs === 4 ? [states, Rhs(child(ex,e))] : states
    elseif head === :for; c = child(ex, e);  [SplitDef(c,e), Rhs(c)]
    elseif contains([:let, untyped_comprehensions], head); c = child(ex, e); 
        [Rhs(c), fill(SplitDef(c,e), nargs-1)]
    elseif contains(typed_comprehensions, head); c = child(ex, e)
        [Rhs(e), Rhs(c), fill(SplitDef(c,e), nargs-2)]
        
    elseif haskey(updating_ops, head); [Lhs(e), Rhs(e)]
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
    elseif head === :type;     c=child(ex, e); [Nonsyntax(),
                                                SplitDef(e,c), Rhs(TypeEnv(c))]
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

    decorate(argstates(state, ex), ex)
end

# ---- post-decoration processing ---------------------------------------------

## set_source!(): propagate source file info ##
function set_source!(ex::LocNode, locex, line, file)
    ex.loc.file = file
end
set_source!(ex::Node, locex, line, file) = (ex.loc = Loc(locex, line, file))
function set_source!(ex::ExNode, locex, line, file)
    ex.loc = Loc(locex, line, file)
    locex  = nothing
    for arg in argsof(ex)
        if isa(arg, LocNode) 
            line = arg.loc.line #valueof(arg).line
            if arg.loc.file != empty_symbol;  file = arg.loc.file;  end
        end
        set_source!(arg, locex, line, file)
        locex = isa(arg, LocNode) ? arg.loc : nothing
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
    if isblocknode(ex); postprocess_env!(envs, envof(ex)); end
    for arg in argsof(ex); postprocess_env!(envs, arg);    end
end

postprocess_env!(envs::Set{LocalEnv}, ::NoEnv) = nothing
function postprocess_env!(envs::Set{LocalEnv}, env::LocalEnv)
    if contains(envs, env); return; end
    add!(envs, env)
    p = env.parent
    p_assigned = isa(p, LocalEnv) ? p.assigned : Set{None}()
    env.defined  = union(env.defined, setdiff(env.assigned, p_assigned))
    env.assigned = union(env.defined, p_assigned)
end

# ---- analyze(): wrap and then propagate source file info among LocNode's

analyze(ex, process_envs::Bool) = analyze(Rhs(NoEnv()), ex, process_envs)
analyze(env::Env, ex, process_envs::Bool) = analyze(Rhs(env), ex, process_envs)
function analyze(s::State, ex, process_envs::Bool)
    node = wrap(s, ex)
    set_source!(node, nothing, -1, empty_symbol)
    if process_envs; postprocess_env!(Set{LocalEnv}(), node); end
    node
end

end # module
