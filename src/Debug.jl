
module Debug

include(Pkg.dir("Debug","src","AST.jl"))
include(Pkg.dir("Debug","src","Meta.jl"))
include(Pkg.dir("Debug","src","Analysis.jl"))
include(Pkg.dir("Debug","src","Runtime.jl"))
include(Pkg.dir("Debug","src","Graft.jl"))
include(Pkg.dir("Debug","src","Eval.jl"))
include(Pkg.dir("Debug","src","Flow.jl"))
include(Pkg.dir("Debug","src","UI.jl"))
using Debug.AST, Debug.Meta, Debug.Analysis, Debug.Graft, Debug.Eval
using Debug.Flow, Debug.UI

# It seems that @instrument has to be exported in order not to be deleted
export @debug, @bp, @instrument

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
