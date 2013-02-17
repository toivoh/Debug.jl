
module Debug
export @debug, @instrument, @bp, debug_eval, Scope, Node, isblocknode, BPNode

include(Base.find_in_path("Debug/src/AST.jl"))
include(Base.find_in_path("Debug/src/Meta.jl"))
include(Base.find_in_path("Debug/src/Analysis.jl"))
include(Base.find_in_path("Debug/src/Runtime.jl"))
include(Base.find_in_path("Debug/src/Graft.jl"))
include(Base.find_in_path("Debug/src/Eval.jl"))
include(Base.find_in_path("Debug/src/Flow.jl"))
include(Base.find_in_path("Debug/src/UI.jl"))
using AST, Meta, Analysis, Graft, Eval, Flow, UI

is_trap(::Event)    = false
is_trap(::LocNode)  = false
is_trap(node::Node) = isblocknode(parentof(node))

macro debug(ex)
    code_debug(UI.instrument(ex))
end
macro instrument(trap_ex, ex)
    @gensym trap_var
    code_debug(quote
        const $trap_var = $trap_ex
        $(instrument(is_trap, trap_var, ex))
    end)
end

function code_debug(ex)
    globalvar = esc(gensym("globalvar"))
    quote
        $globalvar = false
        try
            global $globalvar
            $globalvar = true
        end
        if !$globalvar
            error("@debug: must be applied in global (i.e. module) scope!")
        end
        $(esc(ex))
    end
end

end # module
