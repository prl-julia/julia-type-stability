using CSV, DataFrames, Query

#
# Merge stability-stats-intypes.csv table summing up occurs field.
#
# Run from a root of a pkgs directory, i.e. every subdir corresponds to
# a package and holds a `stability-stats-intypes.csv` file, e.g.
#
# ❯ JULIA_PROJECT=~/s/repo/Stability/scripts/julia julia ~/s/repo/Stability/scripts/julia/merge-intypes.jl
#


idir="."

main() = begin
    resdf = DataFrame()
    for package in readdir(idir)
        isfile(package) && continue
        in="$idir/$package/stability-stats-intypes.csv"
        isfile(in) || (@warn "File not found: $in"; continue;)
        @info "Processing " package
        resdf = vcat(resdf, CSV.read(in, DataFrame))
        resdf = @from i in resdf begin
            @group i.occurs by i.pack, i.modl, i.tyname, i.depth into g
            @select {pack=key(g)[1], modl=key(g)[2], tyname=key(g)[3], occurs=sum(g), depth=key(g)[4]}
            @collect DataFrame
        end
    end
    resdf = resdf |> @orderby_descending(_.depth) |> DataFrame # we will be loading deepest-nested types first
    CSV.write("merged-intypes.csv", resdf)
    print("Done! Bye!")
end

main();
