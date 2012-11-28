Debug.jl v0
===========
Prototype interactive debugger for [julia](julialang.org)

Installation
------------
In julia, install the `Debug` package:

    load("pkg.jl")
    Pkg.init()  # If you haven't done it before
    Pkg.add("Debug")

Interactive Usage
-----------------
Use the `@debug` macro to mark code that you want to step through.
`@debug` can only be used in global scope, since it needs access to all
scopes that surround a piece of code to be analyzed.

Simple example:

    julia> load("Debug.jl")

    julia> using Debug

    julia> @debug begin
               x = 0
               for k=1:2
                   x += k
               end
               x
           end

    at :2
    debug:2> x
    x not defined

    debug:2> s

    at :3
    debug:3> x
    0

    debug:3> x = 10
    10

    debug:3> s

    at :4
    debug:4> x
    10

    debug:4> s

    at :4
    debug:4> x
    11

    debug:4> s

    at :6
    debug:6> x
    13

    debug:6> x += 3
    16

    debug:6> s
    16

    julia>

The following single-character commands have special meaing:   
`s`: step into    
`c`: continue running    
`q`: quit debug session (calls `error("interrupted")`)    
Any command string that is not one of these single characters is parsed
and evaluated in the current scope.

Custom Traps
------------
The `@debug` macro takes an optional trap function to be used instead of
the default interactive trap. The example

    load("Debug.jl")
    using Base, Debug

    firstline = -1
    function trap(loc::Loc, scope::Scope) 
        global firstline = (firstline == -1) ? loc.line : firstline
        line = loc.line - firstline + 1
        print(line, ":")

        if (line == 2); debug_eval(scope, :(x += 1)) end

        if (line >  1); print("\tx = ", debug_eval(scope, :x)) end
        if (line == 3); print("\tk = ", debug_eval(scope, :k)) end
        println()
    end

    @debug trap function f(n)
        x = 0       # line 1
        for k=1:n   # line 2
            x += k  # line 3
        end         # line 4
        x = x*x     # line 5
        x           # line 6
    end

    f(3)

produces the output

    1:
    2:	x = 1
    3:	x = 1	k = 1
    3:	x = 2	k = 2
    3:	x = 4	k = 3
    5:	x = 7
    7:	x = 49

The `scope` argument passed to the `trap` function can be used with
`debug_eval(scope, ex)` to evaluate an expression `ex` as if it were in 
that scope.
