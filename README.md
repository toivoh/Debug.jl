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

`Debug` currently requires a julia build from 2012-12-05 or later.

Interactive Usage
-----------------
Use the `@debug` macro to mark code that you want to be able to step through.
Use the `@bp` macro to set a breakpoint -- interactive debugging will commence at the first breakpoint encountered.
`@debug` can only be used in global scope, since it needs access to all
scopes that surround a piece of code to be analyzed.

The following single-character commands have special meaing:   
`h`: display help text   
`s`: step into   
`n`: step over any enclosed scope   
`o`: step out from the current scope   
`c`: continue to next breakpoint   
`q`: quit debug session (calls `error("interrupted")`)   
Anything else is parsed and evaluated in the current scope,
including e.g. the string `" s"`.

Example:

    julia> @debug let
           parts = {}
           @bp       # 3
           for j=1:3 # 4
           for i=1:3 # 5
           push(parts,"($i,$j) ") # 6
           end # 7
           end # 8
           @bp # 9
           println(parts...)
           end

    at :3
    debug:3> j
    in anonymous: j not defined
 
    debug:3> parts
    {}

    debug:3> s

    at :4
    debug:4> s

    at :5
    debug:5> s

    at :6
    debug:6> i
    1

    debug:6> s

    at :6
    debug:6> i
    2

    debug:6> parts
    {"(1,1) "}

    debug:6> parts = {}
    {}

    debug:6> o

    at :5
    debug:5> j
    2

    debug:5> n

    at :5
    debug:5> j
    3

    debug:5> push(parts, "foo ")
    {"(2,1) ", "(3,1) ", "(1,2) ", "(2,2) ", "(3,2) ", "foo "}

    debug:5> c

    at :9
    debug:9> parts
    {"(2,1) ", "(3,1) ", "(1,2) ", "(2,2) "  ...  "(1,3) ", "(2,3) ", "(3,3) "}

    debug:9> c
    (2,1) (3,1) (1,2) (2,2) (3,2) foo (1,3) (2,3) (3,3) 

    julia>

Experimental Features
---------------------
Positions in the instrumented code are represented by their corresponding nodes
in the decorated AST produced for it.
The debugger currently makes available some of its internal state through
interpolation syntax:   
`$n`:    The current node   
`$s`:    The current scope   
`$bp`:   `Set{Node}` of enabled breakpoints   
`$nobp`: `Set{Node}` of disabled `@bp` breakpoints   
`$pre`:  `Dict{Node}` of grafts   
These can be used e.g. to control aspects of the debugging process.   

Breakpoints can be handled using e.g.

    add($bp,   $n)  # set breakpoint at the current node
    del($bp,   $n)  # unset breakpoint at the current node
    add($nobp, $n)  # ignore @bp breakpoint at current node

The user can also graft code snippets into existing code. E.g.

    $pre[$n] = :(x = 0)

will make the code `x = 0` execute right before the current node,
at each visit.

The user may navigate the decorated AST to find other nodes to use than
the current node `$n` in the examples above, though there is a need for more
tools to support this.

Custom Traps
------------
There is an `@instrument` macro that works similar to the `@debug` macro,
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
The main effort so far has gone into analyzing the scoping of symbols in a 
piece of code, and to modify code to allow one piece of code to be evaluated as
if it were at some particular point in another piece of code.
The interactive debug facility is built on top of this.

* The code passed to `@debug` is _analyzed_.
  AST nodes are replaced with `Debug.AST.Node` nodes that represent the same
  thing, but also keep track of parent, static scope, and location in the code.
  Static scopes keep track of the symbols that they (re)introduce.
* The code is then _instrumented_ to insert trap calls at each stepping point,
  entry/exit to scope blocks, etc.
  A `Scope` (runtime scope) object that contains getter and setter
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
