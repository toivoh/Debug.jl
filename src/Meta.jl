
#   Debug.Meta:
# ===============
# Metaprogramming tools used throughout the Debug package

module Meta
using Base, AST
export quot, is_expr

quot(ex) = expr(:quote, {ex})

# todo: doesn't handle ExNode{Block}
typealias Ex Union(Expr, ExNode{Symbol})

is_expr(ex,       head)        = false
is_expr(ex::Ex, head::Symbol)  = ex.head == head
is_expr(ex::Ex, heads::Set)    = has(heads, ex.head)
is_expr(ex::Ex, heads::Vector) = contains(heads, ex.head)
is_expr(ex, head, n::Int)      = is_expr(ex, head) && length(ex.args) == n

end  # module
