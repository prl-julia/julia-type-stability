#############################################
#
#  Stats for type stability, module level
#
#############################################

import Base.@kwdef
include("equality.jl")

# -------------------------------------------
#
# Statistics gathered per method instance.
#
# -------------------------------------------
@kwdef struct MIStats
    st       :: Bool # if the instance is stable
    gd       :: Bool # if the instance is grounded
    gt       :: Int  # number of gotos in the instance
    rt       :: Int  # number of returns in the instance
    rettype  :: Any  # return type inferred; NOTE: should probably be a Datatype
    intypes  :: Core.SimpleVector # have to use this b/c that's what we get from
    # `reconstruct_func_call`; a vector of input types
end

@deriveEq(MIStats)

# Stats about control-flow graph of a method instance
# Currently, number of gotos, and number of returns
cfg_stats(code :: CodeInfo) = begin
    gt = 0
    rt = 0

    for st in code.code
        if is_goto(st)
            gt += 1
        elseif is_return(st)
            rt += 1
        end
    end
    (gt,rt)
end

is_goto(::Core.GotoNode) = true
is_goto(e::Expr) = e.head == :gotoifnot
is_goto(::Any) = false
is_return(e::Expr) = e.head == :return
is_return(::Any) = false


# -------------------------------------------
#
# Statistics gathered per method.
#
# -------------------------------------------

# Note on "mutable": stats are only mutable during their calculation.
@kwdef mutable struct MethodStats
    occurs   :: Int  # how many instances of the method found
    stable   :: Int  # how many stable instances of the method
    grounded :: Int  # how many grounded instances of the method
    nospec   :: Int  # the nospecialized bitmap (if /=0, there are nospec. params)
    vararg   :: Int  # if the method is a varags method (0/1)
    fail     :: Int  # how many times fail to detect stability of an instance (cf. Issues #7, #8)
end

@deriveEq(MethodStats)

# convenient default constructor
fstats_default(nospec=0, vararg=0) = MethodStats(0,0,0,nospec,vararg,0)

# This is needed for modstats_summary: we smash data about individual methods together
# and get coarse-grained module stats
# This has to be clewver: many things can be simply summed, but not all.
import Base.(+)
(+)(fs1 :: MethodStats, fs2 :: MethodStats) =
  MethodStats(
      fs1.occurs+fs2.occurs,
      fs1.stable+fs2.stable,
      fs1.grounded+fs2.grounded,
      fs1.nospec + min(1, abs(fs2.nospec)),
      fs1.vararg + fs2.vararg,
      fs1.fail+fs2.fail
  )

# This is needed for modstats_summary
show_comma_sep(xs::Vector) = join(xs, ",")


# --------------------------------------------------------
#
# Statistics for all types occured during instantiations.
#
# --------------------------------------------------------

# Note on "mutable": stats are only mutable during their calculation.
@kwdef mutable struct InTypeStats
    modl   :: String
    occurs :: Int
end

InTypeStats(modl :: Module) = InTypeStats("$modl", 0)
InTypeStats(modl :: String) = InTypeStats(modl, 0)

@deriveEq(InTypeStats)

# -------------------------------------------
#
# Statistics gathered per module.
#
# -------------------------------------------

@kwdef struct ModuleStats
  modl    :: Module
  mestats :: Dict{Method, MethodStats}
  mistats :: Dict{MethodInstance, MIStats}
  tystats :: Dict{Any, InTypeStats}
end

ModuleStats(modl :: Module) = ModuleStats(
    modl,
    Dict{Method, MethodStats}(),
    Dict{Method, MIStats}(),
    Dict{Any, InTypeStats}()
)

@deriveEq(ModuleStats)

# Generate a summary of stability data in the module: just a fold (+) over stats
# of individual methods / instances
modstats_summary(ms :: ModuleStats) = begin
  fs = foldl((+), values(ms.mestats); init=fstats_default())
  [length(ms.mestats),fs.occurs,fs.stable,fs.grounded,fs.nospec,fs.vararg,fs.fail]
end


# ----------------------------------------------------------
#
# Entry point to the whole file: compute stats over a module
#
# ----------------------------------------------------------

#
# module_stats :: (Module, IO) -> ModuleStats
#
# Given a module object compute stabilty stats for this module.
#
# Assumption:
#   All code of interest from the module has been compiled. In plain terms, you need to call a method
#   at least once to have some data about it.
#
# Normally, you would have a package X exporting main module also called X.
# You run a test suite of the corresponding package and then call `module_stats(X)`.
#
module_stats(modl :: Module, errio :: IO = stderr) = begin
    res = ModuleStats(modl)
    mis = all_mis_of_module(modl)
    for mi in mis

        # Plan: for every method instance `mi` need to update every of the three fields
        #       in `res` (ModuleStats): 
        #       step 1) method stats (`res.mestats`)
        #       step 2) instance stats (`res.mistats`)
        #       step 3) input types (`res.tystats`)

        # Special cases: @generated, blocklisted
        if isdefined(mi.def, :generator) # can't handle @generated functions, Issue #11
            @debug "GENERATED $(mi)"
            continue
        end
        is_blocklisted(modl, mi.def.module) && (@debug "alien: $mi.def defined in $mi.def.module"; continue)

        # Starting step 1: Lookup method stats object for this `mi`
        mest = get!(res.mestats, mi.def,
                  fstats_default(mi.def.nospecialize,
                                 occursin("Vararg","$(mi.def.sig)")))
        try
            # Get code of the `mi` for later analysis
            call = reconstruct_func_call(mi)
            if call === nothing # this mi is a constructor call - skip
                delete!(res.mestats, mi.def)
                continue
            end

            mest.occurs += 1

            # Finishing step 1 and starting step 2: Check stability/groundedness of the code
            mi_st = false
            mi_gd = false
            (code,rettype) = run_type_inference(call...);
            if is_concrete_type(rettype)
                mest.stable += 1
                mi_st = true
                if is_grounded_call(code)
                    mest.grounded += 1
                    mi_gd = true
                end
            end

            # Finishing step 2: all that is left is to handle instance CFG stats
            res.mistats[mi] = MIStats(mi_st, mi_gd, cfg_stats(code)..., rettype, call[2] #= input types =#)
            # Note on intypes: historically, they lived in MIStats, but for more precise analysis
            #                  we now have them separately one by one, see Step 3 below

            # Step 3: Collect intypes
            intypes = Base.unwrap_unionall(mi.specTypes).types[2:end]
            for ty in intypes
                tymodl = moduleChainOfType(ty)
                tystat = get!(res.tystats,
                            ty,
                            InTypeStats(tymodl))
                tystat.occurs += 1
            end
        catch err
            mest.fail += 1
            print(errio, "ERROR: ");
            showerror(errio, err, stacktrace(catch_backtrace()))
            println(errio)
        end
    end
    res
end
