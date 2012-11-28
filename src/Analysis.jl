
#   Debug.Analysis:
# ===================
# Scoping analysis used to support instrument and graft

module Analysis
using Base, AST, Meta
import Base.promote_rule

export analyze


# ---- Helpers ----------------------------------------------------------------

is_linenumber(ex::LineNumberNode) = true
is_linenumber(ex::Expr)           = is(ex.head, :line)
is_linenumber(ex)                 = false

is_file_linenumber(ex)            = is_expr(ex, :line, 2)

get_linenumber(ex::Expr)           = ex.args[1]
get_linenumber(ex::LineNumberNode) = ex.line
get_sourcefile(ex::Expr)           = string(ex.args[2])

const dict_comprehension        = symbol("dict-comprehension")
const typed_comprehension       = symbol("typed-comprehension")
const typed_dict_comprehension  = symbol("typed-dict-comprehension")

const untyped_comprehensions = [:comprehension, dict_comprehension]
const typed_comprehensions =   [typed_comprehension, typed_dict_comprehension]


# ---- decorate(): add scoping info to AST ------------------------------------
# Rewrites AST, exchanging some Expr:s etc for Block/Sym/Leaf/Loc
# to include scope/other relevant info and to classify nodes.

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


function decorate(states::Vector, args::Vector) 
    {decorate(s, arg) for (s, arg) in zip(states, args)}
end
decorate(states::Vector, ex::Expr) = expr(ex.head, decorate(states, ex.args))

decorate(s::State,       ex)                 = Leaf(ex)
decorate(s::SimpleState, ex::LineNumberNode) = Loc(ex, ex.line)
decorate(s::SimpleState, ex::SymbolNode)     = decorate(s, ex.name)
decorate(s::Def, ex::Symbol) = (add_defined( s.env, ex); Sym(ex,raw(s.env)))
decorate(s::Lhs, ex::Symbol) = (add_assigned(s.env, ex); Sym(ex,raw(s.env)))
decorate(s::SimpleState, ex::Symbol) = Sym(ex,raw(s.env))

# SplitDef: Def with different scopes for left and right side, e.g.
# let x_inner = y_outer
# type T_outer{S_inner} <: Q_outer
type SplitDef <: State;
    ls::Env;
    rs::Env;
end
decorate(s::SplitDef, ex) = decorate(Def(s.ls), ex)
function decorate(s::SplitDef, ex::Expr)
    head, nargs = ex.head, length(ex.args)
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
function decorate(s::Sig, ex::Expr)
    @assert contains([:call, :curly], ex.head)
    if is_expr(ex.args[1], :curly) first = s;
    else; first = (isa(s.s,Def) ? s.s : Lhs(s.s.env));
    end
    states = [first, fill(Def(s.inner), length(ex.args)-1)]
    decorate(states, ex)
end

# return a Vector of visit states for each arg of an expr(head, args)
function argstates(state::SimpleState, head, args)
    e, nargs = state.env, length(args)

    if contains([:function, :(=)], head) && is_expr(args[1], :call)
        if isa(e, TypeEnv); return argstates(Def(raw(e)), head, args); end
        c = child(e); [Sig(state, c), Rhs(c)]
    elseif contains([:function, :(->)], head)
        c = child(e); [Def(c),        Rhs(c)]
        
    elseif contains([:global, :local], head); fill(Def(e), nargs)
    elseif head === :while;              [Rhs(e),        Rhs(child(e))]
    elseif head === :try; cc = child(e); [Rhs(child(e)), Def(cc),Rhs(cc)]
    elseif head === :for; c = child(e);  [SplitDef(c,e), Rhs(c)]
    elseif contains([untyped_comprehensions, :let], head); c = child(e); 
        [Rhs(c), fill(SplitDef(c,e), nargs-1)]
    elseif contains(typed_comprehensions, head); c = child(e)
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
    elseif head === :abstract;  c=child(e); [SplitDef(e,c)]
    elseif head === :type;      c=child(e); [SplitDef(e,c), Rhs(TypeEnv(c))]
    elseif head === :typealias; c=child(e); [SplitDef(e,c), Rhs(c)]

    else fill(Rhs(e), nargs)
    end
end

function decorate(state::SimpleState, ex::Expr)
    head, args  = ex.head, ex.args
    if head === :line;                     return Loc(ex, args...)
    elseif contains([:quote, :top], head); return Leaf(ex)
    elseif head === :macrocall; return decorate(state, macroexpand(ex))
    end

    states = argstates(state, head, args)
    if head === :block; Block(decorate(states, args), raw(state.env))
    else                decorate(states, ex)
    end
end

# ---- post-decoration processing ---------------------------------------------

## set_source!(): propagate source file info ##
set_source!(ex,       file::String) = nothing
set_source!(ex::Loc, file::String) = (ex.file = file)
function set_source!(ex::Union(Expr,Block), file::String)
    for arg in ex.args
        if isa(arg, Loc) && arg.file != ""; file = arg.file; end
        set_source!(arg, file)
    end
end

## postprocess_env!: find defined symbols among assigned ##
postprocess_env!(envs::Set{LocalEnv}, ex) = nothing
postprocess_env!(envs::Set{LocalEnv}, ex::Sym) = postprocess_env!(envs, ex.env)
function postprocess_env!(envs::Set{LocalEnv}, ex::Union(Expr,Block))
    if isa(ex, Block);  postprocess_env!(envs, ex.env); end
    for arg in ex.args; postprocess_env!(envs, arg);    end
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

# ---- analyze(): decorate and then propagate source file info among Loc's ---

analyze(ex, process_envs::Bool) = analyze(Rhs(NoEnv()), ex, process_envs)
analyze(env::Env, ex, process_envs::Bool) = analyze(Rhs(env), ex, process_envs)
function analyze(s::State, ex, process_envs::Bool)
    node = decorate(s, ex)
    set_source!(node, "")
    if process_envs; postprocess_env!(Set{LocalEnv}(), node); end
    node
end

end # module
