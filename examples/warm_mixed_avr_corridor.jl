# Native feasibility recovery from the closest bounded joint-master iterate.
include("p2_mixed_avr_500.jl")
function warm_corridor(root;output_name="security-master-corridor-complete-warm",source_name="security-master-corridor-centered",seconds=900.,tight=false)
    source=joinpath(root,source_name)
    prior=read_multi_period_security(joinpath(source,"result.json"))
    x=mix_inputs(joinpath(root,"preflight-warm-corridor"));factors=[.9,1.,1.05,1.,.9]
    studies=[read_study(joinpath(source,"period-$t.json")) for t in 1:5]
    ids=[:generator_60,:branch_36,:branch_562];events=[only(e for e in x.events if e.contingency.id==id) for id in ids]
    starts=[Dict(k=>v for (k,v) in p.states if !isnothing(v)) for p in prior.periods]
    equipment=[(;taps=p.tap_settings[:base],shunts=p.shunt_settings[:base],
        scenarios=Dict(id=>(;taps=p.tap_settings[id],shunts=p.shunt_settings[id]) for id in [:base;ids])) for p in prior.periods]
    controls=[DroopControl(d.control_id;slope_bounds=d.bounds.slope,v_ref_bounds=d.bounds.v_ref,
        initial=prior.droops[d.control_id]) for d in x.controls]
    mix_attempt(x,joinpath(root,output_name),factors,events;studies,starts,controls,
        initial_equipment=equipment,objective_policy=:feasibility,schedule=true,seconds,
        initial_avr_targets=prior.avr_targets,initial_relief=prior.relief,
        initial_balancing_power=[p.balancing_power for p in prior.periods],
        reserve_generator_outages=[g.id for g in x.setup.case.generators if g.available],
        solver_options=Dict("mu_strategy"=>"monotone","mu_init"=>(tight ? 1e-8 : 1e-4),"bound_push"=>(tight ? 1e-12 : 1e-5),
            "bound_frac"=>(tight ? 1e-12 : 1e-5),"slack_bound_push"=>(tight ? 1e-12 : 1e-5),
            "slack_bound_frac"=>(tight ? 1e-12 : 1e-5)))
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1||error("provide reserve campaign root")
    warm_corridor(abspath(ARGS[1]))
end
