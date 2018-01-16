#=
    Helper functions to store constraint mappings
=#
cmap(m::LinQuadSolverInstance) = m.constraint_mapping

function Base.getindex(m::LinQuadSolverInstance, c::CI{F,S}) where F where S
    dict = constrdict(m, c)
    return dict[c]
end
constrdict(m::LinQuadSolverInstance, ::LCI{LE})  = cmap(m).less_than
constrdict(m::LinQuadSolverInstance, ::LCI{GE})  = cmap(m).greater_than
constrdict(m::LinQuadSolverInstance, ::LCI{EQ})  = cmap(m).equal_to
constrdict(m::LinQuadSolverInstance, ::LCI{IV})  = cmap(m).interval

constrdict(m::LinQuadSolverInstance, ::VLCI{MOI.Nonnegatives})  = cmap(m).nonnegatives
constrdict(m::LinQuadSolverInstance, ::VLCI{MOI.Nonpositives}) = cmap(m).nonpositives
constrdict(m::LinQuadSolverInstance, ::VLCI{MOI.Zeros})         = cmap(m).zeros

constrdict(m::LinQuadSolverInstance, ::QCI{LE})  = cmap(m).q_less_than
constrdict(m::LinQuadSolverInstance, ::QCI{GE})  = cmap(m).q_greater_than
constrdict(m::LinQuadSolverInstance, ::QCI{EQ})  = cmap(m).q_equal_to

constrdict(m::LinQuadSolverInstance, ::SVCI{LE}) = cmap(m).upper_bound
constrdict(m::LinQuadSolverInstance, ::SVCI{GE}) = cmap(m).lower_bound
constrdict(m::LinQuadSolverInstance, ::SVCI{EQ}) = cmap(m).fixed_bound
constrdict(m::LinQuadSolverInstance, ::SVCI{IV}) = cmap(m).interval_bound

constrdict(m::LinQuadSolverInstance, ::VVCI{MOI.Nonnegatives}) = cmap(m).vv_nonnegatives
constrdict(m::LinQuadSolverInstance, ::VVCI{MOI.Nonpositives}) = cmap(m).vv_nonpositives
constrdict(m::LinQuadSolverInstance, ::VVCI{MOI.Zeros}) = cmap(m).vv_zeros

constrdict(m::LinQuadSolverInstance, ::SVCI{MOI.ZeroOne}) = cmap(m).binary
constrdict(m::LinQuadSolverInstance, ::SVCI{MOI.Integer}) = cmap(m).integer

constrdict(m::LinQuadSolverInstance, ::VVCI{MOI.SOS1}) = cmap(m).sos1
constrdict(m::LinQuadSolverInstance, ::VVCI{MOI.SOS2}) = cmap(m).sos2

_getrhs(set::LE) = set.upper
_getrhs(set::GE) = set.lower
_getrhs(set::EQ) = set.value

_getsense(m::LinQuadSolverInstance, ::EQ) = Cchar('E')
_getsense(m::LinQuadSolverInstance, ::LE) = Cchar('L')
_getsense(m::LinQuadSolverInstance, ::GE) = Cchar('G')
_getsense(m::LinQuadSolverInstance, ::MOI.Zeros)        = Cchar('E')
_getsense(m::LinQuadSolverInstance, ::MOI.Nonpositives) = Cchar('L')
_getsense(m::LinQuadSolverInstance, ::MOI.Nonnegatives) = Cchar('G')
_getboundsense(m::LinQuadSolverInstance, ::MOI.Nonpositives) = Cchar('U')
_getboundsense(m::LinQuadSolverInstance, ::MOI.Nonnegatives) = Cchar('L')


_variableub(m::LinQuadSolverInstance) = Cchar('U')
_variablelb(m::LinQuadSolverInstance) = Cchar('L')

function MOI.isvalid(m::LinQuadSolverInstance, ref::CI{F,S}) where F where S
    dict = constrdict(m, ref)
    if haskey(dict, ref)
        return true
    end
    return false
end
#=
    Get number of constraints
=#

function MOI.get(m::LinQuadSolverInstance, ::MOI.NumberOfConstraints{F, S}) where F where S
    length(constrdict(m, MOI.ConstraintIndex{F,S}(UInt(0))))
end
function MOI.canget(m::LinQuadSolverInstance, ::MOI.NumberOfConstraints{F, S}) where F where S
    return (F,S) in lqs_supported_constraints(m)
end

#=
    Get list of constraint references
=#

function MOI.get(m::LinQuadSolverInstance, ::MOI.ListOfConstraintIndices{F, S}) where F where S
    collect(keys(constrdict(m, MOI.ConstraintIndex{F,S}(UInt(0)))))
end
function MOI.canget(m::LinQuadSolverInstance, ::MOI.ListOfConstraintIndices{F, S}) where F where S
    return (F,S) in lqs_supported_constraints(m)
end

#=
    Get list of constraint types in model
=#

function MOI.get(m::LinQuadSolverInstance, ::MOI.ListOfConstraints)
    ret = []
    for (F,S) in lqs_supported_constraints(m)
        if MOI.get(m, MOI.NumberOfConstraints{F,S}()) > 0
            push!(ret, (F,S))
        end
    end
    ret
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.ListOfConstraints) = true

#=
    Set variable bounds
=#

function setvariablebound!(m::LinQuadSolverInstance, col::Int, bound::Float64, sense::Cchar)
    lqs_chgbds!(m, [col], [bound], [sense])
end

function setvariablebound!(m::LinQuadSolverInstance, v::MOI.SingleVariable, set::LE)
    setvariablebound!(m, getcol(m, v), set.upper, _variableub(m))
end
function setvariablebound!(m::LinQuadSolverInstance, v::MOI.SingleVariable, set::GE)
    setvariablebound!(m, getcol(m, v), set.lower, _variablelb(m))
end
function setvariablebound!(m::LinQuadSolverInstance, v::MOI.SingleVariable, set::EQ)
    setvariablebound!(m, getcol(m, v), set.value, _variableub(m))
    setvariablebound!(m, getcol(m, v), set.value, _variablelb(m))
end
function setvariablebound!(m::LinQuadSolverInstance, v::MOI.SingleVariable, set::IV)
    setvariablebound!(m, getcol(m, v), set.upper, _variableub(m))
    setvariablebound!(m, getcol(m, v), set.lower, _variablelb(m))
end

function MOI.addconstraint!(m::LinQuadSolverInstance, v::MOI.SingleVariable, set::S) where S <: Union{LE, GE, EQ, IV}
    setvariablebound!(m, v, set)
    m.last_constraint_reference += 1
    ref = MOI.ConstraintIndex{SinVar, S}(m.last_constraint_reference)
    dict = constrdict(m, ref)
    dict[ref] = v.variable
    ref
end

#=
    Get constraint set of variable bound
=#

getbound(m::LinQuadSolverInstance, c::SVCI{LE}) = lqs_getub(m, getcol(m, m[c]))
getbound(m::LinQuadSolverInstance, c::SVCI{GE}) = lqs_getlb(m, getcol(m, m[c]))
getbound(m::LinQuadSolverInstance, c::SVCI{EQ}) = lqs_getlb(m, getcol(m, m[c]))

function MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::SVCI{S}) where S <: Union{LE, GE, EQ}
    S(getbound(m, c))
end

function MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::SVCI{IV})
    col = getcol(m, m[c])
    lb = lqs_getlb(m, col)
    ub = lqs_getub(m, col)
    return Interval{Float64}(lb, ub)
end

MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::SVCI{S}) where S <: Union{LE, GE, EQ, IV} = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintSet, ::Type{<:SVCI{S}}) where S <: Union{LE, GE, EQ, IV} = true

#=
    Get constraint function of variable bound
=#

function MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, c::SVCI{<: Union{LE, GE, EQ, IV}})
    return MOI.SingleVariable(m[c])
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, c::SVCI{<: Union{LE, GE, EQ, IV}}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, ::Type{<:SVCI{<: Union{LE, GE, EQ, IV}}}) = true

#=
    Change variable bounds of same set
=#

function MOI.modifyconstraint!(m::LinQuadSolverInstance, c::SVCI{S}, newset::S) where S<: Union{LE, GE, EQ, IV}
    setvariablebound!(m, MOI.SingleVariable(m[c]), newset)
end
MOI.canmodifyconstraint(m::LinQuadSolverInstance, c::SVCI{S}, newset::S) where S<: Union{LE, GE, EQ, IV} = true

#=
    Delete a variable bound
=#

function MOI.delete!(m::LinQuadSolverInstance, c::SVCI{S}) where S <: Union{LE, GE, EQ, IV}
    dict = constrdict(m, c)
    vref = dict[c]
    setvariablebound!(m, MOI.SingleVariable(vref), MOI.Interval{Float64}(-Inf, Inf))
    delete!(dict, c)
end
MOI.candelete(m::LinQuadSolverInstance, c::SVCI{S}) where S <: Union{LE, GE, EQ, IV} = true

#=
    Vector valued bounds
=#
function setvariablebounds!(m::LinQuadSolverInstance, func::VecVar, set::S)  where S <: Union{MOI.Nonnegatives, MOI.Nonpositives}
    n = MOI.dimension(set)
    lqs_chgbds!(m, getcol.(m, func.variables), fill(0.0, n), fill(_getboundsense(m,set), n))
end
function setvariablebounds!(m::LinQuadSolverInstance, func::VecVar, set::MOI.Zeros)
    n = MOI.dimension(set)
    lqs_chgbds!(m, getcol.(m, func.variables), fill(0.0, n), fill(_variablelb(m), n))
    lqs_chgbds!(m, getcol.(m, func.variables), fill(0.0, n), fill(_variableub(m), n))
end

function MOI.addconstraint!(m::LinQuadSolverInstance, func::VecVar, set::S) where S <: Union{MOI.Nonnegatives, MOI.Nonpositives, MOI.Zeros}
    @assert length(func.variables) == MOI.dimension(set)
    setvariablebounds!(m, func, set)
    m.last_constraint_reference += 1
    ref = MOI.ConstraintIndex{VecVar, S}(m.last_constraint_reference)
    dict = constrdict(m, ref)
    dict[ref] = func.variables
    return ref
end

#=
    Add linear constraints
=#

function MOI.addconstraint!(m::LinQuadSolverInstance, func::Linear, set::T) where T <: Union{LE, GE, EQ, IV}
    addlinearconstraint!(m, func, set)
    m.last_constraint_reference += 1
    ref = MOI.ConstraintIndex{Linear, T}(m.last_constraint_reference)
    dict = constrdict(m, ref)
    dict[ref] = lqs_getnumrows(m)
    push!(m.constraint_primal_solution, NaN)
    push!(m.constraint_dual_solution, NaN)
    return ref
end

function addlinearconstraint!(m::LinQuadSolverInstance, func::Linear, set::S) where S <: Union{LE, GE, EQ}
    addlinearconstraint!(m, func, _getsense(m,set), _getrhs(set))
end

function addlinearconstraint!(m::LinQuadSolverInstance, func::Linear, set::IV)
    addlinearconstraint!(m, func, lqs_ctrtype_map(m)[:RANGE], set.lower)
    lqs_chgrngval!(m, [lqs_getnumrows(m)], [set.upper - set.lower])
end

function addlinearconstraint!(m::LinQuadSolverInstance, func::Linear, sense::Cchar, rhs)
    if abs(func.constant) > eps(Float64)
        warn("Constant in scalar function moved into set.")
    end
    lqs_addrows!(m, [1], getcol.(m, func.variables), func.coefficients, [sense], [rhs - func.constant])
end

#=
    Add linear constraints (plural)
=#

function MOI.addconstraints!(m::LinQuadSolverInstance, func::Vector{Linear}, set::Vector{S}) where S <: Union{LE, GE, EQ, IV}
    @assert length(func) == length(set)
    numrows = lqs_getnumrows(m)
    addlinearconstraints!(m, func, set)
    crefs = Vector{MOI.ConstraintIndex{Linear, S}}(length(func))
    for i in 1:length(func)
        m.last_constraint_reference += 1
        ref = MOI.ConstraintIndex{Linear, S}(m.last_constraint_reference)
        dict = constrdict(m, ref)
        dict[ref] = numrows + i
        push!(m.constraint_primal_solution, NaN)
        push!(m.constraint_dual_solution, NaN)
        crefs[i] = ref
    end
    return crefs
end

function addlinearconstraints!(m::LinQuadSolverInstance, func::Vector{Linear}, set::Vector{S}) where S <: Union{LE, GE, EQ, IV}
    addlinearconstraints!(m, func, fill(_getsense(m,set[1]), length(func)), [_getrhs(s) for s in set])
end

function addlinearconstraints!(m::LinQuadSolverInstance, func::Vector{Linear}, set::Vector{IV})
    numrows = lqs_getnumrows(m)
    addlinearconstraints!(m, func, fill(lqs_ctrtype_map(m)[:RANGE], length(func)), [s.lower for s in set])
    numrows2 = lqs_getnumrows(m)
    lqs_chgrngval!(m, collect(numrows+1:numrows2), [s.upper - s.lower for s in set])
end

function addlinearconstraints!(m::LinQuadSolverInstance, func::Vector{Linear}, sense::Vector{Cchar}, rhs::Vector{Float64})
    # loop through once to get number of non-zeros and to move rhs across
    nnz = 0
    for (i, f) in enumerate(func)
        if abs(f.constant) > eps(Float64)
            warn("Constant in scalar function moved into set.")
            rhs[i] -= f.constant
        end
        nnz += length(f.coefficients)
    end

    rowbegins = Vector{Int}(length(func))   # index of start of each row
    column_indices = Vector{Int}(nnz)       # flattened columns for each function
    nnz_vals = Vector{Float64}(nnz)         # corresponding non-zeros
    cnt = 1
    for (fi, f) in enumerate(func)
        rowbegins[fi] = cnt
        for (var, coef) in zip(f.variables, f.coefficients)
            column_indices[cnt] = getcol(m, var)
            nnz_vals[cnt] = coef
            cnt += 1
        end
    end
    lqs_addrows!(m, rowbegins, column_indices, nnz_vals, sense, rhs)
end

#=
    Constraint set of Linear function
=#

function MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::LCI{S}) where S <: Union{LE, GE, EQ}
    rhs = lqs_getrhs(m, m[c])
    S(rhs)
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintSet, ::LCI{<: Union{LE, GE, EQ}}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintSet, ::Type{<:LCI{<: Union{LE, GE, EQ}}}) = true

#=
    Constraint function of Linear function
=#

function MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, c::LCI{<: Union{LE, GE, EQ, IV}})
    # TODO more efficiently
    colidx, coefs = lqs_getrows(m, m[c])
    MOI.ScalarAffineFunction(m.variable_references[colidx+1] , coefs, 0.0)
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, c::LCI{<: Union{LE, GE, EQ, IV}}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, ::Type{<:LCI{<: Union{LE, GE, EQ, IV}}}) = true

#=
    Scalar Coefficient Change of Linear Constraint
=#

function MOI.modifyconstraint!(m::LinQuadSolverInstance, c::LCI{<: Union{LE, GE, EQ, IV}}, chg::MOI.ScalarCoefficientChange{Float64})
    col = m.variable_mapping[chg.variable]
    lqs_chgcoef!(m, m[c], col, chg.new_coefficient)
end
MOI.canmodifyconstraint(m::LinQuadSolverInstance, c::LCI{<: Union{LE, GE, EQ, IV}}, chg::MOI.ScalarCoefficientChange{Float64}) = true

#=
    Change RHS of linear constraint without modifying sense
=#

function MOI.modifyconstraint!(m::LinQuadSolverInstance, c::LCI{S}, newset::S) where S <: Union{LE, GE, EQ}
    # the column 0 (or -1 in 0-index) is the rhs.
    lqs_chgcoef!(m, m[c], 0, _getrhs(newset))
end
MOI.canmodifyconstraint(m::LinQuadSolverInstance, c::LCI{S}, newset::S) where S <: Union{LE, GE, EQ} = true

function MOI.modifyconstraint!(m::LinQuadSolverInstance, c::LCI{IV}, set::IV)
    # the column 0 (or -1 in 0-index) is the rhs.
    # a range constraint has the RHS value of the lower limit of the range, and
    # a rngval equal to upper-lower.
    row = m[c]
    lqs_chgcoef!(m, row, 0, set.lower)
    lqs_chgrngval!(m, [row], [set.upper - set.lower])
end
MOI.canmodifyconstraint(m::LinQuadSolverInstance, c::LCI{IV}, set::IV) = true

#=
    Delete a linear constraint
=#

function deleteref!(m::LinQuadSolverInstance, row::Int, ref::LCI{<: Union{LE, GE, EQ, IV}})
    deleteref!(cmap(m).less_than, row, ref)
    deleteref!(cmap(m).greater_than, row, ref)
    deleteref!(cmap(m).equal_to, row, ref)
    deleteref!(cmap(m).interval, row, ref)
end
function MOI.delete!(m::LinQuadSolverInstance, c::LCI{<: Union{LE, GE, EQ, IV}})
    dict = constrdict(m, c)
    row = dict[c]
    lqs_delrows!(m, row, row)
    deleteat!(m.constraint_primal_solution, row)
    deleteat!(m.constraint_dual_solution, row)
    deleteref!(m, row, c)
end
MOI.candelete(m::LinQuadSolverInstance, c::LCI{<: Union{LE, GE, EQ, IV}}) = true

#=
    MIP related constraints
=#
"""
    hasinteger(m::LinQuadSolverInstance)::Bool
A helper function to determine if the solver instance `m` has any integer
components (i.e. binary, integer, special ordered sets, etc).
"""
function hasinteger(m::LinQuadSolverInstance)
    length(cmap(m).integer) + length(cmap(m).binary) + length(cmap(m).sos1) + length(cmap(m).sos2) > 0
end

#=
    Binary constraints
 for some reason CPLEX doesn't respect bounds on a binary variable, so we
 should store the previous bounds so that if we delete the binary constraint
 we can revert to the old bounds

 Xpress is worse, once binary the bounds are changed independly of what the user does
=#
function MOI.addconstraint!(m::LinQuadSolverInstance, v::SinVar, ::MOI.ZeroOne)
    m.last_constraint_reference += 1
    ref = MOI.ConstraintIndex{SinVar, MOI.ZeroOne}(m.last_constraint_reference)
    dict = constrdict(m, ref)
    ub = lqs_getub(m, getcol(m, v))
    lb = lqs_getlb(m, getcol(m, v))
    dict[ref] = (v.variable, lb, ub)
    lqs_chgctype!(m, [getcol(m, v)], [lqs_vartype_map(m)[:BINARY]])
    setvariablebound!(m, getcol(m, v), 1.0, _variableub(m))
    setvariablebound!(m, getcol(m, v), 0.0, _variablelb(m))
    lqs_make_problem_type_integer(m)
    ref
end
function MOI.delete!(m::LinQuadSolverInstance, c::SVCI{MOI.ZeroOne})
    dict = constrdict(m, c)
    (v, lb, ub) = dict[c]
    lqs_chgctype!(m, [getcol(m, v)], [lqs_vartype_map(m)[:CONTINUOUS]])
    setvariablebound!(m, getcol(m, v), ub, _variableub(m))
    setvariablebound!(m, getcol(m, v), lb, _variablelb(m))
    delete!(dict, c)
    if !hasinteger(m)
        lqs_make_problem_type_continuous(m)
    end
end
MOI.candelete(m::LinQuadSolverInstance, c::SVCI{MOI.ZeroOne}) = true

MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::SVCI{MOI.ZeroOne}) =MOI.ZeroOne()
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::SVCI{MOI.ZeroOne}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintSet, ::Type{<:SVCI{MOI.ZeroOne}}) = true

MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, c::SVCI{MOI.ZeroOne}) = m[c]
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, c::SVCI{MOI.ZeroOne}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, ::Type{<:SVCI{MOI.ZeroOne}}) = true


#=
    Integer constraints
=#

function MOI.addconstraint!(m::LinQuadSolverInstance, v::SinVar, ::MOI.Integer)
    lqs_chgctype!(m, [getcol(m, v)], [lqs_vartype_map(m)[:INTEGER]])
    m.last_constraint_reference += 1
    ref = MOI.ConstraintIndex{SinVar, MOI.Integer}(m.last_constraint_reference)
    dict = constrdict(m, ref)
    dict[ref] = v.variable
    lqs_make_problem_type_integer(m)
    ref
end

function MOI.delete!(m::LinQuadSolverInstance, c::SVCI{MOI.Integer})
    dict = constrdict(m, c)
    v = dict[c]
    lqs_chgctype!(m, [getcol(m, v)], [lqs_vartype_map(m)[:CONTINUOUS]])
    delete!(dict, c)
    if !hasinteger(m)
        lqs_make_problem_type_continuous(m)
    end
end
MOI.candelete(m::LinQuadSolverInstance, c::SVCI{MOI.Integer}) = true

MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::SVCI{MOI.Integer}) =MOI.Integer()
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::SVCI{MOI.Integer}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintSet, ::Type{<:SVCI{MOI.Integer}}) = true

MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, c::SVCI{MOI.Integer}) = m[c]
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, c::SVCI{MOI.Integer}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, ::Type{<:SVCI{MOI.Integer}}) = true


#=
    SOS constraints
=#

function MOI.addconstraint!(m::LinQuadSolverInstance, v::VecVar, sos::MOI.SOS1)
    lqs_make_problem_type_integer(m)
    lqs_addsos!(m, getcol.(m, v.variables), sos.weights, lqs_sertype_map(m)[:SOS1])
    m.last_constraint_reference += 1
    ref = MOI.ConstraintIndex{VecVar, MOI.SOS1}(m.last_constraint_reference)
    dict = constrdict(m, ref)
    dict[ref] = length(cmap(m).sos1) + length(cmap(m).sos2) + 1
    ref
end

function MOI.addconstraint!(m::LinQuadSolverInstance, v::VecVar, sos::MOI.SOS2)
    lqs_make_problem_type_integer(m)
    lqs_addsos!(m, getcol.(m, v.variables), sos.weights, lqs_sertype_map(m)[:SOS2])
    m.last_constraint_reference += 1
    ref = MOI.ConstraintIndex{VecVar, MOI.SOS2}(m.last_constraint_reference)
    dict = constrdict(m, ref)
    dict[ref] = length(cmap(m).sos1) + length(cmap(m).sos2) + 1
    ref
end

function MOI.delete!(m::LinQuadSolverInstance, c::VVCI{<:Union{MOI.SOS1, MOI.SOS2}})
    dict = constrdict(m, c)
    idx = dict[c]
    lqs_delsos!(m, idx, idx)
    deleteref!(cmap(m).sos1, idx, c)
    deleteref!(cmap(m).sos2, idx, c)
    if !hasinteger(m)
        lqs_make_problem_type_continuous(m)
    end
end
MOI.candelete(m::LinQuadSolverInstance, c::VVCI{<:Union{MOI.SOS1, MOI.SOS2}}) = true

function MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::VVCI{MOI.SOS1})
    indices, weights, types = lqs_getsos(m, m[c])
    @assert types == lqs_sertype_map(m)[:SOS1]
    return MOI.SOS1(weights)
end

function MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::VVCI{MOI.SOS2})
    indices, weights, types = lqs_getsos(m, m[c])
    @assert types == lqs_sertype_map(m)[:SOS2]
    return MOI.SOS2(weights)
end

MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintSet, c::VVCI{<:Union{MOI.SOS1, MOI.SOS2}}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintSet, ::Type{<:VVCI{<:Union{MOI.SOS1, MOI.SOS2}}}) = true

function MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, c::VVCI{<:Union{MOI.SOS1, MOI.SOS2}})
    indices, weights, types = lqs_getsos(m, m[c])
    return MOI.VectorOfVariables(m.variable_references[indices])
end

MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, c::VVCI{<:Union{MOI.SOS1, MOI.SOS2}}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintFunction, ::Type{<:VVCI{<:Union{MOI.SOS1, MOI.SOS2}}}) = true


#=
    Quadratic constraint
=#

function MOI.addconstraint!(m::LinQuadSolverInstance, func::Quad, set::S) where S <: Union{LE, GE, EQ}
    addquadraticconstraint!(m, func, set)
    m.last_constraint_reference += 1
    ref = MOI.ConstraintIndex{Quad, S}(m.last_constraint_reference)
    dict = constrdict(m, ref)
    dict[ref] = lqs_getnumqconstrs(m)
    push!(m.qconstraint_primal_solution, NaN)
    push!(m.qconstraint_dual_solution, NaN)
    return ref
end

function addquadraticconstraint!(m::LinQuadSolverInstance, func::Quad, set::S) where S<: Union{LE, GE, EQ}
    addquadraticconstraint!(m, func, _getsense(m,set), _getrhs(set))
end

function addquadraticconstraint!(m::LinQuadSolverInstance, f::Quad, sense::Cchar, rhs::Float64)
    if abs(f.constant) > 0
        warn("Constant in quadratic function. Moving into set")
    end
    ri, ci, vi = reduceduplicates(
        getcol.(m, f.quadratic_rowvariables),
        getcol.(m, f.quadratic_colvariables),
        f.quadratic_coefficients
    )
    lqs_addqconstr!(m,
        getcol.(m, f.affine_variables),
        f.affine_coefficients,
        rhs - f.constant,
        sense,
        ri, ci, vi
    )
end

function reduceduplicates(rowi::Vector{T}, coli::Vector{T}, vals::Vector{S}) where T where S
    @assert length(rowi) == length(coli) == length(vals)
    d = Dict{Tuple{T, T},S}()
    for (r,c,v) in zip(rowi, coli, vals)
        if haskey(d, (r,c))
            d[(r,c)] += v
        else
            d[(r,c)] = v
        end
    end
    ri = Vector{T}(length(d))
    ci = Vector{T}(length(d))
    vi = Vector{S}(length(d))
    for (i, (key, val)) in enumerate(d)
        ri[i] = key[1]
        ci[i] = key[2]
        vi[i] = val
    end
    ri, ci, vi
end

#=
    Vector valued constraints
=#


function MOI.addconstraint!(m::LinQuadSolverInstance, func::VecLin, set::S) where S <: Union{MOI.Nonnegatives, MOI.Nonpositives, MOI.Zeros}
    @assert MOI.dimension(set) == length(func.constant)

    nrows = lqs_getnumrows(m)
    addlinearconstraint!(m, func, _getsense(m,set))
    nrows2 = lqs_getnumrows(m)

    m.last_constraint_reference += 1
    ref = MOI.ConstraintIndex{VecLin, S}(m.last_constraint_reference)

    dict = constrdict(m, ref)
    dict[ref] = collect(nrows+1:nrows2)
    for i in 1:MOI.dimension(set)
        push!(m.constraint_primal_solution, NaN)
        push!(m.constraint_dual_solution, NaN)
    end
    ref
end

function addlinearconstraint!(m::LinQuadSolverInstance, func::VecLin, sense::Cchar)
    @assert length(func.outputindex) == length(func.variables) == length(func.coefficients)
    # get list of unique rows
    rows = unique(func.outputindex)
    @assert length(rows) == length(func.constant)
    # sort into row order
    pidx = sortperm(func.outputindex)
    cols = getcol.(m, func.variables)[pidx]
    vals = func.coefficients[pidx]
    # loop through to gte starting position of each row
    rowbegins = Vector{Int}(length(rows))
    rowbegins[1] = 1
    cnt = 1
    for i in 2:length(pidx)
        if func.outputindex[pidx[i]] != func.outputindex[pidx[i-1]]
            cnt += 1
            rowbegins[cnt] = i
        end
    end
    lqs_addrows!(m, rowbegins, cols, vals, fill(sense, length(rows)), -func.constant)
end

function MOI.modifyconstraint!(m::LinQuadSolverInstance, ref::VLCI{<: Union{MOI.Nonnegatives, MOI.Nonpositives, MOI.Zeros}}, chg::MOI.VectorConstantChange{Float64})
    @assert length(chg.new_constant) == length(m[ref])
    for (r, v) in zip(m[ref], chg.new_constant)
        lqs_chgcoef!(m, r, 0, -v)
    end
end
MOI.canmodifyconstraint(m::LinQuadSolverInstance, ref::VLCI{<: Union{MOI.Nonnegatives, MOI.Nonpositives, MOI.Zeros}}, chg::MOI.VectorConstantChange{Float64}) = true

#=
    Transform constraint
=#
function MOI.transformconstraint!(m::LinQuadSolverInstance, ref::LCI{S}, newset::S) where S
    error("Cannot transform constraint of same set. use `modifyconstraint!` instead.")
end
function MOI.transformconstraint!(m::LinQuadSolverInstance, ref::LCI{S1}, newset::S2) where S1 where S2 <: Union{LE, GE, EQ}
    dict = constrdict(m, ref)
    row = dict[ref]
    lqs_chgsense!(m, [row], [_getsense(m,newset)])
    m.last_constraint_reference += 1
    ref2 = MOI.ConstraintIndex{Linear, S2}(m.last_constraint_reference)
    dict2 = constrdict(m, ref2)
    dict2[ref2] = row
    delete!(dict, ref)
    return ref2
end
function MOI.cantransformconstraint(m::LinQuadSolverInstance, ref::LCI{S}, newset::S) where S
    false
end
function MOI.cantransformconstraint(m::LinQuadSolverInstance, ref::LCI{S1}, newset::S2) where S1 where S2 <: Union{LE, GE, EQ}
    true
end