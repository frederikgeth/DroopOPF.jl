# S1 equipment-only families. Fixed calibrated 8% droops; no contingencies.
include("s1_arpae14_joint_sensitivity.jl")
const EQ_OUT=joinpath(GATED_ROOT,"artifacts/s1_arpae14_equipment")
const EQ_CONFIG="zero_q_shifted-loss-uniform8-db0.0"
eq_state(r)=ACState(Float64.(r["vm"]),Float64.(r["va"]),Float64.(r["pg"]),Float64.(r["qg"]))
eq_settings(d)=Dict(parse(Int,k)=>Float64(v) for (k,v) in d)
function eq_policy(c,family)
    all=gated_policies(c)
    (tap_controls=family in ("tap","tap_shunt") ? all.tap_controls : TapControl[],
     shunt_controls=family in ("shunt","tap_shunt") ? all.shunt_controls : ShuntControl[])
end
function eq_details(c,r,angles,policy)
    haskey(r,"state") || return
    s=eq_state(r["state"]);taps=eq_settings(r["taps"]);bs=eq_settings(r["susceptances"])
    replay=validate_feasibility_witness(FeasibilityProblem(c;policy...,angle_limits=angles),FeasibilityWitness(s;taps,susceptances=bs))
    replay["valid"]==r["point_pass"] || error("saved state replay mismatch")
    physical=with_shunt_settings(with_tap_settings(c,taps),bs);flows=branch_flows(physical.network,s)
    idx=DroopOPF._bus_indices(c.network);bm=c.base_power
    r["buses"]=[Dict("id"=>b.id,"vm"=>s.vm[i],"vmin"=>b.v_min,"vmax"=>b.v_max,"lower_margin"=>s.vm[i]-b.v_min,"upper_margin"=>b.v_max-s.vm[i]) for (i,b) in enumerate(c.network.buses)]
    r["generators"]=[Dict("id"=>g.id,"available"=>g.available,"pg_mw"=>s.pg[i]*bm,"qg_mvar"=>s.qg[i]*bm,"pmin_mw"=>g.p_min*bm,"pmax_mw"=>g.p_max*bm,"qmin_mvar"=>g.q_min*bm,"qmax_mvar"=>g.q_max*bm) for (i,g) in enumerate(c.generators)]
    r["branches"]=[Dict("id"=>b.id,"kind"=>string(b.kind),"from"=>b.from_bus,"to"=>b.to_bus,"rating_mva"=>isfinite(b.thermal_limit) ? b.thermal_limit*bm : nothing,
        "from_mva"=>abs(flows.from[i])*bm,"to_mva"=>abs(flows.to[i])*bm,"thermal_margin_mva"=>isfinite(b.thermal_limit) ? (b.thermal_limit-max(abs(flows.from[i]),abs(flows.to[i])))*bm : nothing,
        "angle_rad"=>s.va[idx[b.from_bus]]-s.va[idx[b.to_bus]],"angle_min_rad"=>angles[b.id][1],"angle_max_rad"=>angles[b.id][2],"tap"=>b.tap_ratio) for (i,b) in enumerate(physical.network.branches) if b.available]
    r["tap_movements"]=[Dict("id"=>b.id,"source"=>b.tap_ratio,"value"=>get(taps,b.id,b.tap_ratio),"delta"=>get(taps,b.id,b.tap_ratio)-b.tap_ratio) for b in c.network.branches if b.available && b.kind==:transformer]
    r["shunt_movements"]=[Dict("id"=>b.id,"source_b"=>sum(b.step_susceptances.*b.state),"value_b"=>get(bs,b.id,sum(b.step_susceptances.*b.state)),"delta_b"=>get(bs,b.id,sum(b.step_susceptances.*b.state))-sum(b.step_susceptances.*b.state)) for b in c.network.banks if b.available]
    r["loss_mw"]=(sum(s.pg[i] for (i,g) in enumerate(c.generators) if g.available)-sum(l.p for l in c.loads))*bm
    r["replayed"]=true
end
function run_equipment()
    mkpath(EQ_OUT);source,_,angles,_=gated_inputs()
    manifest=JSON.parsefile(joinpath(GATED_ROOT,"artifacts/s1_arpae14_matched_sensitivity/selected_baseline.json"))
    path=joinpath(GATED_ROOT,manifest["selected_case"])
    bytes2hex(sha256(read(path)))==manifest["sha256"] || error("baseline hash changed")
    c=read_study(path).case;write_study(joinpath(EQ_OUT,"baseline-study.json"),Study(c))
    baseline=[]
    for folder in ("s1_arpae14_matched_sensitivity","s1_arpae14_confirmation")
        path=joinpath(GATED_ROOT,"artifacts",folder,"rows.jsonl")
        for line in readlines(path)
            r=JSON.parse(line);r["tags"]["config"]==EQ_CONFIG || continue
            r["reused_from"]=relpath(path,GATED_ROOT);r["tags"]["family"]="fixed"
            r["name"]="fixed-"*r["name"];push!(baseline,r)
        end
    end
    @assert length(baseline)==30 && all(r["accepted"] for r in baseline)
    seeds=Dict();seedchecks=[]
    for objective in ("cost","loss"),factor in (.9,.95,1.,1.05,1.1)
        if factor in (.9,1.,1.1)
            state,path=js_seed(source,objective,factor)
        else
            path=joinpath(GATED_ROOT,"artifacts/s1_arpae14_confirmation","opf-$objective-$factor.json")
            sol=JSON.parsefile(path)["solution"]
            state=ACState([sol["bus"][string(b.id)]["vm"] for b in source.network.buses],[sol["bus"][string(b.id)]["va"] for b in source.network.buses],
                [get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"] for g in source.generators],[get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"] for g in source.generators])
        end
        audit=validate_feasibility_witness(FeasibilityProblem(DroopOPF._feasibility_scaled_case(source,factor);angle_limits=angles),FeasibilityWitness(state))
        audit["valid"] || error("source precursor failed")
        seeds[(objective,factor)]=state;push!(seedchecks,Dict("objective"=>objective,"factor"=>factor,"hash"=>bytes2hex(sha256(read(path))),"valid"=>true))
    end
    write(joinpath(EQ_OUT,"source_precursors.json"),JSON.json(seedchecks;pretty=true))
    policies=Dict(f=>eq_policy(c,f) for f in ("fixed","tap","shunt","tap_shunt"))
    shunts=[Dict("id"=>x.bank_id,"bounds"=>[DroopOPF._shunt_policy(c,x).lower,DroopOPF._shunt_policy(c,x).upper]) for x in policies["shunt"].shunt_controls]
    write(joinpath(EQ_OUT,"protocol.json"),JSON.json(Dict("baseline_sha256"=>manifest["sha256"],"families"=>DroopOPF._json_data(policies),"shunt_bounds"=>shunts,"smoothing_absolute_pu"=>1e-6,"iterations"=>600,"native_seconds"=>20.,"new_solves"=>90,"reused_baseline"=>30,"tap_bounds_note"=>"plus/minus 5% source tap: exploratory study assumption","shunts"=>"continuous susceptance, not discrete switching","timing"=>"base-case independent solves, no contingencies; settings may differ by demand","droops"=>"all five fixed; uniform 8%, no deadband, nominal loss OPF calibration","objective"=>"unchanged native dispatch deviation" );pretty=true))
    # A fixed-control witness is also a witness for each relaxed equipment family.
    precursors=[]
    for r in baseline
        scaled=DroopOPF._feasibility_scaled_case(c,r["tags"]["factor"])
        for family in keys(policies)
            a=validate_feasibility_witness(FeasibilityProblem(scaled;policies[family]...,angle_limits=angles),FeasibilityWitness(eq_state(r["state"]);taps=eq_settings(r["taps"]),susceptances=eq_settings(r["susceptances"])))
            a["valid"] || error("baseline witness not feasible in relaxed family")
            push!(precursors,Dict("baseline"=>r["name"],"family"=>family,"valid"=>true))
        end
        eq_details(scaled,r,angles,policies["fixed"])
    end
    write(joinpath(EQ_OUT,"inherited_witnesses.json"),JSON.json(precursors;pretty=true))
    ledger=joinpath(EQ_OUT,"rows.jsonl")
    if !isfile(ledger);open(ledger,"w") do io;for r in baseline;println(io,JSON.json(r));end;end;end
    rows=[JSON.parse(s) for s in readlines(ledger)];done=Set(r["name"] for r in rows)
    for family in ("tap","shunt","tap_shunt"),factor in (.9,.95,1.,1.05,1.1),objective in ("cost","loss"),solver in (:ipopt,:madnlp,:ccopt)
        name="$family-$factor-$objective-$solver";name in done && continue
        scaled=DroopOPF._feasibility_scaled_case(c,factor)
        tags=Dict("family"=>family,"factor"=>factor,"initialization_objective"=>objective,"config"=>EQ_CONFIG)
        r=js_cell(scaled,seeds[(objective,factor)],angles,solver,tags;reactive_epsilon=1e-6,policies[family]...)
        r["name"]=name;r["model_gate"]="feasible from retained fixed-equipment witness"
        eq_details(scaled,r,angles,policies[family])
        open(ledger,"a") do io;println(io,JSON.json(r));end
        push!(rows,r);push!(done,name)
        println("EQUIPMENT ",length(rows),"/120 ",name," verified=",r["point_pass"]," accepted=",r["accepted"]);flush(stdout)
    end
    @assert length(rows)==120
    write(joinpath(EQ_OUT,"replay_summary.json"),JSON.json(Dict("cells"=>length(rows),"states_replayed"=>count(r->get(r,"replayed",false),rows),"physical_verified"=>count(r->r["point_pass"],rows),"solver_accepted"=>count(r->r["accepted"],rows),"inherited_witness_checks"=>length(precursors));pretty=true))
end
abspath(PROGRAM_FILE)==(@__FILE__) && run_equipment()
