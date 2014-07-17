
#   Debug.Graft:
# ================
# Debug instrumentation of code, and transformation of ASTs to act as if they
# were evaluated inside such code (grafting)

module Graft
using Debug.AST, Debug.Meta, Debug.Analysis, Debug.Runtime
import Debug.Meta
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
    @gensym scope    
    ex = instrument(Context(trap_pred,trap_ex,NoEnv(),scope), analyze(ex,true))
    quote
        $scope = $(quot(ModuleScope))(eval)
        $ex
    end
end


function code_getset(sym::Symbol)
    val = gensym(string(sym))
    :( ()->$sym, $val->($sym=$val) )
end
function code_scope(scopesym::Symbol, parent, env::Env, syms)
    pairs = {Expr(:(=>), quot(sym), code_getset(sym)) for sym in syms}
    :(local $scopesym = $(quot(LocalScope))(
        $parent, 
        $(Expr(:typed_dict,
               :($(quot(Symbol))=>$(quot((Function,Function)))), pairs...)),
        $(quot(env))
    ))
end


code_trap(c::Context, node) = Expr(:call, c.trap_ex, quot(node), c.scope_ex)
code_trap_if(c::Context,node) = c.trap_pred(node) ? code_trap(c,node) : nothing

function instrument(c::Context, node::Node)
    if isa(node.state, Rhs) && !is_in_type(node) && c.trap_pred(node)
        Expr(:block, code_trap(c, node), 
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
            Expr(ex.head, ex.args[1], code_enterleave(enter,ex.args[2],leave))
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
            while !is(e, c.env);  union!(syms, e.defined); e = e.parent  end
            
            name = gensym("scope")
            push!(args, code_scope(name, c.scope_ex, envof(node), syms))
            c = Context(c, envof(node), name)

            node.introduces_scope = true
        end
    end
    for arg in argsof(node); push!(args, instrument(c, arg)); end
    Expr(headof(node), args...)
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
    (haskey(s,sym) && !haskey(envof(ex),sym)) ? Expr(:call,quot(getter(s,sym))) : sym
end
function rawgraft(s::LocalScope, ex::Ex)
    head, args = headof(ex), argsof(ex)
    if head == :(=)
        lhs, rhs = args
        if isa(lhs, SymNode)             # assignment to symbol
            rhs = rawgraft(s, rhs)
            sym = exof(lhs)
            if haskey(envof(lhs), sym) || !(sym in s.env.assigned); return :($sym = $rhs)
            elseif haskey(s, sym);   return Expr(:call, quot(setter(s,sym)), rhs)
            else; error("No setter in scope found for $(sym)!")
            end
        elseif is_expr(lhs, :tuple)  # assignment to tuple
            tup = Node(Plain(gensym("tuple"))) # don't recurse into tup
            return rawgraft(s, Expr(:block,
                 :($tup  = $rhs    ),
                {:($dest = $tup[$k]) for (k,dest)=enumerate(argsof(lhs))}...))
        elseif is_expr(lhs, [:ref, :.]) || isa(lhs, PLeaf)# need no lhs rewrite
        else error("graft: not implemented: $ex")       
        end  
    elseif haskey(Analysis.updating_ops, head) && isa(args[1], SymNode)
        # x+=y ==> x=x+y etc.
        op = Analysis.updating_ops[head]
        return rawgraft(s, :( $(args[1]) = ($op)($(args[1]), $(args[2])) ))
    end        
    Expr(head, {rawgraft(s,arg) for arg in args}...)
end

end # module
