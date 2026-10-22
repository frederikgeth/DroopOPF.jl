"""Physical settings for the optimizable standard volt-var droop family.

`deadband_low` and `deadband_high` are nonnegative widths below and above
`v_ref`; they may differ or both be fixed at zero for a no-deadband curve.
"""
struct DroopSettings{T<:Real}
    slope::T
    v_ref::T
    deadband_low::T
    deadband_high::T
    function DroopSettings{T}(
        slope::T,
        v_ref::T,
        deadband_low::T,
        deadband_high::T,
    ) where {T<:Real}
        all(isfinite, (slope, v_ref, deadband_low, deadband_high)) ||
            throw(ArgumentError("droop settings must be finite"))
        slope > zero(T) || throw(ArgumentError("droop slope must be positive"))
        v_ref > zero(T) || throw(ArgumentError("voltage reference must be positive"))
        deadband_low >= zero(T) && deadband_high >= zero(T) ||
            throw(ArgumentError("deadband widths must be nonnegative"))
        v_ref - deadband_low > zero(T) ||
            throw(ArgumentError("the lower deadband edge must be positive"))
        new{T}(slope, v_ref, deadband_low, deadband_high)
    end
end

function DroopSettings(slope, v_ref, deadband_low, deadband_high)
    T = promote_type(
        typeof(slope),
        typeof(v_ref),
        typeof(deadband_low),
        typeof(deadband_high),
    )
    return DroopSettings{T}(
        T(slope),
        T(v_ref),
        T(deadband_low),
        T(deadband_high),
    )
end

DroopSettings(control::VoltVarDroop) = DroopSettings(
    control.slope,
    control.schedule.v_ref,
    control.schedule.v_ref - control.schedule.v_db_low,
    control.schedule.v_db_high - control.schedule.v_ref,
)

"""M3 optimized settings, reference objective, and scenario-indexed SCOPF result."""
struct DroopDesignResult
    control_id::Int
    reference_settings::DroopSettings{Float64}
    settings::DroopSettings{Float64}
    reference_objective::Float64
    result::SCOPFResult
end

_json_data(settings::DroopSettings) = Dict(
    string(field) => _json_data(getfield(settings, field))
    for field in fieldnames(typeof(settings))
)
_json_data(design::DroopDesignResult) = Dict(
    "control_id" => design.control_id,
    "reference_settings" => _json_data(design.reference_settings),
    "settings" => _json_data(design.settings),
    "reference_objective" => _json_data(design.reference_objective),
    "result" => _json_data(design.result),
)

"""Write an optimized M3 droop design and its training result to versioned JSON."""
write_droop_design(path::AbstractString, design::DroopDesignResult) =
    _write_scopf_json(path, "DroopOPF.DroopDesignResult", design)

function _droop_settings_from_data(data)
    return DroopSettings(
        Float64(data["slope"]),
        Float64(data["v_ref"]),
        Float64(data["deadband_low"]),
        Float64(data["deadband_high"]),
    )
end

"""Read an M3 design; independently validate it against its study before use."""
function read_droop_design(path::AbstractString)
    data = _read_scopf_json(path, "DroopOPF.DroopDesignResult")
    return DroopDesignResult(
        Int(data["control_id"]),
        _droop_settings_from_data(data["reference_settings"]),
        _droop_settings_from_data(data["settings"]),
        Float64(data["reference_objective"]),
        _scopf_result_from_data(data["result"]),
    )
end

function _control_with_settings(control::VoltVarDroop, settings::DroopSettings)
    schedule = VoltageSchedule(
        settings.v_ref;
        v_db_low = settings.v_ref - settings.deadband_low,
        v_db_high = settings.v_ref + settings.deadband_high,
        unit = control.schedule.unit,
    )
    return VoltVarDroop(
        schedule,
        settings.slope,
        control.q_at_deadband,
        control.capability,
    )
end

"""Return a copy of a study with one control replaced by optimized settings."""
function with_droop_settings(
    study::Study,
    control_id::Integer,
    settings::DroopSettings,
)
    1 <= control_id <= length(study.case.controls) ||
        throw(ArgumentError("control_id is out of range"))
    controls = copy(study.case.controls)
    controls[control_id] = _control_with_settings(controls[control_id], settings)
    case = Case(
        study.case.id;
        base_power = study.case.base_power,
        base_frequency = study.case.base_frequency,
        network = study.case.network,
        loads = study.case.loads,
        generators = study.case.generators,
        controls = controls,
        attachments = study.case.attachments,
    )
    return _copy_study(study; case)
end

with_droop_settings(study::Study, design::DroopDesignResult) =
    with_droop_settings(study, design.control_id, design.settings)

function _droop_parameter_bounds(bounds, reference, name; positive = false)
    if isnothing(bounds)
        return (Float64(reference), Float64(reference))
    end
    length(bounds) == 2 || throw(ArgumentError("$name bounds must contain two values"))
    lower, upper = Float64(bounds[1]), Float64(bounds[2])
    all(isfinite, (lower, upper)) || throw(ArgumentError("$name bounds must be finite"))
    lower <= upper || throw(ArgumentError("$name lower bound must not exceed its upper bound"))
    if positive
        lower > 0 || throw(ArgumentError("$name lower bound must be positive"))
    else
        lower >= 0 || throw(ArgumentError("$name lower bound must be nonnegative"))
    end
    return lower, upper
end

# Equivalent affine coordinates for finite free controller intervals.
function _normalized_control_variable(model, name, lower, upper, initial)
    width=upper-lower
    isfinite(width) && width>0 || throw(ArgumentError("normalization requires a finite positive interval"))
    z=@variable(model,lower_bound=0.,upper_bound=1.,base_name=name*"_normalized")
    set_start_value(z,(initial-lower)/width)
    physical=lower+width*z
    maps=get!(model.ext,:control_normalization_maps,Any[])
    push!(maps,(name=name,coordinate=z,physical=physical,lower=lower,width=width))
    physical
end

function _droop_design_variable(model, name, bounds, initial;normalize=false)
    lower, upper = bounds
    lower == upper && return lower
    normalize && return _normalized_control_variable(model,name,lower,upper,Float64(initial))
    variable = @variable(model, base_name = name)
    set_lower_bound(variable, lower)
    set_upper_bound(variable, upper)
    set_start_value(variable, Float64(initial))
    return variable
end

_droop_design_value(value::Real) = Float64(value)
_droop_design_value(value::VariableRef) = JuMP.value(value)
_droop_design_value(value::AffExpr) = JuMP.value(value)

_droop_parameter_start(value::Real, fallback) = Float64(value)
function _droop_parameter_start(value::VariableRef, fallback)
    start = start_value(value)
    isnothing(start) ? Float64(fallback) : Float64(start)
end
function _droop_parameter_start(value::AffExpr, fallback)
    starts = JuMP.value(v -> something(start_value(v), NaN), value)
    isfinite(starts) ? Float64(starts) : Float64(fallback)
end

"""
    optimize_droop_parameters(study, control_id; slope_bounds, ...)

Optimize one control's slope, voltage reference, and asymmetric deadband widths
as variables shared by the base case and every training contingency. Omitted
bounds fix that setting at its M2 value. The dispatch objective is unchanged,
so fixing all bounds at the reference reproduces M2. This is a smooth-NLP
design problem for Ipopt or MadNLP; CCOpt may be used only after reconstructing
the optimized fixed curve.
"""
function optimize_droop_parameters(
    study::Study,
    control_id::Integer;
    slope_bounds = nothing,
    v_ref_bounds = nothing,
    deadband_low_bounds = nothing,
    deadband_high_bounds = nothing,
    smooth_epsilon::Real = 1.0e-5,
    smooth_reactive_relative_epsilon::Real = smooth_epsilon,
    smooth_reactive_epsilon::Union{Nothing,Real} = nothing,
    optimizer_factory = Ipopt.Optimizer,
    optimizer_attributes::AbstractDict = Dict{String,Any}(),
    silent::Bool = true,
    reference_result::Union{Nothing,SCOPFResult} = nothing,
    initial_settings::Union{Nothing,DroopSettings} = nothing,
)
    study = _validated_study(study)
    1 <= control_id <= length(study.case.controls) ||
        throw(ArgumentError("control_id is out of range"))
    optimizer_factory === CCOpt.Optimizer && throw(ArgumentError(
        "CCOpt does not optimize M3 droop parameters; reconstruct the design " *
        "and use solve_scopf(...; encoding=:complementarity) for an exact fixed-curve solve",
    ))
    all(x -> isfinite(x) && x > 0, (smooth_epsilon, smooth_reactive_relative_epsilon)) ||
        throw(ArgumentError("smoothing widths must be positive and finite"))
    isnothing(smooth_reactive_epsilon) ||
        (isfinite(smooth_reactive_epsilon) && smooth_reactive_epsilon > 0) ||
        throw(ArgumentError("reactive smoothing width must be positive and finite"))
    control = study.case.controls[control_id]
    reference = DroopSettings(control)
    slope_range = _droop_parameter_bounds(
        slope_bounds,
        reference.slope,
        "slope";
        positive = true,
    )
    v_ref_range = _droop_parameter_bounds(
        v_ref_bounds,
        reference.v_ref,
        "v_ref";
        positive = true,
    )
    deadband_low_range = _droop_parameter_bounds(
        deadband_low_bounds,
        reference.deadband_low,
        "deadband_low",
    )
    deadband_high_range = _droop_parameter_bounds(
        deadband_high_bounds,
        reference.deadband_high,
        "deadband_high",
    )
    v_ref_range[1] - deadband_low_range[2] > 0 ||
        throw(ArgumentError("bounds permit a nonpositive lower deadband edge"))
    (deadband_low_range == (0.,0.) && deadband_high_range == (0.,0.)) ||
        deadband_low_range[1] + deadband_high_range[1] > 0 ||
        throw(ArgumentError("bounds permit a zero-width deadband"))
    initial = isnothing(initial_settings) ? DroopSettings(
        clamp(reference.slope, slope_range...), clamp(reference.v_ref, v_ref_range...),
        clamp(reference.deadband_low, deadband_low_range...),
        clamp(reference.deadband_high, deadband_high_range...)) : initial_settings
    initial_values = (initial.slope, initial.v_ref, initial.deadband_low, initial.deadband_high)
    parameter_ranges = (slope_range, v_ref_range, deadband_low_range, deadband_high_range)
    all(value -> isfinite(value), initial_values) ||
        throw(ArgumentError("initial droop settings must be finite"))
    all(pair -> pair[2][1] <= pair[1] <= pair[2][2], zip(initial_values, parameter_ranges)) ||
        throw(ArgumentError("initial droop settings must lie within the design bounds"))
    reference_result = isnothing(reference_result) ?
        solve_scopf(
            study;
            smooth_epsilon = smooth_epsilon,
            smooth_reactive_relative_epsilon = smooth_reactive_relative_epsilon,
            smooth_reactive_epsilon = smooth_reactive_epsilon,
            optimizer_factory = optimizer_factory,
            optimizer_attributes = optimizer_attributes,
            silent = silent,
        ) : reference_result
    reference_result.encoding == :smooth &&
        reference_result.smooth_epsilon == Float64(smooth_epsilon) &&
        reference_result.smooth_reactive_relative_epsilon ==
            Float64(smooth_reactive_relative_epsilon) &&
        reference_result.smooth_reactive_epsilon ==
            (isnothing(smooth_reactive_epsilon) ? nothing : Float64(smooth_reactive_epsilon)) ||
        throw(ArgumentError("reference result uses different smoothing settings"))
    equilibrium_report(study, reference_result).valid ||
        throw(ArgumentError("the reference M2 study must solve and validate before optimization"))

    controls = [DroopControl(control_id; slope_bounds, v_ref_bounds,
        deadband_low_bounds, deadband_high_bounds, initial)]
    design = optimize_droop_parameters(study, controls;
        smooth_epsilon, smooth_reactive_relative_epsilon, smooth_reactive_epsilon,
        optimizer_factory, optimizer_attributes, silent,
        initial_states=reference_result.states)
    settings = get(design.settings, Int(control_id), initial)
    return DroopDesignResult(Int(control_id), _float_settings(reference),
        _float_settings(settings), reference_result.objective, design.result)
end

"""Independently replay an optimized design with an exact physical droop curve."""
function validate_droop_design(study::Study, design::DroopDesignResult; kwargs...)
    optimized = with_droop_settings(study, design)
    return equilibrium_report(optimized, design.result; kwargs...)
end

"""Evaluate an optimized base dispatch against contingencies excluded from training.

Returns a named tuple containing the held-out study, result, and independent
report. Held-out IDs must differ from the training scenario IDs.
"""
function evaluate_held_out_contingencies(
    study::Study,
    design::DroopDesignResult,
    contingencies::AbstractVector{<:Contingency};
    smooth_epsilon::Real = design.result.smooth_epsilon,
    smooth_reactive_relative_epsilon::Real =
        design.result.smooth_reactive_relative_epsilon,
    smooth_reactive_epsilon::Union{Nothing,Real} =
        design.result.smooth_reactive_epsilon,
    kwargs...,
)
    training_ids = Set(contingency.id for contingency in study.contingencies)
    all(contingency -> !(contingency.id in training_ids), contingencies) ||
        throw(ArgumentError("held-out contingency IDs must not appear in training"))
    optimized = with_droop_settings(study, design)
    held_out = _copy_study(optimized; contingencies)
    base = get(design.result.states, :base, nothing)
    isnothing(base) && throw(ArgumentError("the optimized design has no base state"))
    result = evaluate_contingencies(
        held_out,
        base;
        fixed_base_tap_settings=get(design.result.tap_settings, :base, Dict()),
        fixed_base_shunt_settings=get(design.result.shunt_settings, :base, Dict()),
        smooth_epsilon = smooth_epsilon,
        smooth_reactive_relative_epsilon = smooth_reactive_relative_epsilon,
        smooth_reactive_epsilon = smooth_reactive_epsilon,
        kwargs...,
    )
    return (study = held_out, result = result, report = equilibrium_report(held_out, result))
end
