
#   Debug.Graft:
# ================
# Debug instrumentation of code, and transformation of ASTs to act as if they
# were evaluated inside such code (grafting)

module Graft
using Base, AST
import Base.ref, Base.assign, Base.has

export trap, Scope


trap(args...) = error("No debug trap installed for ", typeof(args))


# ---- Helpers ----------------------------------------------------------------

quot(ex) = expr(:quote, ex)

is_expr(ex,       head::Symbol)   = false
is_expr(ex::Expr, head::Symbol)   = ex.head == head
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

instrument(ex) = add_traps((nothing,quot(NoScope())), ex)

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
            if has(lhs.env, sym); return :($sym = $rhs)
            else
                if has(s, sym); return expr(:call, get_setter(s, sym), rhs)
                else; error("No setter in scope found for $sym!")
                end
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


end # module