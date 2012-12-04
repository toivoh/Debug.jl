
#   Debug.Eval:
# ===============
# eval in debug scope

module Eval
using Base, AST, Analysis, Graft
export debug_eval, Scope

# tie together Analysis and Graft
graft(env::Env, scope::Scope, ex) = Graft.graft(scope, analyze(env, ex, false))
graft(scope::Scope, ex) =                 graft(child(NoEnv()), scope, ex)

debug_eval(scope::NoScope, ex) = eval(ex)
function debug_eval(scope::LocalScope, ex)
    e = child(expr(:let, ex), NoEnv()) # todo: actually wrap ex in a let?
    grafted = graft(e, scope, ex)

    assigned = e.assigned - scope.env.assigned
    if !isempty(e.defined)
        error("debug_eval: cannot define $(tuple(e.defined...)) in top scope")
    elseif !isempty(assigned) 
        error("debug_eval: cannot assign $(tuple(assigned...)) in top scope")
    end

    eval(expr(:let, grafted))
end

end # module
