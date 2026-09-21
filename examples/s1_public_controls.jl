include("s1_experiments.jl")

"""Explicit synthetic overlay anchored to a validated fixed-equipment solution."""
function s1_public_overlay(case,anchor,source;bank_count=12)
    validate_joint_design(case,anchor).valid || error("public baseline must independently validate first")
    isempty(case.controls) && isempty(case.network.banks) || error("overlay expects an imported uncontrolled case")
    indices=Dict(b.id=>i for (i,b) in enumerate(case.network.buses))
    controls=VoltVarDroop[];attachments=GeneratorControlAttachment[];excluded=[]
    for (i,g) in enumerate(case.generators)
        q=anchor.opf.state.qg[i]
        if !g.available || min(q-g.q_min,g.q_max-q)<=1e-3
            push!(excluded,Dict("generator_id"=>g.id,"reason"=>"unavailable or less than 1e-3 pu Q headroom at anchor"))
            continue
        end
        v=anchor.opf.state.vm[indices[g.bus_id]]
        slope=.04/(g.q_max-g.q_min)
        cap=ReactiveCapability(p_min=g.p_min,p_max=g.p_max,q_min=g.q_min,q_max=g.q_max)
        push!(controls,VoltVarDroop(VoltageSchedule(v;v_db_low=v-.005,v_db_high=v+.005),slope,q,cap))
        push!(attachments,GeneratorControlAttachment(g.id,length(controls),RegulatedLocation(:bus,g.bus_id)))
    end
    ranked=sort([l for l in case.loads if l.q>0];by=l->(-l.q,l.bus_id))
    bus_ids=unique(l.bus_id for l in ranked)[1:min(bank_count,length(unique(l.bus_id for l in ranked)))]
    banks=[ShuntBank(100000+id,id;step_susceptances=(isodd(k) ? .01 : -.01,),
        step_conductances=(0.,),legal_states=[(i,) for i in 0:4],state=(0,)) for (k,id) in enumerate(bus_ids)]
    net=case.network
    overlay=Case(case.id*"-s1-overlay";base_power=case.base_power,base_frequency=case.base_frequency,
        network=ACNetwork(net.buses,net.branches;shunts=net.shunts,banks),
        loads=case.loads,generators=case.generators,controls,attachments)
    table=DroopOPF._matpower_array(read(source,String),"branch")
    taps=[TapControl(b.id;lower=.95*b.tap_ratio,upper=1.05*b.tap_ratio,nominal=b.tap_ratio)
        for (i,b) in enumerate(net.branches) if b.available && table[i,9]!=0.]
    policies=(tap_controls=taps,shunt_controls=[ShuntControl(b.id) for b in banks],
        droop_controls=[DroopControl(i;slope_bounds=(.5*c.slope,2*c.slope)) for (i,c) in enumerate(controls)])
    metadata=Dict("kind"=>"synthetic study overlay, not measured equipment",
        "source_sha256"=>bytes2hex(sha256(read(source))),"excluded_generators"=>excluded,
        "droop_rule"=>"available generators with >1e-3 pu Q headroom; q0 and reference voltage from independently validated anchor; half-deadbands 0.005 pu; slope 0.04/(Qmax-Qmin); free slope range 0.5 to 2 times nominal",
        "tap_rule"=>"available branches with explicit nonzero MATPOWER TAP; synthetic ratio bounds 0.95 to 1.05 times supplied ratio; phase fixed",
        "bank_rule"=>"largest positive-Q load buses ordered by Q then bus ID; alternating capacitor/reactor single-step banks; step +/-0.01 pu B, G=0; legal counts 0:4; initially disconnected",
        "bank_count"=>length(banks),"tap_count"=>length(taps),"droop_count"=>length(controls),
        "unchanged"=>"network branches, supplied fixed shunts, generator capabilities and dispatch references",
        "costs_imported"=>false,"source_angle_limits_enforced"=>false)
    return overlay,policies,metadata
end

function s1_source_audit(case,result,source)
    (isnothing(result) || isnothing(result.opf.state)) && return nothing
    table=DroopOPF._matpower_array(read(source,String),"branch")
    state=result.opf.state;indices=Dict(b.id=>i for (i,b) in enumerate(case.network.buses))
    angles=[rad2deg(state.va[indices[b.from_bus]]-state.va[indices[b.to_bus]]) for b in case.network.branches]
    angle_violation=maximum(max(table[i,12]-angles[i],angles[i]-table[i,13],0.) for i in eachindex(angles) if table[i,11]>0)
    regimes=Dict("deadband"=>0,"sloping"=>0,"saturated"=>0)
    replay=with_joint_settings(case,result)
    for a in replay.attachments
        c=replay.controls[a.control_id];v=state.vm[indices[a.location.bus_id]]
        q=state.qg[findfirst(g->g.id==a.generator_id,replay.generators)]
        key=(abs(q-c.capability.q_min)<1e-5 || abs(q-c.capability.q_max)<1e-5) ? "saturated" :
            c.schedule.v_db_low<=v<=c.schedule.v_db_high ? "deadband" : "sloping"
        regimes[key]+=1
    end
    Dict("source_angle_violation_degrees"=>angle_violation,"droop_regions"=>regimes)
end

function s1_public_controls(out)
    mkpath(out);rows=[]
    for n in (118,300)
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        case=load_matpower_case(source;base_frequency=60.)
        row,anchor=s1_attempt(out,"public$n-baseline",case,s1_flat(case);tags=Dict("study"=>"public_baseline"))
        push!(rows,row);s1_summary(out,rows)
        row["valid"] || continue
        row["source_audit"]=s1_source_audit(case,anchor,source)
        write_study(joinpath(out,"public$n-original.json"),Study(case))
        c,p,metadata=s1_public_overlay(case,anchor,source;bank_count=n==118 ? 12 : 32)
        write(joinpath(out,"public$n-overlay.json"),JSON.json(metadata;pretty=true))
        write_study(joinpath(out,"public$n-controls.json"),Study(c))
        # Every start uses the same physical case, bounds, objective and smoothing.
        for factor in (1.,1.05)
            stressed=s1_load(c,factor)
            write_study(joinpath(out,"public$n-load$factor.json"),Study(stressed))
            for solver in (:ipopt,:madnlp),mode in (:anchor,:flat_low,:flat_high)
                policy=mode==:anchor ? p : s1_reseed(c,p;fraction=mode==:flat_low ? .2 : .8)
                state=mode==:anchor ? anchor.opf.state : s1_flat(c)
                row,r=s1_attempt(out,"public$n-load$factor-$solver-$mode",stressed,state;policies=policy,solver,
                    tags=Dict("study"=>"public_joint","load_factor"=>factor,"start"=>string(mode)))
                if get(row,"physical_valid",false) && get(row,"policy_valid",false)
                    row["source_audit"]=s1_source_audit(stressed,r,source)
                end
                push!(rows,row);s1_summary(out,rows)
            end
        end
        for fraction in (0.,.5)
            selected=(tap_controls=p.tap_controls[1:floor(Int,fraction*length(p.tap_controls))],
                shunt_controls=p.shunt_controls[1:floor(Int,fraction*length(p.shunt_controls))],
                droop_controls=p.droop_controls[1:floor(Int,fraction*length(p.droop_controls))])
            row,r=s1_attempt(out,"public$n-count$fraction",c,anchor.opf.state;policies=selected,
                tags=Dict("study"=>"public_count","fraction"=>fraction))
            get(row,"physical_valid",false) && get(row,"policy_valid",false) && (row["source_audit"]=s1_source_audit(c,r,source))
            push!(rows,row);s1_summary(out,rows)
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_public_controls(abspath(ARGS[1]))
