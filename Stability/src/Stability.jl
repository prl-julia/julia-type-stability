# Compute type stability 
# (instead of printing it, as in @code_arntype@
# Inspired by julia/stdlib/InteractiveUtils/src/codeview.jl 
module Stability

using Core: MethodInstance
using MethodAnalysis: visit
using Pkg
using CSV

export is_stable_type, is_stable_call, all_mis_of_module,
       FunctionStats, ModuleStats, module_stats, modstats_summary, modstats_table,
       package_stats, loop_pkgs_stats,
       show_comma_sep

# We do nasty things with Pkg.test
if get(ENV, "DEV", "NO") != "NO"
  include("pkg-test-override.jl")
end

# Wheather we do parallel processing of packages
PAR = get(ENV, "PAR", "NO") != "NO"
if PAR
    using Distributed
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

struct TypeInferenceError <: Exception
    f :: Any
    t :: Any
end

# f: function
# t: tuple of argument types
function is_stable_call(@nospecialize(f), @nospecialize(t))
    ct = code_typed(f, t, optimize=false)
    if length(ct) == 0
        throw(TypeInferenceError(f,t)) # type inference failed
    end
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
# We don't quite understand hwo to process generic method instances (cf. issue #2)
# We used to detect them, count, but don't test for stability.
# Currently, we use Base.unwrap_unionall and the test just works (yes, for types
# with free type variables). This still requires more thinking.

is_generic_instance(mi :: MethodInstance) = typeof(mi.specTypes) == UnionAll

# Note [Unknown instances]
# Some instances we just can't resolve -- for unknown reasons.
# E.g. In JSON test suite there's a `lower` method that is unknown.

is_known_instance(mi :: MethodInstance) = isdefined(mi.def.module, mi.def.name)

struct StabilityError <: Exception
    met :: Method
    sig :: Any
end

# Result: pair of the function object and the tuple of types of arguments
#         or nothing if it's constructor call.
reconstruct_func_call(mi :: MethodInstance) = begin
    sig = Base.unwrap_unionall(mi.specTypes).types
    if is_func_type(sig[1])
        (sig[1].instance, sig[2:end])
    else
        nothing
    end
end

# Get the Function object given its type (`typeof(f)` for regular functions and
# `Type{T}` for constructors)
is_func_type(funcType :: Type{T} where T <: Function) = true
is_func_type(::Any) = false

# Result: all (compiled) method instances of the given module
# Note: This seems to recourse into things like X.Y (submodules) if modl=X.
# But it seem to bring even more, so I'm not positive how
# MethodAnalysis.visit works.
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
  fail    :: Int  # how many times fail to detect stability due to @code_typed (cf. Issues #7, #8)
end

fstats_default() = FunctionStats(0,0,0)
import Base.(+)
(+)(fs1 :: FunctionStats, fs2 :: FunctionStats) =
  FunctionStats(
    fs1.occurs+fs2.occurs,
    fs1.stable+fs2.stable,
    fs1.fail+fs2.fail)

show_comma_sep(fs::FunctionStats) =
    "$(fs.occurs),$(fs.stable),$(fs.fail)"

struct ModuleStats
  modl   :: Module
  stats  :: Dict{Method, FunctionStats}
end

ModuleStats(modl :: Module) = ModuleStats(modl, Dict{Method, FunctionStats}())

module_stats(modl :: Module, errio :: IO = stderr) = begin
    res = ModuleStats(modl)
    mis = all_mis_of_module(modl)
    for mi in mis
        if isdefined(mi.def, :generator) # can't handle @generated functions, Issue #11
            @debug "GENERATED $(mi)"
            continue
        end

        fs = get!(fstats_default, res.stats, mi.def)
        try
            call = reconstruct_func_call(mi)
            if call === nothing # this mi is a constructor call - skip
                delete!(res.stats, mi.def)
                continue
            end
            fs.occurs += 1
            is_st = is_stable_call(call...);
            if is_st
                fs.stable += 1
            end
        catch err
            fs.fail += 1
            print(errio, "ERROR: ");
            showerror(errio, err, stacktrace(catch_backtrace()))
            println(errio)
        end
    end
    res
end

modstats_summary(ms :: ModuleStats) =
  foldl((+), values(ms.stats); init=fstats_default())

struct ModuleStatsRecord
    modl     :: String
    funcname :: String
    occurs   :: Int
    stable   :: Float64
    size     :: Int
    file     :: String
    line     :: Int
end

modstats_table(ms :: ModuleStats, errio = stderr :: IO) :: Vector{ModuleStatsRecord} = begin
    res = []
    for (meth,fstats) in ms.stats
        try
            modl = "$(meth.module)"
            mname = "$(meth.name)"
            msrclen = length(meth.source)
            mfile = "$(meth.file)"
            mline = meth.line
            push!(res,
                  ModuleStatsRecord(
                      modl, mname, fstats.occurs, fstats.stable/fstats.occurs,
                      msrclen, mfile, mline))
        catch err
            println(errio, "ERROR: modstats_table: $(meth)");
            throw(err)
        end
    end
    res
end

#
#  Stats for type stability: Package level
#

# package_stats: (pakg: String) -> IO ()
#
# Run stability analysis for the package `pakg`.
# Results are stored in the following files of the temp directory (see also "Side Effects" below):
# * stability-stats.out
# * stability-errors.out
# * stability-stats.csv
#
# Assumes: current directory is a project, so Pkg.activate(".") makes sense.
#
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
    ENV["STAB_PKG_NAME"] = pakg
    ENV["WORK_DIR"] = work_dir

    # set up and test the package `pakg`
    try
        Pkg.activate(".")
        Pkg.add(pakg)
        Pkg.test(pakg)
        st =
            eval(Meta.parse(
                open(f-> read(f,String), joinpath(wdir, "stabilty-stats.txt","r"))))
        CSV.write(joinpath(work_dir, "stability-stats.csv"), st)
    catch e
        println("Error when running tests for package $(pakg)")
    finally
        cd(start_dir)
        # TODO: |--- it's hard to figure what's right path to activate here
        #       v    we go with Stability.jl's root
        Pkg.activate(dirname(@__DIR__))
    end

end

loop_pkgs_stats(pksg_list_filename::String) = begin
    pkgs = readlines(pksg_list_filename)
    if PAR
        pmap(package_stats, pkgs)
    else
        for p in pkgs
            package_stats(p)
        end
    end
end

end # module

