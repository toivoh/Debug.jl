
#   Debug.Meta:
# ===============
# Metaprogramming tools used throughout the Debug package

module Meta
using Base, AST
export quot, is_expr

quot(ex) = expr(:quote, {ex})

is_expr(ex,     head)          = false
is_expr(ex::Ex, head::Symbol)  = headof(ex) == head
is_expr(ex::Ex, heads::Set)    = has(heads, headof(ex))
is_expr(ex::Ex, heads::Vector) = contains(heads, headof(ex))
is_expr(ex,     head, n::Int)  = is_expr(ex, head) && nargsof(ex) == n

end # module
