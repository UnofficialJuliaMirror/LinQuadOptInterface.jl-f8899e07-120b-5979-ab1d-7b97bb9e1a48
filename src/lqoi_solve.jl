function hasquadratic(m::LinQuadSolverInstance)
    m.obj_is_quad || (length(cmap(m).q_less_than) + length(cmap(m).q_greater_than) + length(cmap(m).q_equal_to) > 0)
end

#=
    Optimize the model
=#

function MOI.optimize!(m::LinQuadSolverInstance)
    # reset storage
    fill!(m.variable_primal_solution, NaN)
    fill!(m.variable_dual_solution, NaN)
    fill!(m.constraint_primal_solution, NaN)
    fill!(m.constraint_dual_solution, NaN)
    m.primal_status = MOI.UnknownResultStatus
    m.dual_status   = MOI.UnknownResultStatus
    m.primal_result_count = 0
    m.dual_result_count = 0

    t = time()
    if hasinteger(m)
        lqs_mipopt!(m)
    elseif hasquadratic(m)
        lqs_qpopt!(m)
    else
        lqs_lpopt!(m)
    end
    m.solvetime = time() - t

    # termination_status
    m.termination_status = lqs_terminationstatus(m)
    m.primal_status = lqs_primalstatus(m)
    m.dual_status = lqs_dualstatus(m)

    if m.primal_status in [MOI.FeasiblePoint, MOI.InfeasiblePoint]
        # primal solution exists
        lqs_getx!(m, m.variable_primal_solution)
        lqs_getax!(m, m.constraint_primal_solution)
        m.primal_result_count = 1
        # CPLEX can return infeasible points
    elseif m.primal_status == MOI.InfeasibilityCertificate
        lqs_getray!(m, m.variable_primal_solution)
        m.primal_result_count = 1
    end
    if m.dual_status in [MOI.FeasiblePoint, MOI.InfeasiblePoint]
        # dual solution exists
        lqs_getdj!(m, m.variable_dual_solution)
        lqs_getpi!(m, m.constraint_dual_solution)
        m.dual_result_count = 1
        # dual solution may not be feasible
    elseif m.dual_status == MOI.InfeasibilityCertificate
        lqs_dualfarkas!(m, m.constraint_dual_solution)
        m.dual_result_count = 1
    end

    #=
        CPLEX has the dual convention that the sign of the dual depends on the
        optimization sense. This isn't the same as the MOI convention so we need
        to correct that.
    =#
    # TODO
    if MOI.get(m, MOI.ObjectiveSense()) == MOI.MaxSense
        m.constraint_dual_solution *= -1
        m.variable_dual_solution *= -1
    end
end


#=
    Result Count
=#
function MOI.get(m::LinQuadSolverInstance, ::MOI.ResultCount)
    max(m.primal_result_count, m.dual_result_count)
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.ResultCount) = true

#=
    Termination status
=#

function MOI.get(m::LinQuadSolverInstance, ::MOI.TerminationStatus)
    m.termination_status
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.TerminationStatus) = true

#=
    Primal status
=#

function MOI.get(m::LinQuadSolverInstance, p::MOI.PrimalStatus)
    m.primal_status
end
function MOI.canget(m::LinQuadSolverInstance, p::MOI.PrimalStatus)
    m.primal_result_count >= p.N
end

#=
    Dual status
=#

function MOI.get(m::LinQuadSolverInstance, d::MOI.DualStatus)
    m.dual_status
end
function MOI.canget(m::LinQuadSolverInstance, d::MOI.DualStatus)
    m.dual_result_count >= d.N
end

#=
    Objective Value
=#


function MOI.get(m::LinQuadSolverInstance, attr::MOI.ObjectiveValue)
    if attr.resultindex == 1
        lqs_getobjval(m) + m.objective_constant
    else
        error("Unable to access multiple objective values")
    end
end
function MOI.canget(m::LinQuadSolverInstance, attr::MOI.ObjectiveValue)
    if attr.resultindex == 1
        return true
    else
        return false
    end
end

#=
    Variable Primal solution
=#


function MOI.get(m::LinQuadSolverInstance, ::MOI.VariablePrimal, v::MOI.VariableIndex)
    col = m.variable_mapping[v]
    return m.variable_primal_solution[col]
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.VariablePrimal, v::MOI.VariableIndex) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.VariablePrimal, ::Type{<:MOI.VariableIndex}) = true

function MOI.get(m::LinQuadSolverInstance, ::MOI.VariablePrimal, v::Vector{MOI.VariableIndex})
    MOI.get.(m, MOI.VariablePrimal(), v)
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.VariablePrimal, v::Vector{MOI.VariableIndex}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.VariablePrimal, ::Type{<:Vector{MOI.VariableIndex}}) = true

#=
    Variable Dual solution
=#


function MOI.get(m::LinQuadSolverInstance,::MOI.ConstraintDual, c::SVCI{<: Union{LE, GE, EQ, IV}})
    vref = m[c]
    col = m.variable_mapping[vref]
    return m.variable_dual_solution[col]
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintDual, c::SVCI{<: Union{LE, GE, EQ, IV}}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintDual, ::Type{<:SVCI{<: Union{LE, GE, EQ, IV}}}) = true

#=
    Constraint Primal solution
=#

function MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintPrimal, c::LCI{<: Union{LE, GE, EQ, IV}})
    row = m[c]
    return m.constraint_primal_solution[row]
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintPrimal, c::LCI{<: Union{LE, GE, EQ, IV}}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintPrimal, ::Type{<:LCI{<: Union{LE, GE, EQ, IV}}}) = true


# vector valued constraint duals
MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintPrimal, c::VLCI{<: Union{MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives}}) = m.constraint_primal_solution[m[c]]
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintPrimal, c::VLCI{<: Union{MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives}}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintPrimal, ::Type{<:VLCI{<: Union{MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives}}}) = true

#=
    Constraint Dual solution
=#

_checkdualsense(::LCI{LE}, dual) = dual <= 0.0
_checkdualsense(::LCI{GE}, dual) = dual >= 0.0
_checkdualsense(::LCI{IV}, dual) = true
_checkdualsense(::LCI{EQ}, dual) = true

function MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintDual, c::LCI{<: Union{LE, GE, EQ, IV}})
    row = m[c]
    dual = m.constraint_dual_solution[row]
    @assert _checkdualsense(c, dual)
    return dual
end
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintDual, c::LCI{<: Union{LE, GE, EQ, IV}}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintDual, ::Type{<:LCI{<: Union{LE, GE, EQ, IV}}}) = true

# vector valued constraint duals
MOI.get(m::LinQuadSolverInstance, ::MOI.ConstraintDual, c::VLCI{<: Union{MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives}}) = m.constraint_dual_solution[m[c]]
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintDual, c::VLCI{<: Union{MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives}}) = true
MOI.canget(m::LinQuadSolverInstance, ::MOI.ConstraintDual, ::Type{<:VLCI{<: Union{MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives}}}) = true

#=
    Solution Attributes
=#

# struct ObjectiveBound <: AbstractSolverInstanceAttribute end
MOI.get(m::LinQuadSolverInstance, ::MOI.ObjectiveBound) = lqs_getbestobjval(m)
MOI.canget(m::LinQuadSolverInstance, ::MOI.ObjectiveBound) = true

# struct RelativeGap <: AbstractSolverInstanceAttribute  end
MOI.get(m::LinQuadSolverInstance, ::MOI.RelativeGap) = lqs_getmiprelgap(m)
MOI.canget(m::LinQuadSolverInstance, ::MOI.RelativeGap) = true

# struct SolveTime <: AbstractSolverInstanceAttribute end
MOI.get(m::LinQuadSolverInstance, ::MOI.SolveTime) = m.solvetime
MOI.canget(m::LinQuadSolverInstance, ::MOI.SolveTime) = true

# struct SimplexIterations <: AbstractSolverInstanceAttribute end
MOI.get(m::LinQuadSolverInstance, ::MOI.SimplexIterations) = lqs_getitcnt(m)
MOI.canget(m::LinQuadSolverInstance, ::MOI.SimplexIterations) = true

# struct BarrierIterations <: AbstractSolverInstanceAttribute end
MOI.get(m::LinQuadSolverInstance, ::MOI.BarrierIterations) = lqs_getbaritcnt(m)
MOI.canget(m::LinQuadSolverInstance, ::MOI.BarrierIterations) = true

# struct NodeCount <: AbstractSolverInstanceAttribute end
MOI.get(m::LinQuadSolverInstance, ::MOI.NodeCount) = lqs_getnodecnt(m)
MOI.canget(m::LinQuadSolverInstance, ::MOI.NodeCount) = true

# struct RawSolver <: AbstractSolverInstanceAttribute end
MOI.get(m::LinQuadSolverInstance, ::MOI.RawSolver) = m
MOI.canget(m::LinQuadSolverInstance, ::MOI.RawSolver) = true