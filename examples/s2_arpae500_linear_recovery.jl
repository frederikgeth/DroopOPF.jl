# Diagnostic backend recovery after sampled MUMPS factorization bottleneck.
# Physics and acceptance gates are identical to the saved design adapter.
include("s2_arpae500_followup.jl")
function s2500_linear_attempt(name,original,controls,seedstudy,seeds,angles;solver=:ipopt,retry=false,factors=(1.,),normalization=false,mu=1e-6,scheduled=true,linear_solver=MadNLP.UmfpackSolver)
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
    record["normalization"]=normalization ? "physical bounds mapped to unit intervals" : "physical coordinates"
    record["initial_barrier"]=solver==:ccopt ? mu : nothing;record["scheduled_relaxation"]=solver==:ccopt ? scheduled : nothing
    record["initialization"]="Declared saved S1 or accepted S2 full primal witness; selected controls remain free"
    parameters=Dict{Int,NamedTuple}()
    for control in controls
        p=DroopOPF._joint_droop_policy(original.case,control);names=keys(p.ranges)
        initial=DroopSettings(seedstudy.case.controls[control.control_id])
        parameters[control.control_id]=NamedTuple{names}(Tuple(DroopOPF._droop_design_variable(model,
            "shared_$(control.control_id)_$k",getfield(p.ranges,k),getfield(initial,k);normalize=normalization) for k in names))
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
                    normalize_controls=normalization,droop_parameter_variables=parameters)
            else
                DroopOPF._build_acopf_model(c;voltage_epsilon=1e-6,reactive_relative_epsilon=1e-6,
                    reactive_epsilon=1e-6,silent=true,shared_model=model,scenario_prefix=prefix,set_objective=false,
                    initial_state=starts[id],reactive_assignments=study.reactive_assignments,
                    tap_controls=taps,shunt_controls=banks,normalize_controls=normalization,droop_parameter_variables=parameters)
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
        opts["relaxation_update"]=scheduled ? CCOpt.ScheduledRelaxationUpdate(sigma_init=1e-6,sigma_min=1e-14,target_accuracy=1e-11) : CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14)
        opts["output_file"]=joinpath(out,"solver_iterations.log")
        opts["file_print_level"]=MadNLP.INFO
        barrier=MadNLP.MonotoneUpdate(1e-11,10.);barrier.mu_init=mu
        opts["barrier"]=barrier;opts["bound_push"]=1e-8;opts["bound_fac"]=1e-8
    end
    opts["linear_solver"]=linear_solver
    record["linear_solver"]=string(linear_solver)
    for (key,value) in opts;set_optimizer_attribute(model,key,value);end
    set_optimizer_attribute(model,solver==:ipopt ? "max_cpu_time" : "max_wall_time",record["seconds_budget"])
    if solver==:ipopt;set_optimizer_attribute(model,"print_level",0);set_optimizer_attribute(model,"mu_strategy","adaptive");end
    record["variables"]=num_variables(model);record["constraints"]=num_constraints(model;count_variable_in_set_constraints=true)
    timed=@timed optimize!(model)
    record["elapsed_seconds"]=timed.time;record["solver_status"]=string(termination_status(model))
    record["native_success"]=termination_status(model) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.ALMOST_LOCALLY_SOLVED,JuMP.MOI.OPTIMAL)
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

function s2500_run_linear_recovery(confirmation;madnlp_seed=nothing)
    isempty(strip(confirmation)) && error("Confirmed scope required")
    folder=joinpath(S2500_OUT,"linear_recovery");mkpath(folder)
    strategies=Any[]
    if !isnothing(madnlp_seed)
        push!(strategies,(;solver=:madnlp,name="expanded-madnlp-umfpack",seed_directory=madnlp_seed,
            original_directory="qualification/nominal-ipopt/round-2/master",normalization=true))
    end
    push!(strategies,(;solver=:ccopt,name="pilot-ccopt-umfpack",seed_directory="recovery/physical-small-mu",
        original_directory="pilot-ipopt",normalization=false))
    paths=["examples/s2_arpae500_linear_recovery.jl","examples/s2_arpae500_followup.jl",
        "examples/s2_arpae500_qualification.jl","examples/s2_arpae500_recovery.jl","examples/s2_arpae500_campaign.jl",
        "Project.toml","Manifest.toml","artifacts/s1_free_droop/500/angle_limits.json",
        "test/data/arpae/c1_network01/results/scenario_02_pmin0_qsym/network_model.json"]
    for strategy in strategies
        append!(paths,[relpath(joinpath(S2500_OUT,strategy.seed_directory,file),FD_ROOT) for file in ("optimized-1.0.json","result-1.0.json","summary.json")])
    end
    fd_save(joinpath(folder,"protocol.json"),(;confirmation,strategies,maximum_attempts=length(strategies),
        reason="One-second sample of expanded Ipopt retry showed MUMPS factorization; 523-second wall time versus 300-second native CPU budget",
        numerical_change="UMFPACK linear solver with identical equations, physical bounds, objective and acceptance tolerances",
        budget_per_attempt=(iterations=6000,native_seconds=300),
        run_source_hashes=Dict(p=>bytes2hex(sha256(read(joinpath(FD_ROOT,p)))) for p in paths)))
    rows=Any[];controls=s214_multi_controls(fd_inputs(500).base);angles=fd_inputs(500).angles
    for strategy in strategies
        dir=joinpath(S2500_OUT,strategy.seed_directory)
        original=read_study(joinpath(S2500_OUT,strategy.original_directory,"input-1.0.json"))
        seedstudy=read_study(joinpath(dir,"optimized-1.0.json"));seed=read_scopf_result(joinpath(dir,"result-1.0.json"))
        lane=s2500_linear_attempt("linear_recovery/"*strategy.name,original,controls,seedstudy,Dict(1.0=>seed),angles;
            solver=strategy.solver,retry=true,normalization=strategy.normalization,mu=1e-10,scheduled=false)
        push!(rows,lane.record);fd_save(joinpath(folder,"summary.json"),(;attempts=rows))
    end
end
