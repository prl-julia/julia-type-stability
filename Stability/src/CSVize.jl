#
# Reshape the stats into a tabular form for storing as CSV
#

struct ModuleStatsPerMethodRecord
    modl     :: String
    funcname :: String
    occurs   :: Int
    stable   :: Float64
    grounded :: Float64
    rettypes :: Int
    nospec   :: Int
    vararg   :: Int
    size     :: Int
    file     :: String
    line     :: Int
end

struct ModuleStatsPerInstanceRecord
    modl     :: String
    funcname :: String
    stable   :: Bool
    grounded :: Bool
    gotos    :: Int
    returns  :: Int
    rettype  :: String
    intypes  :: String
    file     :: String
    line     :: Int
end

struct ModuleStatsInTypeRecord
    pack     :: String
    modl     :: String
    tyname   :: String
    occurs   :: Int
    depth    :: Int
end

#
# Convert stats dicitonaries to vectors of records
#
modstats_table(ms :: ModuleStats, errio = stdout :: IO) ::
    Tuple{
        Vector{ModuleStatsPerMethodRecord},
        Vector{ModuleStatsPerInstanceRecord},
        Vector{ModuleStatsInTypeRecord}} = begin

        resmeth = []
        resmi = []
        resty = []

        m2rettype = Dict{Method, Set{String}}()
        for (mi,cfgst) in ms.mistats
            try
                meth = mi.def
                modl = "$(meth.module)"
                mename = "$(meth.name)"
                msrclen = length(meth.source)
                rettype = "$(cfgst.rettype)"
                intypes = join(cfgst.intypes, ",")
                mfile = "$(meth.file)"
                mline = meth.line
                push!(resmi,
                      ModuleStatsPerInstanceRecord(
                          modl, mename,
                          cfgst.st, cfgst.gd,
                          cfgst.gt, cfgst.rt,
                          rettype, intypes,
                          mfile, mline))
                push!(get!(m2rettype, meth, Set{String}()), rettype)
            catch err
                if !endswith(err.msg, "has no field var") # see JuliaLang/julia/issues/38195
                    println(errio, "ERROR: modstats_table: mi-loop: $(mi)");
                    throw(err)
                else
                    @info "the #38195 bug with $mename"
                end
            end
        end
        for (meth,fstats) in ms.mestats
            try
                modl = "$(meth.module)"
                mname = "$(meth.name)"
                msrclen = length(meth.source)
                mfile = "$(meth.file)"
                mline = meth.line
                push!(resmeth,
                      ModuleStatsPerMethodRecord(
                          modl, mname, fstats.occurs,
                          fstats.stable/fstats.occurs, fstats.grounded/fstats.occurs,
                          length(get(m2rettype, meth, Set{String}())), # lookup can fail either
                            # b/c JuliaLang/julia/issues/38195 or
                            # type inference failure inside module_stats()
                          meth.nospecialize, fstats.vararg,
                          msrclen,
                          mfile, mline))
            catch err
                println(errio, "ERROR: modstats_table: m-loop: $(meth)");
                throw(err)
            end
        end
        for (ty,tystat) in ms.tystats
            try
                pack = tystat.pack
                modl = "$(tystat.modl)"
                tyname = "$(ty)"
                push!(resty,
                      ModuleStatsInTypeRecord(pack, modl, tyname, tystat.occurs, tystat.depth))
            catch err
                println(errio, "ERROR: modstats_table: ty-loop: $err");
                throw(err)
            end
        end
        (resmeth,resmi,resty)
end
