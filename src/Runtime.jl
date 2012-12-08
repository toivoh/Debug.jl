
#   Debug.Runtime:
# ==================
# Scope data type used at runtime

module Runtime
using Base, AST, Meta
import Base.ref, Base.assign, Base.has, Base.isequal
export Scope, ModuleScope, LocalScope, getter, setter
export Frame, parent_frame, enclosing_scope_frame, scope_frameof


# ---- Scope: runtime symbol table with getters and setters -------------------

abstract Scope

type ModuleScope <: Scope; end
type LocalScope <: Scope
    parent::Scope
    syms::Dict
    env::Env
end

has(s::ModuleScope, sym::Symbol) = false
has(s::LocalScope,  sym::Symbol) = has(s.syms, sym) || has(s.parent, sym)

function get_entry(scope::LocalScope, sym::Symbol)
    has(scope.syms, sym) ? scope.syms[sym] : get_entry(scope.parent, sym)
end

getter(scope::LocalScope, sym::Symbol) = get_entry( scope, sym)[1]
setter(scope::LocalScope, sym::Symbol) = get_entry( scope, sym)[2]
ref(   scope::LocalScope,     sym::Symbol) = getter(scope, sym)()
assign(scope::LocalScope, x,  sym::Symbol) = setter(scope, sym)(x)


# ---- Frame: Runtime node instance -------------------------------------------

type Frame
    node::Node
    scope::Scope
end
isequal(f1::Frame, f2::Frame) = (f1.node === f2.node && f1.scope === f2.scope)

function parent_frame(f::Frame)
    @assert !is_function(f.node)
    node = parentof(f.node)
    Frame(node, introduces_scope(node) ? f.scope.parent : f.scope)
end

enclosing_scope_frame(f::Frame) = scope_frameof(parent_frame(f))

scope_frameof(f::Frame) = is_scope_node(f.node) ? f : parent_frame(f)

end # module
