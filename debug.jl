
module Debug
using Base
export trap, @debug, debug_eval, Scope

include("AST.jl")
include("Analysis.jl")
include("Graft.jl")
include("Eval.jl")
include("Trap.jl")
using AST, Analysis, Graft, Eval, Trap

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
        $(quot(()->(global dostep = true)))()
        $(esc(instrument(trap, ex)))
    end
end

end # module
