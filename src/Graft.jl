
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
    trap_pred::Function
    trap_ex
    env::Env
    scope_ex
end
Context(c::Context,e::Env,scope_ex) = Context(c.trap_pred,c.trap_ex,e,scope_ex)

function instrument(trap_pred::Function, trap_ex, ex)
    instrument(Context(trap_pred, trap_ex, NoEnv(), quot(ModuleScope())),
               analyze(ex,true))
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


code_trap(c::Context, node) = expr(:call, c.trap_ex, quot(node), c.scope_ex)
code_trap_if(c::Context,node) = c.trap_pred(node) ? code_trap(c,node) : nothing

function instrument(c::Context, node::Node)
    if isa(node.state, Rhs) && !is_in_type(node) && c.trap_pred(node)
        expr(:block, code_trap(c, node), 
             is_emittable(node) ? instrument_node(c, node) : quot(nothing))
    else
        instrument_node(c, node)
    end
end

code_enterleave(::Nothing, ex, ::Nothing) = ex
code_enterleave(enter,     ex, ::Nothing) = quote; $enter; $ex; end
code_enterleave(::Nothing, ex, leave) = :(try         $ex; finally $leave; end)
code_enterleave(enter,     ex, leave) = :(try $enter; $ex; finally $leave; end)

function instrument_node(c::Context, node::Node)
    ex = instrument_args(c, node)
    if is_scope_node(node)
        enter, leave = code_trap_if(c,Enter(node)), code_trap_if(c,Leave(node))
        if is_function(node)
            @assert is_function(ex)
            expr(ex.head, ex.args[1], code_enterleave(enter,ex.args[2],leave))
        else
            code_enterleave(enter, ex, leave)
        end
    else
        ex
    end
end

instrument_args(c::Context, node::Node) = exof(node)
function instrument_args(c::Context, node::ExNode)
    args = {}
    if isblocknode(node)
        if !is(envof(node), c.env)
            # create new Scope
            syms, e = Set{Symbol}(), envof(node)
            while !is(e, c.env);  add_each(syms, e.defined); e = e.parent;  end
            
            name = gensym("scope")
            push(args, code_scope(name, c.scope_ex, envof(node), syms))
            c = Context(c, envof(node), name)

            node.introduces_scope = true
        end
    end
    for arg in argsof(node); push(args, instrument(c, arg)); end
    expr(headof(node), args)        
end


# ---- graft ------------------------------------------------------------------
# Rewrite an (analyzed) AST to work as if it were inside
# the given scope, when evaluated in global scope. 
# Replaces reads and writes to variables from that scope 
# with getter/setter calls.

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
    elseif has(Analysis.updating_ops, head) && isa(args[1], SymNode)
        # x+=y ==> x=x+y etc.
        op = Analysis.updating_ops[head]
        return rawgraft(s, :( $(args[1]) = ($op)($(args[1]), $(args[2])) ))
    end        
    expr(head, {rawgraft(s,arg) for arg in args})
end

end # module
