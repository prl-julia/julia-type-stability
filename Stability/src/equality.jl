#######################################################################
#
# Generic definition of structural equality of structs
#
# Authors: Julia Belyakova, Artem Pelenitsyn
#
#######################################################################

# (T, T) → Bool
# Checks `e1` and `e2` for structural equality,
#   i.e. compares all the fields of `e1` and `e2`
# Returns `true` if values are equal
# ASSUMTION: `e1` and `e2` have the same run-time type
# NOTE: Relies on metaprogramming
@generated structEqual(e1, e2) = begin
    # if there are no fields, we can simply return true
    if fieldcount(e1) == 0
        return :(true)
    end
    mkEq    = fldName -> :(e1.$fldName == e2.$fldName)
    # generate individual equality checks
    eqExprs = map(mkEq, fieldnames(e1))
    # construct &&-expression for chaining all checks
    mkAnd   = (expr, acc) -> Expr(:&&, expr, acc)
    # no need in initial accumulator because eqExprs is not empty
    foldr(mkAnd, eqExprs)
end

# (Any, Any) → Bool
# Checks `e1` and `e2` of arbitrary run-time types
# for structural equality and returns `true` if values are equal
genericStructEqual(e1, e2) =
    # if types are different, expressions are not equal
    typeof(e1) != typeof(e2) ?
        false :
    # othewise we need to perform a structural check
        structEqual(e1, e2)

# Derive a method of `==` for the given type
macro deriveEq(T)
    :(Base.:(==)(x::$T, y::$T) = structEqual(x,y))
end
