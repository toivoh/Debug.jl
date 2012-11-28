
#   Debug.Trap:
# ===============
# Interactive debug trap

module Trap
using Base, AST, Eval
export enter_debug, trap

enter_debug() = (global dostep = true)
function trap(loc::Loc, scope::Scope)
    global dostep
    if !dostep; return; end
    print("\nat ", loc.file, ":", loc.line)
    while true
        print("\ndebug:$(loc.line)> "); flush(OUTPUT_STREAM)
        cmd = readline(stdin_stream)[1:end-1]
        if cmd == "s";     break
        elseif cmd == "c"; dostep = false; break
        elseif cmd == "q"; error("interrupted")
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
