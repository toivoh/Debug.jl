
#   Debug.Analysis:
# ===================
# Scoping analysis used to support instrument and graft

module Analysis
using Base, AST
import Base.promote_rule

export analyze


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
const typed_dict_comprehension  = symbol("typed-dict-comprehension")

const untyped_comprehensions = [:comprehension, dict_comprehension]
const typed_comprehensions =   [typed_comprehension, typed_dict_comprehension]


# ---- decorate(): add scoping info to AST ------------------------------------
# Rewrites AST, exchanging some Expr:s etc for Block/Sym/Leaf/Line
# to include scope/other relevant info and to classify nodes.

abstract State
promote_rule{S<:State,T<:State}(::Type{S},::Type{T}) = State

abstract SimpleState <: State
type Def <: SimpleState;  env::Env;  end  # definition, e.g. inside local
type Lhs <: SimpleState;  env::Env;  end  # e.g. to the left of =
type Rhs <: SimpleState;  env::Env;  end  # plain evaluation

function decorate(states::Vector, args::Vector) 
    {decorate(s, arg) for (s, arg) in zip(states, args)}
end
decorate(states::Vector, ex::Expr) = expr(ex.head, decorate(states, ex.args))

decorate(s::State,       ex)                 = Leaf(ex)
decorate(s::SimpleState, ex::LineNumberNode) = Line(ex, ex.line)
decorate(s::SimpleState, ex::SymbolNode)     = decorate(s, ex.name)
decorate(s::Def, ex::Symbol) = (add_defined( s.env, ex); Sym(ex,s.env))
decorate(s::Lhs, ex::Symbol) = (add_assigned(s.env, ex); Sym(ex,s.env))
decorate(s::SimpleState, ex::Symbol) = Sym(ex,s.env)

# Typ: inside type. todo: better way?
type Typ <: SimpleState;  env::Env;  end
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
        inner = child(e); [Sig(state, inner), Rhs(inner)]
    elseif contains([:function, :(->)], head)
        inner = child(e); [Def(inner),        Rhs(inner)]
        
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

# ---- set_source!(): propagate source info in a decorated AST ----------------
set_source!(ex,       file::String) = nothing
set_source!(ex::Line, file::String) = (ex.file = file)
function set_source!(ex::Union(Expr,Block), file::String)
    for arg in ex.args
        if isa(arg, Line) && arg.file != ""; file = arg.file; end
        set_source!(arg, file)
    end
end


# ---- analyze(): decorate and then propagate source file info among Line's ---

analyze(ex) = analyze(Rhs(child(NoEnv())), ex)
function analyze(s::State, ex)
    node = decorate(s, ex)
    set_source!(node, "")
    node
end

end # module
