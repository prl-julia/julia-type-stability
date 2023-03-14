using Test
using Stability

module M

f(x::Int64) = 42

end

@testset "Basic tests for computing module stats" begin
# Dummy test: untill the funciton is compiled (e.g. run at least once),
# we won't see any stats:
@test module_stats(M) == ModuleStats(M)

M.f(1) # compile

# TODO: add ==-test
@test module_stats(M) != ModuleStats(M)
end
