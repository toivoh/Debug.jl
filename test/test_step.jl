include(find_in_path("Debug.jl"))

module TestStep
using Base, Debug, Debug.Flow

state = DBState()
ip    = 1

function trap(node, scope::Scope)
    global firstline, ip
    if isa(node, BPNode);  firstline = node.loc.line;  end
    if !Flow.pretrap(state, node, scope); return; end

    line = node.loc.line - firstline + 1
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
    (1, stepover!), 
    (2, singlestep!), (3, singlestep!), (4, singlestep!),
    (6, stepover!), (9, stepover!),
    (10, singlestep!), (11, stepout!),
    (14, stepover!),
    (17, singlestep!), (18, stepout!),
    (20, stepover!),
    (23, singlestep!), (24, stepout!),
    (26, stepover!),
    (29, singlestep!), (30, stepout!),
    (32, stepover!),
    (35, singlestep!), (36, stepout!),
    (38, singlestep!), 
    (42, stepover!),
    (43, singlestep!), (39, stepout!),
    (44, continue!),
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
    for x=1:3   # 14
        z=x^2   # 15
    end
    for x=1:3   # 17
        z=x^2   # 18
    end
    while x>0   # 20
        x-=1    # 21
    end
    while x<5   # 23
        x+=1    # 24
    end
    try         # 26
        x       # 27
    end
    try         # 29
        x       # 30
    end
    [begin      # 32
       x^2      # 33
     end for x=1:3]
    [begin      # 35
       x^2      # 36
     end for x=1:3]
     function f(x) # 38
         x -= 1 # 39
         2x     # 40
     end
     f(3)       # 42
     f(4)       # 43
     y = 7      # 44
     y = 8      # 45
end

@assert ip == length(instructions)+1

end  # module
