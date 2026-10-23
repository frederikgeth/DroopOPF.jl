# Targeted numerical recovery for the confirmed 500-bus S2 campaign.
include("s2_arpae500_campaign.jl")
const S2500_RECOVERY_EXECUTED_SOURCE=read(@__FILE__,String)
function s2500_targeted_attempt(name,original,controls,seedstudy,seeds,angles;solver=:ipopt,retry=false,factors=(1.,),normalization=false,mu=1e-6,scheduled=true,
    droop_normalization=normalization,seconds_budget=nothing,ac_builder=DroopOPF._build_acopf_model,objective_factor=1.,
    mpcc_implied_q_bounds=false,linear_solver=nothing,cc_builder=DroopOPF._build_complementarity_opf_model,
    feasibility_first=false,optimizer_options=Dict{String,Any}(),ccopt_sigma_init=1e-6,
    stage_observer=nothing,feasibility_regularization=0.)
    out=joinpath(S2500_OUT,name);mkpath(out)
    write(joinpath(out,"loaded_recovery_adapter.jl"),S2500_RECOVERY_EXECUTED_SOURCE)
    record=Dict{String,Any}("name"=>name,"solver"=>string(solver),"retry"=>retry,
        "accepted"=>false,"iterations_budget"=>retry || solver==:ccopt ? 6000 : 3000,"seconds_budget"=>retry || solver==:ccopt ? 300. : 120.,
        "objective_kind"=>"nominal_base_active_loss","training_factors"=>collect(factors))
    isnothing(seconds_budget) || (record["seconds_budget"]=seconds_budget)
    record["droop_normalization"]=droop_normalization
    record["objective_factor"]=objective_factor
    objective_factor==1. || (record["objective_kind"]="individual_demand_base_active_loss")
    record["model_builder"]=string(ac_builder)
    record["complementarity_model_builder"]=string(cc_builder)
    record["mpcc_implied_q_bounds"]=mpcc_implied_q_bounds
    record["feasibility_first"]=feasibility_first
    record["feasibility_regularization"]=feasibility_regularization
    feasibility_regularization>=0 || error("Feasibility regularization must be nonnegative")
    record["optimizer_option_overrides"]=optimizer_options
    record["ccopt_sigma_init"]=solver==:ccopt && scheduled ? ccopt_sigma_init : nothing
    record["linear_solver_override"]=isnothing(linear_solver) ? nothing : string(linear_solver)
    fd_save(joinpath(out,"contract.json"),record)
    println("START comparison ",name);flush(stdout)
    encoding=solver==:ccopt ? :complementarity : :smooth
    model=Model(solver==:ccopt ? CCOpt.Optimizer : solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer);set_silent(model)
    solver==:ccopt && DroopOPF.MathOptComplements.Bridges.add_all_bridges(model)
    record["encoding"]=string(encoding)
    record["strategy"]=solver==:ccopt ? (retry ? "proportional small-barrier recovery" : "scheduled relaxation from full primal witness") : "smooth full-primal warm start"
    record["relaxation_rule"]=scheduled ? "ScheduledRelaxationUpdate sigma_init=$ccopt_sigma_init, sigma_min=1e-14, target_accuracy=1e-11" : "ProportionalRelaxationUpdate sigma_min=1e-14"
    record["normalization"]=normalization ? "physical bounds mapped to unit intervals" : "physical coordinates"
    record["initial_barrier"]=solver==:ccopt ? mu : nothing
    record["scheduled_relaxation"]=solver==:ccopt ? scheduled : nothing
    solver==:ccopt || (record["relaxation_rule"]="Inapplicable: smooth backend")
    record["initialization"]="Saved numerical primal start; source/native status is recorded in the campaign protocol; selected controls remain free"
    parameters=Dict{Int,NamedTuple}()
    for control in controls
        p=DroopOPF._joint_droop_policy(original.case,control);names=keys(p.ranges)
        initial=DroopSettings(seedstudy.case.controls[control.control_id])
        parameters[control.control_id]=NamedTuple{names}(Tuple(DroopOPF._droop_design_variable(model,
            "shared_$(control.control_id)_$k",getfield(p.ranges,k),getfield(initial,k);normalize=droop_normalization) for k in names))
    end
    blocks=Dict{Float64,Any}();removed_q_bounds=0
    for (j,f) in enumerate(factors)
        study=DroopOPF._copy_study(original;case=DroopOPF._feasibility_scaled_case(original.case,f))
        write_study(joinpath(out,"input-$f.json"),study)
        ids=[:base;[c.id for c in study.contingencies]]
        cases=[study.case;[scenario_case(study.case,c) for c in study.contingencies]]
        starts=s214_starts(study,seeds[f].states[:base],seeds[f]);vars=Any[];deltas=Dict{Symbol,VariableRef}()
        fd_save(joinpath(out,"starts-$f.json"),starts)
        for (k,(id,c)) in enumerate(zip(ids,cases))
            prefix="demand_$(j)_scenario_$(k)_"
            taps=[TapControl(t.branch_id;lower=t.lower,upper=t.upper,nominal=t.nominal,
                initial=clamp(get(seeds[f].tap_settings,id,seeds[f].tap_settings[:base])[t.branch_id],t.lower,t.upper))
                for t in DroopOPF._scenario_tap_controls(study,c)]
            banks=[ShuntControl(t.bank_id;lower=t.lower,upper=t.upper,nominal=t.nominal,
                initial=clamp(get(seeds[f].shunt_settings,id,seeds[f].shunt_settings[:base])[t.bank_id],t.lower,t.upper)) for t in study.shunt_controls]
            _,v=if solver==:ccopt
                cc_builder(c;silent=true,shared_model=model,
                    scenario_prefix=prefix,set_objective=false,initial_state=starts[id],
                    reactive_assignments=study.reactive_assignments,tap_controls=taps,shunt_controls=banks,
                    normalize_controls=normalization,droop_parameter_variables=parameters)
            else
                ac_builder(c;voltage_epsilon=1e-6,reactive_relative_epsilon=1e-6,
                    reactive_epsilon=1e-6,silent=true,shared_model=model,scenario_prefix=prefix,set_objective=false,
                    initial_state=starts[id],reactive_assignments=study.reactive_assignments,
                    tap_controls=taps,shunt_controls=banks,normalize_controls=normalization,droop_parameter_variables=parameters)
            end
            if solver==:ccopt && mpcc_implied_q_bounds
                # Nonnegative projection slacks and their linking equalities
                # already impose these bounds, even in the relaxed NLP.
                gi=Dict(g.id=>i for (i,g) in enumerate(c.generators))
                for a in c.attachments
                    i=gi[a.generator_id];g=c.generators[i];g.available || continue
                    d=c.controls[a.control_id];q=v.qg[i]
                    if has_lower_bound(q) && lower_bound(q)<=d.capability.q_min
                        delete_lower_bound(q);removed_q_bounds+=1
                    end
                    if has_upper_bound(q) && upper_bound(q)>=d.capability.q_max
                        delete_upper_bound(q);removed_q_bounds+=1
                    end
                end
            end
            push!(vars,v)
            if k>1
                delta=DroopOPF._add_response_constraints!(model,study,c,vars[1],v,prefix)
                if !isnothing(delta) && haskey(seeds[f].balancing_power,id)
                    set_start_value(delta,seeds[f].balancing_power[id])
                end
                isnothing(delta) || (deltas[id]=delta)
                DroopOPF._couple_equipment!(model,study.control_policy,vars[1].taps,vars[1].shunts,v)
            end
            idx=DroopOPF._bus_indices(c.network)
            for b in c.network.branches
                b.available || continue;lo,hi=angles[b.id]
                from_angle=v.va[idx[b.from_bus]];to_angle=v.va[idx[b.to_bus]]
                if from_angle isa JuMP.NonlinearExpression || to_angle isa JuMP.NonlinearExpression
                    @NLconstraint(model,lo<=from_angle-to_angle<=hi)
                else
                    @constraint(model,lo<=from_angle-to_angle<=hi)
                end
            end
        end
        blocks[f]=(;study,ids,vars,deltas)
    end
    nominal=blocks[objective_factor]
    loss_objective=sum(nominal.vars[1].pg)-sum(l.p for l in nominal.study.case.loads)
    @objective(model,Min,loss_objective)
    opts=Dict{String,Any}("tol"=>solver==:ccopt ? 1e-11 : 1e-9,"max_iter"=>record["iterations_budget"],"bound_relax_factor"=>0.)
    if solver==:ccopt
        opts["acceptable_tol"]=1e-11
        opts["relaxation_update"]=scheduled ? CCOpt.ScheduledRelaxationUpdate(sigma_init=ccopt_sigma_init,sigma_min=1e-14,target_accuracy=1e-11) : CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14)
        opts["output_file"]=joinpath(out,"solver_iterations.log")
        opts["file_print_level"]=MadNLP.INFO
        if !isnothing(mu)
            barrier=MadNLP.MonotoneUpdate(1e-11,10.);barrier.mu_init=mu
            opts["barrier"]=barrier;opts["bound_push"]=1e-8;opts["bound_fac"]=1e-8
        else
            record["strategy"]="S1-matched default barrier and bound push; relaxation rule recorded separately"
        end
    end
    for (key,value) in opts;set_optimizer_attribute(model,key,value);end
    for (key,value) in optimizer_options;set_optimizer_attribute(model,key,value);end
    isnothing(linear_solver) || set_optimizer_attribute(model,"linear_solver",linear_solver)
    set_optimizer_attribute(model,solver==:ipopt ? "max_cpu_time" : "max_wall_time",record["seconds_budget"])
    if solver==:ipopt;set_optimizer_attribute(model,"print_level",0);set_optimizer_attribute(model,"mu_strategy","adaptive");end
    record["variables"]=num_variables(model);record["constraints"]=num_constraints(model;count_variable_in_set_constraints=true)
    record["free_shared_droop_variables"]=count(v->startswith(JuMP.name(v),"shared_"),all_variables(model))
    record["redundant_q_bounds_removed"]=removed_q_bounds
    maps=[(;factor=f,id,reduction=v.reduction) for (f,b) in blocks for (id,v) in zip(b.ids,b.vars) if hasproperty(v,:reduction)]
    isempty(maps) || fd_save(joinpath(out,"network_reduction_maps.json"),maps)
    preliminary=nothing
    if feasibility_first
        penalty=sum(((getfield(parameters[control.control_id],k)-getfield(DroopSettings(seedstudy.case.controls[control.control_id]),k))/(bounds[2]-bounds[1]))^2
            for control in controls for (k,bounds) in pairs(DroopOPF._joint_droop_policy(original.case,control).ranges)
            if bounds[2]>bounds[1])
        @objective(model,Min,feasibility_regularization*penalty)
        preliminary=@timed optimize!(model)
        good=termination_status(model) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.ALMOST_LOCALLY_SOLVED,JuMP.MOI.OPTIMAL)
        record["feasibility_stage"]=(;status=string(termination_status(model)),native_success=good,elapsed_seconds=preliminary.time)
        fd_save(joinpath(out,"feasibility-stage.json"),record["feasibility_stage"])
        isnothing(stage_observer) || stage_observer(model,blocks,parameters,:feasibility,out)
        println("FEASIBILITY ",name," status=",termination_status(model));flush(stdout)
        if good
            warm_variables=all_variables(model);warm_values=value.(warm_variables)
            for (variable,initial_value) in zip(warm_variables,warm_values);set_start_value(variable,initial_value);end
            @objective(model,Min,loss_objective)
        end
    end
    timed=isnothing(preliminary) || record["feasibility_stage"].native_success ? (@timed optimize!(model)) : preliminary
    record["loss_stage_started"]=isnothing(preliminary) || record["feasibility_stage"].native_success
    record["final_objective_kind"]=record["loss_stage_started"] ? "base_active_loss" :
        feasibility_regularization>0 ? "temporary_droop_distance_regularization" : "constant_feasibility"
    record["native_optimizer_calls"]=isnothing(preliminary) ? 1 : record["feasibility_stage"].native_success ? 2 : 1
    record["elapsed_seconds"]=timed.time;record["solver_status"]=string(termination_status(model))
    record["native_success"]=termination_status(model) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.ALMOST_LOCALLY_SOLVED,JuMP.MOI.OPTIMAL)
    isnothing(stage_observer) || stage_observer(model,blocks,parameters,
        isnothing(preliminary) || record["feasibility_stage"].native_success ? :loss : :feasibility_final,out)
    if solver==:ccopt
        record["ccopt_diagnostics"]=ccopt_diagnostics(model)
        has_values(model) && fd_save(joinpath(out,"last_scenario_encoding_audit.json"),ccopt_encoding_audit(model))
        ipm=unsafe_backend(model).solver.ipm
        residual=MadNLP.primal(ipm.f).-MadNLP.primal(ipm.zl).+MadNLP.primal(ipm.zu).+ipm.jacl
        top=sortperm(abs.(residual);rev=true)[1:min(20,length(residual))]
        record["relaxed_nlp_stationarity_diagnostic"]=Dict("unscaled_infinity_norm"=>maximum(abs,residual),
            "top_coordinate_residuals"=>[Dict("internal_index"=>i,"residual"=>residual[i]) for i in top],
            "mu_final"=>ipm.mu,"scope"=>"Final relaxed NLP coordinate residual, not original-MPCC stationarity")
        has_values(model) && (record["complementarity_product_max"]=maximum(DroopOPF._complementarity_residual(v) for b in values(blocks) for v in b.vars))
    end
    record["iterations"]=try Int(JuMP.MOI.get(backend(model),JuMP.MOI.BarrierIterations())) catch; nothing end
    results=Dict{Float64,SCOPFResult}();optimized=original
    if has_values(model)
        settings=Dict(id=>DroopSettings((DroopOPF._droop_design_value(getfield(p,k)) for k in keys(p))...) for (id,p) in parameters)
        for id in sort(collect(keys(settings)));optimized=with_droop_settings(optimized,id,settings[id]);end
        write_study(joinpath(out,"controller.json"),optimized)
        refs=Dict(c.control_id=>DroopSettings(original.case.controls[c.control_id]) for c in controls)
        checks=Any[]
        for f in factors
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
                fd_save(joinpath(out,"validation-$f.json"),report)
                (;factor=f,valid=report.valid && angle_margin>=-1e-6,policy_valid=report.policy_valid,angle_min_margin_rad=angle_margin)
            catch error
                (;factor=f,valid=false,error=sprint(showerror,error))
            end
            push!(checks,assessment)
        end
        record["checks"]=checks
        record["master_objective_pu"]=objective_value(model)
        record["nominal_loss_mw"]=results[objective_factor].objective*original.case.base_power
        record["objective_demand_loss_mw"]=record["nominal_loss_mw"]
        record["objective_replay_error"]=abs(objective_value(model)-results[objective_factor].objective)
        record["accepted"]=record["native_success"] && all(x.valid for x in checks) && record["objective_replay_error"]<1e-8
    end
    fd_save(joinpath(out,"summary.json"),record)
    println("END comparison ",name," accepted=",record["accepted"]," status=",record["solver_status"]);flush(stdout)
    (;record,study=optimized,results)
end

function s2500_recover_pilot()
    original=read_study(joinpath(S2500_OUT,"pilot_study.json"));controls=s214_multi_controls(fd_inputs(500).base);angles=fd_inputs(500).angles
    rows=Any[]
    strategies=(("physical-scheduled",false,1e-6,true,"madnlp"),
                ("physical-small-mu",false,1e-10,false,"madnlp"),
                ("normalized-larger-barrier",true,1e-4,true,"ipopt"))
    paths=["examples/s2_arpae500_recovery.jl","examples/s2_arpae500_campaign.jl","Project.toml","Manifest.toml"]
    append!(paths,["artifacts/s2_scopf/ieee500_native/pilot-$s/$file" for s in ("ipopt","madnlp") for file in ("controller.json","result-1.0.json")])
    folder=joinpath(S2500_OUT,"recovery");mkpath(folder)
    fd_save(joinpath(folder,"protocol.json"),(;scope="Targeted recovery within user-confirmed 500-bus controls/bounds, unchanged equations/objective/tolerances",strategies,
        maximum_attempts=3,budget_per_attempt=(iterations=6000,native_seconds=300),run_source_hashes=Dict(p=>bytes2hex(sha256(read(joinpath(FD_ROOT,p)))) for p in paths)))
    for (name,norm,mu,sched,solver_seed) in strategies
        dir=joinpath(S2500_OUT,"pilot-$solver_seed")
        seedstudy=read_study(joinpath(dir,"controller.json"));seed=read_scopf_result(joinpath(dir,"result-1.0.json"))
        lane=s2500_targeted_attempt("recovery/$name",original,controls,seedstudy,Dict(1.0=>seed),angles;solver=:ccopt,retry=true,normalization=norm,mu,scheduled=sched)
        push!(rows,lane.record)
        fd_save(joinpath(folder,"summary.json"),(;attempts=rows,selected=lane.record["accepted"] ? lane.record["name"] : nothing))
        lane.record["accepted"] && break
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s2500_recover_pilot()
