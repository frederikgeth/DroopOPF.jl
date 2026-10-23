# Explicitly constrain both observed corridor outages with coherent equipment starts.
include("p2_mixed_avr_500.jl")
using MadNLP
function refine_corridor(root;solver=:ipopt)
    x=mix_inputs(joinpath(root,"preflight-corridor"));factors=[.9,1.,1.05,1.,.9]
    parent=read_multi_period_security(joinpath(root,"security-master-guard/result.json"))
    ledger=JSON.parsefile(joinpath(MIX_ROOT,"artifacts/p2_mixed_avr_500_20261022/aggregate-checks.json"))
    old=Dict{Symbol,MultiPeriodSecurityResult}()
    for id in (:branch_36,:branch_562)
        matches=[r for lane in ("designed","fixed") for r in ledger["scans"][lane]["rows"]
            if r["event"]==string(id)&&r["status"]=="native_and_independent_pass"]
        isempty(matches)&&error("no qualified topology start for $id")
        old[id]=read_multi_period_security(joinpath(first(matches)["path"],"result.json"))
    end
    ids=[:generator_60,:branch_36,:branch_562]
    events=[only(e for e in x.events if e.contingency.id==id) for id in ids]
    starts=[Dict(:base=>parent.periods[t].states[:base],:generator_60=>parent.periods[t].states[:generator_60],
        :branch_36=>old[:branch_36].periods[t].states[:branch_36],
        :branch_562=>old[:branch_562].periods[t].states[:branch_562]) for t in 1:5]
    equipment=[(;taps=parent.periods[t].tap_settings[:base],shunts=parent.periods[t].shunt_settings[:base],
        scenarios=Dict(id=>(;taps=(id in (:base,:generator_60) ? parent : old[id]).periods[t].tap_settings[id],
            shunts=(id in (:base,:generator_60) ? parent : old[id]).periods[t].shunt_settings[id])
            for id in [:base;ids])) for t in 1:5]
    controls=[DroopControl(d.control_id;slope_bounds=d.bounds.slope,v_ref_bounds=d.bounds.v_ref,
        initial=parent.droops[d.control_id]) for d in x.controls]
    mix_attempt(x,joinpath(root,solver==:madnlp ? "security-master-corridor-madnlp" : solver==:centered ? "security-master-corridor-centered" : "security-master-corridor"),factors,events;controls,starts,
        initial_equipment=equipment,objective_policy=:reserve,
        reserve_generator_outages=[g.id for g in x.setup.case.generators if g.available],
        schedule=true,seconds=240.,optimizer_factory=solver==:madnlp ? MadNLP.Optimizer : DroopOPF.Ipopt.Optimizer,
        solver_options=solver==:madnlp ? Dict() : solver==:centered ? Dict("mu_strategy"=>"monotone","mu_init"=>.1,
            "bound_push"=>.01,"bound_frac"=>.01,"slack_bound_push"=>.01,"slack_bound_frac"=>.01) :
            Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
end
length(ARGS) in (1,2)||error("provide reserve campaign root and optional solver")
refine_corridor(abspath(ARGS[1]);solver=length(ARGS)==2 ? Symbol(ARGS[2]) : :ipopt)
