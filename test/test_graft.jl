include("debug.jl")

module TestGraft
export @syms
using Base, Debug, Debug.Analysis
const is_expr = Debug.Analysis.is_expr
export cut_grafts, @test_graft

macro graft(args...)
    error("Should never be invoked directly!")
end

macro test_graft(ex)
    stem, grafts = cut_grafts(ex)
    grafts = tuple(grafts...)  # make grafts work as just a value
    @gensym trap
    code = esc(quote
        $trap(line, file, scope) = debug_eval(scope, $(quot(grafts))[line])
        $(Debug.instrument(trap, stem))
    end)
    @show code
    code
end

cut_grafts(ex) = (grafts = {}; (cut_grafts!(grafts, ex), grafts))

cut_grafts!(grafts::Vector, ex) = ex
function cut_grafts!(grafts::Vector, ex::Expr)
    code = {}
    for arg in ex.args
        if Debug.Analysis.is_linenumber(arg)
            # omit the original line numbers
        elseif is_expr(arg, :macrocall) && arg.args[1] == symbol("@graft")
            @assert length(arg.args) == 2                
            push(grafts, arg.args[2])
            push(code, expr(:line, length(grafts)))
        else
            push(code, cut_grafts!(grafts, arg))
        end
    end
    expr(ex.head, code)
end

@test_graft begin
    let
        local x = 11
        @graft (@assert x == 11; x = 2)
        @assert x == 2
    end
end

end # module
