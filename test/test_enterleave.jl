module TestTrap
import Debug
using Compat, Debug, Debug.AST, Debug.Meta
import Debug.Node, Debug.Scope

is_trap(::Node) = false
is_trap(node::ExNode) = isblocknode(parentof(node))
is_trap(::@compat(Union{Event})) = true

ip = 1

function trap(e::Event, s::Scope)
    global ip
#    println(typeof(e), headof(e.node))
    @assert isa(e, answers[ip][1])
    @assert answers[ip][2] === headof(e.node)
    ip += 1
end
function trap(node::ExNode, s::Scope)
    global ip
#    println(headof(node))
    @assert answers[ip] == headof(node)
    ip += 1
end
function output(x)
    global ip
#    println(x)
    @assert answers[ip] == x
    ip += 1
end


macro test_enterleave(ex)
    Debug.code_debug(Debug.Graft.instrument(is_trap, trap, ex))
end

answers = Any[
    :while, (Enter,:while), (Leave,:while),
    :(=),
    :while,(Enter,:while),:+=,:call,1,:+=,:call,2,:+=,:call,3,(Leave,:while),
    :try, (Enter,:try),
        :while, (Enter,:while), (Leave,:while), :call, "try",
    (Leave,:try),
    :for, (Enter,:for), :call, 2, :call, 3, :call, 4, (Leave,:for),
    :call, (Enter,:let), :call, 5, (Leave,:let), 5,
    :call, (Enter,:comprehension),
        :call, 12, :call, 13,
    (Leave,:comprehension), [12,13],
    :function,
    :call, (Enter,:function), :call, 9, :call, (Leave,:function), 81
]

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
        output("try")
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
