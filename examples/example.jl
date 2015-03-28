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
