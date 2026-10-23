# Fresh reserve-aware continuation. Never writes to the sealed source campaign.
include("p2_mixed_avr_500.jl")
const RESERVE_ORIGIN=joinpath(MIX_ROOT,"artifacts/p2_mixed_avr_500_20261022")
function reserve_case(folder)
    isdir(folder) || mkpath(folder)
    x=mix_inputs(folder)
    x
end
function reserve_run(folder,phase)
    x=reserve_case(joinpath(folder,"preflight-"*replace(phase,":"=>"-")));factors=[.9,1.,1.05,1.,.9]
    origin=read_multi_period_security(joinpath(RESERVE_ORIGIN,"multi-design-hot","result.json"))
    if phase=="base"
        return mix_attempt(x,joinpath(folder,"reserve-base"),factors,[];controls=x.controls,
            starts=[Dict(:base=>p.states[:base]) for p in origin.periods],
            initial_equipment=mixed_equipment_starts(origin.periods),objective_policy=:reserve_loss,
            schedule=true,seconds=180.)
    end
    if startswith(phase,"master")
        source=phase in ("master","master-reserve","master-polish","master-guard","master-feasible") ? "reserve-base" : "security-master-reserve"
        solution=read_multi_period_security(joinpath(folder,source,"result.json"))
        validate_multi_period_security([read_study(joinpath(folder,source,"period-$t.json")) for t in 1:5],solution).valid || error("unqualified master seed")
        ids=phase in ("master","master-reserve","master-polish","master-guard","master-feasible") ? [:generator_60] : [:generator_60,:generator_14]
        events=[only(e for e in x.events if e.contingency.id==id) for id in ids]
        c=x.setup.case
        for (id,setting) in solution.droops;c=with_droop_settings(Study(c),id,setting).case;end
        starts=mix_response_starts(x,solution,c,events,factors)
        controls=[DroopControl(d.control_id;slope_bounds=d.bounds.slope,v_ref_bounds=d.bounds.v_ref,
            initial=solution.droops[d.control_id]) for d in x.controls]
        return mix_attempt(x,joinpath(folder,phase=="master" ? "security-master" : phase=="master-reserve" ? "security-master-reserve" : phase=="master-polish" ? "security-master-polish" : phase=="master-guard" ? "security-master-guard" : phase=="master-feasible" ? "security-master-feasible" : "security-master-two"),factors,events;
            controls,starts,initial_equipment=mixed_equipment_starts(solution.periods),
            objective_policy=phase=="master-feasible" ? :feasibility : phase in ("master-reserve","master-two","master-guard") ? :reserve : :reserve_loss,
            reserve_generator_outages=phase in ("master-guard","master-feasible") ? [g.id for g in x.setup.case.generators if g.available] : Int[],schedule=true,seconds=180.,
            solver_options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
    elseif startswith(phase,"scan:")
        parts=split(phase,":");candidate=parts[2]
        shard=length(parts)>=3 ? parse(Int,parts[3]) : 1
        shards=length(parts)>=4 ? parse(Int,parts[4]) : 1
        return reserve_scan(x,folder,candidate;shard,shards)
    end
    error("unknown phase")
end
function reserve_scan(x,folder,candidate;seconds=5.,shard=1,shards=1,response=:s2_proportional,emergency=true)
    1<=shard<=shards || error("invalid shard")
    solution=read_multi_period_security(joinpath(folder,candidate,"result.json"))
    originals=[read_study(joinpath(folder,candidate,"period-$t.json")) for t in 1:5]
    validate_multi_period_security(originals,solution).valid || error("unqualified scan seed")
    c=x.setup.case
    for (id,setting) in solution.droops;c=with_droop_settings(Study(c),id,setting).case;end
    factors=[.9,1.,1.05,1.,.9];rows=Any[]
    # Generator outages first, then branches. No predictive safe skipping.
    events=sort(x.events;by=e->candidate=="security-master-guard" ?
        (1,isempty(e.contingency.generator_ids),string(e.contingency.id)) :
        (e.contingency.id in (:branch_36,:branch_562) ? 0 : 1,isempty(e.contingency.generator_ids),string(e.contingency.id)))
    scanroot=joinpath(folder,"scan-"*candidate*(shards==1 ? "" : "-shard-$shard-of-$shards"));mkpath(scanroot)
    journal=joinpath(scanroot,"summary.json")
    if isfile(journal);append!(rows,JSON.parsefile(journal)["rows"]);end
    done=Set(Symbol(r isa NamedTuple ? r.event : r["event"]) for r in rows)
    selected_events=[e for (i,e) in enumerate(events) if mod(i-1,shards)==shard-1]
    for e in selected_events
        id=e.contingency.id;id in done && continue
        studies=[only(mix_studies(x,[factors[t]],[e];case=c,assignments=solution.periods[t].reactive_assignments)) for t in 1:5]
        starts=mix_response_starts(x,solution,c,[e],factors)
        equipment=mixed_equipment_starts(solution.periods)
        if all(haskey(p.states,id)&&!isnothing(p.states[id]) for p in solution.periods)
            for t in 1:5;starts[t][id]=solution.periods[t].states[id];end
            equipment=[(;taps=p.tap_settings[id],shunts=p.shunt_settings[id]) for p in solution.periods]
        end
        path=joinpath(scanroot,string(id))
        attempt=mix_attempt(x,path,factors,[e];studies,starts,fixed_bases=solution.periods,
            initial_equipment=equipment,seconds,response,emergency,
            solver_options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
        selected=attempt;chosen=path
        if !attempt.summary.accepted
            prior=attempt.result
            retry_starts=[Dict{Symbol,ACState{Float64}}(k=>v for (k,v) in p.states if !isnothing(v)) for p in prior.periods]
            eq=[(;taps=p.tap_settings[id],shunts=p.shunt_settings[id]) for p in prior.periods]
            retry=path*"-retry"
            selected=mix_attempt(x,retry,factors,[e];studies,starts=retry_starts,fixed_bases=solution.periods,
                initial_equipment=eq,seconds=20.,response,emergency,
                solver_options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
            chosen=retry
        end
        push!(rows,(;event=id,accepted=selected.summary.accepted,path=chosen,status=selected.summary.status))
        mix_save(journal,(;candidate,shard,shards,complete=length(rows)==length(selected_events),rows,
            accepted=count(r->r isa NamedTuple ? r.accepted : r["accepted"],rows)))
        GC.gc(false)
    end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("fresh campaign directory and phase required")
    reserve_run(abspath(ARGS[1]),ARGS[2])
end
