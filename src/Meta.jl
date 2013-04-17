
#   Debug.Meta:
# ===============
# Metaprogramming tools used throughout the Debug package

module Meta
using Debug.AST
export Ex, quot, is_expr
export isblocknode, is_function, is_scope_node, is_in_type, introduces_scope
export dict_comprehension, typed_comprehension, typed_dict_comprehension
export untyped_comprehensions, typed_comprehensions, comprehensions
export headof, argsof, argof, nargsof

typealias Ex Union(Expr, ExNode)


quot(ex) = expr(:quote, {ex})

is_expr(ex::Ex, head)          = headof(ex) === head
is_expr(ex::Ex, heads::Set)    = has(heads, headof(ex))
is_expr(ex::Ex, heads::Vector) = contains(heads, headof(ex))
is_expr(ex,     head)          = false
is_expr(ex,     head, n::Int)  = is_expr(ex, head) && nargsof(ex) == n

isblocknode(node) = is_expr(node, :block)

# for both kinds of AST:s
is_function(node)     = false
is_function(node::Ex) = is_expr(node, [:function, :->], 2) ||
    (is_expr(node, :(=), 2) && is_expr(argof(node,1), :call))

# Detect whether - or _ is used in heads (changed in Julia/#2393)
if (:(Int[x for x=1:3])).head == :typed_comprehension
    const typed_dict               = :typed_dict
    const dict_comprehension       = :dict_comprehension
    const typed_comprehension      = :typed_comprehension
    const typed_dict_comprehension = :typed_dict_comprehension
else
    const typed_dict               = symbol("typed-dict")
    const dict_comprehension       = symbol("dict-comprehension")
    const typed_comprehension      = symbol("typed-comprehension")
    const typed_dict_comprehension = symbol("typed-dict-comprehension")
end

const untyped_comprehensions = [:comprehension, dict_comprehension]
const typed_comprehensions   = [typed_comprehension, typed_dict_comprehension]
const comprehensions = [untyped_comprehensions, typed_comprehensions]

const scope_heads = Set(:while, :try, :for, :let, comprehensions...)
is_scope_node(ex) = is_expr(ex, scope_heads) || is_function(ex)

# only for Node/Nothing
is_in_type(::Nothing) = false
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
