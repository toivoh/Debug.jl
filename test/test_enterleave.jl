
include(find_in_path("Debug.jl"))

module TestTrap
import Debug
using Base, Debug, Debug.AST, Debug.Meta

is_trap(node)    = false
is_trap(::Event) = true

ip = 1

function trap(e::Event, s::Scope)
    global ip
    @assert isa(e, answers[ip][1])
    @assert answers[ip][2] === headof(e.node)
    ip += 1
end
function output(x)
    global ip
    @assert answers[ip] == x
    ip += 1
end


macro test_enterleave(ex)
    Debug.code_debug(Debug.Graft.instrument(is_trap, trap, ex))
end

answers = {
    (Enter,:while), (Leave,:while),
    (Enter,:while), 1, 2, 3, (Leave,:while),
    (Enter,:try), (Enter,:while), (Leave,:while), :try, (Leave,:try),
    (Enter,:for), 2, 3, 4, (Leave,:for),
    (Enter,:let), 5, (Leave,:let), 5,
    (Enter,:comprehension), 12, 13, (Leave,:comprehension), [12,13],
    (Enter,:function), 9, (Leave,:function), 81
}

@test_enterleave begin
    while false
    end
    i = 0
    while i < 3
        i += 1
        output(i)
    end

    try
        while false
        end
        output(:try)
    end    

    for x=2:4
        output(x)
    end
    
    output(let x=5
        output(x)
        x
    end)

    output([(output(x); x) for x=12:13])

    function f(x)
        output(x)
        x^2
    end

    output(f(9))
end

@assert ip == length(answers) + 1

end # module
