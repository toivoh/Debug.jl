
module Debug
using Base
export instrument, trap

macro show(ex)
    quote
        print($(string(ex,"\t=")))
        show($ex)
    end
end


trap(args...) = error("No debug trap installed for ", typeof(args))

# ---- Helpers ----------------------------------------------------------------

quot(ex) = expr(:quote, ex)

is_expr(ex, head::Symbol) = (isa(ex, Expr) && (ex.head == head))
is_expr(ex, head::Symbol, n::Int) = is_expr(ex, head) && length(ex.args) == n

is_linenumber(ex::LineNumberNode) = true
is_linenumber(ex::Expr)           = is(ex.head, :line)
is_linenumber(ex)                 = false

get_linenumber(ex::Expr)           = ex.args[1]
get_linenumber(ex::LineNumberNode) = ex.line


# ---- instrument -------------------------------------------------------------

type Context
    line::Int
    file::String
end
Context() = Context(0, "")

instrument(ex) = instrument(Context(), ex)

instrument(c::Context, ex) = ex
function instrument(c::Context, ex::Expr)
    head, args = ex.head, ex.args
    if contains([:line, :quote, :top, :macrocall, :type], head)
        ex
    elseif head === :block
        code = {}
        for arg in args
            if is_linenumber(arg)
                c.line = get_linenumber(arg)
                if is_expr(arg, :line, 2); c.file = arg.args[2]; end
                
                push(code, arg)
            else
                push(code, :($(quot(trap))($(c.line), $(quot(c.file)))) )
                push(code, instrument(arg))
            end
        end
        expr(head, code)
    else
        expr(head, {instrument(arg) for arg in args})
    end
end

end # module