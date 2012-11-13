
module Debug
using Base
export instrument

macro show(ex)
    quote
        print($(string(ex,"\t=")))
        show($ex)
    end
end


# ---- Helpers ----------------------------------------------------------------

is_linenumber(ex::LineNumberNode) = true
is_linenumber(ex::Expr)           = is(ex.head, :line)
is_linenumber(ex)                 = false

get_linenumber(ex::Expr)           = ex.args[1]
get_linenumber(ex::LineNumberNode) = ex.line


# ---- instrument -------------------------------------------------------------

instrument(ex) = ex
function instrument(ex::Expr)
    head, args = ex.head, ex.args
    if contains([:line, :quote, :top, :macrocall, :type], head)
        ex
    elseif head === :block
        code = {}
        for arg in args
            if !is_linenumber(arg)            
                push(code, :(debug_hook()))
            end
            push(code, instrument(arg))
        end
        expr(head, code)
    else
        expr(head, {instrument(arg) for arg in args})
    end
end

end # module