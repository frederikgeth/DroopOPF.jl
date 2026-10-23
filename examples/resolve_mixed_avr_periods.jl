# Independent period solves provide starts for a final native five-period solve.
# Only that final joint result is eligible for the exhaustive qualification.
include("p2_mixed_avr_500.jl")
function resolve_periods(root,event_id)
    id=Symbol(event_id);candidate="security-master-guard";factors=[.9,1.,1.05,1.,.9]
    x=mix_inputs(joinpath(root,"preflight-period-resolution"))
    parent=read_multi_period_security(joinpath(root,candidate,"result.json"))
    event=only(e for e in x.events if e.contingency.id==id)
    scan=only(p for p in readdir(root;join=true) if startswith(basename(p),"scan-"*candidate)&&isdir(joinpath(p,event_id*"-retry")))
    studies=[read_study(joinpath(scan,event_id*"-retry","period-$t.json")) for t in 1:5]
    old=read_multi_period_security(joinpath(MIX_ROOT,"artifacts/p2_mixed_avr_500_20261022/scan-designed",event_id,"result.json"))
    out=joinpath(root,"resolutions-periods",event_id);mkpath(out);solutions=Any[]
    for t in 1:5
        starts=[Dict(:base=>parent.periods[t].states[:base],id=>old.periods[t].states[id])]
        eq=[(;taps=old.periods[t].tap_settings[id],shunts=old.periods[t].shunt_settings[id])]
        r=mix_attempt(x,joinpath(out,"period-$t"),[factors[t]],[event];studies=[studies[t]],starts,
            fixed_bases=[parent.periods[t]],initial_equipment=eq,seconds=60.,
            solver_options=Dict("mu_strategy"=>"monotone","mu_init"=>.001,"bound_push"=>1e-8,"bound_frac"=>1e-8,
                "slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
        r.summary.accepted || return
        push!(solutions,r.result.periods[1])
    end
    starts=[Dict(:base=>parent.periods[t].states[:base],id=>solutions[t].states[id]) for t in 1:5]
    eq=[(;taps=p.tap_settings[id],shunts=p.shunt_settings[id]) for p in solutions]
    path=joinpath(out,"joint-native")
    joint=mix_attempt(x,path,factors,[event];studies,starts,initial_equipment=eq,
        fixed_bases=parent.periods,seconds=60.,solver_options=Dict("mu_strategy"=>"monotone","mu_init"=>.001,
            "bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
    write(joinpath(root,"resolutions-periods/summary.json"),JSON.json((;candidate,
        rows=[(;event=id,accepted=joint.summary.accepted,path,status=joint.summary.status)]);pretty=true)*"\n")
end
length(ARGS)==2||error("provide root and event")
resolve_periods(abspath(ARGS[1]),ARGS[2])
