# Inspired by julia/stdlib/InteractiveUtils/src/codeview.jl 

f = sin
t = (Float64,)

# TODO: I get the following error with the current code
# > ERROR: MethodError: no method matching is_stable_call(::Core.Compiler.Const)
# Investigate!

# cf. warntype_type_printer in the above mentioned file
is_stable_type(@nospecialize(ty)) = begin
    ty isa Type &&
        (!Base.isdispatchelem(ty) || ty == Core.Box) &&
        !(ty isa Union && Base.is_expected_union(ty))

    # Note 1: isdispatchelem is roughly eqviv. isleaftype (from Julia pre-1.0)
    # Note 2: Core.Box is a type of a heap-allocated value
    # Note 3: expected union is a trivial union (e.g. 
    #         Union{Int,Missing}; those are deemed "probably
    #         harmless"
end

is_stable_call(@nospecialize(f), @nospecialize(t)) = begin

    ct = code_typed(f, t)
    ct1 = ct[1] # we ought to have just one method body, I think
    src = ct1[1] # that's code; [2] is return type, I think

    slottypes = src.slottypes

    # the following check is taken verbatim from code_warntype
    if !isa(slottypes, Vector{Any})
        return true # I don't know when we get here,
                    # over-approx. as stable
    end

    result = true

    for i = 1:length(slottypes)
        result = result && is_stable_call(slottypes[i])
    end
    result
end

