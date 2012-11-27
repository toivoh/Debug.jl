
module Debug
using Base
export trap, @debug, debug_eval, Scope

include("AST.jl")
include("Analysis.jl")
include("Graft.jl")
using AST, Analysis, Graft


# tie together Analysis and Graft
instrument(trap_ex, ex) = Graft.instrument(trap_ex,    analyze(     ex, true))
graft(env::Env, scope::Scope, ex) = Graft.graft(scope, analyze(env, ex, false))
graft(scope::Scope, ex) = graft(child(NoEnv()), scope, ex)

macro debug(args...)
    code_debug(args...)
end

code_debug(ex) = code_debug(quot(trap), ex)
function code_debug(trap_ex, ex)
    globalvar = esc(gensym("globalvar"))
    @gensym trap
    quote
        $globalvar = false
        try
            global $globalvar
            $globalvar = true
        end
        if !$globalvar
            error("@debug: must be applied in global scope!")
        end
        const $(esc(trap)) = $(esc(trap_ex))
        $(quot(()->(global dostep = true)))()
        $(esc(instrument(trap, ex)))
    end
end

debug_eval(scope::NoScope, ex) = eval(ex)
function debug_eval(scope::LocalScope, ex)
    e = child(NoEnv())
    grafted = graft(e, scope, ex)

    assigned = e.assigned - scope.env.assigned
    if !isempty(e.defined)
        error("debug_eval: cannot define $(tuple(e.defined...)) in top scope")
    elseif !isempty(assigned) 
        error("debug_eval: cannot assign $(tuple(assigned...)) in top scope")
    end

    eval(expr(:let, grafted))
end

global dostep = true
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
