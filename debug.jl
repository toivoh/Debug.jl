
module Debug
using Base
export trap, @debug, debug_eval, Scope

include("AST.jl")
include("Analysis.jl")
include("Graft.jl")
using AST, Analysis, Graft


trap(args...) = error("No debug trap installed for ", typeof(args))

# tie together Analysis and Graft
instrument(trap_ex, ex) = Graft.instrument(trap_ex, analyze(ex, true))
graft(scope::Scope, ex) = Graft.graft(scope,        analyze(ex, false))


macro debug(ex)
    globalvar = esc(gensym("globalvar"))
    quote
        $globalvar = false
        try
            global $globalvar
            $globalvar = true
        end
        if !$globalvar
            error("@debug: must be applied in global scope!")
        end
        $(esc(instrument(quot(trap), ex)))
    end
end

#debug_eval(scope::Scope, ex) = eval(graft(scope, ex))
debug_eval(scope::NoScope, ex) = eval(ex)
function debug_eval(scope::LocalScope, ex)
    ex2 = graft(scope, ex)
    eval(ex2)
#     eval(graft(scope, ex)) # doesn't work?
end

end # module
