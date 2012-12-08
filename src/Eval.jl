
#   Debug.Eval:
# ===============
# eval in debug scope

module Eval
using Base, AST, Runtime, Graft
export debug_eval, Scope

debug_eval(scope::ModuleScope, ex) = scope.eval(ex)
function debug_eval(scope::LocalScope, ex)
    e = child(expr(:let, ex), NoEnv()) # todo: actually wrap ex in a let?
    grafted = graft(e, scope, ex)

    assigned = e.assigned - scope.env.assigned
    if !isempty(e.defined)
        error("debug_eval: cannot define $(tuple(e.defined...)) in top scope")
    elseif !isempty(assigned) 
        error("debug_eval: cannot assign $(tuple(assigned...)) in top scope")
    end

    eval = get_eval(scope)
    eval(expr(:let, grafted))
end

end # module
