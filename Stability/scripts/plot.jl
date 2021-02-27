using CSV, DataFrames

ENV["GKSwstype"] = "nul"  # can run headless

using StatsPlots

# Plot a scatter plot with Y=stability and X=column with the
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
    @df df scatter(
           cols(col),
           :stable,
           size=(1200,800),
           legend=false,
           title=df_name,
           xaxis=:log10,
           xlim=[mi,ma])
    savefig(joinpath(prefix,"$(df_name)-$(col).png"))
end

# Plot with plot_col for every package in the list stored in pkgs_file
# Assumes: every package name corespondes to a dir in the current dir
plot_pkgs(pkgs_file :: String, col :: Symbol) = begin
    isfile(pkgs_file) || (@error "Invalid package list file $pkgs_file"; return)

    odir="by-$col"
    #!isdir(odir) || rm(odir, force=true, recursive=true) # more reproducible
    #mkdir(odir)
    isdir(odir) || mkdir(odir)

    pkgs = readlines(pkgs_file)
    for p in pkgs
        in = "$p/stability-stats.csv"
        isfile(in) || (@warn "No stats file for package $p"; continue)
        df = CSV.read(in, DataFrame)
        plot_col(df, col, p, odir)
    end
end
