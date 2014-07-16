
#   Debug.Runtime:
# ==================
# Scope data type used at runtime

module Runtime
using Debug.AST, Debug.Meta
import Base: haskey, isequal, getindex, setindex!
export Scope, ModuleScope, LocalScope, getter, setter, get_eval
export Frame, parent_frame, enclosing_scope_frame, scope_frameof


# ---- Scope: runtime symbol table with getters and setters -------------------

abstract Scope

type ModuleScope <: Scope
    eval::Function
end
type LocalScope <: Scope
    parent::Scope
    syms::Dict
    env::Env
end

haskey(s::ModuleScope, sym::Symbol) = false
haskey(s::LocalScope,  sym::Symbol) = haskey(s.syms, sym) || haskey(s.parent, sym)

function get_entry(scope::LocalScope, sym::Symbol)
    haskey(scope.syms, sym) ? scope.syms[sym] : get_entry(scope.parent, sym)
end

getter(scope::LocalScope, sym::Symbol) = get_entry( scope, sym)[1]
setter(scope::LocalScope, sym::Symbol) = get_entry( scope, sym)[2]
getindex(scope::LocalScope, sym::Symbol) = getter(scope,sym)()
setindex!(scope::LocalScope, x,  sym::Symbol) = setter(scope, sym)(x)

get_eval(scope::ModuleScope) = scope.eval
get_eval(scope::LocalScope)  = get_eval(scope.parent)


# ---- Frame: Runtime node instance -------------------------------------------

type Frame
    node::Node
    scope::Scope
end
isequal(f1::Frame, f2::Frame) = (f1.node === f2.node && f1.scope === f2.scope)
==(f1::Frame, f2::Frame)      = (f1.node === f2.node && f1.scope === f2.scope)

function parent_frame(f::Frame)
    @assert !is_function(f.node)
    node = parentof(f.node)
    Frame(node, introduces_scope(node) ? f.scope.parent : f.scope)
end

enclosing_scope_frame(f::Frame) = scope_frameof(parent_frame(f))

scope_frameof(f::Frame) = is_scope_node(f.node) ? f : parent_frame(f)

end # module
