include("p2_targeted_relaxations.jl")
function targeted_joint(root,phase)
    x=p2_inputs(joinpath(root,"preflight-joint-"*replace(phase,":"=>"-")))
    if startswith(phase,"scan:")
        parts=split(phase,":");candidate=length(parts)==4 ? parts[2] : "joint-five"
        return reserve_scan(x,root,candidate;shard=parse(Int,parts[end-1]),shards=parse(Int,parts[end]),response=:limit_aware,emergency=false)
    end
    ids=startswith(phase,"augment-") ? [:branch_21,:branch_36,:branch_562,:generator_14,:generator_60] : [:branch_21,:branch_36,:branch_562]
    events=[only(e for e in x.events if e.contingency.id==id) for id in ids]
    if phase=="augment-polish"
        factors=[1.05];source=read_multi_period_security(joinpath(root,"joint-augment-peak/result.json"));p=source.periods[1]
        starts=[Dict(k=>v for (k,v) in p.states)];eq=[(;taps=p.tap_settings[:base],shunts=p.shunt_settings[:base],
            scenarios=Dict(id=>(;taps=p.tap_settings[id],shunts=p.shunt_settings[id]) for id in keys(p.states)))];targets=source.avr_targets
    elseif phase=="augment-peak"
        factors=[1.05];source=read_multi_period_security(joinpath(root,"joint-five/result.json"));p=source.periods[3]
        states=Dict(k=>v for (k,v) in p.states);equipment=Dict(id=>(;taps=p.tap_settings[id],shunts=p.shunt_settings[id]) for id in keys(p.states))
        for id in (:generator_14,:generator_60)
            paths=[joinpath(d,string(id)*"-retry") for d in readdir(root;join=true) if startswith(basename(d),"scan-joint-five-") && isfile(joinpath(d,string(id)*"-retry/result.json"))]
            prior=read_multi_period_security(joinpath(only(paths),"result.json")).periods[3]
            states[id]=prior.states[id];equipment[id]=(;taps=prior.tap_settings[id],shunts=prior.shunt_settings[id])
        end
        starts=[states];eq=[(;taps=p.tap_settings[:base],shunts=p.shunt_settings[:base],scenarios=equipment)];targets=[source.avr_targets[3]]
    elseif phase=="peak"
        factors=[1.05]
        parents=Dict(id=>read_multi_period_security(joinpath(root,"$(id)-original-1p05/result.json")) for id in ids)
        source=parents[:branch_21];starts=[Dict(:base=>source.periods[1].states[:base],
            (id=>parents[id].periods[1].states[id] for id in ids)...)]
        eq=[(;taps=source.periods[1].tap_settings[:base],shunts=source.periods[1].shunt_settings[:base],
            scenarios=Dict(:base=>(;taps=source.periods[1].tap_settings[:base],shunts=source.periods[1].shunt_settings[:base]),
            (id=>(;taps=parents[id].periods[1].tap_settings[id],shunts=parents[id].periods[1].shunt_settings[id]) for id in ids)...))]
        targets=source.avr_targets
    elseif phase in ("five","augment-five")
        factors=[.9,1.,1.05,1.,.9]
        seed=phase=="five" ? "joint-peak" : "joint-augment-polish"
        source=read_multi_period_security(joinpath(root,seed,"result.json"))
        JSON.parsefile(joinpath(root,seed,"summary.json"))["accepted"] || error("peak seed unqualified")
        p=source.periods[1]
        starts=[Dict(id=>ACState(copy(s.vm),copy(s.va),s.pg.*(f/1.05),s.qg.*(f/1.05)) for (id,s) in p.states) for f in factors]
        eq=fill((;taps=p.tap_settings[:base],shunts=p.shunt_settings[:base],
            scenarios=Dict(id=>(;taps=p.tap_settings[id],shunts=p.shunt_settings[id]) for id in keys(p.states))),5)
        targets=fill(source.avr_targets[1],5)
    else
        error("phase must be peak or five")
    end
    controls=[DroopControl(d.control_id;slope_bounds=d.bounds.slope,v_ref_bounds=d.bounds.v_ref,
        initial=source.droops[d.control_id]) for d in x.controls]
    mix_attempt(x,joinpath(root,"joint-"*phase),factors,events;controls,starts,initial_equipment=eq,
        initial_avr_targets=targets,response=:limit_aware,emergency=false,schedule=true,objective_policy=:feasibility,seconds=phase=="augment-polish" ? 60. : 180.,
        solver_options=merge(Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8),
            phase=="augment-polish" ? Dict("hessian_approximation"=>"limited-memory","mu_strategy"=>"monotone","mu_init"=>1e-8) : Dict()))
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    targeted_joint(abspath(ARGS[1]),ARGS[2])
end
