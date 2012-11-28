Debug.jl v0
===========
Prototype interactive debugger for [julia](julialang.org).

Installation
------------
Install the `Debug` julia package:

    load("pkg.jl")
    Pkg.init()  # If you haven't done it before
    Pkg.add("Debug")

Usage
-----
Use the `@debug` macro to mark code that you want to step through.
`@debug` must be used in global scope.

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
`q`: interrupt debug session (calls `error("interrupted")`)
