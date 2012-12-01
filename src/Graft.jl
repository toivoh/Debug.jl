
#   Debug.Graft:
# ================
# Debug instrumentation of code, and transformation of ASTs to act as if they
# were evaluated inside such code (grafting)

module Graft
using Base, AST, Meta
import Base.ref, Base.assign, Base.has

export Scope, NoScope, LocalScope


# ---- Scope: runtime symbol table with getters and setters -------------------

abstract Scope

type NoScope <: Scope; end
type LocalScope <: Scope
    parent::Scope
    syms::Dict
    env::Env
end

has(s::NoScope,    sym::Symbol) = false
has(s::LocalScope, sym::Symbol) = has(s.syms, sym) || has(s.parent, sym)

function get_entry(scope::LocalScope, sym::Symbol)
    has(scope.syms, sym) ? scope.syms[sym] : get_entry(scope.parent, sym)
end

getter(scope::LocalScope, sym::Symbol) = get_entry( scope, sym)[1]
setter(scope::LocalScope, sym::Symbol) = get_entry( scope, sym)[2]
ref(   scope::LocalScope,     sym::Symbol) = getter(scope, sym)()
assign(scope::LocalScope, x,  sym::Symbol) = setter(scope, sym)(x)


# ---- instrument -------------------------------------------------------------
# Add Scope creation and debug traps to (analyzed) code
# A call to trap() is added after every AST.Loc (expr(:line) / LineNumberNode)

type Context
    trap_ex
    env::Env
    scope_ex
end

function code_getset(sym::Symbol)
    val = gensym(string(sym))
    :( ()->$sym, $val->($sym=$val) )
end
const typed_dict = symbol("typed-dict")
function code_scope(scopesym::Symbol, parent, env::Env, syms)
    pairs = {expr(:(=>), quot(sym), code_getset(sym)) for sym in syms}
    :(local $scopesym = $(quot(LocalScope))(
        $parent, 
        $(expr(typed_dict, :($(quot(Symbol))=>$(quot((Function,Function)))), 
            pairs...)),
        $(quot(env))
    ))
end

function instrument(trap_ex, ex)
    instrument(Context(trap_ex, NoEnv(), quot(NoScope())), ex)
end

instrument(c::Context, node::Union(Leaf,Sym)) = exof(node)
function instrument(c::Context, ex::Expr)
    expr(headof(ex), {instrument(c, arg) for arg in argsof(ex)})
end
function instrument(c::Context, ex::Block)
    code = {}

    if isa(envof(ex), LocalEnv) && is_expr(envof(ex).source, :type)
        for arg in argsof(ex)        
            if !isa(arg, Trap);  push(code, instrument(c, arg));  end
        end
        return expr(:block, code)
    end

    if !is(envof(ex), c.env)
        syms, e = Set{Symbol}(), envof(ex)
        while !is(e, c.env);  add_each(syms, e.defined); e = e.parent;  end

        name = gensym("scope")
        push(code, code_scope(name, c.scope_ex, envof(ex), syms))
        c = Context(c.trap_ex, envof(ex), name)
    end
    
    for arg in argsof(ex)
        if isa(arg, Trap)
            if isa(arg, Loc);  push(code, exof(arg))  end
            push(code, :($(c.trap_ex)($(quot(arg)), $(c.scope_ex))) )
        else
            push(code, instrument(c, arg))
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

graft(s::LocalScope, ex)                    = ex
graft(s::LocalScope, node::Union(Leaf,Loc)) = exof(node)
function graft(s::LocalScope, ex::Sym)
    sym = exof(ex)
    (has(s,sym) && !has(envof(ex),sym)) ? expr(:call,quot(getter(s,sym))) : sym
end
function graft(s::LocalScope, ex::Union(Expr, Block))
    head, args = headof(ex), argsof(ex)
    if head == :(=)
        lhs, rhs = args
        if isa(lhs, Sym)             # assignment to symbol
            rhs = graft(s, rhs)
            sym = exof(lhs)
            if has(envof(lhs), sym) || !has(s.env.assigned, sym); return :($sym = $rhs)
            elseif has(s, sym);   return expr(:call, quot(setter(s,sym)), rhs)
            else; error("No setter in scope found for $(sym)!")
            end
        elseif is_expr(lhs, :tuple)  # assignment to tuple
            tup = Leaf(gensym("tuple")) # don't recurse into tup
            return graft(s, expr(:block,
                 :($tup  = $rhs    ),
                {:($dest = $tup[$k]) for (k,dest)=enumerate(argsof(lhs))}...))
        elseif is_expr(lhs, [:ref, :.]) || isa(lhs, Leaf) # need no lhs rewrite
        else error("graft: not implemented: $ex")       
        end  
    elseif has(updating_ops, head) && isa(args[1], Sym)  # x+=y ==> x=x+y etc.
        op = updating_ops[head]
        return graft(s, :( $(args[1]) = ($op)($(args[1]), $(args[2])) ))
    end        
    expr(head, {graft(s,arg) for arg in args})
end

end # module
