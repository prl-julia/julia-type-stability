# Compute type stability 
# (instead of printing it, as in @code_arntype@
# Inspired by julia/stdlib/InteractiveUtils/src/codeview.jl 
module Stability

using Core: MethodInstance
using MethodAnalysis: visit
using Pkg

export is_stable_type, is_stable_call, is_stable_instance, all_mis_of_module,
       FunctionStats, ModuleStats, module_stats,
       package_stats

# We do nasty things with Pkg.test
const OVERRIDE_PKG_TEST = true
if OVERRIDE_PKG_TEST
  include("pkg-test-override.jl")
end

# turn on debug info:
# julia> ENV["JULIA_DEBUG"] = Main
# turn off:
# juila> ENV["JULIA_DEBUG"] = nothing

# Follows `warntype_type_printer` in the above mentioned file
is_stable_type(@nospecialize(ty)) = begin
    if ty isa Type && (!Base.isdispatchelem(ty) || ty == Core.Box)
        if ty isa Union && Base.is_expected_union(ty)
            true # this is a "mild" problem, so we round up to "stable"
        else
            false
        end
    else
        true
    end
    # Note 1: Core.Box is a type of a heap-allocated value
    # Note 2: isdispatchelem is roughly eqviv. to
    #         isleaftype (from Julia pre-1.0)
    # Note 3: expected union is a trivial union (e.g. 
    #         Union{Int,Missing}; those are deemed "probably
    #         harmless"
end

# f: function name
# t: tuple of argument types
function is_stable_call(@nospecialize(f), @nospecialize(t))
    ct = code_typed(f, t, optimize=false)
    ct1 = ct[1] # we ought to have just one method body, I think
    src = ct1[1] # that's code; [2] is return type, I think
    slottypes = src.slottypes

    # the following check is taken verbatim from code_warntype
    if !isa(slottypes, Vector{Any})
        return true # I don't know when we get here,
                    # over-approx. as stable
    end

    result = true
    
    slotnames = Base.sourceinfo_slotnames(src)
    for i = 1:length(slottypes)
        stable = is_stable_type(slottypes[i])
        @debug "is_stable_call slot:" slotnames[i] slottypes[i] stable
        result = result && stable
    end
    result
end

#
# MethodInstance-based interface (thanks to MethodAnalysis.jl)
#

is_stable_instance(mi :: MethodInstance) =
    is_stable_call(getfield(mi.def.module, mi.def.name), mi.specTypes.types[2:end])

all_mis_of_module(modl :: Module) = begin
    mis = []

    visit(modl) do item
       isa(item, MethodInstance) && push!(mis, item)
       true   # walk through everything
    end
    mis
end

#
#  Stats for type stability: Module level
#

# function stats are only mutable during their calculation
mutable struct FunctionStats
  occurs :: Int  # how many occurances of the method found (all instances)
  stable :: Int  # how many stable instances
end

fstats() = FunctionStats(0,0)

struct ModuleStats
  modl   :: Module # or Symbol?
  stats  :: Dict{Symbol, FunctionStats}
end

ModuleStats(modl :: Module) = ModuleStats(modl, Dict{Symbol, FunctionStats}())

module_stats(modl :: Module) = begin
    res = ModuleStats(modl)
    mis = all_mis_of_module(modl)
    for mi in mis
        fs = get!(fstats, res.stats, mi.def.name)
        fs.occurs += 1
        if is_stable_instance(mi); fs.stable += 1 end
    end
    res
end

#
#  Stats for type stability: Package level
#

package_stats(pakg :: String) = begin
    # prepare a subdir in the current dir to test this particular path
    # and enter it? Given that Pkg.test already implements sandboxing...
    mkpath(pakg)
    cd(pakg)

    try
      # set up and test the package `pakg`
      Pkg.activate(".")
      Pkg.add(pakg)
      ENV["STAB_PKG_NAME"] = pakg
      Pkg.test(pakg)
    catch e
      println("Error when running tests for package $(pakg):\n$(e)")
    end
    
    #error("package_stats: not fully implemented yet")
end

end # module

