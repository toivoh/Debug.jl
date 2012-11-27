Debug.jl v0
===========
Simple usage example:

    julia> load("Debug.jl")

    julia> using Debug

    julia> @debug begin    # line 1
               x = 0       # line 2
               for k=1:3   # line 3
                   x += k  # line 4
               end         # line 5
               x           # line 6
           end

    : 2
    debug> x
    x not defined

    debug> n

    : 3
    debug> x
    0

    debug> x=10
    10

    debug> n

    : 4
    debug> x
    10

    debug> n

    : 4
    debug> x
    11

    debug> n

    : 4
    debug> x
    13

    debug> n

    : 6
    debug> x
    16

    debug> x += 4
    20

    debug> n
    20

    julia> 

The following single-character commands have special meaing:   
`n`: next / step into    
`r`: run   
`q`: interrupt debug session (calls `error("interrupted")`)
