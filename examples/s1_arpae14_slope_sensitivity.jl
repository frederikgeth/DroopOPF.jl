include("s1_arpae14_gated.jl")
const SENS_OUT=joinpath(GATED_OUT,"slope_sensitivity")
const SENS_RATIOS=(0.5,0.75,1.0,1.25,1.5,2.0)

function sensitivity_case(base, anchor, ratios)
    idx=DroopOPF._bus_indices(base.network)
    controls=copy(base.controls)
    for (ci,d) in enumerate(base.controls)
        ratio=get(ratios,ci,1.0)
        slope=d.slope*ratio
        a=only(filter(x->x.control_id==ci,base.attachments))
        gi=findfirst(g->g.id==a.generator_id,base.generators)
        q=anchor.qg[gi]
        vm=anchor.vm[idx[a.location.bus_id]]
        lo=d.schedule.v_ref-d.schedule.v_db_low
        hi=d.schedule.v_db_high-d.schedule.v_ref
        # Preserve the generator's source-Q operating point when changing slope.
        offset=q>1e-9 ? lo : q < -1e-9 ? -hi : 0.0
        vref=vm+slope*q+offset
        sched=VoltageSchedule(vref;v_db_low=vref-lo,v_db_high=vref+hi,unit=d.schedule.unit)
        controls[ci]=VoltVarDroop(sched,slope,d.q_at_deadband,d.capability)
    end
    Case(base.id*"-slope-sensitivity";base_power=base.base_power,base_frequency=base.base_frequency,
        network=base.network,generators=base.generators,loads=base.loads,controls,attachments=base.attachments)
end

function summary_metrics(c, anchor, state)
    idx=DroopOPF._bus_indices(c.network)
    dv=[state.vm[i]-anchor.vm[i] for i in eachindex(state.vm)]
    dp=[state.pg[i]-anchor.pg[i] for i in eachindex(state.pg)]
    dq=[state.qg[i]-anchor.qg[i] for i in eachindex(state.qg)]
    flows=branch_flows(c.network,state)
    util=Tuple{Float64,Int}[]
    for (i,b) in enumerate(c.network.branches)
        b.available && b.thermal_limit>0 || continue
        push!(util,(max(abs(flows.from[i]),abs(flows.to[i]))/b.thermal_limit,b.id))
    end
    maxutil,branchid=isempty(util) ? (0.0,0) : maximum(util)
    return Dict("objective_state_metrics"=>Dict("max_abs_dv_pu"=>maximum(abs.(dv)),"max_abs_dv_bus"=>c.network.buses[argmax(abs.(dv))].id,
        "max_abs_dpg_pu"=>maximum(abs.(dp)),"max_abs_dpg_generator"=>c.generators[argmax(abs.(dp))].id,
        "max_abs_dq_pu"=>maximum(abs.(dq)),"max_abs_dq_generator"=>c.generators[argmax(abs.(dq))].id,
        "max_branch_utilization"=>maxutil,"max_branch_id"=>branchid,
        "vm_min"=>minimum(state.vm),"vm_max"=>maximum(state.vm),
        "pg"=>Dict(string(g.id)=>state.pg[i] for (i,g) in enumerate(c.generators)),
        "qg"=>Dict(string(g.id)=>state.qg[i] for (i,g) in enumerate(c.generators))))
end

function run_sensitivity(out=SENS_OUT)
    mkpath(out)
    source,anchor,angles,candidates=gated_inputs()
    rows=Any[]
    for variant in ("no_deadband","with_deadband")
        base=candidates[variant]
        plan=Tuple{String,Dict{Int,Float64}}[]
        for ratio in SENS_RATIOS
            push!(plan,("all_$(ratio)",Dict(i=>ratio for i in eachindex(base.controls))))
        end
        for ci in eachindex(base.controls),ratio in SENS_RATIOS
            ratio==1.0 && continue
            push!(plan,("g$(only(filter(a->a.control_id==ci,base.attachments)).generator_id)_$(ratio)",Dict(ci=>ratio)))
        end
        for (label,ratios) in plan
            name="$(variant)-$(label)"
            path=joinpath(out,name*"-diagnostics.json")
            if isfile(path)
                push!(rows,JSON.parsefile(path));continue
            end
            c=sensitivity_case(base,anchor,ratios)
            # Every slope setting is source-point calibrated and independently gated.
            anchor_gate=check_feasibility(FeasibilityProblem(c;angle_limits=angles);witnesses=[FeasibilityWitness(anchor)],solve_missing=false)
            anchor_gate.status==:feasible || error("$name source anchor failed: $(anchor_gate.status)")
            result=optimize_joint_design(c;initial_state=anchor,smooth_epsilon=1e-6,
                optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>600,"max_cpu_time"=>20.,"bound_relax_factor"=>0.),
                _measurement_hook=(phase,model)->gated_angles(angles,c,phase,model))
            solverok=validate_joint_design(c,result)
            result.opf.state===nothing && error("$name has no returned state")
            st=result.opf.state
            point=check_feasibility(FeasibilityProblem(c;angle_limits=angles);witnesses=[FeasibilityWitness(st)],solve_missing=false)
            metric=summary_metrics(c,anchor,st)["objective_state_metrics"]
            row=Dict{String,Any}("variant"=>variant,"case"=>label,"ratios"=>Dict(string(k)=>v for (k,v) in ratios),
                "slope_percent_full_q_span"=>Dict(string(a.generator_id)=>4*get(ratios,a.control_id,1.) for a in base.attachments),
                "anchor_gate"=>string(anchor_gate.status),"solver_status"=>string(result.opf.termination_status),
                "solver_valid"=>solverok.solver_valid,"policy_valid"=>solverok.policy_valid,
                "point_gate"=>string(point.status),"objective"=>result.opf.objective,
                "anchor_objective"=>7.413382532486392,"metrics_vs_source_opf"=>metric,
                "exact_droop_audit"=>exact_droop_audit(c,result),
                "point_checks"=>validate_feasibility_witness(FeasibilityProblem(c;angle_limits=angles),FeasibilityWitness(st)))
            write_joint_design(joinpath(out,name*"-design.json"),result)
            write_feasibility_result(joinpath(out,name*"-gate.json"),FeasibilityProblem(c;angle_limits=angles),point)
            write(path,JSON.json(row;pretty=true));push!(rows,row)
            println(name," ",row["solver_status"]," anchor=",row["anchor_gate"]," point=",row["point_gate"]," obj=",row["objective"]);flush(stdout)
        end
    end
    write(joinpath(out,"summary.json"),JSON.json(rows;pretty=true))
    println("SENSITIVITY COMPLETE ",length(rows));flush(stdout)
end

if abspath(PROGRAM_FILE)==@__FILE__
    run_sensitivity()
end
