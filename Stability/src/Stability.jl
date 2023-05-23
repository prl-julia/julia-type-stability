#
# Package for Type Stability analysis of Julia packages
#
module Stability

using Core: MethodInstance, CodeInstance, CodeInfo
using MethodAnalysis: visit
using Pkg
using CSV

export is_concrete_type, is_grounded_call, all_mis_of_module,
       MIStats, MethodStats, InTypeStats, ModuleStats,
       module_stats, modstats_summary, modstats_table,
       package_stats, cfg_stats,
       show_comma_sep

#
# Configuration Parameters
#

# We do nasty things with Pkg.test
if get(ENV, "DEV", "NO") != "NO"
  include("pkg-test-override.jl")
end

# turn on debug info:
# julia> ENV["JULIA_DEBUG"] = Main
# turn off:
# juila> ENV["JULIA_DEBUG"] = nothing

include("MethodAnalysis.jl")
include("Stats.jl")
include("CSVize.jl")
include("Utils.jl")

#
#  The main entry point for package-level analysis
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
#   * stability-stats-intypes.csv
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
        println("[Stability] Error when running tests for package $(pakg)")
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
    txtToCsv(work_dir, "stability-stats-intypes")
    @myinfo pkgtag "Results successfully converted to CSV. The package is DONE!"
end

end # module
