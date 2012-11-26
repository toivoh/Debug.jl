
module Debug
using Base
export trap, @debug, debug_eval, Scope

include("AST.jl")
include("Analysis.jl")
include("Graft.jl")
using AST, Analysis, Graft

# tie together Analysis and Graft
instrument(ex)          = Graft.instrument(analyze(ex))
graft(scope::Scope, ex) = Graft.graft(scope, analyze(ex))


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
        $(esc(instrument(ex)))
    end
end

#debug_eval(scope::Scope, ex) = eval(graft(scope, ex))
function debug_eval(scope::Scope, ex)
    ex2 = graft(scope, ex)
    eval(ex2)
#     eval(graft(scope, ex)) # doesn't work?
end

end # module
