# Native 500-bus S2 adapter. Import performs no numerical solve.
include("s2_arpae14_ccopt_recovery.jl")
const S2500_OUT=joinpath(FD_ROOT,"artifacts/s2_scopf/ieee500_native")
function s2500_seed_result(case,record)
    state=a500_state(record["state"])
    SCOPFResult(Dict{Symbol,Union{Nothing,ACState{Float64}}}(:base=>state),Dict{Symbol,Float64}(),
        (sum(state.pg)-sum(l.p for l in case.loads)),:NOT_RUN,:NO_SOLUTION,:preventive,:smooth,
        1e-6,1e-6,1e-6,"Saved S1 start",nothing,
        Dict(:base=>a500_settings(record["taps"])),Dict(:base=>a500_settings(record["susceptances"])),
        TapControl[],ShuntControl[],SCOPFControlPolicy(taps=:corrective,shunts=:corrective))
end
function s2500_attempt(name,original,controls,seedstudy,seeds,angles;solver=:ipopt,retry=false,factors=(1.,))
    out=joinpath(S2500_OUT,name);mkpath(out)
    record=Dict{String,Any}("name"=>name,"solver"=>string(solver),"retry"=>retry,
        "accepted"=>false,"iterations_budget"=>retry || solver==:ccopt ? 6000 : 3000,"seconds_budget"=>retry || solver==:ccopt ? 300. : 120.,
        "objective_kind"=>"nominal_base_active_loss","training_factors"=>collect(factors))
    fd_save(joinpath(out,"contract.json"),record)
    println("START comparison ",name);flush(stdout)
    encoding=solver==:ccopt ? :complementarity : :smooth
    model=Model(solver==:ccopt ? CCOpt.Optimizer : solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer);set_silent(model)
    solver==:ccopt && DroopOPF.MathOptComplements.Bridges.add_all_bridges(model)
    record["encoding"]=string(encoding)
    record["strategy"]=solver==:ccopt ? (retry ? "proportional small-barrier recovery" : "scheduled relaxation from full primal witness") : "smooth full-primal warm start"
    record["relaxation_rule"]=!retry ? "ScheduledRelaxationUpdate sigma_init=1e-6, sigma_min=1e-14, target_accuracy=1e-11" : "ProportionalRelaxationUpdate sigma_min=1e-14"
    record["normalization"]="droop and equipment physical bounds mapped to unit intervals"
    record["initialization"]="Declared saved S1 or accepted S2 full primal witness; selected controls remain free"
    parameters=Dict{Int,NamedTuple}()
    for control in controls
        p=DroopOPF._joint_droop_policy(original.case,control);names=keys(p.ranges)
        initial=DroopSettings(seedstudy.case.controls[control.control_id])
        parameters[control.control_id]=NamedTuple{names}(Tuple(DroopOPF._droop_design_variable(model,
            "shared_$(control.control_id)_$k",getfield(p.ranges,k),getfield(initial,k);normalize=true) for k in names))
    end
    blocks=Dict{Float64,Any}()
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
        opts["relaxation_update"]=!retry ? CCOpt.ScheduledRelaxationUpdate(sigma_init=1e-6,sigma_min=1e-14,target_accuracy=1e-11) : CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14)
        opts["output_file"]=joinpath(out,"solver_iterations.log")
        opts["file_print_level"]=MadNLP.INFO
        barrier=MadNLP.MonotoneUpdate(1e-11,10.);barrier.mu_init=retry ? 1e-8 : 1e-6
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
        record["nominal_loss_mw"]=results[1.].objective*original.case.base_power
        record["objective_replay_error"]=abs(objective_value(model)-results[1.].objective)
        record["accepted"]=record["native_success"] && all(x.valid for x in checks) && record["objective_replay_error"]<1e-8
    end
    fd_save(joinpath(out,"summary.json"),record)
    println("END comparison ",name," accepted=",record["accepted"]," status=",record["solver_status"]);flush(stdout)
    (;record,study=optimized,results)
end

function s2500_pilot(confirmation)
    isempty(strip(confirmation)) && error("Explicit 500-bus equipment confirmation required")
    mkpath(S2500_OUT)
    x=fd_inputs(500);case=x.base
    selected=JSON.parsefile(joinpath(FD_ROOT,"artifacts/s1_free_droop/500/attempts/design-droop_tap_shunt-1.0-cost-ccopt.json"))
    @assert selected["accepted"]
    equipment=a500_policy(case,"tap_shunt";reference=selected)
    @assert length(equipment.tap_controls)==131 && length(equipment.shunt_controls)==11
    catalog=contingency_catalog(case);write_contingency_catalog(joinpath(S2500_OUT,"catalog.json"),catalog)
    full=Study(case;contingencies=eligible_contingencies(catalog),mode=:preventive,
        participation=Dict(g.id=>g.p_max for g in case.generators if g.available),equipment...,
        control_policy=SCOPFControlPolicy(taps=:corrective,shunts=:corrective))
    controls=s214_multi_controls(case)
    seedstudy=full
    for (id,settings) in selected["droops"]
        seedstudy=with_droop_settings(seedstudy,parse(Int,id),DroopSettings(settings["slope"],settings["v_ref"],settings["deadband_low"],settings["deadband_high"]))
    end
    seed=s2500_seed_result(case,selected)
    physical=with_shunt_settings(with_tap_settings(seedstudy.case,seed.tap_settings[:base]),seed.shunt_settings[:base])
    @assert validate_equilibrium(physical,seed.states[:base]).valid
    scores=contingency_screening_scores(physical,seed.states[:base];catalog)
    chosen=Symbol[]
    for kind in (:line,:transformer,:generator)
        family=filter(score->score.device_kind==kind,scores)
        isempty(family) || push!(chosen,first(sort(family;by=s->-s.raw_score)).contingency_id)
    end
    pilot=DroopOPF._copy_study(seedstudy;contingencies=filter(c->c.id in chosen,full.contingencies))
    @assert length(pilot.contingencies)==3
    write_study(joinpath(S2500_OUT,"pilot_study.json"),pilot)
    files=["Project.toml","Manifest.toml","examples/s2_arpae500_campaign.jl","examples/s2_arpae14_ccopt_recovery.jl",
        "examples/s2_arpae14_solver_designs.jl","examples/s2_arpae14_multidemand.jl","examples/s2_arpae14_followup.jl","examples/s2_arpae14_campaign.jl",
        "artifacts/s1_arpae500/calibrated-study.json","artifacts/s1_free_droop/500/attempts/design-droop_tap_shunt-1.0-cost-ccopt.json"]
    append!(files,[relpath(joinpath(root,file),FD_ROOT) for (root,_,fs) in walkdir(joinpath(FD_ROOT,"src")) for file in fs if endswith(file,".jl")])
    fd_save(joinpath(S2500_OUT,"protocol.json"),(;confirmation,tap_controls=full.tap_controls,shunt_controls=full.shunt_controls,
        control_policy=full.control_policy,controls,pilot_contingencies=chosen,pilot_selection="Highest saved-reference loading/share in each eligible line/transformer/generator family; ranking is not a security pass",
        eligible_outages=length(full.contingencies),excluded_islanding=count(e->e.disposition==:excluded,catalog.entries),
        objective="Base active loss; preventive Pmax-weighted response; outage feasibility only",smoothing_absolute_q_pu=1e-6,
        primary_budget=(smooth_iterations=3000,smooth_seconds=120,ccopt_iterations=6000,ccopt_seconds=300),
        retry_budget=(max_per_lane=1,iterations=6000,native_seconds=300),
        island_scope="Explicit catalogue and structural load-isolation failures; no discarded load or generator trip is silently assumed",
        run_source_hashes=Dict(p=>bytes2hex(sha256(read(joinpath(FD_ROOT,p)))) for p in files)))
    rows=Any[];beststudy=pilot;bestseeds=Dict(1.0 => seed);best=nothing
    for solver in (:ipopt,:madnlp,:ccopt)
        lane=s2500_attempt("pilot-$solver",pilot,controls,beststudy,bestseeds,x.angles;solver)
        push!(rows,lane.record)
        if !lane.record["accepted"]
            warm=haskey(lane.results,1.) && !isnothing(lane.results[1.].states[:base]) ? lane.results : bestseeds
            lane=s2500_attempt("retry-pilot-$solver",pilot,controls,lane.study,warm,x.angles;solver,retry=true)
            push!(rows,lane.record)
        end
        if lane.record["accepted"]
            beststudy=lane.study;bestseeds=lane.results;best=lane.record["name"]
        end
        fd_save(joinpath(S2500_OUT,"pilot_summary.json"),(;attempts=rows,last_accepted=best,pilot_contingencies=chosen))
    end
    fd_save(joinpath(S2500_OUT,"STATUS.json"),(;status=all(any(r["accepted"] && r["solver"]==string(s) for r in rows) for s in (:ipopt,:madnlp,:ccopt)) ? "pilot_qualified" : "pilot_partially_qualified",
        pilot_attempts=length(rows),eligible_outages=length(full.contingencies),excluded_islanding=count(e->e.disposition==:excluded,catalog.entries),
        all_connected_outages_qualified=false,multidemand_qualified=false,full_n1_accepted=false,closed=false))
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==1 || error("Supply explicit equipment confirmation")
    s2500_pilot(only(ARGS))
end
