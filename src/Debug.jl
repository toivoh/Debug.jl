
module Debug
using Base
export @debug, @bp, debug_eval, Scope, Node, BlockNode, BPNode

include(find_in_path("Debug/src/AST.jl"))
include(find_in_path("Debug/src/Meta.jl"))
include(find_in_path("Debug/src/Analysis.jl"))
include(find_in_path("Debug/src/Graft.jl"))
include(find_in_path("Debug/src/Eval.jl"))
include(find_in_path("Debug/src/UI.jl"))
using AST, Meta, Analysis, Graft, Eval, UI

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

end # module
