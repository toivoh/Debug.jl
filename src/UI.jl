
#   Debug.UI:
# =============
# Interactive debug trap

module UI
using Base, Meta, AST, Eval
import AST.is_trap
export trap, @bp, BreakPoint

type BreakPoint <: Trap; end
is_trap(::BreakPoint) = true

macro bp()
    Leaf(BreakPoint())
end

dostep = false
trap(::BreakPoint, scope::Scope) = (global dostep = true)
function trap(loc::Loc, scope::Scope)
    global dostep
    if !dostep; return; end
    print("\nat ", loc.file, ":", loc.line)
    while true
        print("\ndebug:$(loc.line)> "); flush(OUTPUT_STREAM)
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
