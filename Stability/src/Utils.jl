#
# Kitchen sink
#

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
    isfile(resf) || (throw(ErrorException("Stability analysis failed to produce output $resf")))
    st =
        eval(Meta.parse(
            open(f-> read(f,String), resf,"r")))
    CSV.write(joinpath(work_dir, "$basename.csv"), st)
end
