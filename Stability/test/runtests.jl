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

fmeth=methods(M.f)[1]
finst=fmeth.specializations[1]

@test module_stats(M) ==
    ModuleStats(M,
                Dict(fmeth=>MethodStats(; occurs=1, stable=1, grounded=1, nospec=0, vararg=0, fail=0)),
                Dict(finst=>MIStats(; st=1, gd=1, gt=0, rt=0, rettype=Int64, intypes=Core.svec(Int64))),
                )
end
