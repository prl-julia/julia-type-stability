using CSV, DataFrames

ENV["GKSwstype"] = "nul"  # can run headless

using StatsPlots

plot_col(df :: DataFrame, col :: Symbol, df_name :: String = "noname") = begin
    mi=max(1, minimum(df[!, col]))
    ma=maximum(df[!, col])
    @df df scatter(
           cols(col),
           :stable,
           xaxis=:log10,
           xlim=[mi,ma])
    savefig("$(df_name)-$(col).pdf")
end
