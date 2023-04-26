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

moduleChainOfType(@nospecialize(ty)) :: String = begin
    mod=parentmodule(ty)
    res="$mod"
    while parentmodule(ty) != mod
        mod = parentmodule(mod)
        res = "$mod." * res
    end
    res
end

#
# sequence_nothing : (v :: Vector{Union{T, Nothing}}) -> Union{Nothing, Vector{T}}
#
# traverse_nothing looks into the given vetor and if it sees nothing, returns nothing,
# otherwise it returns the input vector.
#
# traverse_nothing([1,nothing,2]) |-> nothing
# traverse_nothing([1,2]) |-> [1,2]
#
sequence_nothing(v :: Vector) :: Union{Nothing, Vector} = begin
    any(isnothing, v) && return nothing
    v
end


#
# slice_parametric_type: (ty, depth :: Int) -> Union{
#                                                Vector{Tuple{Any, Int}},
#                                                Nothing}
#
# Slice a type constructor into pieces, record the depth of nestedness of every piece.
#
# Example: Vector{Vector{Int}} |-> [(Vector{Vector{Int}}, 0), (Vector{Int}, 1), (Int, 2)]
#
# If we see existentials anywhere in the type, we return nothing because we're unsure how
# to deal with variables (a naive approach would yield pieces with unbound variables).
#
slice_parametric_type(@nospecialize(ty), depth :: Int = 0) :: Union{Vector{Tuple{Any, Int}}, Nothing} = begin

    ####### Special cases:
    #
    # - Unions
    ty == Union{} && return [] # empty union
    typeof(ty) == Union &&     # binary union
        return sequence_nothing(vcat(slice_parametric_type(ty.a, depth+1),
                    slice_parametric_type(ty.b, depth+1)))

    # - Varargs
    typeof(ty) == Core.TypeofVararg && return sequence_nothing(slice_parametric_type(ty.T, depth+1))

    # - Most likely values, or something weird with no field `parameters`
    hasproperty(ty, :parameters) || return []

    # - Existentials (UnionAll): we explicitly discqualify types that have existentials for now
    typeof(ty) == UnionAll && return nothing

    ####### Normal stuff: atoms and parametric constructors
    #
    params = ty.parameters

    # - Non-parametric atomic type
    isempty(params) && return [(ty, depth)]

    # - parametric
    rec = map(ty1 -> slice_parametric_type(ty1, depth+1), params)
    recFlat = reduce(vcat, rec)
    sequence_nothing(push!(recFlat, (ty, depth)))
end
