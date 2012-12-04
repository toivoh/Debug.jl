
#   Debug.UI:
# =============
# Interactive debug trap

module UI
using Base, Meta, AST, Eval, Flow
export trap

state = DBState()
function trap(node::Node, scope::Scope)
    if !Flow.trap(state, node, scope); return; end
    print("\nat ", node.loc.file, ":", node.loc.line)
    while true
        print("\ndebug:$(node.loc.line)> "); flush(OUTPUT_STREAM)
        cmd = readline(stdin_stream)[1:end-1]
        if cmd == "s";     break
        elseif cmd == "c"; state.singlestep = false; break
        elseif cmd == "q"; state.singlestep = false; error("interrupted")
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
