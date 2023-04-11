#
# Pure method stability analysis
#
# Inspired by Julia's @code_warntyped, so uses Julia's own type inference
#

# Instead of printing concretness of inferred type (as @code_warntype@ does),
# return a bool
# Follows `warntype_type_printer` in:
# julia/stdlib/InteractiveUtils/src/codeview.jl
is_concrete_type(@nospecialize(ty)) = begin
    if ty isa Type && (!Base.isdispatchelem(ty) || ty == Core.Box)
        if ty isa Union && Base.is_expected_union(ty)
            true # this is a "mild" problem, so we round up to "stable"
        else
            false
        end
    else
        true
    end
    # Note 1: Core.Box is a type of a heap-allocated value
    # Note 2: isdispatchelem is roughly eqviv. to
    #         isleaftype (from Julia pre-1.0)
    # Note 3: expected union is a trivial union (e.g.
    #         Union{Int,Missing}; those are deemed "probably
    #         harmless"
end

struct TypeInferenceError <: Exception
    f :: Any
    t :: Any
end

# Args:
# * f: function
# * t: tuple of argument types
# Returns: pair (CodeInstance - typed IR, Inferred Type of the Body)
function run_type_inference(@nospecialize(f), @nospecialize(t))
    ct = code_typed(f, t, optimize=false)
    if length(ct) == 0
        throw(TypeInferenceError(f,t)) # type inference failed
    end
    ct[1] # we ought to have just one method body, I think
end

# Accepts inferred method body and checks if every slot in it is concrete
is_grounded_call(src :: CodeInfo) = begin
    slottypes = src.slottypes

    # the following check is taken verbatim from code_warntype
    if !isa(slottypes, Vector{Any})
        return true # I don't know when we get here,
                    # over-approx. as stable
    end

    result = true

    slotnames = Base.sourceinfo_slotnames(src)
    for i = 1:length(slottypes)
        stable = is_concrete_type(slottypes[i])
        @debug "is_stable_call slot:" slotnames[i] slottypes[i] stable
        result = result && stable
    end
    result
end

#
# Section: MethodInstance-based pure interface (thanks to MethodAnalysis.jl)
#

# Note [Generic Method Instances]
# We don't quite understand how to process generic method instances (cf. issue #2)
# We used to detect them, count, but don't test for stability.
# Currently, we use Base.unwrap_unionall and the test just works (yes, for types
# with free type variables). This still requires more thinking.

is_generic_instance(mi :: MethodInstance) = typeof(mi.specTypes) == UnionAll

# Note [Unknown instances]
# Some instances we just can't resolve.
# E.g. In JSON test suite there's a `lower` method that is unknown.
# This is rare and due to macro magic.

is_known_instance(mi :: MethodInstance) = isdefined(mi.def.module, mi.def.name)

struct StabilityError <: Exception
    met :: Method
    sig :: Any
end

# reconstruct_func_call : MethodInstance -> IO (Union{ (Method, [Type]), Nothing })
#
# What does Julia do about (top-level) function calls like `abc(1,xyz)`?
# 1. Identifiy types of the inputs (1 :: Int, xyz :: Blah)
# 2. Dispatch: figure out which implementation (aka method) of `abc` will be used.
# 3. Compile the method (2) using the input types (1) to get a "method instance".
# 
# `reconstruct_func_call` does the reverse transformation:
# Accepts a method instance (3) as found in Julia VM cache after executing some code.
# Returns: pair of a method object (2) and a tuple of types of arguments (1)
#         or nothing if it's constructor call.
#
# ### Why IO?
# 
# The analysis here is pure. The only reason we add IO is a sheaky hack we implement
# to trace suspicous cases of inputs that we don't understand very well. In particular,
# generic signatures of method instances. In theory they shouldn't appear but in
# practise they do. So we log then in a file generic-instances.txt
#
reconstruct_func_call(mi :: MethodInstance) = begin
    unwrp = Base.unwrap_unionall(mi.specTypes)
    unwrp != mi.specTypes && (@warn "Generic method instance found: $mi";
        run(pipeline(`$mi.specTypes`, stdout="generic-instances.txt")))
    sig = unwrp.types
    # @show mi.specTypes # -- tuple
    # @show sig          # -- svec
    if is_func_type(sig[1]) && (unwrp == mi.specTypes)
        (sig[1].instance, sig[2:end])
    else
        nothing
    end
end

# Get the Function object given its type (`typeof(f)` for regular functions and
# `Type{T}` for constructors)
is_func_type(funcType :: Type{T} where T <: Function) = true
is_func_type(::Any) = false

# Returns: all (compiled) method instances of the given module
# Note: This seems to recourse into things like X.Y (submodules) if modl=X.
all_mis_of_module(modl :: Module) = begin
    mis = []

    visit(modl) do item
       isa(item, MethodInstance) && push!(mis, item)
       true   # walk through everything
    end
    mis
end
