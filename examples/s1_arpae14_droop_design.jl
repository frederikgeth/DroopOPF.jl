# S1 slope design and frozen nominal design demand replay, no contingencies.
include("s1_arpae14_equipment.jl")
const DD_OUT=joinpath(GATED_ROOT,"artifacts/s1_arpae14_droop_design")
const DD_FAMILIES=("droop","tap_droop","shunt_droop","joint")
function dd_policy(c,family)
    equipment=eq_policy(c,family=="droop" ? "fixed" : family=="tap_droop" ? "tap" : family=="shunt_droop" ? "shunt" : "tap_shunt")
    ds=[DroopControl(i;slope_bounds=(.02/(d.capability.q_max-d.capability.q_min),.08/(d.capability.q_max-d.capability.q_min))) for (i,d) in enumerate(c.controls)]
    (;equipment...,droop_controls=ds)
end
function dd_seed(source,objective,factor)
    factor in (.9,1.,1.1) && return js_seed(source,objective,factor)
    path=joinpath(GATED_ROOT,"artifacts/s1_arpae14_confirmation","opf-$objective-$factor.json")
    sol=JSON.parsefile(path)["solution"]
    s=ACState([sol["bus"][string(b.id)]["vm"] for b in source.network.buses],[sol["bus"][string(b.id)]["va"] for b in source.network.buses],
        [get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"] for g in source.generators],[get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"] for g in source.generators])
    s,path
end
function dd_cell(c,start,angles,solver,family,name;policy=nothing,out=DD_OUT,objective_hook=nothing)
    p=isnothing(policy) ? dd_policy(c,family) : policy
    opts=solver==:ipopt ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>600,"max_cpu_time"=>20.,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive","print_level"=>0) :
         solver==:madnlp ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>600,"max_wall_time"=>20.,"bound_relax_factor"=>0.) :
         merge(m5_ccopt_options(),s1_ccopt_profile(:tight),Dict{String,Any}("max_iter"=>600,"max_wall_time"=>20.))
    kwargs=solver==:ccopt ? (encoding=:complementarity,) : (optimizer_factory=solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer,)
    timed=@timed optimize_joint_design(c;initial_state=start,smooth_epsilon=1e-6,smooth_reactive_epsilon=1e-6,p...,optimizer_attributes=opts,kwargs...,_measurement_hook=(phase,m)->begin
        gated_angles(angles,c,phase,m)
        isnothing(objective_hook) || objective_hook(phase,m)
    end)
    result=timed.value;check=validate_joint_design(c,result)
    write_joint_design(joinpath(out,"$name-result.json"),result)
    r=Dict{String,Any}("name"=>name,"solver"=>string(solver),"elapsed_seconds"=>timed.time,"solver_status"=>string(result.opf.termination_status),"solver_success"=>check.solver_valid,"policy_valid"=>check.policy_valid,"point_pass"=>false,"accepted"=>false,"objective"=>isfinite(result.opf.objective) ? result.opf.objective : nothing)
    if result.opf.state!==nothing
        curve= DroopOPF._joint_droop_case(c,result)
        policy=(tap_controls=p.tap_controls,shunt_controls=p.shunt_controls)
        audit=validate_feasibility_witness(FeasibilityProblem(curve;policy...,angle_limits=angles),FeasibilityWitness(result.opf.state;taps=result.taps,susceptances=result.susceptances))
        r["point_pass"]=audit["valid"] && check.policy_valid;r["accepted"]=r["point_pass"] && check.solver_valid
        r["point_checks"]=DroopOPF._json_data(audit);r["state"]=DroopOPF._json_data(result.opf.state)
        r["taps"]=DroopOPF._json_data(result.taps);r["susceptances"]=DroopOPF._json_data(result.susceptances)
        r["droops"]=DroopOPF._json_data(result.droops)
        r["slopes_percent"]=[100*d.slope*(d.capability.q_max-d.capability.q_min) for d in curve.controls]
        r["reference_movements"]=[curve.controls[i].schedule.v_ref-c.controls[i].schedule.v_ref for i in eachindex(c.controls)]
        eq_details(curve,r,angles,policy)
    end
    r
end
function run_droop_design()
    mkpath(DD_OUT);source,_,angles,_=gated_inputs();base=read_study(joinpath(EQ_OUT,"baseline-study.json")).case
    write_study(joinpath(DD_OUT,"baseline-study.json"),Study(base))
    seeds=Dict();checks=[]
    for factor in (.9,.95,1.,1.05,1.1),objective in ("cost","loss")
        s,path=dd_seed(source,objective,factor)
        a=validate_feasibility_witness(FeasibilityProblem(DroopOPF._feasibility_scaled_case(source,factor);angle_limits=angles),FeasibilityWitness(s));@assert a["valid"]
        seeds[(objective,factor)]=s;push!(checks,Dict("factor"=>factor,"objective"=>objective,"sha256"=>bytes2hex(sha256(read(path))),"valid"=>true))
    end
    write(joinpath(DD_OUT,"source_precursors.json"),JSON.json(checks;pretty=true))
    inherited=[]
    for line in readlines(joinpath(EQ_OUT,"rows.jsonl"))
        r=JSON.parse(line);r["tags"]["family"]=="fixed" || continue
        c=DroopOPF._feasibility_scaled_case(base,r["tags"]["factor"])
        for family in DD_FAMILIES
            p=dd_policy(c,family)
            for d in p.droop_controls;@assert DroopOPF._joint_droop_policy(c,d).ranges.slope[1]<=c.controls[d.control_id].slope<=DroopOPF._joint_droop_policy(c,d).ranges.slope[2];end
            a=validate_feasibility_witness(FeasibilityProblem(c;tap_controls=p.tap_controls,shunt_controls=p.shunt_controls,angle_limits=angles),FeasibilityWitness(eq_state(r["state"]);taps=eq_settings(r["taps"]),susceptances=eq_settings(r["susceptances"])));@assert a["valid"]
            push!(inherited,Dict("source"=>r["name"],"family"=>family,"valid"=>true))
        end
    end
    write(joinpath(DD_OUT,"inherited_witnesses.json"),JSON.json(inherited;pretty=true))
    write(joinpath(DD_OUT,"protocol.json"),JSON.json(Dict("families"=>collect(DD_FAMILIES),"slopes_percent_bounds"=>[2,8],"references"=>"fixed at nominal loss-OPF-calibrated 8% references; not recalibrated as slopes change","deadband"=>0,"equipment"=>"same all-device policies as equipment campaign","design_cells"=>120,"frozen_cells"=>120,"selection"=>"one best accepted nominal-demand design per family, objective first then name; no out-of-demand selection","frozen_scope"=>"all droops, taps and shunts fixed at selected nominal design values","objective"=>"unchanged dispatch deviation","smoothing_voltage_and_absolute_q"=>1e-6,"max_iter"=>600,"native_seconds"=>20);pretty=true))
    ledger=joinpath(DD_OUT,"design_rows.jsonl");rows=isfile(ledger) ? [JSON.parse(s) for s in readlines(ledger)] : Any[];done=Set(r["name"] for r in rows)
    for family in DD_FAMILIES,factor in (.9,.95,1.,1.05,1.1),objective in ("cost","loss"),solver in (:ipopt,:madnlp,:ccopt)
        name="$family-$factor-$objective-$solver";name in done && continue
        c=DroopOPF._feasibility_scaled_case(base,factor)
        r=dd_cell(c,seeds[(objective,factor)],angles,solver,family,name)
        r["tags"]=Dict("family"=>family,"factor"=>factor,"initialization_objective"=>objective)
        r["model_gate"]="feasible: retained baseline witness within design bounds"
        open(ledger,"a") do io;println(io,JSON.json(r));end;push!(rows,r)
        println("DESIGN ",length(rows),"/120 ",name," accepted=",r["accepted"]);flush(stdout)
    end
    @assert length(rows)==120
    frozenledger=joinpath(DD_OUT,"frozen_rows.jsonl");frozenrows=isfile(frozenledger) ? [JSON.parse(s) for s in readlines(frozenledger)] : Any[];done=Set(r["name"] for r in frozenrows);selected=[]
    for family in DD_FAMILIES
        candidates=filter(r->r["tags"]["family"]==family && r["tags"]["factor"]==1. && r["accepted"],rows)
        isempty(candidates) && error("no accepted nominal design $family")
        chosen=first(sort(candidates;by=r->(r["objective"],r["name"])))
        result=read_joint_design(joinpath(DD_OUT,chosen["name"]*"-result.json"))
        frozen=with_joint_settings(base,result)
        frozenpath=joinpath(DD_OUT,"$family-frozen-study.json");write_study(frozenpath,Study(frozen))
        # The selected design itself must witness the frozen nominal model.
        a=validate_feasibility_witness(FeasibilityProblem(frozen;angle_limits=angles),FeasibilityWitness(result.opf.state));@assert a["valid"]
        push!(selected,Dict("family"=>family,"source"=>chosen["name"],"sha256"=>bytes2hex(sha256(read(frozenpath))),"slopes_percent"=>chosen["slopes_percent"],"nominal_witness_valid"=>true))
        for factor in (.9,.95,1.,1.05,1.1),objective in ("cost","loss"),solver in (:ipopt,:madnlp,:ccopt)
            name="frozen-$family-$factor-$objective-$solver";name in done && continue
            c=DroopOPF._feasibility_scaled_case(frozen,factor)
            tags=Dict("family"=>family,"factor"=>factor,"initialization_objective"=>objective,"selected_design"=>chosen["name"])
            r=js_cell(c,seeds[(objective,factor)],angles,solver,tags;reactive_epsilon=1e-6);r["name"]=name
            eq_details(c,r,angles,eq_policy(c,"fixed"))
            open(frozenledger,"a") do io;println(io,JSON.json(r));end;push!(frozenrows,r)
            println("FROZEN ",length(frozenrows),"/120 ",name," accepted=",r["accepted"]);flush(stdout)
        end
    end
    @assert length(frozenrows)==120
    write(joinpath(DD_OUT,"selected_designs.json"),JSON.json(selected;pretty=true))
end
abspath(PROGRAM_FILE)==(@__FILE__) && run_droop_design()
