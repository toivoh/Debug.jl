
module Debug
using Base
export trap, instrument
#import Base.promote_rule

macro show(ex)
    quote
        print($(string(ex,"\t= ")))
        show($ex)
        println()
    end
end


trap(args...) = error("No debug trap installed for ", typeof(args))


# ---- Helpers ----------------------------------------------------------------

quot(ex) = expr(:quote, ex)

is_expr(ex,       head::Symbol)   = false
is_expr(ex::Expr, head::Symbol)   = ex.head == head
is_expr(ex, head::Symbol, n::Int) = is_expr(ex, head) && length(ex.args) == n

is_linenumber(ex::LineNumberNode) = true
is_linenumber(ex::Expr)           = is(ex.head, :line)
is_linenumber(ex)                 = false

is_file_linenumber(ex)            = is_expr(ex, :line, 2)

get_linenumber(ex::Expr)           = ex.args[1]
get_linenumber(ex::LineNumberNode) = ex.line
get_sourcefile(ex::Expr)           = string(ex.args[2])

const doublecolon = symbol("::")
const typed_comprehension = symbol("typed-comprehension")


function replicate_last{T}(v::Vector{T}, n)
    if n < length(v)-1; error("replicate_last: cannot shrink v more!"); end
    [v[1:end-1], fill(v[end], n+1-length(v))]
end


# ---- instrument -------------------------------------------------------------

type Leaf{T};  ex::T;                           end
type Line{T};  ex::T; line::Int; file::String;  end

analyze(ex) = analyze("", ex)

analyze(file::String, ex) = Leaf(ex)
analyze(file::String, ex::LineNumberNode) = Line(ex, ex.line, file)
function analyze(file::String, ex::Expr)
    head, args = ex.head, ex.args
    if head === :line; Line(ex, ex.args[1], file)
    elseif contains([:quote, :top, :macrocall, :type], head) Leaf(ex)
    else expr(head, {
        begin
            if is_expr(arg, :line, 2); file = string(arg.args[2]); end
            analyze(file, arg) 
        end 
        for arg in args })
    end
end

instrument(ex) = instrument_(analyze(ex))

instrument_(node::Union(Leaf,Line)) = node.ex
function instrument_(ex::Expr)
    head, args = ex.head, ex.args
    if head === :block
        code = {}
        for arg in args
            push(code, instrument_(arg))
            if isa(arg, Line)
                push(code, :($(quot(trap))($(arg.line), $(quot(arg.file)))) )
            end
        end
        expr(head, code)
    else
        expr(head, {instrument_(arg) for arg in args})
    end
end

end # module
