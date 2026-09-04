"""Independent checks for a solved AC equilibrium."""
struct EquilibriumValidationReport{T<:Real}
    valid::Bool
    power_balance_max::T
    droop_residual_max::T
    voltage_min_margin::T
    voltage_max_margin::T
    generator_p_min_margin::T
    generator_p_max_margin::T
    generator_q_min_margin::T
    generator_q_max_margin::T
    branch_thermal_min_margin::T
    unavailable_generator_max::T
    smooth_exact_droop_gap::T
    smooth_epsilon::Union{Nothing,T}
    violations::Vector{Symbol}
end

struct EquilibriumReport{T<:Real}
    case_id::String
    valid::Bool
    termination_status::Symbol
    primal_status::Symbol
    objective::T
    validation::EquilibriumValidationReport{T}
end

_max_abs(values) = isempty(values) ? 0.0 : maximum(abs, values)
_min_value(values) = isempty(values) ? Inf : minimum(values)

function validate_equilibrium(
    case::Case,
    state::ACState;
    power_tolerance::Real = 1.0e-6,
    droop_tolerance::Real = 1.0e-5,
    limit_tolerance::Real = 1.0e-6,
    unavailable_tolerance::Real = 1.0e-8,
    smooth_epsilon::Union{Nothing,Real} = nothing,
)
    isnothing(case.network) && throw(ArgumentError("case has no AC network"))
    all(x -> x >= 0 && isfinite(x),
        (power_tolerance, droop_tolerance, limit_tolerance, unavailable_tolerance)) ||
        throw(ArgumentError("validation tolerances must be finite and nonnegative"))
    if !isnothing(smooth_epsilon)
        smooth_epsilon > 0 && isfinite(smooth_epsilon) ||
            throw(ArgumentError("smooth_epsilon must be positive and finite"))
    end

    balance = power_balance(case, state)
    droop = droop_residual(case, state)
    network = case.network

    voltage_lower = [state.vm[i] - bus.v_min for (i, bus) in enumerate(network.buses)]
    voltage_upper = [bus.v_max - state.vm[i] for (i, bus) in enumerate(network.buses)]
    generator_p_lower = [
        state.pg[i] - generator.p_min
        for (i, generator) in enumerate(case.generators) if generator.available
    ]
    generator_p_upper = [
        generator.p_max - state.pg[i]
        for (i, generator) in enumerate(case.generators) if generator.available
    ]
    generator_q_lower = [
        state.qg[i] - generator.q_min
        for (i, generator) in enumerate(case.generators) if generator.available
    ]
    generator_q_upper = [
        generator.q_max - state.qg[i]
        for (i, generator) in enumerate(case.generators) if generator.available
    ]
    unavailable_generator = [
        max(abs(state.pg[i]), abs(state.qg[i]))
        for (i, generator) in enumerate(case.generators) if !generator.available
    ]
    branch_margins = operating_margins(network, state)

    smooth_exact_gap = 0.0
    if !isnothing(smooth_epsilon)
        bus_indices = _bus_indices(network)
        generator_indices = Dict(g.id => i for (i, g) in enumerate(case.generators))
        for attachment in case.attachments
            generator_index = generator_indices[attachment.generator_id]
            generator = case.generators[generator_index]
            generator.available || continue
            location_index = bus_indices[attachment.location.bus_id]
            control = case.controls[attachment.control_id]
            exact = droop_response(control, state.vm[location_index]; p = state.pg[generator_index])
            smooth = _smooth_droop_value(control, state.vm[location_index], smooth_epsilon)
            smooth_exact_gap = max(smooth_exact_gap, abs(smooth - exact))
        end
    end

    power_balance_max = Float64(_max_abs(balance.vector))
    droop_residual_max = Float64(_max_abs(droop))
    voltage_min_margin = Float64(_min_value(voltage_lower))
    voltage_max_margin = Float64(_min_value(voltage_upper))
    generator_p_min_margin = Float64(_min_value(generator_p_lower))
    generator_p_max_margin = Float64(_min_value(generator_p_upper))
    generator_q_min_margin = Float64(_min_value(generator_q_lower))
    generator_q_max_margin = Float64(_min_value(generator_q_upper))
    branch_thermal_min_margin = Float64(_min_value(branch_margins))
    unavailable_generator_max = Float64(_max_abs(unavailable_generator))
    smooth_exact_gap = Float64(smooth_exact_gap)
    smooth_epsilon_value = isnothing(smooth_epsilon) ? nothing : Float64(smooth_epsilon)

    violations = Symbol[]
    power_balance_max <= power_tolerance || push!(violations, :power_balance)
    droop_residual_max <= droop_tolerance || push!(violations, :droop)
    voltage_min_margin >= -limit_tolerance || push!(violations, :voltage_min)
    voltage_max_margin >= -limit_tolerance || push!(violations, :voltage_max)
    generator_p_min_margin >= -limit_tolerance || push!(violations, :generator_p_min)
    generator_p_max_margin >= -limit_tolerance || push!(violations, :generator_p_max)
    generator_q_min_margin >= -limit_tolerance || push!(violations, :generator_q_min)
    generator_q_max_margin >= -limit_tolerance || push!(violations, :generator_q_max)
    branch_thermal_min_margin >= -limit_tolerance || push!(violations, :branch_thermal)
    unavailable_generator_max <= unavailable_tolerance ||
        push!(violations, :unavailable_generator)

    return EquilibriumValidationReport(
        isempty(violations), power_balance_max, droop_residual_max,
        voltage_min_margin, voltage_max_margin,
        generator_p_min_margin, generator_p_max_margin,
        generator_q_min_margin, generator_q_max_margin,
        branch_thermal_min_margin, unavailable_generator_max,
        smooth_exact_gap, smooth_epsilon_value, violations,
    )
end

function validate_equilibrium(case::Case, result::ACOPFResult; kwargs...)
    isnothing(result.state) &&
        throw(ArgumentError("cannot validate an ACOPFResult without a state"))
    return validate_equilibrium(case, result.state; smooth_epsilon = result.smooth_epsilon, kwargs...)
end

"""Combine solver metadata with an independent equilibrium validation."""
function equilibrium_report(case::Case, result::ACOPFResult; kwargs...)
    validation = validate_equilibrium(case, result; kwargs...)
    solver_success = result.termination_status in
        (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL, :ALMOST_OPTIMAL)
    return EquilibriumReport(
        case.id,
        solver_success && validation.valid,
        result.termination_status,
        result.primal_status,
        result.objective,
        validation,
    )
end

"""Render an equilibrium report as compact Markdown for logs and artifacts."""
function markdown_report(report::EquilibriumReport)
    validation = report.validation
    lines = [
        "# Equilibrium report: $(report.case_id)",
        "",
        "- Valid: `$(report.valid)`",
        "- Termination status: `$(report.termination_status)`",
        "- Primal status: `$(report.primal_status)`",
        "- Objective: `$(report.objective)`",
        "- Smooth epsilon: `$(validation.smooth_epsilon)`",
        "",
        "## Independent checks",
        "",
        "| Quantity | Value |",
        "|---|---:|",
        "| Maximum AC power-balance residual | $(validation.power_balance_max) |",
        "| Maximum exact droop residual | $(validation.droop_residual_max) |",
        "| Minimum voltage lower margin | $(validation.voltage_min_margin) |",
        "| Minimum voltage upper margin | $(validation.voltage_max_margin) |",
        "| Minimum branch thermal margin | $(validation.branch_thermal_min_margin) |",
        "| Smooth/exact droop gap | $(validation.smooth_exact_droop_gap) |",
        "",
        "Violations: `$(isempty(validation.violations) ? :none : validation.violations)`",
    ]
    return join(lines, "\n")
end
