
module Debug
import Base.*
export @debug, debug_hook, debug_eval, Scope, getdefs, code_debug

const doublecolon = symbol("::")

quot(ex) = expr(:quote, ex)

is_expr(ex, head::Symbol) = (isa(ex, Expr) && (ex.head == head))
is_expr(ex, head::Symbol, n::Int) = is_expr(ex, head) && length(ex.args) == n

is_symbol(ex::Symbol)      = true
is_symbol(ex::SymbolNode ) = true
is_symbol(ex)              = false

get_symbol(ex::Symbol)     = ex
get_symbol(ex::SymbolNode) = ex.name

is_linenumber(ex::LineNumberNode) = true
is_linenumber(ex::Expr)           = is(ex.head, :line)
is_linenumber(ex)                 = false

get_linenumber(ex::Expr)           = ex.args[1]
get_linenumber(ex::LineNumberNode) = ex.line

# ---- macro_expand -----------------------------------------------------------

# expand() seems to do a number of things, including macro expansion.
# macro_expand() should confine it to macros.
function macro_expand(ex::Expr)
    if ex.head === :macrocall;                 return expand(ex); end
    if ex.head === :quote || ex.head === :top; return ex;         end
    expr(ex.head, {macro_expand(arg) for arg in ex.args})
end
macro_expand(ex) = ex


# ---- getdefs: gather defined symbols by scope -------------------------------

type DefinedSyms
    scopes::ObjectIdDict
    syms::Set{Symbol}
end

enter(c::DefinedSyms, ex) = enter(c.scopes, ex)
function enter(scopes::ObjectIdDict, ex)
    scopes[ex] = syms = Set{Symbol}()
    DefinedSyms(scopes, syms)
end

const comprehensions = [:comprehension, symbol("cell-comprehension")]

getdefs(c::DefinedSyms, exs::Vector) = (for ex in exs; getdefs(c, ex); end)
function getdefs(c::DefinedSyms, ex::Expr)
    head = ex.head
    args = ex.args

    if contains([:line, :quote, :top, :type], head); return; end
    if head === :macrocall; return; end  # don't go in there for now
    if head === :let
        body = args[1]
        c_outer, c_inner = c, enter(c, body)
        getdefs(c_inner, body)
        for arg in args[2:end]
            if is_expr(arg, :(=))
                lhs, rhs = arg.args[1], arg.args[2]
                getdefs(c_outer, rhs)
            else
                lhs = arg
            end
            getdefs_lhs(c_inner, lhs)
            c.scopes[lhs] = c_inner.syms
        end
        return
    end
    if contains(comprehensions, head)
        c = enter(c, args[1])
        getdefs(c, args)
        for arg in args[2:end]
            c.scopes[arg] = c.syms
        end
    end
    if head === :try
        try_body, catch_arg, catch_body = args[1], args[2], args[3]

        getdefs(enter(c, try_body), try_body)

        c = enter(c, catch_body)
        getdefs_lhs(c, catch_arg)
        getdefs(c, catch_body)
        c.scopes[catch_arg] = c.syms
        return
    end

    if contains([:function, :for, :while, :(->)], head)
        c = enter(c, ex)
    end
    if head === :(=) || head === :(->)
        getdefs_lhs(c, args[1])
        getdefs(c, args[2])
    elseif contains([:local, :global], head)
        getdefs_lhs(c, args)
    elseif head === :function
        getdefs_lhs(c, args[1])
        getdefs(c, args[2])
    else
        getdefs(c, args)
    end
end
getdefs(c::DefinedSyms, ex) = nothing

getdefs_lhs(c::DefinedSyms, exs::Vector) = (for e in exs; getdefs_lhs(c,e);end)
function getdefs_lhs(c::DefinedSyms, ex::Expr)
    head = ex.head
    args = ex.args
    nargs = length(args)
    
    if head === doublecolon && nargs == 2
        getdefs_lhs(c, args[1])
        getdefs(c, args[2])
    elseif contains([:call, :tuple], head)
        getdefs_lhs(c, args)        
    elseif head === :ref
        getdefs(c, args)
    else
        error("getdefs_lhs: don't know how to handle head=$head")
    end
end
getdefs_lhs(c::DefinedSyms, ex::Symbol)     = (add(c.syms, ex); nothing)
getdefs_lhs(c::DefinedSyms, ex::SymbolNode) = getdefs(c, ex.name)
getdefs_lhs(c::DefinedSyms, ex)             = nothing


function getdefs(ex::Expr)
    scopes = ObjectIdDict()
    getdefs(enter(scopes, ex), ex)
    scopes
end


# ---- Scope: runtime symbol table with getters and setters -------------------

abstract Scope

type NoScope <: Scope; end
haskey(scope::NoScope, sym::Symbol) = false

type LocalScope <: Scope
    parent::Scope
    syms::Dict
end

function haskey(scope::LocalScope, sym::Symbol)
    haskey(scope.syms, sym) || haskey(scope.parent, sym)
end
function get_entry(scope::LocalScope, sym::Symbol)
    haskey(scope.syms, sym) ? scope.syms[sym] : get_entry(scope.parent, sym)
end

get_getter(scope::LocalScope, sym::Symbol) = get_entry(scope, sym)[1]
get_setter(scope::LocalScope, sym::Symbol) = get_entry(scope, sym)[2]
getindex(   scope::LocalScope,     sym::Symbol) = get_getter(scope, sym)()
assign(scope::LocalScope, x,  sym::Symbol) = get_setter(scope, sym)(x)

function code_getset(sym::Symbol)
    val = gensym(string(sym))
    :( ()->($sym), ($val)->(($sym)=($val)) )
end
function code_scope(scope::Symbol, parent, syms)
    pairs = {expr(:(=>), quot(sym), code_getset(sym)) for sym in syms}
    :(local ($scope) = ($quot(LocalScope))(($parent), ($expr(:cell1d, pairs))))
end


# ---- @debug: instrument an AST with debug code ------------------------------

type DbgShared
    line::Integer
    file
    scopes::ObjectIdDict
    DbgShared(scopes::ObjectIdDict) = new(-1, nothing, scopes)    
end

type CodeDebug
    shared::DbgShared
    scope_sym
    syms::Set{Symbol}
end
CodeDebug(shared::DbgShared, scope) = CodeDebug(shared, scope, Set{Symbol}())

function enter(c::CodeDebug, ex)
    CodeDebug(c.shared, c.scope_sym, union(c.syms, c.shared.scopes[ex]))
end

code_debug(c::CodeDebug, exs::Vector) = {code_debug(c, ex) for ex in exs}
function code_debug(c::CodeDebug, ex::Expr)
    if contains([:line, :quote, :top, :type], ex.head); return ex; end
    if ex.head === :macrocall; return ex; end  # don't go in there for now

    scopes = c.shared.scopes
    if haskey(scopes, ex); c = enter(c, ex); end

    if ex.head === :block || ex.head === :body
        args = {}
        if !isempty(c.syms)
            # emit Scope object
            scope_sym = gensym("scope")
            push(args, code_scope(scope_sym, c.scope_sym, c.syms))
            del_all(c.syms)
            c.scope_sym = scope_sym
        end
        for arg in ex.args
            if is_linenumber(arg)
                c.shared.line = get_linenumber(arg)
                if is_expr(arg, :line, 2)
                    c.shared.file = arg.args[2]
                end
                push(args, arg)
                continue
            end
            line, file, scope = c.shared.line, c.shared.file, c.scope_sym
            push(args, :( debug_hook(($quot(line)), ($quot(file)), ($scope)) ))
            push(args, code_debug(c, arg))
        end
        return expr(ex.head, args)
    end

    return expr(ex.head, code_debug(c, ex.args))
end
code_debug(c::CodeDebug, ex) = ex

function code_debug(ex) 
#    ex = macro_expand(ex)
    println("ex =\n", ex)
    code_debug(CodeDebug(DbgShared(getdefs(ex)), quot(NoScope())), ex)
end


debug_hook(line::Int, scope::Scope) = nothing

macro debug(ex)
    globalvar = esc(gensym("globalvar"))
    quote
        ($globalvar) = false
        try
            global ($globalvar)
            ($globalvar) = true
        end
        if !($globalvar)
            error("@debug: must be applied in global scope!")
        end
        ($esc(code_debug(ex)))
    end
end


# ---- debug_eval: eval an expression inside a Scope (by substitution) --------

const updating_ops = {
 :+= => :+,   :-= => :-,  :*= => :*,  :/= => :/,  ://= => ://, :.//= => :.//,
:.*= => :.*, :./= => :./, :\= => :\, :.\= => :.\,  :^= => :^,   :.^= => :.^,
 :%= => :%,   :|= => :|,  :&= => :&,  :$= => :$,  :<<= => :<<,  :>>= => :>>,
 :>>>= => :>>>}

function resym(s::LocalScope, ex::Expr)
    head, args = ex.head, ex.args
    if head === :(=)
        if is_symbol(args[1])
            lhs = get_symbol(args[1])
            if !haskey(s, lhs) error("Cannot assign to ($lhs): not in scope.") end
            setter = get_setter(s, lhs)
            rhs = resym(s, args[2])
            expr(:call, quot(setter), rhs)
        elseif is_expr(args[1], :tuple)
            tup = esc(gensym("tuple"))
            resym(s, expr(:block, :( ($tup) = ($args[2])                ),
                                 {:( ($dest) = ($tupleref)(($tup),($k)) ) for 
                                     (dest,k)=enumerate(args[1].args)}...))
        else
            expr(head, {resym(s, arg) for arg in args})
        end
    elseif haskey(updating_ops, head) # Translate updating ops, e g x+=1 ==> x=x+1
        op = updating_ops[head]
        resym(s, :( ($args[1]) = ($op)(($args[1]), ($args[2])) ))
    elseif head === :quote || head === :top; ex
    elseif head === :escape; ex.args[1]  # bypasses substitution
    else                     expr(head, {resym(s, arg) for arg in args})
    end        
end
resym(s::LocalScope, node::SymbolNode) = resym(s, node.name)
function resym(s::LocalScope, ex::Symbol) 
    haskey(s, ex) ? :(($quot(get_getter(s, ex)))()) : ex
end
resym(s::Scope, ex) = ex

debug_eval(scope::Scope, ex) = eval(resym(scope, ex))
# function debug_eval(scope::Scope, ex) 
#     ex = resym(scope, ex)
#     println("ex = ", ex)
#     eval(ex)
# end

end  # module
