using Test, DroopOPF
include("droop_security_workflow.jl")
c=droop_security_case(;rating=2.)
bank=ShuntBank(201,30;step_susceptances=(.02,),legal_states=((0,),(1,),(2,)),state=(1,))
case=Case("security-equipment-audit";base_power=c.base_power,base_frequency=c.base_frequency,
    network=ACNetwork(c.network.buses,c.network.branches;banks=[bank]),
    generators=c.generators,loads=c.loads,controls=c.controls,attachments=c.attachments)
study=Study(case;participation=Dict(7=>2.,9=>1.),
    tap_controls=[TapControl(11;lower=.99,upper=1.01)],
    shunt_controls=[ShuntControl(201;lower=0.,upper=.04)],
    control_policy=SCOPFControlPolicy(taps=:corrective,shunts=:corrective,
        tap_movement_limits=Dict(11=>.005),shunt_movement_limits=Dict(201=>.01)))
seed=solve_scopf(study;smooth_epsilon=1e-5,initial_states=Dict(:base=>droop_security_start(case)))
@test equilibrium_report(study,seed).valid
out=isempty(ARGS) ? "artifacts/droop_security/equipment" : abspath(only(ARGS))
r=optimize_droop_security(study,[DroopControl(2;slope_bounds=(.04,.1))];
    initial_states=seed.states,max_rounds=3,on_iteration=x->security_round_bundle(out,x))
write_droop_security(joinpath(out,"result.json"),r)
write(joinpath(out,"report.md"),markdown_report(r))
@test r.full_n1_accepted
@test all(a.report.valid for a in last(r.iterations).assessments)
@test last(r.iterations).study.control_policy == study.control_policy
println("Equipment policy and exhaustive driver: 4/4 checks passed")
