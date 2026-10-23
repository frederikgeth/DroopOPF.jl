# Demand/backend-matched S1 starts and small joint masters, then addition.
include("s2_500bus_feasibility_first_design.jl")
const SDQ_S1_SOURCE=read(@__FILE__,String)
function sdq_s1_start(solver,factor,events)
    checks=JSON.parsefile(joinpath(SDQ_OUT,"s1-start-checks.json"));@assert checks["passed"]
    row=only(filter(r->r["solver"]==string(solver) && r["factor"]==factor,checks["starts"]))
    source=joinpath(FD_ROOT,row["result_path"])
    @assert bytes2hex(sha256(read(source)))==row["result_sha256"]
    design=read_joint_design(source);@assert design.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
    controller=read_study(joinpath(S2500_OUT,"pilot_study.json"))
    for (id,settings) in design.droops;controller=with_droop_settings(controller,id,settings);end
    controller=DroopOPF._copy_study(controller;contingencies=events)
    # Convex reserve-start QP. This only supplies a numerical initial dispatch;
    # its 50-MW heuristic loss buffer is not a constraint in the AC master.
    c=controller.case;gens=c.generators;limits=[g.p_max for g in gens]
    gi=Dict(g.id=>i for (i,g) in enumerate(gens))
    for a in c.attachments;limits[gi[a.generator_id]]=min(limits[gi[a.generator_id]],c.controls[a.control_id].capability.p_max);end
    qp=Model(Ipopt.Optimizer);set_silent(qp)
    set_optimizer_attribute(qp,"tol",1e-9);set_optimizer_attribute(qp,"max_cpu_time",30.);set_optimizer_attribute(qp,"print_level",0)
    set_optimizer_attribute(qp,"bound_relax_factor",0.);set_optimizer_attribute(qp,"max_iter",1000)
    pg=@variable(qp,[1:length(gens)])
    for (i,g) in enumerate(gens)
        set_lower_bound(pg[i],g.p_min);set_upper_bound(pg[i],limits[i]);set_start_value(pg[i],design.opf.state.pg[i])
        g.available || fix(pg[i],0.;force=true)
    end
    @constraint(qp,sum(pg)==sum(design.opf.state.pg))
    for event in events
        outage=scenario_case(c,event);alpha=DroopOPF._participation(controller,outage)
        lost=sum(pg[i] for (i,g) in enumerate(gens) if g.available && !outage.generators[i].available;init=0.)
        for (i,g) in enumerate(outage.generators)
            g.available || continue
            @constraint(qp,pg[i]+alpha[i]*(lost+.5)<=limits[i])
        end
    end
    @objective(qp,Min,sum((pg[i]-design.opf.state.pg[i])^2/max(limits[i],1e-3) for (i,g) in enumerate(gens) if g.available))
    optimize!(qp)
    @assert termination_status(qp) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.OPTIMAL)
    base=ACState(design.opf.state.vm,design.opf.state.va,value.(pg),design.opf.state.qg)
    states=Dict{Symbol,Union{Nothing,ACState{Float64}}}(:base=>base)
    taps=Dict{Symbol,Dict{Int,Float64}}();banks=Dict{Symbol,Dict{Int,Float64}}();deltas=Dict{Symbol,Float64}()
    taps[:base]=Dict(t.branch_id=>design.taps[t.branch_id] for t in controller.tap_controls)
    banks[:base]=copy(design.susceptances)
    for event in events
        outage=scenario_case(c,event);alpha=DroopOPF._participation(controller,outage)
        lost=sum(base.pg[i] for (i,g) in enumerate(gens) if g.available && !outage.generators[i].available;init=0.)
        delta=lost+.05;deltas[event.id]=delta
        p=[g.available ? base.pg[i]+alpha[i]*delta : 0. for (i,g) in enumerate(outage.generators)]
        q=[g.available ? base.qg[i] : 0. for (i,g) in enumerate(outage.generators)]
        states[event.id]=ACState(copy(base.vm),copy(base.va),p,q)
        taps[event.id]=Dict(t.branch_id=>design.taps[t.branch_id] for t in DroopOPF._scenario_tap_controls(controller,outage))
        banks[event.id]=copy(design.susceptances)
    end
    demand=sum(l.p*factor for l in c.loads)
    seed=SCOPFResult(states,deltas,sum(base.pg)-demand,:NOT_RUN,:NO_SOLUTION,controller.mode,design.encoding,
        1e-6,1e-6,1e-6,"Numerical S1/QP reserve start, not AC acceptance",controller.reactive_assignments,
        taps,banks,controller.tap_controls,controller.shunt_controls,controller.control_policy)
    metadata=(;source=row["result_path"],source_sha256=row["result_sha256"],initialization_optimizer_calls=1,
        initialization_kind="convex reserve-start QP; not an AC solve or certificate",qp_status=string(termination_status(qp)),
        heuristic_loss_buffer_mw=50.,buffer_is_not_in_AC_model=true,
        generation_movement_l1_mw=sum(abs.(base.pg-design.opf.state.pg))*c.base_power,original_S1_base_replayed=true)
    (;controller,seed,metadata)
end

function sdq_s1_design(solver=:ccopt;factor=1.,max_rounds=3)
    @assert !isempty(strip(get(ENV,"SDQ_CONTROL_CONFIRMATION",""))) && factor<1.1
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    label="$(solver)-$(round(Int,factor*10000))-s1-seeded";summary=joinpath(SDQ_OUT,"summary-$label.json")
    isfile(summary) && error("Preserve completed S1-seeded recovery")
    original=read_study(joinpath(S2500_OUT,"pilot_study.json"));all_events=eligible_contingencies(contingency_catalog(original.case))
    chosen_ids=Set([:generator_14,:generator_60])
    factor==1.05 && union!(chosen_ids,[:branch_36,:branch_562])
    initial=sdq_s1_start(solver,factor,filter(e->e.id in chosen_ids,all_events))
    controller=initial.controller;seed=initial.seed
    controls=s214_multi_controls(fd_inputs(500).base);angles=fd_inputs(500).angles
    fd_save(joinpath(SDQ_OUT,"protocol-$label.json"),(;confirmation=ENV["SDQ_CONTROL_CONFIRMATION"],solver,factor,max_rounds,
        initialization=initial.metadata,initial_outages=sort(collect(chosen_ids);by=string),shared_free_variables=102,
        maximum_master_models_per_round=2,seconds_per_native_stage=180.,maximum_additions_per_round=4,
        source_sha256=bytes2hex(sha256(SDQ_S1_SOURCE)),policy="normal limits, no relief, exact active response",
        ccopt_strategy="First: S1-matched default barrier/bound push, physical coordinates, proportional relaxation. Second: exact reduction and scaled Q projection, UMFPACK, feasibility first."))
    rounds=Any[];accepted=false;selected=nothing
    for round in 1:max_rounds
        attempts=Any[];chosen=nothing
        for i in 1:2
            name="solver_demand_qualification/$label/round-$round/attempt-$i";folder=joinpath(S2500_OUT,name)
            ispath(folder) && error("Preserve existing attempt")
            mkpath(folder)
            write(joinpath(folder,"loaded_s1_driver.jl"),SDQ_S1_SOURCE)
            write(joinpath(folder,"loaded_network_reduction.jl"),NR_SOURCE)
            for file in ("s2_500bus_s1_seeded_design.jl","s2_500bus_feasibility_first_design.jl","s2_500bus_separator_starts.jl","s2_500bus_scaled_mpcc.jl","s2_arpae500_recovery.jl","audit_s2_500bus_solver_demand.py")
                cp(joinpath(@__DIR__,file),joinpath(folder,"executed_"*file))
            end
            fd_save(joinpath(folder,"free-controls.json"),controls)
            lane=s2500_targeted_attempt(name,controller,controls,controller,Dict(factor=>seed),angles;
                solver,retry=true,factors=(factor,),objective_factor=factor,seconds_budget=180.,
                normalization=false,droop_normalization=i==2 && solver!=:ccopt,
                mu=nothing,scheduled=false,feasibility_first=i==2,
                linear_solver=solver==:ipopt || (solver==:ccopt && i==1) ? nothing : MadNLP.UmfpackSolver,
                mpcc_implied_q_bounds=solver==:ccopt && i==2,
                cc_builder=i==1 ? DroopOPF._build_complementarity_opf_model : sdq_scaled_mpcc,
                ac_builder=sdq_reduced,
                optimizer_options=solver==:ipopt && i==2 ? Dict("hessian_approximation"=>"limited-memory") : Dict{String,Any}())
            python=get(ENV,"SDQ_PYTHON","/tmp/s214-plot-env/bin/python");script=joinpath(@__DIR__,"audit_s2_500bus_solver_demand.py")
            read(`$python $script $folder`,String)
            good=lane.record["accepted"] && JSON.parsefile(joinpath(folder,"independent-audit.json"))["accepted"]
            push!(attempts,(;name,accepted=good,record=lane.record))
            fd_save(joinpath(SDQ_OUT,"progress-$label.json"),(;round,attempts))
            if good;chosen=lane;break;end
        end
        scan=nothing
        if !isnothing(chosen)
            selected=chosen.record["name"];controller=chosen.study;seed=chosen.results[factor]
            full=DroopOPF._copy_study(controller;case=DroopOPF._feasibility_scaled_case(controller.case,factor),contingencies=all_events)
            scan=s2500_scan("solver_demand_qualification/$label/round-$round/demand-$factor",full,seed,angles;solver=:ipopt)
            accepted=scan.accepted
        end
        push!(rounds,(;round,attempts,selected,working_outages=[c.id for c in controller.contingencies],
            scan=isnothing(scan) ? nothing : (;accepted=scan.accepted,exhaustive=scan.exhaustive,evaluated=length(scan.rows),failed=scan.failed)))
        fd_save(summary,(;solver,factor,accepted,selected,rounds,full_n1_accepted=false))
        accepted && break
        isnothing(scan) && break
        isempty(scan.failed) && break
        enriched=sdq_separator_starts(controller,seed,joinpath(S2500_OUT,selected),factor)
        controller=enriched.controller;seed=enriched.seed
    end
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    sdq_s1_design(Symbol(get(ARGS,1,"ccopt"));factor=parse(Float64,get(ARGS,2,"1.0")))
end
