
#   Debug.UI:
# =============
# Interactive debug trap

module UI
using Base, Meta, AST, Eval, Flow
export trap

instrument(ex) = Flow.instrument(trap, ex)

state = DBState()
function trap(node, scope::Scope)
    if !Flow.trap(state, node, scope); return; end
    print("\nat ", node.loc.file, ":", node.loc.line)
    while true
        print("\ndebug:$(node.loc.line)> "); flush(OUTPUT_STREAM)
        cmd = readline(stdin_stream)[1:end-1]
        if cmd == "s";     break
        elseif cmd == "n"; stepover!(state); break
        elseif cmd == "o"; stepout!(state, node, scope);  break
        elseif cmd == "c"; continue!(state); break
        elseif cmd == "q"; continue!(state); error("interrupted")
        end

        try
            ex0, nc = parse(cmd)
            ex = interpolate({:st => state, :n => node, :s => scope,
                              :bp => state.breakpoints, 
                              :pre => state.grafts}, ex0)
            r = debug_eval(scope, ex)
            if !is(r, nothing); show(r); println(); end
        catch e
            println(e)
        end
    end    
end

interpolate(d::Dict, ex) = ex  # including QuoteNode
function interpolate(d::Dict, ex::Ex)
    if is_expr(ex, :$, 1)
        translate(d, argof(ex, 1))
    elseif headof(ex) === :quote
        ex
    else
        expr(headof(ex), {interpolate(d, arg) for arg in ex.args})
    end
end

translate(d::Dict, ex) = error("translate: unimplemented for ex=$ex")
translate(d::Dict, ex::Symbol) = has(d, ex) ? quot(d[ex]) : Node(Plain(ex))

end # module
