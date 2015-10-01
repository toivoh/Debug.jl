
#   Debug.Meta:
# ===============
# Metaprogramming tools used throughout the Debug package

module Meta
using Compat, Debug.AST
export Ex, quot, is_expr
export isblocknode, is_function, is_scope_node, is_in_type, introduces_scope
export untyped_comprehensions, typed_comprehensions, comprehensions
export headof, argsof, argof, nargsof

typealias Ex @compat(Union{Expr, ExNode})


quot(ex) = QuoteNode(ex)

is_expr(ex::Ex, head)          = headof(ex) === head
is_expr(ex::Ex, heads::Set)    = headof(ex) in heads
is_expr(ex::Ex, heads::Vector) = headof(ex) in heads
is_expr(ex,     head)          = false
is_expr(ex,     head, n::Int)  = is_expr(ex, head) && nargsof(ex) == n

isblocknode(node) = is_expr(node, :block)

# for both kinds of AST:s
is_function(node)     = false
is_function(node::Ex) = is_expr(node, [:function, :->], 2) ||
    (is_expr(node, :(=), 2) && is_expr(argof(node,1), :call))

const untyped_comprehensions = [:comprehension, :dict_comprehension]
const typed_comprehensions   = [:typed_comprehension,
                                :typed_dict_comprehension]
const comprehensions = [untyped_comprehensions; typed_comprehensions]

const scope_heads = Set([:while; :try; :for; :let; comprehensions...])
is_scope_node(ex) = is_expr(ex, scope_heads) || is_function(ex)

# only for Node/Nothing
if VERSION >= v"0.4.0-dev"
    is_in_type(::Void) = false
else
    is_in_type(::Nothing) = false
end
function is_in_type(node::Node)
    if isa(node.state, Rhs)
        isa(envof(node), LocalEnv) && is_expr(envof(node).source, :type)
    else
        is_in_type(parentof(node))
    end
end

# only for Node
introduces_scope(node::Node) = node.introduces_scope

## Accessors that work on both Expr:s and ExNode:s ##

headof(ex::Expr)   = ex.head
headof(ex::ExNode) = valueof(ex).head

argsof(ex::Expr)   = ex.args
argsof(ex::ExNode) = valueof(ex).args

nargsof(ex)  = length(argsof(ex))
argof(ex, k) = argsof(ex)[k]


end # module
