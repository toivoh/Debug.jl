
#   Debug.Graft:
# ================
# Debug instrumentation of code, and transformation of ASTs to act as if they
# were evaluated inside such code (grafting)

module Graft
using Base, AST
import Base.ref, Base.assign, Base.has

export trap, Scope, NoScope, LocalScope


trap(args...) = error("No debug trap installed for ", typeof(args))


# ---- Helpers ----------------------------------------------------------------

quot(ex) = expr(:quote, ex)

is_expr(ex,       head)           = false
is_expr(ex::Expr, head::Symbol)   = ex.head == head
is_expr(ex::Expr, heads::Set)     = has(heads, ex.head)
is_expr(ex::Expr, heads::Vector)  = contains(heads, ex.head)
is_expr(ex, head::Symbol, n::Int) = is_expr(ex, head) && length(ex.args) == n

const typed_dict                = symbol("typed-dict")


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
# Add Scope creation and debug traps to (analyzed) code
# A call to trap() is added after every AST.Line (expr(:line) / LineNumberNode)

instrument(ex) = instrument((NoEnv(),quot(NoScope())), ex)

instrument(env, node::Union(Leaf,Sym,Line)) = node.ex
function instrument(env, ex::Expr)
    expr(ex.head, {instrument(env, arg) for arg in ex.args})
end
function instrument(env, ex::Block)
    code = {}
    if !is(ex.env, env[1])
        syms, e = Set{Symbol}(), ex.env
        while !is(e, env[1]);  add_each(syms, e.defined); e = e.parent;  end

        name = gensym("scope")
        push(code, code_scope(name, env[2], syms))
        env = (ex.env, name)
    end
    
    for arg in ex.args
        push(code, instrument(env, arg))
        if isa(arg, Line)
            push(code, :($(quot(trap))($(arg.line), $(quot(arg.file)),
                                       $(env[2]))) )
        end
    end
    expr(:block, code)
end


# ---- graft ------------------------------------------------------------------
# Rewrite an (analyzed) AST to work as if it were inside
# the given scope, when evaluated in global scope. 
# Replaces reads and writes to variables from that scope 
# with getter/setter calls.

const updating_ops = {
 :+= => :+,   :-= => :-,  :*= => :*,  :/= => :/,  ://= => ://, :.//= => :.//,
:.*= => :.*, :./= => :./, :\= => :\, :.\= => :.\,  :^= => :^,   :.^= => :.^,
 :%= => :%,   :|= => :|,  :&= => :&,  :$= => :$,  :<<= => :<<,  :>>= => :>>,
 :>>>= => :>>>}

graft(s::LocalScope, ex) = ex
function graft(s::LocalScope, ex::Sym)
    sym = ex.ex
    if has(ex.env, sym) || !has(s, sym); sym
    else expr(:call, get_getter(s, sym))
    end
end
function graft(s::LocalScope, ex::Union(Expr, Block))
    head, args = get_head(ex), ex.args
    if head == :(=)
        lhs, rhs = args
        if isa(lhs, Sym)
            rhs = graft(s, rhs)
            sym = lhs.ex
            if has(lhs.env, sym); return :($sym = $rhs)
            else
                if has(s, sym); return expr(:call, get_setter(s, sym), rhs)
                else; error("No setter in scope found for $(sym)!")
                end
            end
        elseif is_expr(lhs, :tuple)
            tup = Leaf(gensym("tuple")) # don't recurse into it
            return graft(s, expr(:block, 
                 :( $tup  = $rhs     ),
                {:( $dest = $tup[$k] ) for (k,dest)=enumerate(lhs.args)}...))
        elseif is_expr(lhs, [:ref, :.]) || isa(lhs, Leaf)  # pass down
        else error("graft: not implemented: $ex")       
        end  
    elseif has(updating_ops, head) && isa(args[1], Sym)
        # Translate updating ops, e g x+=1 ==> x=x+1        
        op = updating_ops[head]
        return graft(s, :( $(args[1]) = ($op)($(args[1]), $(args[2])) ))
    end        
    expr(head, {graft(s,arg) for arg in args})
end
graft(s::LocalScope, node::Union(Leaf,Line)) = node.ex


end # module
