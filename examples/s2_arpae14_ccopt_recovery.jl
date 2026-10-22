# Targeted CCOpt convergence recovery; prior campaign artifacts remain unchanged.
include("s2_arpae14_solver_designs.jl")
const S214_RECOVER=joinpath(S214_COMPARE,"ccopt_recovery")
function s214_ccrecover_attempt(name,original,controls,seedstudy,seeds,angles;solver=:ipopt,retry=false)
    out=joinpath(S214_RECOVER,name);mkpath(out)
    record=Dict{String,Any}("name"=>name,"solver"=>string(solver),"retry"=>retry,
        "accepted"=>false,"iterations_budget"=>6000,"seconds_budget"=>300.,
        "objective_kind"=>"nominal_base_active_loss","training_factors"=>collect(S214_TRAIN))
    fd_save(joinpath(out,"contract.json"),record)
    println("START comparison ",name);flush(stdout)
    encoding=solver==:ccopt ? :complementarity : :smooth
    model=Model(solver==:ccopt ? CCOpt.Optimizer : MadNLP.Optimizer);set_silent(model)
    solver==:ccopt && DroopOPF.MathOptComplements.Bridges.add_all_bridges(model)
    record["encoding"]=string(encoding)
    record["strategy"]=retry ? "MadNLP witness with scheduled relaxation" : "MadNLP witness with small initial barrier"
    record["relaxation_rule"]=retry ? "ScheduledRelaxationUpdate sigma_init=1e-6, sigma_min=1e-14, target_accuracy=1e-11" : "ProportionalRelaxationUpdate sigma_min=1e-14"
    record["normalization"]="droop and equipment physical bounds mapped to unit intervals"
    record["initialization"]="Accepted MadNLP multi-demand full primal witness; all selected controls remain free; retry restarts from the same accepted witness with scheduled relaxation"
    parameters=Dict{Int,NamedTuple}()
    for control in controls
        p=DroopOPF._joint_droop_policy(original.case,control);names=keys(p.ranges)
        initial=DroopSettings(seedstudy.case.controls[control.control_id])
        parameters[control.control_id]=NamedTuple{names}(Tuple(DroopOPF._droop_design_variable(model,
            "shared_$(control.control_id)_$k",getfield(p.ranges,k),getfield(initial,k);normalize=true) for k in names))
    end
    blocks=Dict{Float64,Any}()
    for (j,f) in enumerate(S214_TRAIN)
        study=DroopOPF._copy_study(original;case=DroopOPF._feasibility_scaled_case(original.case,f))
        write_study(joinpath(out,"input-$f.json"),study)
        ids=[:base;[c.id for c in study.contingencies]]
        cases=[study.case;[scenario_case(study.case,c) for c in study.contingencies]]
        starts=s214_starts(study,seeds[f].states[:base],seeds[f]);vars=Any[];deltas=Dict{Symbol,VariableRef}()
        fd_save(joinpath(out,"starts-$f.json"),starts)
        for (k,(id,c)) in enumerate(zip(ids,cases))
            prefix="demand_$(j)_scenario_$(k)_"
            taps=[TapControl(t.branch_id;lower=t.lower,upper=t.upper,nominal=t.nominal,
                initial=clamp(seeds[f].tap_settings[id][t.branch_id],t.lower,t.upper))
                for t in DroopOPF._scenario_tap_controls(study,c)]
            banks=[ShuntControl(t.bank_id;lower=t.lower,upper=t.upper,nominal=t.nominal,
                initial=clamp(seeds[f].shunt_settings[id][t.bank_id],t.lower,t.upper)) for t in study.shunt_controls]
            _,v=if solver==:ccopt
                DroopOPF._build_complementarity_opf_model(c;silent=true,shared_model=model,
                    scenario_prefix=prefix,set_objective=false,initial_state=starts[id],
                    reactive_assignments=study.reactive_assignments,tap_controls=taps,shunt_controls=banks,
                    normalize_controls=true,droop_parameter_variables=parameters)
            else
                DroopOPF._build_acopf_model(c;voltage_epsilon=1e-6,reactive_relative_epsilon=1e-6,
                    reactive_epsilon=1e-6,silent=true,shared_model=model,scenario_prefix=prefix,set_objective=false,
                    initial_state=starts[id],reactive_assignments=study.reactive_assignments,
                    tap_controls=taps,shunt_controls=banks,normalize_controls=true,droop_parameter_variables=parameters)
            end
            push!(vars,v)
            if k>1
                delta=DroopOPF._add_response_constraints!(model,study,c,vars[1],v,prefix)
                isnothing(delta) || (deltas[id]=delta)
                DroopOPF._couple_equipment!(model,study.control_policy,vars[1].taps,vars[1].shunts,v)
            end
            idx=DroopOPF._bus_indices(c.network)
            for b in c.network.branches
                b.available || continue;lo,hi=angles[b.id]
                @constraint(model,lo<=v.va[idx[b.from_bus]]-v.va[idx[b.to_bus]]<=hi)
            end
        end
        blocks[f]=(;study,ids,vars,deltas)
    end
    nominal=blocks[1.]
    @objective(model,Min,sum(nominal.vars[1].pg)-sum(l.p for l in nominal.study.case.loads))
    opts=Dict{String,Any}("tol"=>solver==:ccopt ? 1e-11 : 1e-9,"max_iter"=>record["iterations_budget"],"bound_relax_factor"=>0.)
    if solver==:ccopt
        opts["acceptable_tol"]=1e-11
        opts["relaxation_update"]=retry ? CCOpt.ScheduledRelaxationUpdate(sigma_init=1e-6,sigma_min=1e-14,target_accuracy=1e-11) : CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14)
        opts["output_file"]=joinpath(out,"solver_iterations.log")
        opts["file_print_level"]=MadNLP.INFO
        barrier=MadNLP.MonotoneUpdate(1e-11,10.);barrier.mu_init=retry ? 1e-6 : 1e-8
        opts["barrier"]=barrier;opts["bound_push"]=1e-8;opts["bound_fac"]=1e-8
    end
    for (key,value) in opts;set_optimizer_attribute(model,key,value);end
    set_optimizer_attribute(model,solver==:ipopt ? "max_cpu_time" : "max_wall_time",record["seconds_budget"])
    if solver==:ipopt;set_optimizer_attribute(model,"print_level",0);set_optimizer_attribute(model,"mu_strategy","adaptive");end
    record["variables"]=num_variables(model);record["constraints"]=num_constraints(model;count_variable_in_set_constraints=true)
    timed=@timed optimize!(model)
    record["elapsed_seconds"]=timed.time;record["solver_status"]=string(termination_status(model))
    record["native_success"]=termination_status(model) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.ALMOST_LOCALLY_SOLVED,JuMP.MOI.OPTIMAL)
    if solver==:ccopt
        record["ccopt_diagnostics"]=ccopt_diagnostics(model)
        ipm=unsafe_backend(model).solver.ipm
        residual=MadNLP.primal(ipm.f).-MadNLP.primal(ipm.zl).+MadNLP.primal(ipm.zu).+ipm.jacl
        top=sortperm(abs.(residual);rev=true)[1:min(20,length(residual))]
        record["relaxed_nlp_stationarity_diagnostic"]=Dict("unscaled_infinity_norm"=>maximum(abs,residual),
            "top_coordinate_residuals"=>[Dict("internal_index"=>i,"residual"=>residual[i]) for i in top],
            "mu_final"=>ipm.mu,"scope"=>"Final relaxed NLP coordinate residual, not original-MPCC stationarity")
        has_values(model) && (record["complementarity_product_max"]=maximum(DroopOPF._complementarity_residual(v) for b in values(blocks) for v in b.vars))
    end
    record["iterations"]=try Int(JuMP.MOI.get(backend(model),JuMP.MOI.BarrierIterations())) catch; nothing end
    results=Dict{Float64,SCOPFResult}();optimized=seedstudy
    if has_values(model)
        settings=Dict(id=>DroopSettings((DroopOPF._droop_design_value(getfield(p,k)) for k in keys(p))...) for (id,p) in parameters)
        for id in sort(collect(keys(settings)));optimized=with_droop_settings(optimized,id,settings[id]);end
        write_study(joinpath(out,"controller.json"),optimized)
        refs=Dict(c.control_id=>DroopSettings(original.case.controls[c.control_id]) for c in controls)
        checks=Any[]
        for f in S214_TRAIN
            b=blocks[f]
            states=Dict{Symbol,Union{Nothing,ACState{Float64}}}(id=>nothing for id in b.ids)
            taps=Dict{Symbol,Dict{Int,Float64}}();shunts=Dict{Symbol,Dict{Int,Float64}}()
            for (id,v) in zip(b.ids,b.vars)
                statevals=[Float64.(value.(getproperty(v,key))) for key in (:vm,:va,:pg,:qg)]
                if all(x->all(isfinite,x),statevals) && all(>(0),statevals[1]);states[id]=ACState(statevals...);end
                taps[id]=Dict(i=>Float64(value(x)) for (i,x) in v.taps)
                shunts[id]=Dict(i=>Float64(value(x)) for (i,x) in v.shunts)
            end
            loss=isnothing(states[:base]) ? NaN : sum(states[:base].pg)-sum(l.p for l in b.study.case.loads)
            result=SCOPFResult(states,Dict(id=>value(x) for (id,x) in b.deltas),loss,
                Symbol(string(termination_status(model))),Symbol(string(primal_status(model))),b.study.mode,encoding,
                1e-6,1e-6,1e-6,solver_name(model),b.study.reactive_assignments,taps,shunts,
                b.study.tap_controls,b.study.shunt_controls,b.study.control_policy)
            results[f]=result
            design=SCOPFDroopDesignResult(controls,refs,settings,result)
            st=with_droop_settings(b.study,design)
            write_study(joinpath(out,"optimized-$f.json"),st)
            write_scopf_result(joinpath(out,"result-$f.json"),result)
            # Keep failed raw iterates available even if library postprocessing rejects them.
            assessment=try
                report=validate_droop_design(b.study,design)
                angle_margin=minimum(begin
                    idx=DroopOPF._bus_indices(c.network)
                    minimum(min(states[id].va[idx[br.from_bus]]-states[id].va[idx[br.to_bus]]-angles[br.id][1],
                        angles[br.id][2]-states[id].va[idx[br.from_bus]]+states[id].va[idx[br.to_bus]])
                        for br in c.network.branches if br.available)
                end for (id,c) in zip(b.ids,[st.case;[scenario_case(st.case,event) for event in st.contingencies]]))
                projection=s214_island_projection(st,result,angles)
                fd_save(joinpath(out,"island-$f.json"),projection)
                fd_save(joinpath(out,"validation-$f.json"),report)
                (;factor=f,valid=report.valid && projection.valid && angle_margin>=-1e-6,policy_valid=report.policy_valid,island_valid=projection.valid,angle_min_margin_rad=angle_margin)
            catch error
                (;factor=f,valid=false,error=sprint(showerror,error))
            end
            push!(checks,assessment)
        end
        record["checks"]=checks
        record["master_objective_pu"]=objective_value(model)
        record["nominal_loss_mw"]=results[1.].objective*original.case.base_power
        record["objective_replay_error"]=abs(objective_value(model)-results[1.].objective)
        record["accepted"]=record["native_success"] && all(x.valid for x in checks) && record["objective_replay_error"]<1e-8
    end
    fd_save(joinpath(out,"summary.json"),record)
    println("END comparison ",name," accepted=",record["accepted"]," status=",record["solver_status"]);flush(stdout)
    (;record,study=optimized,results)
end

function s214_ccrecover_run(confirmation)
    isempty(strip(confirmation)) && error("Explicit campaign confirmation required")
    mkpath(S214_RECOVER)
    original=read_study(joinpath(S214_OUT,"full-frozen-ipopt/input.json"))
    seedpath=joinpath(S214_COMPARE,"design-madnlp")
    seedstudy=read_study(joinpath(seedpath,"controller.json"))
    seeds=Dict(f=>read_scopf_result(joinpath(seedpath,"result-$f.json")) for f in S214_TRAIN)
    controls=s214_multi_controls(original.case);angles=fd_inputs(14).angles
    files=["Project.toml","Manifest.toml","examples/s2_arpae14_ccopt_recovery.jl","examples/s2_arpae14_solver_designs.jl",
        "examples/s2_arpae14_multidemand.jl","examples/s2_arpae14_followup.jl","examples/s2_arpae14_campaign.jl",
        relpath(joinpath(seedpath,"controller.json"),FD_ROOT),"artifacts/s2_scopf/ieee14_native/full-frozen-ipopt/input.json"]
    append!(files,[relpath(joinpath(seedpath,"result-$f.json"),FD_ROOT) for f in S214_TRAIN])
    append!(files,[relpath(joinpath(root,file),FD_ROOT) for (root,_,fs) in walkdir(joinpath(FD_ROOT,"src")) for file in fs if endswith(file,".jl")])
    fd_save(joinpath(S214_RECOVER,"protocol.json"),(;confirmation,training_factors=S214_TRAIN,held_out_factors=S214_HOLD,
        controls,tap_controls=original.tap_controls,shunt_controls=original.shunt_controls,control_policy=original.control_policy,
        objective="100-percent base active loss; remaining training states feasibility only",
        primary_budget=(iterations=6000,native_seconds=300),retry_budget=(iterations=6000,native_seconds=300,max_retries=1),
        strategies=["Full accepted MadNLP primal witness, proportional relaxation, mu_init1e-8",
                    "Same accepted MadNLP witness, scheduled relaxation sigma_init1e-6, mu_init1e-6"],
        native_tolerance=1e-11,physical_tolerances="AC/limits/coupling1e-6, exact droop1e-5; unchanged",
        diagnosis="Previous physical training feasibility passed but native dual feasibility stalled; no global infeasibility claim",
        island_assumption="G5 trip and unloaded bus8 disconnection, retained network steady-state only",
        run_source_hashes=Dict(p=>bytes2hex(sha256(read(joinpath(FD_ROOT,p)))) for p in files)))
    attempts=Any[];heldout=Any[];selected=nothing
    lane=nothing
    for retry in (false,true)
        name=retry ? "scheduled-ccopt" : "madnlp-seed-ccopt"
        lane=s214_ccrecover_attempt(name,original,controls,seedstudy,seeds,angles;solver=:ccopt,retry)
        push!(attempts,lane.record)
        fd_save(joinpath(S214_RECOVER,"summary.json"),(;attempts,heldout,selected))
        if lane.record["accepted"];selected=name;break;end
    end
    if !isnothing(selected)
        for f in S214_HOLD
            st=DroopOPF._copy_study(lane.study;case=DroopOPF._feasibility_scaled_case(lane.study.case,f))
            nearest=S214_TRAIN[argmin(abs.(collect(S214_TRAIN).-f))];seed=lane.results[nearest]
            prefix="multidemand/solver_design_comparison/ccopt_recovery/heldout-ccopt-$f"
            r=s214_attempt(prefix,st,DroopControl[],s214_starts(st,seed.states[:base],seed),angles;solver=:ccopt)
            primary=r.record
            if !r.record["accepted"]
                r=s214_attempt("multidemand/solver_design_comparison/ccopt_recovery/retry-heldout-ccopt-$f",st,DroopControl[],s214_starts(st,seed.states[:base],r.result),angles;solver=:ccopt,retry=true)
            end
            projection=try s214_island_projection(st,r.result,angles) catch; nothing end
            isnothing(projection) || fd_save(joinpath(S214_RECOVER,"island-heldout-ccopt-$f.json"),projection)
            push!(heldout,(;solver=:ccopt,factor=f,primary,final=r.record,island_valid=!isnothing(projection) && projection.valid,
                accepted=r.record["accepted"] && !isnothing(projection) && projection.valid))
        end
    end
    fd_save(joinpath(S214_RECOVER,"summary.json"),(;attempts,heldout,selected))
    fd_save(joinpath(S214_RECOVER,"STATUS.json"),(;status=isnothing(selected) ? "recovery_unqualified" : all(r.accepted for r in heldout) ? "recovered_sampled_demands" : "recovered_training_only",
        selected,attempts=length(attempts),heldout_lanes=length(heldout),accepted_heldout_lanes=count(r->r.accepted,heldout),
        general_full_n1_claim=false,s1_status="closed"))
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==1 || error("Supply explicit equipment confirmation")
    s214_ccrecover_run(only(ARGS))
end
