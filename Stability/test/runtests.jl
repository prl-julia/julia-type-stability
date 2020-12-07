using Stability, Test

# Test from
# http://www.johnmyleswhite.com/notebook/2013/12/06/writing-type-stable-code-in-julia/
function sumofsins1(n::Integer)  
    r = 0
    for i in 1:n
        r += sin(3.4)
    end
    return r
end
function sumofsins2(n::Integer)
    r = 0.0
    for i in 1:n
        r += sin(3.4)
    end
    return r
end

@testset "is_stable_call tests" begin
    f = sin
    t = (Float64,)
    @test is_stable_call(f,t)
    @test ! is_stable_call(sumofsins1, (Int64,))
    @test is_stable_call(sumofsins2, (Int64,))
end

