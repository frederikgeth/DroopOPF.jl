# Fresh P2 policy assessment. Historical S2 evidence is input only.
include("p2_mixed_avr_reserve.jl")
function p2_inputs(folder)
    x=mix_inputs(folder)
    policy=SCOPFControlPolicy(taps=:corrective,shunts=:corrective,
        tap_movement_limits=Dict(t.branch_id=>.025*t.nominal for t in x.taps),
        shunt_movement_limits=Dict(b.id=>2abs(only(b.step_susceptances)) for b in x.setup.case.network.banks if any(s.bank_id==b.id for s in x.shunts)))
    merge(x,(;p2_policy=policy))
end
function p2_run(folder,phase)
    factors=[.9,1.,1.05,1.,.9]
    x=p2_inputs(joinpath(folder,"preflight-"*replace(phase,":"=>"-")))
    if phase=="base"
        mix_save(joinpath(folder,"catalogue.json"),contingency_catalog(x.setup.case))
        mix_save(joinpath(folder,"protocol.json"),(;response="limit_aware",weights="default effective active capability range",
            emergency=false,load_relief=false,physical_limits="normal original bounds, Rate A",
            policy=x.p2_policy,taps=x.taps,shunts=x.shunts,
            equipment_timing="120-second assumed settled sensitivity, continuous; immediate movement zero is not assessed here",
            discrete_bank_recovery=false,manufacturer_timing_verified=false,
            droop="36 shared curves using current mixed-study calibrated bounds, frozen for full-catalogue scans",
            avr="15 largest online generators; nominal +/-0.02 pu, max 0.01 pu/hour; frozen within period across outages",
            factors,ratings="assumed Pmax/0.95",objective="maximum minimum upward headroom; optional subsequent loss",
            screening=false,full_catalogue_resource_optimality=false,prior_evidence="read-only warm starts; no S2 security certificate is migrated"))
        old=joinpath(MIX_ROOT,"artifacts/p2_mixed_avr_reserve_20261023/security-master-guard")
        source=read_multi_period_security(joinpath(old,"result.json"))
        return mix_attempt(x,joinpath(folder,"p2-base"),factors,[];controls=x.controls,
            starts=[Dict(:base=>p.states[:base]) for p in source.periods],
            initial_equipment=mixed_equipment_starts(source.periods),initial_avr_targets=source.avr_targets,
            objective_policy=:reserve,schedule=true,response=:limit_aware,emergency=false,seconds=180.)
    elseif startswith(phase,"master")
        source=read_multi_period_security(joinpath(folder,"p2-base/result.json"))
        ids=phase=="master" ? [:generator_60,:branch_36,:branch_562] : [:generator_60]
        events=[only(e for e in x.events if e.contingency.id==id) for id in ids]
        c=x.setup.case
        for (id,s) in source.droops;c=with_droop_settings(Study(c),id,s).case;end
        controls=[DroopControl(d.control_id;slope_bounds=d.bounds.slope,v_ref_bounds=d.bounds.v_ref,initial=source.droops[d.control_id]) for d in x.controls]
        return mix_attempt(x,joinpath(folder,phase=="master" ? "p2-master" : "p2-master-generator"),factors,events;
            controls,starts=mix_response_starts(x,source,c,events,factors),initial_equipment=mixed_equipment_starts(source.periods),
            initial_avr_targets=source.avr_targets,objective_policy=:reserve,schedule=true,response=:limit_aware,emergency=false,seconds=240.,
            solver_options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
    elseif startswith(phase,"scan:")
        _,candidate,shard,shards=split(phase,":")
        reserve_scan(x,folder,candidate;shard=parse(Int,shard),shards=parse(Int,shards),response=:limit_aware,emergency=false)
    else
        error("unknown phase")
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && p2_run(abspath(ARGS[1]),ARGS[2])
