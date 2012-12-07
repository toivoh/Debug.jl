include(find_in_path("Debug.jl"))

module TestStep
using Base, Debug, Debug.Flow

state = DBState()
ip    = 1

function trap(node, scope::Scope)
    global firstline, ip
    if isa(node, BPNode);  firstline = node.loc.line;  end
    if !Flow.trap(state, node, scope); return; end

    line = node.loc.line - firstline + 1
    @show line

    l, f = instructions[ip]
    ip += 1
    @assert line == l
    if f === stepout!; stepout!(state, node, scope)
    else               f(state)
    end
end

macro test_step(ex)
    Debug.code_debug(Flow.instrument(trap, ex))
end

const instructions = {
    (2, singlestep!), (3, singlestep!), (4, singlestep!),
    (6, stepover!), (9, stepover!),
    (10, singlestep!), (11, stepout!),
    (14, continue!),
}

@test_step let
    @bp         #  1
    let         #  2
        x = 1   #  3
        y = 2   #  4
    end
    let         #  6
        x = 1   #  7
    end
    x = 5       #  9
    let         # 10
        x = 1   # 11
        y = 2   # 12
    end
    x = 6       # 14
    y = 7       # 15
end

@assert ip == length(instructions)+1

end  # module
