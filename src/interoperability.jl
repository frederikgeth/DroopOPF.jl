export model_data, materialize_operating_point, scale_case_loads

"""Return the library's JSON-compatible data representation without writing files.

Schema names and versioning remain owned by the enclosing result/input format.
This representation contains static data and may contain confidential identifiers.
It is not a dynamic model, evidence certificate, or shareable-data sanitizer.
"""
model_data(x) = _json_data(x)

"""Scale supplied active and reactive loads together; preserve equipment and controls."""
function scale_case_loads(c::Case, factor::Real)
    isfinite(factor) && factor >= 0 || throw(ArgumentError("finite nonnegative demand factor required"))
    _feasibility_scaled_case(c, factor)
end

function _materialized_point(c, state, assignments, context)
    assignments = isnothing(assignments) ? reactive_control_assignments(c) : assignments
    validate_equilibrium(c,state;reactive_assignments=assignments).valid ||
        throw(ArgumentError("materialized point failed independent equilibrium validation"))
    (;case=c,state,reactive_assignments=assignments,source_context=context)
end

"""Materialize a validated static result for an external assessment.

Returns `(case, state, reactive_assignments, source_context)`. Reconstructs
selected curves/equipment/relief without solving, repairing, or modifying inputs.
The corresponding result validator gates every optimized-result overload.
An outage endpoint does not specify a dynamic event or corrective action timing.
"""
function materialize_operating_point(c::Case, state::ACState;reactive_assignments=nothing)
    _materialized_point(c,state,reactive_assignments,Dict("role"=>"supplied_equilibrium"))
end
function materialize_operating_point(c::Case, r::ACOPFResult)
    r.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL) ||
        throw(ArgumentError("native OPF result did not converge"))
    isnothing(r.state) && throw(ArgumentError("missing OPF state"))
    _materialized_point(c,r.state,nothing,Dict("origin"=>"ACOPFResult","role"=>"base_equilibrium"))
end
function materialize_operating_point(c::Case, r::JointDesignResult)
    validate_joint_design(c,r).valid || throw(ArgumentError("joint design validation failed"))
    context=Dict("origin"=>"JointDesignResult","role"=>"designed_base_equilibrium",
        "tap_controls"=>model_data(r.tap_controls),"shunt_controls"=>model_data(r.shunt_controls),
        "droop_controls"=>[Dict("control_id"=>d.control_id,"bounds"=>model_data(d.bounds)) for d in r.droop_controls],
        "source_bank_metadata"=>model_data(c.network.banks))
    _materialized_point(with_joint_settings(c,r),r.opf.state,r.reactive_assignments,context)
end
function _point_scenario(s, id)
    id==:base && return s.case
    k=findfirst(x->x.id==id,s.contingencies)
    isnothing(k) && throw(ArgumentError("unknown scenario identity"))
    scenario_case(s.case,s.contingencies[k])
end
function materialize_operating_point(s::Study,r::SCOPFResult;scenario_id=:base)
    validate_equilibrium(s,r).valid || throw(ArgumentError("SCOPF policy/physics validation failed"))
    state=get(r.states,scenario_id,nothing)
    isnothing(state) && throw(ArgumentError("missing scenario state"))
    c=_point_scenario(s,scenario_id)
    c=with_shunt_settings(with_tap_settings(c,get(r.tap_settings,scenario_id,Dict{Int,Float64}())),
        get(r.shunt_settings,scenario_id,Dict{Int,Float64}()))
    context=Dict("origin"=>"SCOPFResult","role"=>(scenario_id==:base ? "preventive_base" : "settled_outage_equilibrium"),
        "response"=>(s.mode==:preventive ? "limit_aware" : "explicit_corrective_redispatch"),
        "study_mode"=>string(s.mode),"participation"=>model_data(s.participation),
        "redispatch_limits"=>model_data(s.redispatch_limits),
        "equipment_control_policy"=>model_data(s.control_policy),"dynamic_action_timing"=>"unspecified")
    _materialized_point(c,state,r.reactive_assignments,context)
end
function materialize_operating_point(s::MultiPeriodStudy,r::MultiPeriodResult;period::Integer)
    validate_multi_period(s,r).valid || throw(ArgumentError("multi-period validation failed"))
    1<=period<=length(s.cases) || throw(ArgumentError("unknown period"))
    c=s.cases[period]
    for (id,settings) in r.droops
        c=with_droop_settings(Study(c),id,settings).case
    end
    _materialized_point(c,r.periods[period].state,r.reactive_assignments,
        Dict("origin"=>"MultiPeriodResult","role"=>"period_equilibrium","duration_hours"=>s.duration_hours[period]))
end
function materialize_operating_point(studies::AbstractVector{<:Study},r::MultiPeriodSecurityResult;
    period::Integer,scenario_id=:base)
    validate_multi_period_security(studies,r).valid || throw(ArgumentError("multi-period security validation failed"))
    1<=period<=length(studies) || throw(ArgumentError("unknown period"))
    s=studies[period];p=r.periods[period];state=get(p.states,scenario_id,nothing)
    isnothing(state) && throw(ArgumentError("missing scenario state"))
    c=_point_scenario(s,scenario_id)
    if r.emergency && scenario_id!=:base
        c=_security_emergency_case(c);rel=r.relief[period][scenario_id]
        c=_security_relief_case(c,rel.dr,rel.shed)
    end
    for (id,settings) in r.droops
        c=with_droop_settings(Study(c),id,settings).case
    end
    c=with_shunt_settings(with_tap_settings(c,p.tap_settings[scenario_id]),p.shunt_settings[scenario_id])
    _materialized_point(c,state,p.reactive_assignments,
        Dict("origin"=>"MultiPeriodSecurityResult","role"=>(scenario_id==:base ? "preventive_period_base" : "settled_outage_equilibrium"),
            "response"=>string(r.response),"emergency"=>r.emergency,"duration_hours"=>r.duration_hours[period],
            "dynamic_action_timing"=>"unspecified"))
end
