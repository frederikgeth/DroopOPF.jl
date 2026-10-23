# Feasibility recovery with a single frozen, explicitly bounded shared curve set.
include("p2_mixed_avr_500.jl")
using SHA
function fixed_curve_reserve(root)
    source=joinpath(root,"security-master-corridor-scaled-avr")
    prior=read_multi_period_security(joinpath(source,"result.json"))
    x=mix_inputs(joinpath(root,"preflight-fixed-curve-corridor"));factors=[.9,1.,1.05,1.,.9]
    inputs=[read_study(joinpath(source,"period-$t.json")) for t in 1:5]
    studies=Study[]
    for s in inputs
        c=s.case
        for (id,setting) in prior.droops;c=with_droop_settings(Study(c),id,setting).case;end
        assignments=DroopOPF._settings_assignments(c,s.reactive_assignments,prior.droops)
        push!(studies,Study(c;reactive_assignments=assignments,contingencies=s.contingencies,
            participation=s.participation,redispatch_limits=s.redispatch_limits,
            tap_controls=s.tap_controls,shunt_controls=s.shunt_controls,control_policy=s.control_policy))
    end
    for d in x.controls
        p=DroopOPF._joint_droop_policy(x.setup.case,d);v=prior.droops[d.control_id]
        all(getfield(p.ranges,k)[1]<=getfield(v,k)<=getfield(p.ranges,k)[2] for k in keys(p.ranges)) || error("curve outside design envelope")
    end
    ids=[:generator_60,:branch_36,:branch_562];events=[only(e for e in x.events if e.contingency.id==id) for id in ids]
    starts=[Dict(k=>v for (k,v) in p.states if !isnothing(v)) for p in prior.periods]
    equipment=[(;taps=p.tap_settings[:base],shunts=p.shunt_settings[:base],
        scenarios=Dict(id=>(;taps=p.tap_settings[id],shunts=p.shunt_settings[id]) for id in [:base;ids])) for p in prior.periods]
    # Equivalent positive AVR projection gain; unchanged physical replay is mandatory.
    text=read(joinpath(MIX_ROOT,"src/jump.jl"),String);i=first(findfirst("function _build_acopf_model(",text))
    _,j=Meta.parse(text,i;greedy=true);fragment=text[i:j-1]
    fragment=replace(fragment,"gain=max(sum(g.q_max-g.q_min for g in generators),1e-6)/.02"=>
        "gain=.01max(sum(g.q_max-g.q_min for g in generators),1e-6)/.02")
    include_string(DroopOPF,fragment,"fixed-curve-numerical-avr-projection.jl")
    out=joinpath(root,"security-corridor-fixed-curve")
    result=Base.invokelatest(mix_attempt,x,out,factors,events;studies,starts,initial_equipment=equipment,
        objective_policy=:feasibility,schedule=true,seconds=300.,
        initial_avr_targets=prior.avr_targets,initial_relief=prior.relief,
        initial_balancing_power=[p.balancing_power for p in prior.periods],
        reserve_generator_outages=[g.id for g in x.setup.case.generators if g.available],
        solver_options=Dict("mu_strategy"=>"monotone","mu_init"=>1e-6,"bound_push"=>1e-9,
            "bound_frac"=>1e-9,"slack_bound_push"=>1e-9,"slack_bound_frac"=>1e-9))
    mix_save(joinpath(out,"curve-provenance.json"),(;source_result=source,
        source_result_sha256=bytes2hex(sha256(read(joinpath(source,"result.json")))),
        settings=prior.droops,all_within_original_design_bounds=true,
        method="shared curves selected from preceding numerical search; frozen for final feasibility recovery; no optimality claim",
        numerical_avr_projection_gain_multiplier=.01,physical_limits_changed=false))
    result
end
length(ARGS)==1||error("provide reserve campaign root")
fixed_curve_reserve(abspath(ARGS[1]))
