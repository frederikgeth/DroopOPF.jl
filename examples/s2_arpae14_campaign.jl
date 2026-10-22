# Confirmed 14-bus S2 campaign: native DroopOPF, no changes to imported references.
include("s1_free_droop.jl")
const S214_OUT=joinpath(FD_ROOT,"artifacts/s2_scopf/ieee14_native")
s214_save(name,x)=fd_save(joinpath(S214_OUT,name),x)
function s214_hook(study,angles,stats)
    function hook(model)
        for (k,c) in enumerate([study.case;[scenario_case(study.case,x) for x in study.contingencies]])
            idx=DroopOPF._bus_indices(c.network)
            for b in c.network.branches
                b.available || continue;lo,hi=angles[b.id]
                f=variable_by_name(model,"scenario_$(k)_va[$(idx[b.from_bus])]")
                t=variable_by_name(model,"scenario_$(k)_va[$(idx[b.to_bus])]")
                @constraint(model,lo<=f-t<=hi)
            end
        end
        pg=[variable_by_name(model,"scenario_1_pg[$i]") for i in eachindex(study.case.generators)]
        @objective(model,Min,sum(pg)-sum(l.p for l in study.case.loads))
        stats["variables"]=num_variables(model);stats["constraints"]=num_constraints(model;count_variable_in_set_constraints=true)
    end
end
function s214_starts(study,base,prior=nothing)
    states=Dict{Symbol,ACState}()
    for (id,c) in zip([:base;[x.id for x in study.contingencies]],[study.case;[scenario_case(study.case,x) for x in study.contingencies]])
        if !isnothing(prior) && !isnothing(get(prior.states,id,nothing))
            states[id]=prior.states[id];continue
        end
        pg=copy(base.pg);qg=copy(base.qg)
        lost=sum(pg[i] for (i,g) in enumerate(c.generators) if !g.available;init=0.)
        alpha=DroopOPF._participation(study,c)
        for (i,g) in enumerate(c.generators)
            pg[i]=g.available ? clamp(pg[i]+alpha[i]*lost,g.p_min,g.p_max) : 0.
            g.available || (qg[i]=0.)
        end
        states[id]=ACState(base.vm,base.va,pg,qg)
    end
    states
end
function s214_attempt(name,study,controls,starts,angles;solver=:ipopt,retry=false)
    out=joinpath(S214_OUT,name);mkpath(out)
    write_study(joinpath(out,"input.json"),study)
    fd_save(joinpath(out,"starts.json"),starts)
    r=Dict{String,Any}("name"=>name,"solver"=>string(solver),"retry"=>retry,
        "accepted"=>false,"physical_valid"=>false,"design_policy_valid"=>isempty(controls),
        "scenario_count"=>1+length(study.contingencies),"objective_kind"=>"base_active_loss",
        "controls"=>a500_json(controls),"iterations_budget"=>retry ? 3000 : 600,"seconds_budget"=>retry ? 120. : 20.)
    opts=Dict{String,Any}("tol"=>solver==:ccopt ? 1e-11 : 1e-9,"max_iter"=>r["iterations_budget"],"bound_relax_factor"=>0.)
    if solver==:ipopt
        opts["max_cpu_time"]=r["seconds_budget"];opts["print_level"]=0;opts["mu_strategy"]="adaptive"
    else
        opts["max_wall_time"]=r["seconds_budget"]
    end
    if solver==:ccopt
        opts["acceptable_tol"]=1e-11;opts["relaxation_update"]=CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14)
        b=MadNLP.MonotoneUpdate(1e-11,10.);b.mu_init=retry ? 1e-8 : 1e-6;opts["barrier"]=b
        opts["bound_push"]=1e-8;opts["bound_fac"]=1e-8
    end
    fd_save(joinpath(out,"contract.json"),r)
    println("START ",name);flush(stdout)
    result=nothing;design=nothing;optimized=study
    try
        parameters=Dict{Int,NamedTuple}()
        function build_parameters(model)
            for control in controls
                p=DroopOPF._joint_droop_policy(study.case,control);names=keys(p.ranges)
                parameters[control.control_id]=NamedTuple{names}(Tuple(DroopOPF._droop_design_variable(model,
                    "s214_$(control.control_id)_$k",getfield(p.ranges,k),getfield(p.initial,k)) for k in names))
            end
            parameters
        end
        kw=solver==:ccopt ? (encoding=:complementarity,) : (optimizer_factory=solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer,)
        timed=@timed solve_scopf(study;initial_states=starts,smooth_epsilon=1e-6,smooth_reactive_epsilon=1e-6,
            optimizer_attributes=opts,kw...,_model_hook=s214_hook(study,angles,r),
            _droop_parameter_builder=isempty(controls) ? nothing : build_parameters)
        result=timed.value;r["elapsed_seconds"]=timed.time;r["allocated_bytes"]=timed.bytes
        write_scopf_result(joinpath(out,"result.json"),result)
        if !isempty(controls)
            settings=Dict(id=>DroopSettings((DroopOPF._droop_design_value(getfield(p,k)) for k in keys(p))...) for (id,p) in parameters)
            refs=Dict(c.control_id=>DroopSettings(study.case.controls[c.control_id]) for c in controls)
            design=SCOPFDroopDesignResult(collect(controls),refs,settings,result)
            write_droop_security(joinpath(out,"design.json"),design)
            optimized=with_droop_settings(study,design)
            r["design_policy_valid"]=validate_droop_design(study,design).policy_valid
        end
        write_study(joinpath(out,"optimized_input.json"),optimized)
        report=equilibrium_report(optimized,result);write_scopf_report(joinpath(out,"validation.json"),report)
        r["solver_status"]=string(result.termination_status);r["native_success"]=result.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
        angle_margin=Inf;all_present=true;audits=Dict{String,Any}()
        for (id,c) in zip([:base;[x.id for x in optimized.contingencies]],[optimized.case;[scenario_case(optimized.case,x) for x in optimized.contingencies]])
            state=get(result.states,id,nothing)
            if isnothing(state);all_present=false;continue;end
            taps=result.tap_settings[id];banks=result.shunt_settings[id]
            physical=with_shunt_settings(with_tap_settings(c,taps),banks);idx=DroopOPF._bus_indices(c.network)
            for b in c.network.branches
                b.available || continue;lo,hi=angles[b.id];a=state.va[idx[b.from_bus]]-state.va[idx[b.to_bus]]
                angle_margin=min(angle_margin,a-lo,hi-a)
            end
            audits[string(id)]=a500_json(validate_equilibrium(physical,state))
        end
        fd_save(joinpath(out,"physical_checks.json"),audits)
        r["angle_min_margin_rad"]=angle_margin;r["physical_valid"]=report.physical_valid && all_present && angle_margin>=-1e-6 && r["design_policy_valid"]
        base=get(result.states,:base,nothing)
        if !isnothing(base)
            r["base_loss_mw"]=(sum(base.pg)-sum(l.p for l in study.case.loads))*study.case.base_power
            r["objective_replay_error"]=abs(result.objective-r["base_loss_mw"]/study.case.base_power)
        end
        r["accepted"]=report.valid && r["physical_valid"] && get(r,"objective_replay_error",Inf)<1e-8
        write_scopf_evaluation_report(joinpath(out,"evaluation.md"),optimized,result;context="Native 14-bus S2; source Rate A in all states; base-loss objective; no full N-1 claim if catalog excludes islands.")
    catch error
        error isa InterruptException && rethrow()
        r["error"]=sprint(showerror,error);r["accepted"]=false
    end
    fd_save(joinpath(out,"summary.json"),r)
    println("END ",name," accepted=",r["accepted"]," status=",get(r,"solver_status",get(r,"error","unknown")));flush(stdout)
    (;record=r,result,study=optimized,design)
end
function s214_run()
    x=fd_inputs(14);case=x.base;base=a500_state(x.ref["state"])
    @assert length(case.network.buses)==14 && length(case.controls)==5
    equipment=a500_policy(case,"tap_shunt";reference=x.ref)
    @assert length(equipment.tap_controls)==3 && length(equipment.shunt_controls)==1
    catalog=contingency_catalog(case);write_contingency_catalog(joinpath(mkpath(S214_OUT),"catalog.json"),catalog)
    contingencies=eligible_contingencies(catalog)
    full=Study(case;contingencies,mode=:preventive,participation=Dict(g.id=>g.p_max for g in case.generators if g.available),
        equipment...,control_policy=SCOPFControlPolicy(taps=:corrective,shunts=:corrective))
    controls=[DroopControl(i;slope_bounds=(.02/(d.capability.q_max-d.capability.q_min),.08/(d.capability.q_max-d.capability.q_min)),
        v_ref_bounds=(d.schedule.v_ref-.02,d.schedule.v_ref+.02)) for (i,d) in enumerate(case.controls)]
    protocol=(;confirmation="User confirmed all four items for 14-bus S2 and bounded retries on 2026-10-15",
        scope="Nominal demand, full enumeration of all connected eligible branch/generator outages; source-two subset is bring-up only; no islanding security claim",
        equipment,control_policy=full.control_policy,active_response="Preventive dispatch with Pmax-weighted automatic balancing, renormalized over surviving generators; P/Q capability bounds enforced in every state",
        controls,objective="Base active losses; outage states impose feasibility only",thermal="Source Rate A in every state, conservative relative to source contingency Rate C",
        angles=x.angles,primary_budget=(iterations=600,native_seconds=20),retry_budget=(iterations=3000,native_seconds=120,max_per_lane=1),
        source_hashes=Dict(f=>bytes2hex(sha256(read(joinpath(FD_ROOT,f)))) for f in ("artifacts/s1_arpae14_joint_reference/relative5-study.json","artifacts/s1_arpae14_closeout/calibration_reference.json","examples/s2_arpae14_campaign.jl")))
    s214_save("protocol.json",protocol)
    rows=Any[]
    function runlane(name,study,selected,seed;solver=:ipopt,retry=false)
        lane=s214_attempt(name,study,selected,s214_starts(study,base,seed),x.angles;solver,retry)
        push!(rows,lane.record);s214_save("summary.json",(;attempts=rows,eligible=length(contingencies),excluded=count(e->e.disposition==:excluded,catalog.entries)))
        lane
    end
    baseline=runlane("base-frozen-ipopt",DroopOPF._copy_study(full;contingencies=Contingency[]),DroopControl[],nothing)
    subset=DroopOPF._copy_study(full;contingencies=filter(c->c.id in (:branch_9,:generator_3),contingencies))
    @assert length(subset.contingencies)==2
    source=runlane("source2-frozen-ipopt",subset,DroopControl[],baseline.result)
    source_design=runlane("source2-designed-ipopt",subset,controls,source.result)
    fixed=runlane("full-frozen-ipopt",full,DroopControl[],source.result)
    if !fixed.record["accepted"]
        fixed=runlane("retry-full-frozen-ipopt",full,DroopControl[],fixed.result;retry=true)
    end
    designed=runlane("full-designed-ipopt",full,controls,fixed.result)
    if !designed.record["accepted"]
        designed=runlane("retry-full-designed-ipopt",full,controls,designed.result;retry=true)
    end
    runlane("full-frozen-madnlp",full,DroopControl[],fixed.result;solver=:madnlp)
    alternative=runlane("full-designed-madnlp",full,controls,designed.result;solver=:madnlp)
    for (name,lane) in (("frozen",fixed),("designed",designed))
        lane.record["accepted"] || continue
        exact=runlane("exact-$name-ccopt",lane.study,DroopControl[],lane.result;solver=:ccopt)
        exact.record["accepted"] || runlane("retry-exact-$name-ccopt",lane.study,DroopControl[],exact.result;solver=:ccopt,retry=true)
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s214_run()
