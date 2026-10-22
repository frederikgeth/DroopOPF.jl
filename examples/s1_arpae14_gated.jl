# Corrected-droop S1 campaign. Separate from the historical stress artifacts.
include("s1_arpae14_stress.jl")
const GATED_ROOT=normpath(joinpath(@__DIR__,".."))
const GATED_OUT=joinpath(GATED_ROOT,"artifacts","s1_arpae14_gated")
const GATED_FACTORS=(.9,1.,1.1)

function gated_inputs()
    source=read_study(joinpath(GATED_ROOT,"artifacts","s1_arpae14_stress","source-study.json")).case
    _,anchor,raw=a14_case()
    angles=Dict(b.id=>(Float64(raw["branch"][string(b.id)]["angmin"]),Float64(raw["branch"][string(b.id)]["angmax"])) for b in source.network.branches)
    candidates=Dict(v=>read_study(joinpath(GATED_ROOT,"artifacts","s1_arpae14_corrected_comparison","verified",v*"-study.json")).case for v in ("no_deadband","with_deadband"))
    source,anchor,angles,candidates
end
function gated_policies(c)
    (tap_controls=[TapControl(b.id;lower=.95*b.tap_ratio,upper=1.05*b.tap_ratio,nominal=b.tap_ratio) for b in c.network.branches if b.available && b.kind==:transformer],
     shunt_controls=[ShuntControl(b.id) for b in c.network.banks if b.available],
     droop_controls=[DroopControl(i;slope_bounds=(.5*d.slope,2*d.slope)) for (i,d) in enumerate(c.controls)])
end
function gated_angles(angles,c,phase,model)
    phase==:built || return
    idx=DroopOPF._bus_indices(c.network)
    for b in c.network.branches
        b.available || continue
        lo,hi=angles[b.id];f=variable_by_name(model,"va[$(idx[b.from_bus])]");t=variable_by_name(model,"va[$(idx[b.to_bus])]")
        @constraint(model,lo<=f-t<=hi)
    end
end
function gated_problem(c,p,angles)
    FeasibilityProblem(c;tap_controls=p.tap_controls,shunt_controls=p.shunt_controls,angle_limits=angles)
end
function gated_precursors(out=GATED_OUT)
    mkpath(out);source,anchor,angles,candidates=gated_inputs();rows=[];baseline=Dict{Float64,FeasibilityResult}()
    # Strict source checks and corrected-curve calibration are prerequisites,
    # never replaced by an optimizer converging to a different calibration point.
    qrows=[]
    for (variant,c) in candidates
        idx=DroopOPF._bus_indices(c.network)
        for a in c.attachments
            g=findfirst(g->g.id==a.generator_id,c.generators);d=c.controls[a.control_id];q=anchor.qg[g]
            half=(d.schedule.v_db_high-d.schedule.v_db_low)/2
            ref=anchor.vm[idx[a.location.bus_id]]+d.slope*q+sign(q)*half
            abs(d.schedule.v_ref-ref)<1e-10 || error("incorrect back-calibrated reference")
            d.q_at_deadband==0. || error("nonzero deadband Q")
            abs(d.slope*(d.capability.q_max-d.capability.q_min)-.04)<1e-12 || error("not 4% droop")
            push!(qrows,Dict("variant"=>variant,"generator"=>a.generator_id,"vg"=>anchor.vm[idx[a.location.bus_id]],
                "pg"=>anchor.pg[g],"qg"=>q,"vref"=>ref,"slope"=>d.slope,"deadband_halfwidth"=>half,
                "qmin"=>d.capability.q_min,"qmax"=>d.capability.q_max))
        end
        for (name,case) in (("source",source),("candidate",c))
            p=FeasibilityProblem(case;angle_limits=angles)
            r=check_feasibility(p;witnesses=[FeasibilityWitness(anchor)],solve_missing=false)
            r.status==:feasible || error("$variant $name calibration failed")
            write_feasibility_result(joinpath(out,"$variant-calibration-$name.json"),p,r)
        end
    end
    write(joinpath(out,"droop_calibration.json"),JSON.json(qrows;pretty=true))
    for factor in GATED_FACTORS
        c=DroopOPF._feasibility_scaled_case(source,factor);p=FeasibilityProblem(c;angle_limits=angles)
        witnesses=FeasibilityWitness[]
        if factor==.9
            s=JSON.parsefile(joinpath(GATED_ROOT,"artifacts","s1_arpae14_source_opf_90","ac_replay_input.json"))["opf"]["state"]
            push!(witnesses,FeasibilityWitness(ACState(Float64.(s["vm"]),Float64.(s["va"]),Float64.(s["pg"]),Float64.(s["qg"]))))
        end
        r=check_feasibility(p;witnesses,initial_states=[anchor],optimizer_attributes=Dict("tol"=>1e-9,"max_iter"=>600,"max_cpu_time"=>20.))
        baseline[factor]=r;write_feasibility_result(joinpath(out,"source-$factor-gate.json"),p,r)
        push!(rows,Dict("variant"=>"source","factor"=>factor,"family"=>"fixed","status"=>string(r.status)))
    end
    for variant in ("no_deadband","with_deadband"),family in (:fixed,:tap,:shunt,:tap_shunt)
        c=candidates[variant];pol=s1_ccopt_family(gated_policies(c),family;count=100)
        witnesses=Dict{String,Vector{FeasibilityWitness}}()
        for factor in GATED_FACTORS
            baseline[factor].status==:feasible && (witnesses["source/$factor"]=[baseline[factor].witness])
        end
        # A saved free-equipment witness is considered only under the declared
        # policy; fixed/partial policies reject any forbidden equipment moves.
        saved=read_joint_design(joinpath(GATED_ROOT,"artifacts","s1_arpae14_objectives_free_equipment",variant*"-feasibility-design.json"))
        witnesses["candidate/0.9"]=[FeasibilityWitness(saved)]
        q=qualify_droop_replacement(source,c;calibration_state=anchor,load_factors=GATED_FACTORS,witnesses,
            initial_states=[anchor],problem_options=(tap_controls=pol.tap_controls,shunt_controls=pol.shunt_controls,angle_limits=angles),
            search_options=(optimizer_attributes=Dict("tol"=>1e-9,"max_iter"=>600,"max_cpu_time"=>20.),))
        write_droop_qualification(joinpath(out,"$variant-$family-qualification.json"),q)
        for (label,p,r) in zip(q.labels,q.problems,q.results)
            startswith(label,"candidate/") || continue
            factor=parse(Float64,split(label,"/")[2])
            write_feasibility_result(joinpath(out,"$variant-$family-$factor-gate.json"),p,r)
            push!(rows,Dict("variant"=>variant,"factor"=>factor,"family"=>string(family),"status"=>string(r.status)))
        end
        println("PRECURSOR ",variant," ",family," ",[(l,r.status) for (l,r) in zip(q.labels,q.results)]);flush(stdout)
    end
    write(joinpath(out,"precursor_summary.json"),JSON.json(rows;pretty=true))
    rows
end

function gated_cell(out,name,c,start,solver,pol,angles,anchor,nominal;tags,calibration_coupled=false)
    row=Dict{String,Any}("name"=>name,"tags"=>tags,"solver"=>string(solver),"gate_status"=>"unresolved","solver_success"=>false,
        "policy_valid"=>false,"calibration_pass"=>false,"elapsed_seconds"=>0.,"diagnostic_only"=>true)
    try
        opts=solver==:ipopt ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>600,"max_cpu_time"=>20.,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive") :
            solver==:madnlp ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>600,"max_wall_time"=>20.,"bound_relax_factor"=>0.) :
            merge(m5_ccopt_options(),s1_ccopt_profile(:tight),Dict{String,Any}("max_iter"=>600,"max_wall_time"=>20.))
        kwargs=solver==:ccopt ? (encoding=:complementarity,) : (optimizer_factory=solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer,)
        measured=@timed optimize_joint_design(c;pol...,initial_state=start,smooth_epsilon=1e-6,
            optimizer_attributes=opts,kwargs...,_measurement_hook=(phase,m)->begin
                gated_angles(angles,c,phase,m)
                calibration_coupled && gated_calibration_hook(nominal,anchor,pol,phase,m)
            end)
        result=measured.value;row["elapsed_seconds"]=measured.time
        write_joint_design(joinpath(out,name*"-design.json"),result)
        check=validate_joint_design(c,result);row["solver_success"]=check.solver_valid;row["policy_valid"]=check.policy_valid
        row["solver_status"]=string(result.opf.termination_status)
        row["objective"]=isfinite(result.opf.objective) ? result.opf.objective : nothing
        row["exact_droop_audit"]=exact_droop_audit(c,result)
        frozen=DroopOPF._joint_droop_case(c,result);p=gated_problem(frozen,pol,angles)
        ws=isnothing(result.opf.state) ? FeasibilityWitness[] : [FeasibilityWitness(result.opf.state;taps=result.taps,susceptances=result.susceptances)]
        gate=check_feasibility(p;witnesses=ws,solve_missing=false)
        write_feasibility_result(joinpath(out,name*"-gate.json"),p,gate)
        row["gate_status"]=string(gate.status);row["point_pass"]=gate.status==:feasible && check.policy_valid
        row["point_checks"]=isempty(ws) ? nothing : validate_feasibility_witness(p,only(ws))
        # Freeze only the optimized curves, preserving source network/demand.
        frozen_nominal=DroopOPF._joint_droop_case(nominal,result)
        calibration=check_feasibility(gated_problem(frozen_nominal,pol,angles);witnesses=[FeasibilityWitness(anchor)],solve_missing=false)
        row["calibration_pass"]=calibration.status==:feasible
        row["frozen_point_pass"]=row["point_pass"]
        if calibration_coupled
            row["policy_valid"] &= row["calibration_pass"]
            row["point_pass"] &= row["calibration_pass"]
        end
        row["frozen_curve_fingerprint"]=DroopOPF._feasibility_case_hash(frozen_nominal)
        row["diagnostic_only"]=!row["calibration_pass"] || !row["point_pass"]
    catch err
        err isa InterruptException && rethrow()
        row["error"]=sprint(showerror,err)
    end
    write(joinpath(out,name*"-diagnostics.json"),JSON.json(row;pretty=true))
    println(name," => ",get(row,"solver_status","error")," gate=",row["gate_status"]," calibrated=",row["calibration_pass"]);flush(stdout)
    row
end

function gated_matrix(out=GATED_OUT;families=S1_CCOPT_FAMILIES)
    source,anchor,angles,candidates=gated_inputs();mkpath(out)
    isfile(joinpath(out,"precursor_summary.json")) || error("run precursors first")
    rows=isfile(joinpath(out,"matrix_summary.json")) ? JSON.parsefile(joinpath(out,"matrix_summary.json")) : Any[]
    done=Set(r["name"] for r in rows)
    empty=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
    for factor in GATED_FACTORS,mode in (:anchor,),solver in (:ipopt,:madnlp,:ccopt)
        name="source-$factor-$mode-$solver";name in done && continue
        row=gated_cell(out,name,DroopOPF._feasibility_scaled_case(source,factor),a14_start(source,anchor,mode),solver,empty,angles,anchor,source;
            tags=Dict("variant"=>"source","factor"=>factor,"family"=>"fixed","start"=>string(mode)))
        push!(rows,row);write(joinpath(out,"matrix_summary.json"),JSON.json(rows;pretty=true))
    end
    for variant in ("no_deadband","with_deadband"),factor in GATED_FACTORS,family in families,mode in (:anchor,),solver in (:ipopt,:madnlp,:ccopt)
        name="$variant-$factor-$family-$mode-$solver";name in done && continue
        c=candidates[variant];pol=s1_ccopt_family(gated_policies(c),family;count=100)
        mode==:anchor || (pol=s1_reseed(c,pol;fraction=mode==:flat_low ? .2 : .8))
        row=gated_cell(out,name,DroopOPF._feasibility_scaled_case(c,factor),a14_start(c,anchor,mode),solver,pol,angles,anchor,c;
            tags=Dict("variant"=>variant,"factor"=>factor,"family"=>string(family),"start"=>string(mode)))
        push!(rows,row);write(joinpath(out,"matrix_summary.json"),JSON.json(rows;pretty=true))
    end
    println("MATRIX COMPLETE ",length(rows));flush(stdout)
end

# Reconcile diagnostics into qualification only after freezing the candidate.
# Raw convergence and a feasible point at one demand are never enough.
function gated_finalize(out=GATED_OUT)
    source,anchor,angles,candidates=gated_inputs()
    rows=JSON.parsefile(joinpath(out,"matrix_summary.json"));summary=[]
    coupled_path=joinpath(out,"calibrated_matrix_summary.json")
    if isfile(coupled_path)
        free=Set(("droop","tap_droop","shunt_droop","joint"))
        rows=vcat([r for r in rows if !(r["tags"]["family"] in free)],JSON.parsefile(coupled_path))
    end
    for row in rows
        if get(row["tags"],"calibration_coupled",false)
            row["frozen_point_pass"]=get(row,"frozen_point_pass",get(row,"point_pass",false))
            row["point_pass"]=row["frozen_point_pass"] && row["calibration_pass"]
            row["policy_valid"] &= row["calibration_pass"]
        end
    end
    for variant in ("no_deadband","with_deadband"),family in (:fixed,:tap,:shunt,:tap_shunt)
        candidate=candidates[variant];pol=s1_ccopt_family(gated_policies(candidate),family;count=100)
        witnesses=Dict{String,Vector{FeasibilityWitness}}()
        for factor in GATED_FACTORS
            for (label,c,path) in (("source",source,"source-$factor-gate.json"),("candidate",candidate,"$variant-$family-$factor-gate.json"))
                problem=label=="source" ? FeasibilityProblem(DroopOPF._feasibility_scaled_case(c,factor);angle_limits=angles) :
                    gated_problem(DroopOPF._feasibility_scaled_case(c,factor),pol,angles)
                r=read_feasibility_result(joinpath(out,path),problem)
                witnesses["$label/$factor"]=r.status==:feasible ? [r.witness] : FeasibilityWitness[]
            end
            for row in rows
                tags=row["tags"]
                tags["variant"]==variant && tags["family"]==string(family) && tags["factor"]==factor && get(row,"point_pass",false) || continue
                result=read_joint_design(joinpath(out,row["name"]*"-design.json"))
                push!(witnesses["candidate/$factor"],FeasibilityWitness(result))
            end
        end
        q=qualify_droop_replacement(source,candidate;calibration_state=anchor,load_factors=GATED_FACTORS,witnesses,
            problem_options=(tap_controls=pol.tap_controls,shunt_controls=pol.shunt_controls,angle_limits=angles),
            search_options=(solve_missing=false,))
        accepted=try require_qualified_replacement(q);true catch e; e isa ArgumentError || rethrow();false end
        write_droop_qualification(joinpath(out,"$variant-$family-final-qualification.json"),q)
        # Reuse expensive evidence only for the exact same frozen scope, and
        # independently replay its bound proofs. Unresolved remains unresolved.
        evidence=[]
        if family==:fixed
            index=findfirst(==("candidate/0.9"),q.labels);p=q.problems[index]
            for suffix in (".json","-strict-global.json")
                path=joinpath(GATED_ROOT,"artifacts","s1_cycle_feasibility",variant*suffix)
                r=read_feasibility_result(path,p)
                suffix==".json" && verified_feasibility_voltage_bounds(p,r)
                push!(evidence,Dict("path"=>relpath(path,GATED_ROOT),"status"=>string(r.status),"scope_verified"=>true))
            end
        end
        push!(summary,Dict("variant"=>variant,"family"=>string(family),"qualified"=>accepted,
            "conditions"=>Dict(l=>string(r.status) for (l,r) in zip(q.labels,q.results)),"reused_escalation"=>evidence))
        for row in rows
            tags=row["tags"]
            tags["variant"]==variant && tags["family"]==string(family) || continue
            row["scope_gate_status"]=string(q.results[findfirst(==("candidate/$(tags["factor"])"),q.labels)].status)
            row["replacement_qualified"]=accepted
            row["diagnostic_only"]=!accepted || !get(row,"point_pass",false)
        end
    end
    # Optimized slopes change the candidate. Even when a point passes, test the
    # frozen curves against calibration and all demand conditions separately.
    cache=Dict{String,Bool}()
    for row in rows
        tags=row["tags"];variant=tags["variant"]
        variant=="source" && continue
        family=Symbol(tags["family"]);family in (:droop,:tap_droop,:shunt_droop,:joint) || continue
        row["replacement_qualified"]=false;row["diagnostic_only"]=true
        get(row,"point_pass",false) && get(row,"calibration_pass",false) || continue
        c=candidates[variant];result=read_joint_design(joinpath(out,row["name"]*"-design.json"))
        candidate=DroopOPF._joint_droop_case(c,result);pol=s1_ccopt_family(gated_policies(c),family;count=100)
        key=string(family)*row["frozen_curve_fingerprint"]
        if !haskey(cache,key)
            witnesses=Dict{String,Vector{FeasibilityWitness}}()
            for factor in GATED_FACTORS
                p=FeasibilityProblem(DroopOPF._feasibility_scaled_case(source,factor);angle_limits=angles)
                r=read_feasibility_result(joinpath(out,"source-$factor-gate.json"),p)
                witnesses["source/$factor"]=r.status==:feasible ? [r.witness] : FeasibilityWitness[]
            end
            witnesses["candidate/$(tags["factor"])"]=[FeasibilityWitness(result.opf.state;taps=result.taps,susceptances=result.susceptances)]
            q=qualify_droop_replacement(source,candidate;calibration_state=anchor,load_factors=GATED_FACTORS,witnesses,
                problem_options=(tap_controls=pol.tap_controls,shunt_controls=pol.shunt_controls,angle_limits=angles),
                search_options=(optimizer_attributes=Dict("tol"=>1e-9,"max_iter"=>600,"max_cpu_time"=>10.),))
            cache[key]=try require_qualified_replacement(q);true catch e; e isa ArgumentError || rethrow();false end
            write_droop_qualification(joinpath(out,row["name"]*"-qualification.json"),q)
        end
        row["replacement_qualified"]=cache[key];row["diagnostic_only"]=!cache[key]
    end
    for row in rows
        row["qualification_reason"]=row["tags"]["variant"]=="source" ? "source baseline" :
            !get(row,"policy_valid",false) ? "design policy failed" :
            !get(row,"calibration_pass",false) ? "optimized curves do not reproduce source calibration" :
            !get(row,"replacement_qualified",false) ? "required demand-scope qualification unresolved" :
            !get(row,"point_pass",false) ? "candidate qualified, but this solver attempt has no verified point" :
            "calibration, required demand scope, and this operating point verified"
    end
    write(joinpath(out,"primary_matrix_summary.json"),JSON.json(rows;pretty=true))
    for row in rows
        write(joinpath(out,row["name"]*"-diagnostics.json"),JSON.json(row;pretty=true))
    end
    coupled=[r for r in rows if get(r["tags"],"calibration_coupled",false)]
    isempty(coupled) || write(joinpath(out,"calibrated_matrix_summary.json"),JSON.json(coupled;pretty=true))
    write(joinpath(out,"qualification_summary.json"),JSON.json(summary;pretty=true))
    println("QUALIFICATION COMPLETE; nominal families qualified ",count(r->r["qualified"],summary),"/",length(summary),
        "; calibrated optimized candidates tested ",length(cache));flush(stdout)
end

function gated_assert_inputs(out=GATED_OUT)
    path=joinpath(out,"protocol.json")
    isfile(path) || return
    protocol=JSON.parsefile(path)
    for (file,digest) in protocol["input_sha256"]
        bytes2hex(sha256(read(joinpath(GATED_ROOT,file))))==digest || error("input changed since campaign began: $file")
    end
end
function gated_calibration_data(c,anchor,id)
    a=only(a for a in c.attachments if a.control_id==id)
    gi=findfirst(g->g.id==a.generator_id,c.generators);bi=findfirst(b->b.id==a.location.bus_id,c.network.buses)
    d=c.controls[id];q=anchor.qg[gi];settings=DroopSettings(d)
    offset=q>0 ? settings.deadband_low : q<0 ? -settings.deadband_high : 0.
    anchor.vm[bi]+offset,q
end
function gated_calibration_policy(c,anchor,pol)
    controls=DroopControl[]
    for control in pol.droop_controls
        base,q=gated_calibration_data(c,anchor,control.control_id)
        lo,hi=control.bounds.slope
        refs=minmax(base+q*lo,base+q*hi)
        initial=isnothing(control.initial) ? DroopSettings(c.controls[control.control_id]) : control.initial
        initial=DroopSettings(initial.slope,base+q*initial.slope,initial.deadband_low,initial.deadband_high)
        push!(controls,DroopControl(control.control_id;slope_bounds=(lo,hi),v_ref_bounds=refs,initial))
    end
    merge(pol,(droop_controls=controls,))
end
function gated_calibration_hook(c,anchor,pol,phase,model)
    phase==:built || return
    for control in pol.droop_controls
        base,q=gated_calibration_data(c,anchor,control.control_id)
        slope=variable_by_name(model,"design_$(control.control_id)_slope")
        reference=variable_by_name(model,"design_$(control.control_id)_v_ref")
        if isnothing(reference)
            abs(q)<=1e-15 || error("unexpected fixed calibration reference")
        else
            @constraint(model,reference==base+q*slope)
        end
    end
end
function gated_calibrated_matrix(out=GATED_OUT)
    source,anchor,angles,candidates=gated_inputs()
    path=joinpath(out,"calibrated_matrix_summary.json")
    rows=isfile(path) ? JSON.parsefile(path) : Any[];done=Set(r["name"] for r in rows)
    for variant in ("no_deadband","with_deadband"),factor in GATED_FACTORS,family in (:droop,:tap_droop,:shunt_droop,:joint),mode in (:anchor,),solver in (:ipopt,:madnlp,:ccopt)
        name="calibrated-$variant-$factor-$family-$mode-$solver";name in done && continue
        c=candidates[variant];pol=s1_ccopt_family(gated_policies(c),family;count=100)
        mode==:anchor || (pol=s1_reseed(c,pol;fraction=mode==:flat_low ? .2 : .8))
        pol=gated_calibration_policy(c,anchor,pol)
        row=gated_cell(out,name,DroopOPF._feasibility_scaled_case(c,factor),a14_start(c,anchor,mode),solver,pol,angles,anchor,c;
            tags=Dict("variant"=>variant,"factor"=>factor,"family"=>string(family),"start"=>string(mode),"calibration_coupled"=>true),calibration_coupled=true)
        push!(rows,row);write(path,JSON.json(rows;pretty=true))
    end
    println("CALIBRATED MATRIX COMPLETE ",length(rows));flush(stdout)
end

if abspath(PROGRAM_FILE)==@__FILE__
    gated_assert_inputs()
    mode=isempty(ARGS) ? "precursors" : ARGS[1]
    mode=="precursors" ? gated_precursors() : mode=="fixed" ? gated_matrix(;families=(:fixed,)) :
        mode=="matrix" ? gated_matrix() : mode=="calibrated" ? gated_calibrated_matrix() : mode=="finalize" ? gated_finalize() : error("unknown mode")
    gated_assert_inputs()
end
