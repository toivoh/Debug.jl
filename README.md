Debug.jl v0
===========
Prototype interactive debugger for [the Julia language](http://julialang.org).
Bug reports and feature suggestions are welcome at
https://github.com/toivoh/Debug.jl/issues.

Installation
------------
In julia, install the `Debug` package:

    Pkg.add("Debug")

`Debug` currently requires a julia build from 2012-12-05 or later.

Interactive Usage
-----------------
First, import the `Debug` package:

    using Debug

Use the `@debug` macro to mark code that you want to be able to step through.
Use the `@bp` macro to set a breakpoint
-- interactive debugging will commence at the first breakpoint encountered.
There is also a conditional version, e.g. `@bp x>0` will break only when x>0.
`@debug` can only be used in global (i.e. module) scope, 
since it needs access to all
scopes that surround a piece of code to be analyzed.

The following single-character commands have special meaning:   
`h`: display help text   
`s`: step into   
`n`: step over any enclosed scope   
`o`: step out from the current scope   
`c`: continue to next breakpoint   
`l [n]`: list `n` source lines above and below current line, if source file information is available at this point (default `n = 3`)   
`p cmd`: print `cmd` evaluated in current scope   
`q`: quit debug session (calls `error("interrupted")`)   
Anything else is parsed and evaluated in the current scope.
To e.g. evaluate a variable named `n`, it can be entered with
a space prepended.


### Example ###

Put the following in a file called `example.jl`:

    using Debug
    @debug function test()
        parts = {}
        @bp
        for j=1:3
            for i=1:3
                push!(parts,"($i,$j) ")
            end
        end
        @bp
        println(parts...)
    end
    
    test()

Then, in the Julia terminal:

    julia> include("example.jl")
    
    at /home/toivo/.julia/Debug/test/example.jl:4
    
          3        parts = {}
     -->  4        @bp
          5        for j=1:3
    
    debug:4> j
    j not defined
    
    debug:4> parts
    {}
    
    debug:4> s
    
    at /home/toivo/.julia/Debug/test/example.jl:5
    
          4        @bp
     -->  5        for j=1:3
          6            for i=1:3
    
    debug:5> s
    
    at /home/toivo/.julia/Debug/test/example.jl:6
    
          5        for j=1:3
     -->  6            for i=1:3
          7                push!(parts,"($i,$j) ")
    
    debug:6> s
    
    at /home/toivo/.julia/Debug/test/example.jl:7
    
          6            for i=1:3
     -->  7                push!(parts,"($i,$j) ")
          8            end
    
    debug:7> i
    1
    
    debug:7> s
    
    at /home/toivo/.julia/Debug/test/example.jl:7
    
          6            for i=1:3
     -->  7                push!(parts,"($i,$j) ")
          8            end
    
    debug:7> i
    2
    
    debug:7> parts
    {"(1,1) "}
    
    debug:7> parts = {}
    {}
    
    debug:7> o
    
    at /home/toivo/.julia/Debug/test/example.jl:6
    
          5        for j=1:3
     -->  6            for i=1:3
          7                push!(parts,"($i,$j) ")
    
    debug:6> j
    2
    
    debug:6> n
    
    at /home/toivo/.julia/Debug/test/example.jl:6
    
          5        for j=1:3
     -->  6            for i=1:3
          7                push!(parts,"($i,$j) ")
    
    debug:6> j
    3
    
    debug:6> push!(parts, "foo ")
    {"(2,1) ","(3,1) ","(1,2) ","(2,2) ","(3,2) ","foo "}
    
    debug:6> c
    
    at /home/toivo/.julia/Debug/test/example.jl:10
    
          9        end
     -->  10       @bp
          11       println(parts...)
    
    debug:10> parts 
    {"(2,1) ","(3,1) ","(1,2) ","(2,2) ","(3,2) ","foo ","(1,3) ","(2,3) ","(3,3) "}
    
    debug:10> c
    (2,1) (3,1) (1,2) (2,2) (3,2) foo (1,3) (2,3) (3,3) 
    
    julia> 


Experimental Features
---------------------
Interpolations in entered code will currently be evaluated in the context of
the `Debug.Session` module, before the expression itself is evaluated
in the context of the current scope.
Some of the debugger's internal state has been made
available through this mechanism, and can be manipulated to influence
debugging:   
`$n`:    The current node   
`$s`:    The current scope   
`$bp`:   `Set{Node}` of enabled breakpoints   
`$nobp`: `Set{Node}` of disabled `@bp` breakpoints   
`$pre`:  `Dict{Node}` of grafts   
Nodes refer to positions in the instrumented code,
represented by nodes in the decorated AST produced from the original code.

Breakpoints can be manipulated using e.g.

    $(push!(bp, n))    # set breakpoint at the current node
    $(delete!(bp, n))  # unset breakpoint at the current node
    $(push!(nobp, n))  # ignore @bp breakpoint at the current node

The above examples can also be written as e.g. `$push!($bp, $n)`.   
Code snippets can also be grafted into instrumented code. E.g.

    $(pre[n] = :(x = 0))

will make the code `x = 0` execute right before each execution of the current
node.

Other nodes than the current node `$n` could be used
in the examples above.
Such nodes can be found by navigating from the current node,
but the there is not much support for this yet.

Custom Traps
------------
There is an `@instrument` macro that works similarly to the `@debug` macro,
but takes as first argument a trap function to be called at each
expression that lies directly in a block. The example

    load("Debug.jl")
    using Base, Debug

    firstline = -1
    function trap(node::Node, scope::Scope) 
        global firstline = (firstline == -1) ? node.loc.line : firstline
        line = node.loc.line - firstline + 1
        print(line, ":")

        if (line == 2); debug_eval(scope, :(x += 1)) end

        if (line >  1); print("\tx = ", debug_eval(scope, :x)) end
        if (line == 3); print("\tk = ", debug_eval(scope, :k)) end
        println()
    end

    @instrument trap function f(n)
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
`@instrument` in turn relies on the function `Debug.Graft.instrument`,
which also allows to to specify at which nodes to add traps.

How it Works
------------
The foundations of the `Debug` package is code for
analyzing the scoping of symbols in a piece of code, 
and to modify code to allow one piece of code to be evaluated as
if it were at some particular point in another piece of code.
The interactive debug facility is built on top of this.
The `@debug` macro triggers a number of steps:

* The code passed to `@debug` is _analyzed_,
  and turned into a decorated AST built from nodes of type `Debug.AST.Node`.
  The format is almost identical to Julia's native AST format,
  but nodes also keep track of
  parent, static scope, and location in the source code.
* The code is then _instrumented_ to insert trap calls at each stepping point,
  entry/exit to scope blocks, etc.
  A `Scope` object that contains getter and setter
  functions for each visible local symbol is also created upon entry to
  each block that lies within a new environment.
* The code passed to `debug_eval` is analyzed in the same way as to `@debug`.
  The code is then _grafted_ into the supplied scope by
  replacing each read/write to a variable
  with a call to the corresponding getter/setter function,
  if it is visible at that point in the grafted code.

Known Issues
------------
I have tried to encode the scoping rules of Julia as accurately as possible,
but I'm bound to have missed something. Also,
* The scoping rules for `for` blocks etc. in global scope
  are not quite accurate.
* Code within macro expansions may become tagged with the wrong source file.

Known issues can also be found at the
[issues page](https://github.com/toivoh/Debug.jl/issues).
Bug reports and feature requests are welcome.
