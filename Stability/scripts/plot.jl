using CSV, DataFrames

ENV["GKSwstype"] = "nul"  # can run headless

using StatsPlots

# Plot a histogram with Y=stability and X=column with the
# given name (col).
# Input:
# - dataframe with columns: :stabilty and col (at least).
# - name of the dataframe -- used to name the output file
# Output: none
# Side Effect:
#   create a graphic file with the plot.
plot_col(df :: DataFrame, col :: Symbol, df_name :: String = "noname", prefix :: String = "") = begin
    mi=max(1, minimum(df[!, col]))
    ma=maximum(df[!, col])
    @df df histogram2d(
           cols(col),
           :stable,
           c=cgrad([:blue, :red]),
           nbins=(200,20),
           size=(1200,800),
           legend=false,
           title=df_name,
           xaxis=:log10,
           xlim=[mi,ma],
           ylim=[0,1.2])
    out=joinpath(prefix,"$(df_name)-$(col).png")
    @info "About to store the plot in $out"
    savefig(out)
end

plot_pkg(pkg :: String, col :: Symbol = :size, odir :: String = ".", idir :: String = ".") = begin
    in = "$idir/$pkg/stability-stats.csv"
    isfile(in) || (@warn "No stats file for package $pkg (failed to open $in)"; return)
    df = CSV.read(in, DataFrame)
    plot_col(df, col, pkg, odir)
end

# Plot with plot_col for every package in the list stored in pkgs_file
# Assumes: every package name corespondes to a dir in the current dir
plot_all_pkgs(pkgs_file :: String, col :: Symbol = :size) = begin
    isfile(pkgs_file) || (@error "Invalid package list file $pkgs_file"; return)

    odir="by-$col"
    #!isdir(odir) || rm(odir, force=true, recursive=true) # more reproducible
    #mkdir(odir)
    isdir(odir) || mkdir(odir)

    pkgs = readlines(pkgs_file)
    for p in pkgs
        plot_pkg(p, col, odir)
    end
end
