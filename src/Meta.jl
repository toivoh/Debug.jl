
#   Debug.Meta:
# ===============
# Metaprogramming tools used throughout the Debug package

module Meta
using Base, AST
export Ex, quot, is_expr, isblocknode
export headof, argsof, argof, nargsof

typealias Ex Union(Expr, ExNode)


quot(ex) = expr(:quote, {ex})

is_expr(ex::Ex, head)          = headof(ex) === head
is_expr(ex::Ex, heads::Set)    = has(heads, headof(ex))
is_expr(ex::Ex, heads::Vector) = contains(heads, headof(ex))
is_expr(ex,     head)          = false
is_expr(ex,     head, n::Int)  = is_expr(ex, head) && nargsof(ex) == n

isblocknode(node) = is_expr(node, :block)

## Accessors that work on both Expr:s and ExNode:s ##

headof(ex::Expr)   = ex.head
headof(ex::ExNode) = valueof(ex).head

argsof(ex::Expr)   = ex.args
argsof(ex::ExNode) = valueof(ex).args

nargsof(ex)  = length(argsof(ex))
argof(ex, k) = argsof(ex)[k]

end # module
