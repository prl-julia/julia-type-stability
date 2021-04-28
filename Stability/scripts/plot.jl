using CSV, DataFrames

ENV["GKSwstype"] = "nul"  # can run headless

using StatsPlots

# Plot a histogram with Y=a stability metrix (:stable or :grounded passed as oy)
# and X=column with the given name (ox).
# Input:
# - dataframe with columns: ox and oy (at least).
# - name of the dataframe -- used to name the output file
# Output: none
# Side Effect:
#   create a graphic file with the plot.
plot_col(df :: DataFrame, ox :: Symbol, oy :: Symbol, df_name :: String = "noname") = begin
    mi=max(1, minimum(df[!, ox]))
    ma=maximum(df[!, ox])
    @info "About to plot $df_name: $(ox) by $(oy)"
    @df df histogram2d(
           cols(ox),
           cols(oy),
           c=cgrad(:viridis),
           cb = true,
        xtickfont=13,
        ytickfont=13,
        #guidefont=font(18),
        #legendfont=font(18),
           nbins=(20,10),
           #title=df_name,
           xlim=[mi,ma+ma/20],
           ylim=[0,1.2])
end

plot_pkg(pkg :: String; ox :: Symbol = :size, oy :: Symbol = :stable,
         granularity :: String = "method",
         idir :: String = ".") = begin
    in = "$idir/$pkg/stability-stats-per-$(granularity).csv"
    isfile(in) || (@warn "No stats file for package $pkg (failed to open $in)"; return)
    df = CSV.read(in, DataFrame)
    plot_col(df, ox, oy, pkg)
end

# Plot with plot_col for every package in the list stored in pkgs_file
# Assumes: every package name corespondes to a dir in the current dir
plot_all_pkgs(pkgs_file :: String, ox :: Symbol = :size, oy :: Symbol = :stable,
			granularity :: String = "method",
			odir :: String = ".") = begin
    isfile(pkgs_file) || (@error "Invalid package list file $pkgs_file"; return)

    #!isdir(odir) || rm(odir, force=true, recursive=true) # more reproducible
    #mkdir(odir)
    isdir(odir) || mkdir(odir)

    pkgs = readlines(pkgs_file)
    plots = []
    for p in pkgs
        push!(plots, plot_pkg(p, ox=ox, oy=oy, granularity=granularity))
    end
    plot(plots..., layout = (2, 5), size=((1200+900)*5,800*2))
    out=joinpath(odir,"$(oy)-by-$(ox).png")
    savefig(out)

end

plot_gran(pkg :: String, gran :: String) = begin
    d = Dict(
        "method" =>
        ([:stable, :grounded],
         [
             :size,
         ]),
        "instance" =>
        ([:st, :gd],
         [
             :gt, :rt
         ])
    )
    (oys, oxs) = d[gran]
    for ox in oxs
        for oy in oys
            plot_pkg(pkg;ox=ox,oy=oy,granularity=gran)
            mkpath("$(pkg)/figs")
            savefig("$(pkg)/figs/$(pkg)-$(ox)-vs-$(oy).pdf")
        end
    end
end

plot_everything(pkg :: String) = begin
    plot_gran(pkg, "method")
    plot_gran(pkg, "instance")
end
