
#   Debug.Trap:
# ===============
# Interactive debug trap

module Trap
using Base, Eval
export enter_debug, trap

enter_debug() = (global dostep = true)
function trap(line::Int, file, scope::Scope)
    global dostep
    if !dostep; return; end
    print(file, "\n: ", line)
    while true
        print("\ndebug> "); flush(OUTPUT_STREAM)
        cmd = readline(stdin_stream)[1:end-1]
        if cmd == "n";     break
        elseif cmd == "r"; dostep = false; break
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
