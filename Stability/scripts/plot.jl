#!/usr/bin/env julia
using CSV, DataFrames

#
# Entry point to this script is `plot_all_pkgs` (at the very bottom) for
# batch processing of many packages or `plot_pkg` for plotting individual package
#

# Metrics we plot grouped by granularity (method vs instance)
metrics = Dict(
    "method" =>
    [ :size ],

    "instance" =>
    [ :gotos, :returns ]
)

ENV["GKSwstype"] = "nul"  # need to run headless (no graphics)

using StatsPlots

# Plot a 2D histogram with OY = a stability metrics (stable or grounded)
# and OX some other label in the dataframe.
# Input:
# - `df` -- dataframe with columns: OX and OY (at least).
# - label for OX axis (should name a column in df)
# - label for OY axis (should name a column in df)
# Output: none
# Side Effect:
# - create a graphic on the virtual plot.
plot_2d_histogram(pkg :: AbstractString; ox :: Symbol = :size, oy :: Symbol = :stable,
         granularity :: String = "method") = begin
    in = "$pkg/stability-stats-per-$(granularity).csv"
    isfile(in) || (@warn "No stats file for package $pkg (failed to open $in)"; return)
    df = CSV.read(in, DataFrame)
    mi=max(1, minimum(df[!, ox]))
    ma=maximum(df[!, ox])
    @df df histogram2d(
        cols(ox),
        cols(oy),
        c=cgrad(:viridis),
        cb = true,
        xtickfont=13,
        ytickfont=13,
        nbins=(20,10),
        xlim=[mi,ma+ma/20],
        ylim=[0,1.2]) # OX scale is adaptive but OY is always 0 to 1 --
                      # for groundedness or stability
end

# Some metrics apply only to granularity "method", others -- to granularity
# "(method) instance". This method loops over metrics applying to the given
# granularity and plots all of them for the given package.
plot_pkg_by_granularity(pkg :: AbstractString, gran :: String) = begin
    oys = [:stable, :grounded]
    oxs = metrics[gran]
    for ox in oxs
        for oy in oys
            @info "About to plot $pkg: $(ox) by $(oy)"
            plot_2d_histogram(pkg;ox=ox,oy=oy,granularity=gran)
            mkpath("$(pkg)/figs")
            savefig("$(pkg)/figs/$(pkg)-$(ox)-vs-$(oy).pdf")
        end
    end
end

# Plot all possible metrics for the given package
plot_pkg(pkg :: AbstractString) = begin
    plot_pkg_by_granularity(pkg, "method")
    plot_pkg_by_granularity(pkg, "instance")
end

# Plot every metric for every package in the list stored in `pkgs_file`
# Assumes: every package name corespondes to a dir in the current dir
plot_all_pkgs(pkgs_file :: String, ox :: Symbol = :size, oy :: Symbol = :stable,
              granularity :: String = "method") = begin
    isfile(pkgs_file) && !isdir(pkgs_file) ||
        error("Invalid package list file $pkgs_file")

    pkgs = readlines(pkgs_file)
    for p in pkgs
        plot_pkg(split(p)[1])
    end
end
