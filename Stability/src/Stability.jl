# Compute type stability 
# (instead of printing it, as in @code_arntype@
# Inspired by julia/stdlib/InteractiveUtils/src/codeview.jl 
module Stability

using Core: MethodInstance
using MethodAnalysis: visit
using Pkg

export is_stable_type, is_stable_call, is_stable_instance, all_mis_of_module,
       FunctionStats, ModuleStats, module_stats, modstats_summary,
       package_stats,
       show_comma_sep

# We do nasty things with Pkg.test
if get(ENV, "DEV", "NO") != "NO"
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

# Note [Generic Method Instances]
# We don't know yet what to do with generic method instances (cf. issue #2)
# So we detect them, count, but don't test for stability.

is_generic_instance(mi :: MethodInstance) = typeof(mi.specTypes) == UnionAll

# Note [Unknown instances]
# Some instances we just can't resolve -- for unknown reasons.
# E.g. In JSON test suite there's a `lower` method that is unknown.

is_known_instance(mi :: MethodInstance) = isdefined(mi.def.module, mi.def.name)

# Result: test if `mi` is stable
# Pre-condition: `mi` is not generic.
is_stable_instance(mi :: MethodInstance) = begin
    res = is_stable_call(
      getfield(mi.def.module, mi.def.name),
      mi.specTypes.types[2:end])
end

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
  occurs  :: Int  # how many occurances of the method found (all instances)
  stable  :: Int  # how many stable instances
  generic :: Int  # how many generic instances (we don't know how to handle them yet)
  undef   :: Int  # how many methods could not get resolved (for unknown reason)
  unstable:: Int  # how many unstable instances (just so that all-but-occurs sums up to occurs)
end

fstats_default() = FunctionStats(0,0,0,0,0)
import Base.(+)
(+)(fs1 :: FunctionStats, fs2 :: FunctionStats) =
  FunctionStats(
    fs1.occurs+fs2.occurs,
    fs1.stable+fs2.stable,
    fs1.generic+fs2.generic,
    fs1.undef+fs2.undef,
    fs1.unstable+fs2.unstable)

show_comma_sep(fs::FunctionStats) =
    "$(fs.occurs),$(fs.stable),$(fs.generic),$(fs.undef)" # Note: we don't print unstable

struct ModuleStats
  modl   :: Module # or Symbol?
  stats  :: Dict{Symbol, FunctionStats}
end

ModuleStats(modl :: Module) = ModuleStats(modl, Dict{Symbol, FunctionStats}())

module_stats(modl :: Module) = begin
    res = ModuleStats(modl)
    mis = all_mis_of_module(modl)
    for mi in mis
        fs = get!(fstats_default, res.stats, mi.def.name)
        fs.occurs += 1
        if     is_generic_instance(mi); fs.generic += 1
        elseif !is_known_instance(mi);  fs.undef   += 1
        elseif is_stable_instance(mi);  fs.stable  += 1
        else                            fs.unstable+= 1 end
    end
    res
end

modstats_summary(ms :: ModuleStats) =
  foldl((+), values(ms.stats); init=fstats_default())

#
#  Stats for type stability: Package level
#

# package_stats: (pakg: String) -> IO ()
# Run stability analysis for the package `pakg`.
# Result is printed on stdout for now (TODO: store as JSON)
# Assumes: current directory is a project, so Pkg.activate(".") makes sense.
# Side effects:
#   Temporary directory with a sandbox for this package is created in the current
#   directory. This temp directory is not removed upon completion and can be reused
#   in the future runs. This reuse shouldn't harm anyone (in theory).
package_stats(pakg :: String) = begin
    # prepare a subdir in the current dir to test this particular path
    # and enter it? Given that Pkg.test already implements sandboxing...
    start_dir=pwd()
    mkpath(pakg)
    cd(pakg)
    work_dir = pwd()

    # set up and test the package `pakg`
    Pkg.activate(".")
    Pkg.add(pakg)
    ENV["STAB_PKG_NAME"] = pakg
    ENV["WORK_DIR"] = work_dir
    try
      Pkg.test(pakg)
    catch e
      println("Error when running tests for package $(pakg)")
    finally
      cd(start_dir)
      Pkg.activate(".")
    end

end

end # module

