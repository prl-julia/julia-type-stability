using CSV, DataFrames, Query

#
# Merge stability-stats-intypes.csv table summing up occurs field.
#
# Run from a root of a pkgs directory, i.e. every subdir corresponds to
# a package and holds a `stability-stats-intypes.csv` file
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
            @group i.occurs by i.modl, i.tyname into g
            @select {modl=key(g)[1], tyname=key(g)[2], occurs=sum(g)}
            @collect DataFrame
        end
    end
    resdf = resdf |> @orderby_descending(_.occurs) |> DataFrame
    CSV.write("merged-intypes.csv", resdf)
    print("Done! Bye!")
end

main();
