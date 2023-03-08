#
# Package for Type Stability Analysis
#
module Stability

using Core: MethodInstance, CodeInstance, CodeInfo
using MethodAnalysis: visit
using Pkg
using CSV

export is_concrete_type, is_grounded_call, all_mis_of_module,
       MethodStats, ModuleStats, module_stats, modstats_summary, modstats_table,
       package_stats, loop_pkgs_stats, cfg_stats,
       show_comma_sep

#
# Configuration Parameters
#

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

#
# Section: Pure stability analysis
# inspired by Julia's @code_warn_typed
#

# Instead of printing concretness of inferred type (as @code_warntype@ does),
# return a bool
# Follows `warntype_type_printer` in:
# julia/stdlib/InteractiveUtils/src/codeview.jl
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

# Accepts inferred method body and checks if every slot in it is concrete
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
# Section: MethodInstance-based pure interface (thanks to MethodAnalysis.jl)
#

# Note [Generic Method Instances]
# We don't quite understand hwo to process generic method instances (cf. issue #2)
# We used to detect them, count, but don't test for stability.
# Currently, we use Base.unwrap_unionall and the test just works (yes, for types
# with free type variables). This still requires more thinking.

is_generic_instance(mi :: MethodInstance) = typeof(mi.specTypes) == UnionAll

# Note [Unknown instances]
# Some instances we just can't resolve.
# E.g. In JSON test suite there's a `lower` method that is unknown.
# This is rare and due to macro magic.

is_known_instance(mi :: MethodInstance) = isdefined(mi.def.module, mi.def.name)

struct StabilityError <: Exception
    met :: Method
    sig :: Any
end

# Accepts a method instance as found in Julia VM cache after executing some code.
# Returns: pair of a function object and a tuple of types of arguments
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

# Returns: all (compiled) method instances of the given module
# Note: This seems to recourse into things like X.Y (submodules) if modl=X.
all_mis_of_module(modl :: Module) = begin
    mis = []

    visit(modl) do item
       isa(item, MethodInstance) && push!(mis, item)
       true   # walk through everything
    end
    mis
end

#
#  Section: Stats for type stability, module level
#  Impure interface
#

# Statistics gathered per method instance.
struct MIStats
    st       :: Bool # if the instance is stable
    gd       :: Bool # if the instance is grounded
    gt       :: Int  # number of gotos in the instance
    rt       :: Int  # number of returns in the instance
    rettype  :: Any  # return type inferred; NOTE: should probably be a Datatype
    intypes  :: Core.SimpleVector # have to use this b/c that's what we get from
    # `reconstruct_func_call`; a vector of input types
end

# Stats about control-flow graph of a method instance
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

# Statistics gathered per method.
# Note on "mutable": stats are only mutable during their calculation.
mutable struct MethodStats
    occurs   :: Int  # how many instances of the method found
    stable   :: Int  # how many stable instances of the method
    grounded :: Int  # how many grounded instances of the method
    nospec   :: Int  # the nospecialized bitmap (if /=0, there are nospec. params)
    vararg   :: Int  # if the method is a varags method (0/1)
    fail     :: Int  # how many times fail to detect stability of an instance (cf. Issues #7, #8)
end

# convenient default constructor
fstats_default(nospec=0, vararg=0) = MethodStats(0,0,0,nospec,vararg,0)

# This is needed for modstats_summary: we smash data about individual methods together
# and get coarse-grained module stats
# This has to be clewver: many things can be simply summed, but not all.
import Base.(+)
(+)(fs1 :: MethodStats, fs2 :: MethodStats) =
  MethodStats(
      fs1.occurs+fs2.occurs,
      fs1.stable+fs2.stable,
      fs1.grounded+fs2.grounded,
      fs1.nospec + min(1, abs(fs2.nospec)),
      fs1.vararg + fs2.vararg,
      fs1.fail+fs2.fail
  )

# This is needed for modstats_summary
show_comma_sep(xs::Vector) = join(xs, ",")

struct ModuleStats
  modl    :: Module
  mestats :: Dict{Method, MethodStats}
  mistats :: Dict{MethodInstance, MIStats}
end

ModuleStats(modl :: Module) = ModuleStats(modl, Dict{Method, MethodStats}(), Dict{Method, MIStats}())

# Generate a summary of stability data in the module: just a fold (+) over stats
# of individual methods / instances
modstats_summary(ms :: ModuleStats) = begin
  fs = foldl((+), values(ms.mestats); init=fstats_default())
  [length(ms.mestats),fs.occurs,fs.stable,fs.grounded,fs.nospec,fs.vararg,fs.fail]
end

# Given a module object after some code of the module has been compiled, compute
# all stabilty stats for this module
module_stats(modl :: Module, errio :: IO = stderr) = begin
    res = ModuleStats(modl)
    mis = all_mis_of_module(modl)
    for mi in mis
        if isdefined(mi.def, :generator) # can't handle @generated functions, Issue #11
            @debug "GENERATED $(mi)"
            continue
        end

        is_blocklisted(modl, mi.def.module) && (@debug "alien: $mi.def defined in $mi.def.module"; continue)

        fs = get!(res.mestats, mi.def,
                  fstats_default(mi.def.nospecialize,
                                 occursin("Vararg","$(mi.def.sig)")))
        try
            call = reconstruct_func_call(mi)
            if call === nothing # this mi is a constructor call - skip
                delete!(res.mestats, mi.def)
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
            res.mistats[mi] = MIStats(mi_st, mi_gd, cfg_stats(code)..., rettype, call[2] #= input types =#)
        catch err
            fs.fail += 1
            print(errio, "ERROR: ");
            showerror(errio, err, stacktrace(catch_backtrace()))
            println(errio)
        end
    end
    res
end

#
# Section: Reshape the stats into a tabular form for storing as CSV
#

struct ModuleStatsPerMethodRecord
    modl     :: String
    funcname :: String
    occurs   :: Int
    stable   :: Float64
    grounded :: Float64
    rettypes :: Int
    nospec   :: Int
    vararg   :: Int
    size     :: Int
    file     :: String
    line     :: Int
end

struct ModuleStatsPerInstanceRecord
    modl     :: String
    funcname :: String
    stable   :: Bool
    grounded :: Bool
    gotos    :: Int
    returns  :: Int
    rettype  :: String
    intypes  :: String
    file     :: String
    line     :: Int
end

# Convert stats to vectors of records
modstats_table(ms :: ModuleStats, errio = stdout :: IO) ::
    Tuple{Vector{ModuleStatsPerMethodRecord}, Vector{ModuleStatsPerInstanceRecord}} = begin
        resmeth = []
        resmi = []
        m2rettype = Dict{Method, Set{String}}()
        for (mi,cfgst) in ms.mistats
            try
                meth = mi.def
                modl = "$(meth.module)"
                mename = "$(meth.name)"
                msrclen = length(meth.source)
                rettype = "$(cfgst.rettype)"
                intypes = join(cfgst.intypes, ",")
                mfile = "$(meth.file)"
                mline = meth.line
                push!(resmi,
                      ModuleStatsPerInstanceRecord(
                          modl, mename,
                          cfgst.st, cfgst.gd,
                          cfgst.gt, cfgst.rt,
                          rettype, intypes,
                          mfile, mline))
                push!(get!(m2rettype, meth, Set{String}()), rettype)
            catch err
                if !endswith(err.msg, "has no field var") # see JuliaLang/julia/issues/38195
                    println(errio, "ERROR: modstats_table: mi-loop: $(mi)");
                    throw(err)
                else
                    @info "the #38195 bug with $mename"
                end
            end
        end
        for (meth,fstats) in ms.mestats
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
                          length(get(m2rettype, meth, Set{String}())), # lookup can fail either
                            # b/c JuliaLang/julia/issues/38195 or
                            # type inference failure inside module_stats()
                          meth.nospecialize, fstats.vararg,
                          msrclen,
                          mfile, mline))
            catch err
                println(errio, "ERROR: modstats_table: m-loop: $(meth)");
                throw(err)
            end
        end
        (resmeth,resmi)
end

# Filter out some uninteresting data, mostly the standard library
# (otherwise we would be measuring the standard library all over again)
is_blocklisted(modl_proccessed :: Module, modl_mi :: Module) = begin
    mmi="$modl_mi"
    mp="$modl_proccessed"

    startswith(mmi,mp) && return false

    return startswith(mmi, "Base") ||
        startswith(mmi, "Core") ||
        startswith(mmi, "REPL") ||
        mmi in ["Test", "Random",] ||
        false
end

# store_cur_version :: String -> IO ()
# Store the version of the given package that we just processed into a file
# named "version.txt"
store_cur_version(pkg::String) = begin
    ver  = installed_pkg_version(pkg)
    fname= "version.txt"
    write(fname, "$ver")
    @info "[Stability] Write down $pkg version to $fname"
end

# installed_pkg_version :: String ->IO String
# Will querry current environment for the version of given package
#
installed_pkg_version(pkg::String) = begin
    deps = collect(values(Pkg.dependencies()))
    i    = findfirst(i -> i.name == pkg, deps)
    if i === nothing
        nothing
    else
        string(deps[i].version)
    end
end

macro myinfo(pkgtag, msg)
    esc(:( @info ("[Stability] [Package: " * $pkgtag * "] " * $msg ) ))
end

txtToCsv(work_dir :: String, basename :: String) = begin
    resf = joinpath(work_dir, "$basename.txt")
    isfile(resf) || (@error "Stability analysis failed to produce output $resf"; return)
    st =
        eval(Meta.parse(
            open(f-> read(f,String), resf,"r")))
    CSV.write(joinpath(work_dir, "$basename.csv"), st)
end

#
#  Section: Stats for type stability, package level
#

# package_stats: (pakg: String, ver: String) -> IO ()
#
# In the current directory:
# - runs stability analysis for the package `pakg` of version `ver` (initializing package environment accordingly)
# - results are stored in the following files of the current directory (see also "Side Effects" below):
#   * stability-stats.out
#   * stability-errors.out
#   * stability-stats-per-method.csv
#   * stability-stats-per-instance.csv
#   * $pakg-version.txt (version stamp for future reference)
#
# Setting a package version:
#   The `ver` parameter has been added recently, and has rough corners. E.g. if you call the function in
#   a directory with a manifest file, we'll process the version specified in the manifest instead of `ver`.
#   So, be sure to run in an empty dir if you care about the `ver` parameter.
#
# Side effects:
#   In the current directory, creates a temporary environment for this package, and the resulting files.
#   Reusing this env shouldn't harm anyone (in theory).
#
# Parallel execution:
#   Possible e.g. with the aid of GNU parallel and the tiny script in scripts/proc_package_parallel.sh.
#   It requires a file with a list of packages passed as the first argument.
#
# REPL:
#   Make sure to run from a reasonable dir, e.g. create a dir for this package yourself
#   and cd into it before calling.
#
package_stats(pakg :: String, ver = nothing) = begin
    work_dir  = pwd()
    ENV["STAB_PKG_NAME"] = pakg
    ENV["WORK_DIR"] = work_dir
    pkgtag = pakg * (ver === nothing ? "" : "@v$ver")

    #
    # Set up and test the package `pakg`
    #
    @myinfo pkgtag "Starting up"
    try
        Pkg.activate(".") # Switch from Stability package-local env to a temp env
        if isfile("Manifest.toml")
            Pkg.instantiate() # package environment has been setup beforehand
        else
            Pkg.add(name=pakg, version=ver)
        end
        # Sanity checking w.r.t Manifest vs $ver parameter
        iver = installed_pkg_version(pakg)
        if !(ver === nothing) && ver != iver
            throw(ErrorException("[Stability] The Manifest file in the current directory declares " *
                            "a version of the package $pakg other than requested. " *
                            "Either remove the Manifest or don't supply the version."))
        end
        pkgtag = pakg * "@v$iver"
        @myinfo pkgtag "Added. Now on to testing"
        Pkg.test(pakg)
        store_cur_version(pakg)
    catch err
        println("Error when running tests for package $(pakg)")
        errio=stderr
        print(errio, "ERROR: ");
        showerror(errio, err, stacktrace(catch_backtrace()))
        println(errio)
    finally
        Pkg.activate(dirname(@__DIR__)) # switch back to Stability env
    end

    #
    # Write down the results
    #
    txtToCsv(work_dir, "stability-stats-per-method")
    txtToCsv(work_dir, "stability-stats-per-instance")
    @myinfo pkgtag "Results successfully converted to CSV. The package is DONE!"
end

end # module
