
module Debug
using Base
export trap, @debug, debug_eval, Scope

include("AST.jl")
include("Analysis.jl")
include("Graft.jl")
using AST, Analysis, Graft


trap(args...) = error("No debug trap installed for ", typeof(args))

# tie together Analysis and Graft
instrument(trap_ex, ex) = Graft.instrument(trap_ex,    analyze(     ex, true))
graft(env::Env, scope::Scope, ex) = Graft.graft(scope, analyze(env, ex, false))
graft(scope::Scope, ex) = graft(child(NoEnv()), scope, ex)

macro debug(args...)
    code_debug(args...)
end

code_debug(ex) = code_debug(quot(trap), ex)
function code_debug(trap_ex, ex)
    globalvar = esc(gensym("globalvar"))
    @gensym trap
    quote
        $globalvar = false
        try
            global $globalvar
            $globalvar = true
        end
        if !$globalvar
            error("@debug: must be applied in global scope!")
        end
        const $(esc(trap)) = $(esc(trap_ex))
        $(esc(instrument(trap, ex)))
    end
end

debug_eval(scope::NoScope, ex) = eval(ex)
function debug_eval(scope::LocalScope, ex)
    e = child(NoEnv())
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
