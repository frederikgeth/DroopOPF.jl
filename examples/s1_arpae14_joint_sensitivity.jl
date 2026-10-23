# S1 fixed-equipment joint sensitivity. Source OPF seeds only; no contingencies.
include("s1_arpae14_gated.jl")
const JS_OUT=joinpath(GATED_ROOT,"artifacts/s1_arpae14_joint_sensitivity")
const JS_PROFILES=[("uniform2",[2.,2.,2.,2.,2.]),("uniform4",[4.,4.,4.,4.,4.]),("uniform8",[8.,8.,8.,8.,8.]),("mixed24842",[2.,4.,8.,4.,2.]),("mixed84248",[8.,4.,2.,4.,8.])]
const JS_EMPTY=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
function js_seed(source,objective,factor)
    folder=objective=="cost" ? "s1_arpae14_demand_anchors" : "s1_arpae14_loss_anchors"
    path=joinpath(GATED_ROOT,"artifacts",folder,"opf-$factor.json")
    sol=JSON.parsefile(path)["solution"]
    state=ACState([sol["bus"][string(b.id)]["vm"] for b in source.network.buses],
        [sol["bus"][string(b.id)]["va"] for b in source.network.buses],
        [get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"] for g in source.generators],
        [get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"] for g in source.generators])
    state,path
end
function js_case(base,anchor,definition,percentages,halfwidth,id)
    idx=DroopOPF._bus_indices(base.network);controls=copy(base.controls)
    for a in base.attachments
        ci=a.control_id;d=base.controls[ci]
        gi=findfirst(g->g.id==a.generator_id,base.generators)
        q=anchor.qg[gi];vm=anchor.vm[idx[a.location.bus_id]]
        slope=(percentages[ci]/100)/(d.capability.q_max-d.capability.q_min)
        q0=definition=="opf_q_centered" ? q : 0.
        ref=definition=="zero_q_shifted" ? vm+slope*q+sign(q)*halfwidth : vm
        schedule=VoltageSchedule(ref;v_db_low=ref-halfwidth,v_db_high=ref+halfwidth)
        controls[ci]=VoltVarDroop(schedule,slope,q0,d.capability)
    end
    Case(id;base_power=base.base_power,base_frequency=base.base_frequency,
        network=base.network,generators=base.generators,loads=base.loads,controls,attachments=base.attachments)
end
function js_cell(c,start,angles,solver,tags;reactive_epsilon=nothing,
    tap_controls=TapControl[],shunt_controls=ShuntControl[],objective_hook=nothing)
    row=Dict{String,Any}("tags"=>tags,"solver"=>string(solver),"point_pass"=>false,"solver_success"=>false,"accepted"=>false,"gate_status"=>"unresolved")
    try
        opts=solver==:ipopt ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>600,"max_cpu_time"=>20.,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive","print_level"=>0) :
            solver==:madnlp ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>600,"max_wall_time"=>20.,"bound_relax_factor"=>0.) :
            merge(m5_ccopt_options(),s1_ccopt_profile(:tight),Dict{String,Any}("max_iter"=>600,"max_wall_time"=>20.))
        kwargs=solver==:ccopt ? (encoding=:complementarity,) : (optimizer_factory=solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer,)
        measurement=@timed optimize_joint_design(c;initial_state=start,smooth_epsilon=1e-6,
            smooth_reactive_epsilon=reactive_epsilon,tap_controls,shunt_controls,optimizer_attributes=opts,kwargs...,_measurement_hook=(phase,m)->begin
                gated_angles(angles,c,phase,m)
                isnothing(objective_hook) || objective_hook(phase,m)
            end)
        result=measurement.value;check=validate_joint_design(c,result)
        row["elapsed_seconds"]=measurement.time
        row["solver_status"]=string(result.opf.termination_status)
        row["solver_success"]=check.solver_valid;row["policy_valid"]=check.policy_valid
        row["objective"]=isfinite(result.opf.objective) ? result.opf.objective : nothing
        if result.opf.state!==nothing
            p=FeasibilityProblem(c;tap_controls,shunt_controls,angle_limits=angles)
            witness=FeasibilityWitness(result.opf.state;taps=result.taps,susceptances=result.susceptances)
            audit=validate_feasibility_witness(p,witness)
            row["point_checks"]=DroopOPF._json_data(audit)
            row["point_pass"]=audit["valid"] && check.policy_valid
            row["gate_status"]=row["point_pass"] ? "feasible" : "unresolved"
            row["accepted"]=row["point_pass"] && check.solver_valid
            row["state"]=DroopOPF._json_data(result.opf.state)
            row["taps"]=DroopOPF._json_data(result.taps)
            row["susceptances"]=DroopOPF._json_data(result.susceptances)
        end
    catch err
        err isa InterruptException && rethrow()
        row["error"]=sprint(showerror,err)
    end
    row
end
function run_joint_sensitivity(out=JS_OUT;reactive_epsilon=nothing)
    mkpath(out);source,_,angles,candidates=gated_inputs();base=candidates["no_deadband"]
    seeds=Dict();seedchecks=[]
    for objective in ("cost","loss"),factor in GATED_FACTORS
        state,path=js_seed(source,objective,factor)
        c=DroopOPF._feasibility_scaled_case(source,factor)
        gate=validate_feasibility_witness(FeasibilityProblem(c;angle_limits=angles),FeasibilityWitness(state))
        gate["valid"] || error("source precursor failed $objective $factor")
        seeds[(objective,factor)]=state
        push!(seedchecks,Dict("objective"=>objective,"factor"=>factor,"path"=>relpath(path,GATED_ROOT),"sha256"=>bytes2hex(sha256(read(path))),"check"=>DroopOPF._json_data(gate)))
    end
    write(joinpath(out,"source_precursors.json"),JSON.json(seedchecks;pretty=true))
    protocol=Dict("cells"=>1080,"definitions"=>["zero_q_shifted","opf_q_centered"],"slope_profiles_G1_to_G5"=>Dict(JS_PROFILES),
        "slope_convention"=>"voltage change across full Qmin-to-Qmax span; slope = percent/100/(Qmax-Qmin)",
        "deadband_total_width_pu"=>[0.,.005,.01],"calibration_objectives"=>["cost","loss"],"initialization_objectives"=>["cost","loss"],
        "calibration_demand"=>1.,"evaluation_demands"=>collect(GATED_FACTORS),"controls"=>"all curves, taps and shunts fixed during solves",
        "objective"=>"unchanged native S1 dispatch deviation","solvers"=>["ipopt","madnlp","ccopt"],"max_iter"=>600,"native_seconds"=>20.,"smooth_epsilon"=>1e-6,
        "absolute_reactive_epsilon"=>reactive_epsilon,
        "scope"=>"joint exploratory sensitivity, not holdout validation; zero-width definitions give identical exact curves",
        "qualification"=>"feasible if all demand levels have a verified witness, otherwise unresolved; no global infeasibility certificate computed")
    write(joinpath(out,"protocol.json"),JSON.json(protocol;pretty=true))
    negatives=[]
    for objective in ("cost","loss"),half in (0.,.0025,.005)
        anchor=seeds[(objective,1.)];c=js_case(base,anchor,"uncalibrated_zero",fill(4.,5),half,"negative-control")
        audit=validate_feasibility_witness(FeasibilityProblem(c;angle_limits=angles),FeasibilityWitness(anchor))
        audit["valid"] && error("negative control unexpectedly calibrated")
        push!(negatives,Dict("calibration_objective"=>objective,"deadband_total_width_pu"=>2half,"calibration_pass"=>audit["valid"],"check"=>DroopOPF._json_data(audit),"action"=>"rejected before solver"))
    end
    write(joinpath(out,"negative_controls.json"),JSON.json(negatives;pretty=true))
    ledger=joinpath(out,"rows.jsonl")
    rows=isfile(ledger) ? [JSON.parse(line) for line in readlines(ledger) if !isempty(line)] : Any[]
    done=Set(r["name"] for r in rows);configs=[]
    for definition in ("zero_q_shifted","opf_q_centered"),calobjective in ("cost","loss"),(profile,percentages) in JS_PROFILES,half in (0.,.0025,.005)
        config="$definition-$calobjective-$profile-db$(2half)"
        anchor=seeds[(calobjective,1.)];c=js_case(base,anchor,definition,percentages,half,config)
        p=FeasibilityProblem(c;angle_limits=angles)
        audit=validate_feasibility_witness(p,FeasibilityWitness(anchor))
        audit["valid"] || error("calibration precursor failed $config")
        write_study(joinpath(out,"$config-study.json"),Study(c))
        push!(configs,Dict("config"=>config,"definition"=>definition,"calibration_objective"=>calobjective,"profile"=>profile,"deadband_total_width_pu"=>2half,"calibration_pass"=>true,"check"=>DroopOPF._json_data(audit),"case_hash"=>DroopOPF._feasibility_case_hash(c)))
        for initobjective in ("cost","loss"),factor in GATED_FACTORS,solver in (:ipopt,:madnlp,:ccopt)
            name="$config-init$initobjective-load$factor-$solver";name in done && continue
            tags=Dict("config"=>config,"definition"=>definition,"calibration_objective"=>calobjective,"initialization_objective"=>initobjective,"profile"=>profile,"slopes_percent_G1_to_G5"=>percentages,"deadband_total_width_pu"=>2half,"factor"=>factor,"family"=>"fixed","start"=>"demand_matched_opf")
            row=js_cell(DroopOPF._feasibility_scaled_case(c,factor),seeds[(initobjective,factor)],angles,solver,tags;reactive_epsilon)
            row["name"]=name
            open(ledger,"a") do io;println(io,JSON.json(row));end
            push!(rows,row);push!(done,name)
            println("SENS ",length(rows),"/1080 ",name," ",get(row,"solver_status",get(row,"error","error"))," verified=",row["point_pass"]);flush(stdout)
        end
        write(joinpath(out,"configurations.json"),JSON.json(configs;pretty=true))
    end
    length(rows)==1080 || error("incomplete ledger")
    println("JOINT SENSITIVITY COMPLETE ",length(rows)," verified ",count(r->r["point_pass"],rows));flush(stdout)
end
abspath(PROGRAM_FILE)==(@__FILE__) && run_joint_sensitivity()
