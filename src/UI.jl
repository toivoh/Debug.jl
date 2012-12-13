
#   Debug.UI:
# =============
# Interactive debug trap

module UI
using Base, Meta, AST, Eval, Flow
export trap

const helptext = 
E"Commands:
--------
h: display this help text
s: step into
n: step over any enclosed scope
o: step out from the current scope
c: continue to next breakpoint
q: quit debug session (calls error(\"interrupted\"))
To e.g. evaluate the variable named `n`, enter it as ` n` (with a space).

Debug variables:
---------------
$n:    current node
$s:    current scope
$bp:   Set{Node} of enabled breakpoints
$nobp: Set{Node} of disabled @bp breakpoints
$pre:  Dict{Node} of grafts

Example usage:
-------------
add($bp, $n)          # set breakpoint at the current node
del($bp, $n)          # unset breakpoint at the current node
add($nobp, $n)        # ignore @bp breakpoint at the current node
$pre[$n] = :(x = 0) # execute x=0 just before the current node, at each visit"


instrument(ex) = Flow.instrument(trap, ex)

state = DBState()
function trap(node, scope::Scope)
    if Flow.pretrap(state, node, scope)
        print("\nat ", node.loc.file, ":", node.loc.line)
        while true
            print("\ndebug:$(node.loc.line)> "); flush(OUTPUT_STREAM)
            cmd = readline(stdin_stream)[1:end-1]
            if cmd == "s";     break
            elseif cmd == "n"; stepover!(state); break
            elseif cmd == "o"; stepout!(state, node, scope);  break
            elseif cmd == "c"; continue!(state); break
            elseif cmd == "q"; continue!(state); error("interrupted")
            elseif cmd == "h"; println(helptext)
            else
                try
                    ex0, nc = parse(cmd)
                    ex = interpolate({
                            :st => state, :n => node, :s => scope,
                            :bp => state.breakpoints, :nobp => state.ignore_bp,
                            :pre => state.grafts}, 
                        ex0)
                    r = debug_eval(scope, ex)
                    if !is(r, nothing); show(r); println(); end
                catch e
                    println(e)
                end
            end
        end
    end
    Flow.posttrap(state, node, scope)
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
