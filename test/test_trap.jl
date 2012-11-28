include(find_in_path("Debug.jl"))

module TestTrap
using Base, Debug

trap(args...) = nothing


@debug trap function f(n)
    x = 0  # this must be line #10
    for k=1:n
        x += k
    end
    x = x*x
    x
end

function trap(loc::Loc, scope::Scope) 
    line = loc.line
    print(line, ":")
    if (line >  10) print("\tx = ", scope[:x]) end
    if (line == 12) print("\tk = ", scope[:k]) end
    println()
end

f(3)

end
