# Initialization-only PQ active-set search. The final solve restores all AVR laws.
include("p2_mixed_avr_500.jl")
function mode_start(root,event_id)
    id=Symbol(event_id);candidate="security-master-guard";factors=[.9,1.,1.05,1.,.9]
    parent=read_multi_period_security(joinpath(root,candidate,"result.json"))
    x=mix_inputs(joinpath(root,"preflight-mode-start-"*event_id))
    event=only(e for e in x.events if e.contingency.id==id)
    scan=only(p for p in readdir(root;join=true) if startswith(basename(p),"scan-"*candidate)&&isdir(joinpath(p,event_id*"-retry")))
    studies=[read_study(joinpath(scan,event_id*"-retry","period-$t.json")) for t in 1:5]
    out=joinpath(root,"resolutions-mode-"*event_id);mkpath(out);prepared=Any[]
    mix_save(joinpath(out,"initialization-policy.json"),(;role="initializer only; not original AVR model",
        altered_generators=[21,24],preparation="near-lower capability Q at frozen PG; one positive-weight unit holds PG to set response signal zero",
        base_mode_audit_not_applicable=true,physical_qualification="final original-mode native solve and unchanged independent audits only"))
    for t in 1:5
        s=studies[t];base=parent.periods[t].states[:base];generators=s.case.generators
        assignments=ReactiveControlAssignment[];qg=copy(base.qg)
        for a in s.reactive_assignments
            if a.generator_id in (21,24)
                i=findfirst(g->g.id==a.generator_id,generators);lo,hi=reactive_limits(generators[i],base.pg[i])
                q=.999lo+.001hi;qg[i]=q
                push!(assignments,ReactiveControlAssignment(a.generator_id,FixedQ(q)))
            else
                push!(assignments,a)
            end
        end
        prepstudy=Study(s.case;reactive_assignments=assignments,contingencies=s.contingencies,
            participation=s.participation,redispatch_limits=Dict(60=>0.),tap_controls=s.tap_controls,
            shunt_controls=s.shunt_controls,control_policy=s.control_policy)
        starts=[Dict(:base=>base,id=>ACState(copy(base.vm),copy(base.va),copy(base.pg),qg))]
        prep=mix_attempt(x,joinpath(out,"prepare-$t"),[factors[t]],[event];studies=[prepstudy],starts,
            fixed_bases=[parent.periods[t]],initial_equipment=mixed_equipment_starts([parent.periods[t]]),seconds=90.,
            solver_options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
        prep.result.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL) || return
        push!(prepared,prep.result)
    end
    starts=[Dict(:base=>parent.periods[t].states[:base],id=>prepared[t].periods[1].states[id]) for t in 1:5]
    eq=[(;taps=prepared[t].periods[1].tap_settings[id],shunts=prepared[t].periods[1].shunt_settings[id]) for t in 1:5]
    path=joinpath(out,"joint-original-native")
    final=mix_attempt(x,path,factors,[event];studies,starts,initial_equipment=eq,
        initial_relief=[p.relief[1] for p in prepared],
        initial_balancing_power=[p.periods[1].balancing_power for p in prepared],
        fixed_bases=parent.periods,seconds=180.,
        solver_options=Dict("bound_push"=>1e-9,"bound_frac"=>1e-9,"slack_bound_push"=>1e-9,"slack_bound_frac"=>1e-9))
    mix_save(joinpath(out,"summary.json"),(;candidate,rows=[(;event=id,accepted=final.summary.accepted,path,status=final.summary.status)]))
end
length(ARGS)==2||error("provide root and event")
mode_start(abspath(ARGS[1]),ARGS[2])
