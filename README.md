Debug.jl v0
===========
Prototype interactive debugger for [julia](julialang.org).
Bug reports and feature suggestions are welcome at
https://github.com/toivoh/Debug.jl/issues.

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

How it Works
------------
The main effort so far has gone into analyzing the scoping of symbols in a 
piece of code, and to modify code to allow one piece of code to be evaluated as
if it were at some particular point in another piece of code.
The interactive debug facility is built on top of this toolbox.

* The code passed to `@debug` is _analyzed_ to mark each block and symbol with
  an environment (static scope).
  Each environment has a parent and a set of symbols that are introduced in it,
  including reintroduced symbols that shadow definitions in an outer scope.
* The code is then _instrumented_ to insert a trap call after each line number
  in a block. A `Scope` (runtime scope) object that contains getter and setter
  functions for each visible local symbol is also created upon entry to
  each block that lies within a new environment.
* The code passed to `debug_eval` is analyzed in the same way as to `@debug`.
  The code is then _grafted_ into the supplied scope by
  replacing each reads/write to a variable
  with a call to the corresponding getter/setter function,
  if it is visible at that point in the grafted code.

Known Issues
------------
I have tried to encode the scoping rules of julia as accurately as possible,
but I'm bound to have missed something. Also,
* The scoping rules for `for` blocks etc. in global scope
  are not quite accurate.
* Code within macro expansions may become tagged with the wrong source file.

Known issues can also be found at the
[issues page](https://github.com/toivoh/Debug.jl/issues).
Bug reports and feature requests are welcome.

The interactive debugger is very crude so far.
It should be the next target for improvement 
once the scoping analysis is reasonably accurate.
