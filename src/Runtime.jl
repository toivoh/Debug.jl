
#   Debug.Runtime:
# ==================
# Scope data type used at runtime

module Runtime
using Base, AST
import Base.ref, Base.assign, Base.has
export Scope, NoScope, LocalScope, getter, setter


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

end # module
