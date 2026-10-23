# Research campaign adapter: one shared controller, five independent demand blocks.
# Importing this file performs no solve. Library behavior remains unchanged.
include("s2_arpae14_followup.jl")
const S214_MULTI=joinpath(S214_OUT,"multidemand")
const S214_TRAIN=(.9,.95,1.,1.05,1.1)
const S214_HOLD=(.925,.975,1.025,1.075)

function s214_multi_controls(case)
    [DroopControl(i;slope_bounds=(.02/(d.capability.q_max-d.capability.q_min),
        .08/(d.capability.q_max-d.capability.q_min)),
        v_ref_bounds=(d.schedule.v_ref-.02,d.schedule.v_ref+.02)) for (i,d) in enumerate(case.controls)]
end

function s214_multi_attempt(name,original,controls,seedstudy,seeds,angles;solver=:ipopt,retry=false)
    out=joinpath(S214_MULTI,name);mkpath(out)
    record=Dict{String,Any}("name"=>name,"solver"=>string(solver),"retry"=>retry,
        "accepted"=>false,"iterations_budget"=>retry ? 3000 : 600,"seconds_budget"=>retry ? 120. : 20.,
        "objective_kind"=>"nominal_base_active_loss","training_factors"=>collect(S214_TRAIN))
    fd_save(joinpath(out,"contract.json"),record)
    println("START multi ",name);flush(stdout)
    model=Model(solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer);set_silent(model)
    parameters=Dict{Int,NamedTuple}()
    for control in controls
        p=DroopOPF._joint_droop_policy(original.case,control);names=keys(p.ranges)
        initial=DroopSettings(seedstudy.case.controls[control.control_id])
        parameters[control.control_id]=NamedTuple{names}(Tuple(DroopOPF._droop_design_variable(model,
            "shared_$(control.control_id)_$k",getfield(p.ranges,k),getfield(initial,k)) for k in names))
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
            _,v=DroopOPF._build_acopf_model(c;voltage_epsilon=1e-6,reactive_relative_epsilon=1e-6,
                reactive_epsilon=1e-6,silent=true,shared_model=model,scenario_prefix=prefix,set_objective=false,
                initial_state=starts[id],reactive_assignments=study.reactive_assignments,
                tap_controls=DroopOPF._scenario_tap_controls(study,c),shunt_controls=study.shunt_controls,
                droop_parameter_variables=parameters)
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
    opts=Dict("tol"=>1e-9,"max_iter"=>record["iterations_budget"],"bound_relax_factor"=>0.)
    for (key,value) in opts;set_optimizer_attribute(model,key,value);end
    set_optimizer_attribute(model,solver==:ipopt ? "max_cpu_time" : "max_wall_time",record["seconds_budget"])
    if solver==:ipopt;set_optimizer_attribute(model,"print_level",0);set_optimizer_attribute(model,"mu_strategy","adaptive");end
    record["variables"]=num_variables(model);record["constraints"]=num_constraints(model;count_variable_in_set_constraints=true)
    timed=@timed optimize!(model)
    record["elapsed_seconds"]=timed.time;record["solver_status"]=string(termination_status(model))
    record["native_success"]=termination_status(model) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.ALMOST_LOCALLY_SOLVED,JuMP.MOI.OPTIMAL)
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
                Symbol(string(termination_status(model))),Symbol(string(primal_status(model))),b.study.mode,:smooth,
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
    println("END multi ",name," accepted=",record["accepted"]," status=",record["solver_status"]);flush(stdout)
    (;record,study=optimized,results)
end

function s214_multidemand(confirmation)
    isempty(strip(confirmation)) && error("Explicit equipment confirmation is required")
    mkpath(S214_MULTI)
    original=read_study(joinpath(S214_OUT,"full-frozen-ipopt/input.json"))
    selected=read_study(joinpath(S214_OUT,"full-designed-ipopt/optimized_input.json"))
    controls=s214_multi_controls(original.case);angles=fd_inputs(14).angles
    sourcepaths=["Project.toml","Manifest.toml","examples/s2_arpae14_multidemand.jl",
        "examples/s2_arpae14_campaign.jl","examples/s2_arpae14_followup.jl"]
    append!(sourcepaths,[relpath(joinpath(root,file),FD_ROOT) for (root,_,files) in walkdir(joinpath(FD_ROOT,"src")) for file in files if endswith(file,".jl")])
    fd_save(joinpath(S214_MULTI,"protocol.json"),(;confirmation,training_factors=S214_TRAIN,held_out_factors=S214_HOLD,
        controls,tap_controls=original.tap_controls,shunt_controls=original.shunt_controls,control_policy=original.control_policy,
        objective="100-percent demand base active losses, all other training states impose feasibility",
        primary_budget=(iterations=600,native_seconds=20),retry_budget=(iterations=3000,native_seconds=120,max_per_backend=1),
        fixed_validation="Freeze the selected accepted controller across all nine demands, Ipopt/MadNLP/CCOpt; one bounded retry for failed lanes",
        island_assumption="G5 trip and unloaded bus8 disconnection, retained-network steady-state projection; no dynamic claim",
        run_source_hashes=Dict(f=>bytes2hex(sha256(read(joinpath(FD_ROOT,f)))) for f in sourcepaths)))
    seeds=Dict(f=>read_scopf_result(joinpath(S214_FOLLOWUP,"$(f<1 ? "retry-" : "")ipopt-demand-$f/result.json")) for f in S214_TRAIN)
    rows=Any[];accepted=Any[]
    for solver in (:ipopt,:madnlp)
        lane=s214_multi_attempt("design-$solver",original,controls,selected,seeds,angles;solver)
        push!(rows,lane.record)
        if !lane.record["accepted"]
            warm=length(lane.results)==5 ? lane.results : seeds
            lane=s214_multi_attempt("retry-design-$solver",original,controls,lane.study,warm,angles;solver,retry=true)
            push!(rows,lane.record)
        end
        lane.record["accepted"] && push!(accepted,lane)
        fd_save(joinpath(S214_MULTI,"design_summary.json"),(;attempts=rows))
    end
    if isempty(accepted)
        fd_save(joinpath(S214_MULTI,"STATUS.json"),(;status="design_unqualified",general_full_n1_claim=false,
            reason="No accepted shared design after bounded retries; no frozen evaluation of an unqualified controller"))
        return
    end
    lane=accepted[argmin([x.record["nominal_loss_mw"] for x in accepted])]
    write_study(joinpath(S214_MULTI,"selected_controller.json"),lane.study)
    fd_save(joinpath(S214_MULTI,"selection.json"),(;name=lane.record["name"],criterion="lowest nominal loss among accepted multi-demand designs"))
    evalrows=Any[]
    for solver in (:ipopt,:madnlp,:ccopt),f in (S214_TRAIN...,S214_HOLD...)
        st=DroopOPF._copy_study(lane.study;case=DroopOPF._feasibility_scaled_case(lane.study.case,f))
        nearest=S214_TRAIN[argmin(abs.(collect(S214_TRAIN).-f))]
        seed=lane.results[nearest]
        r=s214_attempt("multidemand/frozen-$(solver)-demand-$f",st,DroopControl[],s214_starts(st,seed.states[:base],seed),angles;solver)
        primary=r.record
        if !r.record["accepted"]
            r=s214_attempt("multidemand/retry-frozen-$(solver)-demand-$f",st,DroopControl[],s214_starts(st,seed.states[:base],r.result),angles;solver,retry=true)
        end
        projection=isnothing(r.result) ? nothing : s214_island_projection(st,r.result,angles)
        isnothing(projection) || fd_save(joinpath(S214_MULTI,"island-frozen-$(solver)-demand-$f.json"),projection)
        push!(evalrows,(;solver,factor=f,held_out=f in S214_HOLD,primary,final=r.record,
            island_valid=!isnothing(projection) && projection.valid,
            accepted_with_trip_assumption=r.record["accepted"] && !isnothing(projection) && projection.valid))
        fd_save(joinpath(S214_MULTI,"evaluation_summary.json"),(;attempts=evalrows))
    end
    fd_save(joinpath(S214_MULTI,"STATUS.json"),(;status=all(x.accepted_with_trip_assumption for x in evalrows) ? "qualified_sampled_multidemand" : "partially_qualified_sampled_multidemand",
        selected_design=lane.record["name"],design_attempts=length(rows),evaluation_lanes=length(evalrows),
        accepted_evaluation_lanes=count(x->x.accepted_with_trip_assumption,evalrows),general_full_n1_claim=false))
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==1 || error("Supply explicit campaign confirmation as one argument")
    s214_multidemand(only(ARGS))
end
