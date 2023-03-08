#
#  Stats for type stability, module level
#

# Statistics gathered per method instance.
struct MIStats
    st       :: Bool # if the instance is stable
    gd       :: Bool # if the instance is grounded
    gt       :: Int  # number of gotos in the instance
    rt       :: Int  # number of returns in the instance
    rettype  :: Any  # return type inferred; NOTE: should probably be a Datatype
    intypes  :: Core.SimpleVector # have to use this b/c that's what we get from
    # `reconstruct_func_call`; a vector of input types
end

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

# Statistics gathered per method.
# Note on "mutable": stats are only mutable during their calculation.
mutable struct MethodStats
    occurs   :: Int  # how many instances of the method found
    stable   :: Int  # how many stable instances of the method
    grounded :: Int  # how many grounded instances of the method
    nospec   :: Int  # the nospecialized bitmap (if /=0, there are nospec. params)
    vararg   :: Int  # if the method is a varags method (0/1)
    fail     :: Int  # how many times fail to detect stability of an instance (cf. Issues #7, #8)
end

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

struct ModuleStats
  modl    :: Module
  mestats :: Dict{Method, MethodStats}
  mistats :: Dict{MethodInstance, MIStats}
end

ModuleStats(modl :: Module) = ModuleStats(modl, Dict{Method, MethodStats}(), Dict{Method, MIStats}())

# Generate a summary of stability data in the module: just a fold (+) over stats
# of individual methods / instances
modstats_summary(ms :: ModuleStats) = begin
  fs = foldl((+), values(ms.mestats); init=fstats_default())
  [length(ms.mestats),fs.occurs,fs.stable,fs.grounded,fs.nospec,fs.vararg,fs.fail]
end

# Given a module object after some code of the module has been compiled, compute
# all stabilty stats for this module
module_stats(modl :: Module, errio :: IO = stderr) = begin
    res = ModuleStats(modl)
    mis = all_mis_of_module(modl)
    for mi in mis
        if isdefined(mi.def, :generator) # can't handle @generated functions, Issue #11
            @debug "GENERATED $(mi)"
            continue
        end

        is_blocklisted(modl, mi.def.module) && (@debug "alien: $mi.def defined in $mi.def.module"; continue)

        fs = get!(res.mestats, mi.def,
                  fstats_default(mi.def.nospecialize,
                                 occursin("Vararg","$(mi.def.sig)")))
        try
            call = reconstruct_func_call(mi)
            if call === nothing # this mi is a constructor call - skip
                delete!(res.mestats, mi.def)
                continue
            end

            fs.occurs += 1

            # handle stability/groundedness
            mi_st = false
            mi_gd = false
            (code,rettype) = run_type_inference(call...);
            if is_concrete_type(rettype)
                fs.stable += 1
                mi_st = true
                if is_grounded_call(code)
                    fs.grounded += 1
                    mi_gd = true
                end
            end

            # handle instance CFG stats
            res.mistats[mi] = MIStats(mi_st, mi_gd, cfg_stats(code)..., rettype, call[2] #= input types =#)
        catch err
            fs.fail += 1
            print(errio, "ERROR: ");
            showerror(errio, err, stacktrace(catch_backtrace()))
            println(errio)
        end
    end
    res
end
