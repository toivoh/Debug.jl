julia-debugger v0.0
===================

Prototype interactive debugger for Julia

This package is a first attempt towards an interactive debugger for
[Julia](julialang.org).
(It's not interactive yet, though :)

Example
-------
The `@debug` macro instruments a piece of code with debug callbacks,   
which invoke the `debug_hook` function with a current line and scope.   
The `debug_eval` function attempts to `eval` an expression within a provided 
scope.

The code (from `test/test.jl`)

    @debug function f(n)
        x = 0       # line 10
        for k=1:n   # line 11
            x += k  # line 12
        end         # line 13
        x = x*x     # line 14
    end

    function debug_hook(line::Int, file, scope::Scope) 
        print(line, " :")
        if (line == 11) debug_eval(scope, :(x += 1)) end
        if (line >  10) debug_eval(scope, :(print("\tx = ", x))) end
        if (line == 12) debug_eval(scope, :(print("\tk = ", k))) end
        println()
    end

    f(3)

produces the output (from `debug_hook` above)

    10:
    11: 	x = 1
    12: 	x = 1	k = 1
    12: 	x = 2	k = 2
    12: 	x = 4	k = 3
    14: 	x = 7

For slightly more elaborate examples, see the `test/` directory.

Current implementation and limitations
--------------------------------------

 * `@debug` first tries to gather the set of symbols that is defined within
   each scope in the instrumented code.   
   I've tried to encode the scoping rules of Julia, but it's not complete.
   `@debug` will complain unless it's applied at global scope, 
   since it might fail to capture some variables that are visible to the 
   instrumented code otherwise.

 * Secondly, `@debug` instruments the code by inserting a call to `debug_hook`
   before each expression within a `:block` expr in the AST (i e in most block
   structures within the code).
   The first instrumented line of each scope also creates a new `Scope` object,
   with a dict that maps symbols to getter and setter closures, 
   and a link to the containing scope.

 * `debug_eval(scope, ex)` attempts to translate `ex` to replace reads from and
   writes to variables to use getters and setters from `scope` 
   where appropriate. 
   I've tried to encode Julia's assignment rules, but it's not complete.
   Assignment to symbols that are not found in `scope` is prohibited,
   rather than setting a global (without a corresponding `global` declaration 
   in the code).
   This is meant to mimic the behavior of code within the local scope.

   Mutating operators such as `x+=1` are first translated into e g `x=x+1`,
   and then into e g `x_setter(x_getter()+1)`.

Further limitations:
 * No scoping analysis is done for the expression that is passed `debug_eval` yet
 * Not much tested yet.
 * No actual interactive debug hook.
 * Things I don't know about yet...

Also see the [issues](https://github.com/toivoh/julia-debugger/issues)
section for some limitations that I do know about.
