
#   Debug.UI:
# =============
# Interactive debug trap

module UI
using Base, Meta, AST, Eval
import AST.is_emittable
export trap, @bp, BPNode

type BreakPoint <: Trap; end
typealias BPNode Leaf{BreakPoint}
is_emittable(::BPNode) = false


macro bp()
    Leaf(BreakPoint())
end

dostep = false
trap(::BPNode,    scope::Scope) = (global dostep = true)
trap(::BlockNode, scope::Scope) = nothing
function trap(node::Node, scope::Scope)
    global dostep
    if !dostep; return; end
    print("\nat ", node.loc.file, ":", node.loc.line)
    while true
        print("\ndebug:$(node.loc.line)> "); flush(OUTPUT_STREAM)
        cmd = readline(stdin_stream)[1:end-1]
        if cmd == "s";     break
        elseif cmd == "c"; dostep = false; break
        elseif cmd == "q"; dostep = false; error("interrupted")
        end

        try
            ex, nc = parse(cmd)
            r = debug_eval(scope, ex)
            if !is(r, nothing); show(r); println(); end
        catch e
            println(e)
        end
    end
end

end # module
