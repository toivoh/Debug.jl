
#   Debug.Meta:
# ===============
# Metaprogramming tools used throughout the Debug package

module Meta
using Base
export quot, is_expr

quot(ex) = expr(:quote, {ex})

is_expr(ex,       head)           = false
is_expr(ex::Expr, head::Symbol)   = ex.head == head
is_expr(ex::Expr, heads::Set)     = has(heads, ex.head)
is_expr(ex::Expr, heads::Vector)  = contains(heads, ex.head)
is_expr(ex, head::Symbol, n::Int) = is_expr(ex, head) && length(ex.args) == n

end # module
