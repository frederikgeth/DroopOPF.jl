# Add the observed AC counterexample to a bounded shared-design master.
include("p2_mixed_avr_500.jl")
function refine_reserve(root)
    x=mix_inputs(joinpath(root,"preflight-refinement"));factors=[.9,1.,1.05,1.,.9]
    parent=read_multi_period_security(joinpath(root,"security-master-guard/result.json"))
    old=read_multi_period_security(joinpath(MIX_ROOT,"artifacts/p2_mixed_avr_500_20261022/scan-designed/branch_36/result.json"))
    ids=[:generator_60,:branch_36];events=[only(e for e in x.events if e.contingency.id==id) for id in ids]
    starts=[Dict(:base=>parent.periods[t].states[:base],:generator_60=>parent.periods[t].states[:generator_60],
        :branch_36=>old.periods[t].states[:branch_36]) for t in 1:5]
    controls=[DroopControl(d.control_id;slope_bounds=d.bounds.slope,v_ref_bounds=d.bounds.v_ref,
        initial=parent.droops[d.control_id]) for d in x.controls]
    mix_attempt(x,joinpath(root,"security-master-branch36"),factors,events;controls,starts,
        initial_equipment=mixed_equipment_starts(parent.periods),objective_policy=:reserve,
        reserve_generator_outages=[g.id for g in x.setup.case.generators if g.available],
        schedule=true,seconds=240.,solver_options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,
            "slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
end
length(ARGS)==1||error("provide reserve campaign root")
refine_reserve(abspath(ARGS[1]))
