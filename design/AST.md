
Decorated AST users:

    Analysis.jl
    Graft.jl
    debug_eval(scope, ex)  Extract defined/assigned symbols from scope and ex.
    trap() (UI.jl)         Trap on lines, breakpoints etc, access their info.
    test_decorate.jl       Go through AST, check envs and @syms annotations.
    test_graft.jl          Preprocess decorated AST, trap on grafts.
    test_macro_trap.jl     Could use custom Trap type.

