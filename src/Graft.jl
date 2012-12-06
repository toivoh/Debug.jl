
#   Debug.Graft:
# ================
# Debug instrumentation of code, and transformation of ASTs to act as if they
# were evaluated inside such code (grafting)

module Graft
using Base, AST, Meta, Analysis, Runtime
export instrument, graft


# ---- instrument -------------------------------------------------------------
# Add Scope creation and debug traps to (analyzed) code

type Context
    pred::Function
    trap_ex
    env::Env
    scope_ex
end
Context(c::Context, env::Env, scp_ex) = Context(c.pred, c.trap_ex, env, scp_ex)

function instrument(pred::Function, trap_ex, ex)
    instrument(Context(pred,trap_ex,NoEnv(),quot(NoScope())),analyze(ex,true))
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

#instrument(c::Context, ex) = ex # todo: remove?
instrument(c::Context, node::Node) = exof(node)
function instrument(c::Context, ex::Ex)
    if isblocknode(ex)
        if isa(envof(ex), LocalEnv) && is_expr(envof(ex).source, :type)
            code = {}
            for arg in argsof(ex)        
                if is_emittable(arg);  push(code, instrument(c, arg));  end
            end
            return expr(:block, code)
        end
        
        code = {}
        if !is(envof(ex), c.env)
            syms, e = Set{Symbol}(), envof(ex)
            while !is(e, c.env);  add_each(syms, e.defined); e = e.parent;  end
            
            name = gensym("scope")
            push(code, code_scope(name, c.scope_ex, envof(ex), syms))
            c = Context(c, envof(ex), name)
        end
        
        if c.pred(ex)
            push(code, :($(c.trap_ex)($(quot(ex)), $(c.scope_ex))) )
        end
        for arg in argsof(ex)
            if !isblocknode(arg) && c.pred(arg)
                push(code, :($(c.trap_ex)($(quot(arg)), $(c.scope_ex))) )
            end           
            if is_emittable(arg)
                push(code, instrument(c, arg))
            end
        end
        expr(:block, code)
    else
        expr(headof(ex), {instrument(c, arg) for arg in argsof(ex)})
    end
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

graft(env::Env, scope::Scope, ex) = rawgraft(scope, analyze(env, ex, false))
graft(scope::Scope, ex) =           graft(child(NoEnv()), scope, ex)


rawgraft(s::LocalScope, ex)         = ex
rawgraft(s::LocalScope, node::Node) = exof(node)
function rawgraft(s::LocalScope, ex::SymNode)
    sym = exof(ex)
    (has(s,sym) && !has(envof(ex),sym)) ? expr(:call,quot(getter(s,sym))) : sym
end
function rawgraft(s::LocalScope, ex::Ex)
    head, args = headof(ex), argsof(ex)
    if head == :(=)
        lhs, rhs = args
        if isa(lhs, SymNode)             # assignment to symbol
            rhs = rawgraft(s, rhs)
            sym = exof(lhs)
            if has(envof(lhs), sym) || !has(s.env.assigned, sym); return :($sym = $rhs)
            elseif has(s, sym);   return expr(:call, quot(setter(s,sym)), rhs)
            else; error("No setter in scope found for $(sym)!")
            end
        elseif is_expr(lhs, :tuple)  # assignment to tuple
            tup = Node(Plain(gensym("tuple"))) # don't recurse into tup
            return rawgraft(s, expr(:block,
                 :($tup  = $rhs    ),
                {:($dest = $tup[$k]) for (k,dest)=enumerate(argsof(lhs))}...))
        elseif is_expr(lhs, [:ref, :.]) || isa(lhs, PLeaf)# need no lhs rewrite
        else error("graft: not implemented: $ex")       
        end  
    elseif has(updating_ops, head) && isa(args[1], SymNode)
        # x+=y ==> x=x+y etc.
        op = updating_ops[head]
        return rawgraft(s, :( $(args[1]) = ($op)($(args[1]), $(args[2])) ))
    end        
    expr(head, {rawgraft(s,arg) for arg in args})
end

end # module
