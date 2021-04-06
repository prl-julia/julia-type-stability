# Compute type stability 
# (instead of printing it, as in @code_arntype@
# Inspired by julia/stdlib/InteractiveUtils/src/codeview.jl 
module Stability

using Core: MethodInstance, CodeInstance, CodeInfo
using MethodAnalysis: visit
using Pkg
using CSV

export is_concrete_type, is_grounded_call, all_mis_of_module,
       FunctionStats, ModuleStats, module_stats, modstats_summary, modstats_table,
       package_stats, loop_pkgs_stats, cfg_stats,
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
is_concrete_type(@nospecialize(ty)) = begin
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

# Args:
# * f: function
# * t: tuple of argument types
# Returns: pair (CodeInstance - typed IR, Inferred Type of the Body)
function run_type_inference(@nospecialize(f), @nospecialize(t))
    ct = code_typed(f, t, optimize=false)
    if length(ct) == 0
        throw(TypeInferenceError(f,t)) # type inference failed
    end
    ct[1] # we ought to have just one method body, I think
end

is_grounded_call(src :: CodeInfo) = begin
    slottypes = src.slottypes

    # the following check is taken verbatim from code_warntype
    if !isa(slottypes, Vector{Any})
        return true # I don't know when we get here,
                    # over-approx. as stable
    end

    result = true

    slotnames = Base.sourceinfo_slotnames(src)
    for i = 1:length(slottypes)
        stable = is_concrete_type(slottypes[i])
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

struct CfgStats
    st       :: Bool # if the instance is stable
    gd       :: Bool # if the instance is grounded
    gt       :: Int  # number of gotos in the instance
    rt       :: Int  # number of returns in the instance
end

cfgstats_default() = CfgStats(0,0)

# Stats about control-flow graph of a method
# Currently, number of gotos, and number of returns
cfg_stats(code :: CodeInfo) = begin
    gt = 0
    rt = 0

    for st in code.code
        if is_goto(st)
            gt += 1
        elseif is_return(st)
            rt += 1
        end
    end
    (gt,rt)
end

is_goto(::Core.GotoNode) = true
is_goto(e::Expr) = e.head == :gotoifnot
is_goto(::Any) = false
is_return(e::Expr) = e.head == :return
is_return(::Any) = false

# Statistics gathered per method. (It's called "func" for histerical reasons.)
# Note on "mutable": stats are only mutable during their calculation.
mutable struct FunctionStats
    occurs   :: Int  # how many instances of the method found
    stable   :: Int  # how many stable instances of the method
    grounded :: Int  # how many grounded instances of the method
    fail     :: Int  # how many times fail to detect stability of an instance (cf. Issues #7, #8)
end

fstats_default() = FunctionStats(0,0,0,0)

import Base.(+)
(+)(fs1 :: FunctionStats, fs2 :: FunctionStats) =
  FunctionStats(
      fs1.occurs+fs2.occurs,
      fs1.stable+fs2.stable,
      fs1.grounded+fs2.grounded,
      fs1.fail+fs2.fail
  )

show_comma_sep(fs::FunctionStats) =
    "$(fs.occurs),$(fs.stable),$(fs.grounded),$(fs.fail)"

struct ModuleStats
  modl   :: Module
  stats  :: Dict{Method, FunctionStats}
  cfgs   :: Dict{MethodInstance, CfgStats}
end

ModuleStats(modl :: Module) = ModuleStats(modl, Dict{Method, FunctionStats}(), Dict{Method, CfgStats}())

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

            # handle stability/groundedness
            mi_st = false
            mi_gd = false
            (code,rettype) = run_type_inference(call...);
            if is_concrete_type(rettype)
                fs.stable += 1
                mi_st = true
                if is_grounded_call(code)
                    fs.grounded += 1
                    mi_gd = true
                end
            end

            # handle instance CFG stats
            res.cfgs[mi] = CfgStats(mi_st, mi_gd, cfg_stats(code)...)
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

struct ModuleStatsPerMethodRecord
    modl     :: String
    funcname :: String
    occurs   :: Int
    stable   :: Float64
    grounded :: Float64
    size     :: Int
    file     :: String
    line     :: Int
end

struct ModuleStatsPerInstanceRecord
    modl     :: String
    funcname :: String
    st       :: Bool
    gd       :: Bool
    gt       :: Int
    rt       :: Int
    file     :: String
    line     :: Int
end

modstats_table(ms :: ModuleStats, errio = stderr :: IO) ::
    Tuple{Vector{ModuleStatsPerMethodRecord}, Vector{ModuleStatsPerInstanceRecord}} = begin
        resmeth = []
        resmi = []
        for (meth,fstats) in ms.stats
            try
                modl = "$(meth.module)"
                mname = "$(meth.name)"
                msrclen = length(meth.source)
                mfile = "$(meth.file)"
                mline = meth.line
                push!(resmeth,
                      ModuleStatsPerMethodRecord(
                          modl, mname, fstats.occurs,
                          fstats.stable/fstats.occurs, fstats.grounded/fstats.occurs,
                          msrclen,
                          mfile, mline))
            catch err
                println(errio, "ERROR: modstats_table: $(meth)");
                throw(err)
            end
        end
        for (mi,cfgst) in ms.cfgs
            try
                meth = mi.def
                modl = "$(meth.module)"
                mname = "$(meth.name)"
                msrclen = length(meth.source)
                mfile = "$(meth.file)"
                mline = meth.line
                push!(resmi,
                      ModuleStatsPerInstanceRecord(
                          modl, mname,
                          cfgst.st, cfgst.gd,
                          cfgst.gt, cfgst.rt,
                          mfile, mline))
            catch err
                println(errio, "ERROR: modstats_table: $(meth)");
                throw(err)
            end
        end
        (resmeth,resmi)
end

#
#  Stats for type stability: Package level
#

# package_stats: (pakg: String) -> IO ()
#
# Run stability analysis for the package `pakg`.
# Results are stored in the following files of the current directory (see also "Side Effects" below):
# * stability-stats.out
# * stability-errors.out
# * stability-stats.csv
#
# Side effects:
#   In the current directory, creates a temporary environment for this package.
#   Reusing this env shouldn't harm anyone (in theory).
#
# Parallel execution:
#   Possible with the aid of GNU parallel and the tine script in scripts/proc_package_parallel.sh.
#   It requires a file with a list of packages passed as the single argument.
#
# REPL:
#   Make sure to run from a reasonable dir, e.g. create a dir for this package yourself
#   and cd into it before calling.
#
package_stats(pakg :: String) = begin
    start_dir = pwd()
    work_dir  = pwd()
    ENV["STAB_PKG_NAME"] = pakg
    ENV["WORK_DIR"] = work_dir

    @info "[Stability] [Package: " * pakg * "] Starting up"
    # set up and test the package `pakg`
    try
        Pkg.activate(".") # Switch from Stability package-local env to a temp env
        Pkg.add(pakg)
        @info "[Stability] [Package: " * pakg * "] Added. Now on to testing"
        Pkg.test(pakg)
    catch err
        println("Error when running tests for package $(pakg)")
        errio=stderr
        print(errio, "ERROR: ");
        showerror(errio, err, stacktrace(catch_backtrace()))
        println(errio)
    finally
        cd(start_dir)
        Pkg.activate(dirname(@__DIR__)) # switch back to Stability env
    end

    resf = joinpath(work_dir, "stability-stats-per-method.txt")
    isfile(resf) || (@error "Stability analysis failed to produce output $resf"; return)
    st =
        eval(Meta.parse(
            open(f-> read(f,String), resf,"r")))
    CSV.write(joinpath(work_dir, "stability-stats-per-method.csv"), st)

    resf = joinpath(work_dir, "stability-stats-per-instance.txt")
    isfile(resf) || (@error "Stability analysis failed to produce output $resf"; return)
    st =
        eval(Meta.parse(
            open(f-> read(f,String), resf,"r")))
    CSV.write(joinpath(work_dir, "stability-stats-per-instance.csv"), st)
    @info "[Stability] [Package: " * pakg * "] Results successfully converted to CSV. Bye!"
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

add_all_pkgs(pksg_list_filename::String) = begin
    pkgs = readlines(pksg_list_filename)
    Pkg.add(pkgs)
end

end # module

