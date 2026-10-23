# Confirmed 105% polish, continuation capped at 106.25%, and three-backend masters.
include("s2_500bus_scaled_mpcc.jl")
const FM_OUT=joinpath(S2500_OUT,"finish_105_multidemand")
const FM_SOURCE=read(@__FILE__,String)
const FM_EVENTS=(:branch_36,:branch_219,:branch_562,:generator_14,:generator_60)
const FM_FACTORS=(.9,.95,1.,1.05,1.0625)

function fm_cc_ac(c;voltage_epsilon,reactive_relative_epsilon,reactive_epsilon,power_balance_slacks,kwargs...)
    m,v=sdq_scaled_mpcc(c;power_balance_slacks,kwargs...)
    gi=Dict(g.id=>i for(i,g) in enumerate(c.generators))
    for a in c.attachments
        g=c.generators[gi[a.generator_id]];g.available || continue
        d=c.controls[a.control_id];q=v.qg[gi[a.generator_id]]
        has_lower_bound(q) && lower_bound(q)<=d.capability.q_min && delete_lower_bound(q)
        has_upper_bound(q) && upper_bound(q)>=d.capability.q_max && delete_upper_bound(q)
    end
    m,v
end

# A clipped smooth droop already implies its Q interval. Retain stricter physical bounds.
function fm_smooth_cap_ac(c;kwargs...)
    m,v=nr_build_ac(c;kwargs...)
    gi=Dict(g.id=>i for(i,g) in enumerate(c.generators))
    for a in c.attachments
        c.generators[gi[a.generator_id]].available || continue
        d=c.controls[a.control_id];q=v.qg[gi[a.generator_id]]
        has_lower_bound(q) && lower_bound(q)<=d.capability.q_min && delete_lower_bound(q)
        has_upper_bound(q) && upper_bound(q)>=d.capability.q_max && delete_upper_bound(q)
    end
    m,v
end

# Smooth, dimensionless positive departures; no duplicate thermal/voltage proxies.
# All physical emergency bounds stay hard and are audited independently.
function fm_departure(built)
    m=built.m;terms=Any[];epsilon=1e-6
    for b in built.blocks
        b.id==:base && continue
        for(i,bus) in enumerate(b.normal.network.buses)
            voltage=b.v.vm[i];lo=bus.v_min;hi=bus.v_max
            push!(terms,@NLexpression(m,((lo-voltage)+sqrt((lo-voltage)^2+epsilon^2))/(2*.05)))
            push!(terms,@NLexpression(m,((voltage-hi)+sqrt((voltage-hi)^2+epsilon^2))/(2*.05)))
        end
        for branch in b.normal.network.branches
            branch.available || continue
            rate=branch.thermal_limit
            for side in (true,false)
                p,q=b.v.terminal_powers[(branch.id,side)]
                excess=@NLexpression(m,(p^2+q^2)/rate^2-1.)
                push!(terms,@NLexpression(m,(excess+sqrt(excess^2+epsilon^2))/(2*.21)))
            end
        end
    end
    @NLexpression(m,sum(terms[k] for k in eachindex(terms)))
end

function fm_attempt(label,stage,factors,seed,events;solver=:ipopt,zero_shedding=false,
    budgets=Dict{Symbol,Float64}(),seconds=120.,retry=false,fixed_controller=false,
    optimizer_options=Dict{String,Any}(),check_start=false,output_root=FM_OUT,
    direct_relief=false,zero_dr=false,objective_scale=1.,native_call_limit=40,implied_q_bounds=false,emergency=true)
    isfinite(objective_scale) && objective_scale>0 || error("Objective scaling must be positive")
    mkpath(output_root)
    folder=joinpath(output_root,label);ispath(folder) && error("Preserve prior attempt: $folder")
    calls=sum(length(JSON.parsefile(joinpath(p,"stages.json"))) for p in readdir(output_root;join=true)
        if isdir(p) && isfile(joinpath(p,"stages.json"));init=0)
    calls<native_call_limit || error("Confirmed campaign reached its native master-call bound: $native_call_limit")
    mkpath(folder);write(joinpath(folder,"executed_driver.jl"),FM_SOURCE)
    write(joinpath(folder,"executed_adapter.jl"),EL_EXECUTED_SOURCE)
    write(joinpath(folder,"executed_network_reduction.jl"),NR_SOURCE)
    cp(joinpath(@__DIR__,"s2_500bus_scaled_mpcc.jl"),joinpath(folder,"executed_scaled_mpcc.jl"))
    x=el_context()
    fd_save(joinpath(folder,"contract.json"),(;name=label,factors,outages=[e.id for e in events],
        emergency,relief=true,thermal_multiplier=emergency ? 1.1 : 1.,solver,fixed_controller,fixed_base=false,
        normalization=false,restore=false,zero_shedding,zero_dr,direct_relief,objective_scale,implied_q_bounds,penalty_proxies=false,
        response_relaxation_cap=0.,droop_normalization=true,initial_controller=seed.study.case.controls,
        optimizer_options=Dict(k=>string(v) for (k,v) in optimizer_options),check_start,
        free_shared_slopes=fixed_controller ? 0 : 51,free_shared_references=fixed_controller ? 0 : 51,seconds,stage,budgets,retry,
        departure_metric="Smooth positive voltage departures/.05 plus squared-apparent-flow departures/.21; epsilon=1e-6. Hard caps unchanged.",
        objective="Lexicographic shedding, DR, emergency departures, average base losses; zero shedding fixed for independent 105%"))
    built=el_build(x,factors,events;seed,solver,emergency,relief=true,thermal_multiplier=emergency ? 1.1 : 1.,
        restore=false,zero_shedding,zero_dr,direct_relief,penalty_proxies=false,droop_normalization=true,fixed_controller,
        ac_builder=solver==:ccopt ? fm_cc_ac : implied_q_bounds ? fm_smooth_cap_ac : nr_build_ac)
    m=built.m
    maps=[(;factor=b.factor,id=b.id,reduction=b.v.reduction) for b in built.blocks]
    fd_save(joinpath(folder,"network_reduction_maps.json"),maps)
    zero_shedding && foreach(v->(fix(v,0.;force=true);set_start_value(v,0.)),built.shed_all)
    shedding=sum(built.shed_all);dr=sum(built.dr_all)
    departure=stage==:emergency || haskey(budgets,:emergency) ? fm_departure(built) : nothing
    for (key,budget) in budgets
        expression=key==:shedding ? shedding : key==:dr ? dr : departure
        if expression isa JuMP.NonlinearExpression
            @NLconstraint(m,expression<=budget+1e-6)
        else
            @constraint(m,expression<=budget+1e-7)
        end
    end
    objective=stage==:feasibility ? 0. : stage==:shedding ? shedding : stage==:dr ? dr : stage==:emergency ? departure :
        sum(sum(b.v.pg)-sum(l.p for l in b.normal.loads) for b in built.blocks if b.id==:base)/length(factors)
    if objective isa JuMP.NonlinearExpression;@NLobjective(m,Min,objective_scale*objective)
    else;@objective(m,Min,objective_scale*objective);end
    set_optimizer_attribute(m,"tol",solver==:ccopt ? 1e-10 : 1e-8)
    set_optimizer_attribute(m,"max_iter",6000);set_optimizer_attribute(m,"bound_relax_factor",0.)
    set_optimizer_attribute(m,solver==:ipopt ? "max_cpu_time" : "max_wall_time",seconds)
    if solver==:ipopt
        set_optimizer_attribute(m,"print_level",0);set_optimizer_attribute(m,"mu_strategy","adaptive")
        set_optimizer_attribute(m,"hessian_approximation",retry ? "exact" : "limited-memory")
    else
        set_optimizer_attribute(m,"linear_solver",MadNLP.UmfpackSolver)
        if solver==:ccopt
            set_optimizer_attribute(m,"relaxation_update",retry ? CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14) :
                CCOpt.ScheduledRelaxationUpdate(sigma_init=1e-8,sigma_min=1e-14,target_accuracy=1e-10))
            set_optimizer_attribute(m,"acceptable_tol",1e-10)
        end
    end
    for (key,value) in optimizer_options;set_optimizer_attribute(m,key,value);end
    if check_start
        diagnostics=try
            violations=JuMP.primal_feasibility_report(v->something(start_value(v),0.),m;atol=1e-6)
            worst=sort(collect(violations);by=last,rev=true)
            (;violations_over_1e6=length(violations),maximum_violation=maximum(values(violations);init=0.),
                worst=[(;constraint=string(JuMP.index(c)),violation=error) for(c,error) in first(worst,min(20,length(worst)))])
        catch error
            (;evaluation_error=sprint(showerror,error))
        end
        fd_save(joinpath(folder,"initial-model-feasibility.json"),diagnostics)
    end
    println("FINISH MULTI START ",label," ",stage," solver=",solver);flush(stdout)
    timed=@timed optimize!(m)
    native=termination_status(m) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.ALMOST_LOCALLY_SOLVED,JuMP.MOI.OPTIMAL)
    record=(;stage,status=string(termination_status(m)),native_success=native,elapsed_seconds=timed.time,
        objective=has_values(m) ? objective_value(m)/objective_scale : nothing,objective_scale,
        native_objective=has_values(m) ? objective_value(m) : nothing,artificial_max_pu=0.,artificial_net_max_pu=0.,
        native_optimizer_calls=1,solver,free_shared_droop_variables=count(v->startswith(JuMP.name(v),"shared_"),all_variables(m)),
        variables=num_variables(m),constraints=num_constraints(m;count_variable_in_set_constraints=true))
    fd_save(joinpath(folder,"stages.json"),[record]);point=has_values(m) ? el_save_point(folder,built,stage,record) : nothing
    accepted=false
    if !isnothing(point)
        python=get(ENV,"NR_PYTHON","/tmp/s214-plot-env/bin/python")
        read(`$python $(joinpath(@__DIR__,"audit_s2_500bus_network_reduction.py")) $folder $(string(stage))`,String)
        accepted=JSON.parsefile(joinpath(folder,"network-audit-$stage.json"))["accepted"]
    end
    summary=(;label,stage,factors,solver,accepted,record,zero_shedding,budgets)
    fd_save(joinpath(folder,"summary.json"),summary)
    println("FINISH MULTI END ",label," status=",record.status," accepted=",accepted);flush(stdout)
    (;point,folder,summary,accepted)
end

function fm_pipeline(label,factors,seed,events;solver=:ipopt,zero_shedding=false,stages=nothing,
    initial_budgets=Dict{Symbol,Float64}(),profiles=(false,true),optimizer_options=Dict{String,Any}())
    objectives=isnothing(stages) ? (zero_shedding ? (:dr,:emergency,:loss) : (:shedding,:dr,:emergency,:loss)) : stages
    budgets=copy(initial_budgets);rows=Any[];selected=nothing;complete=true
    for stage in objectives
        good=nothing;anchor=seed
        for retry in profiles
            backend=length(factors)==1 && retry ? (solver==:ipopt ? :madnlp : :ipopt) : solver
            run=fm_attempt("$label-$stage-$(retry ? "retry" : "primary")",stage,factors,seed,events;
                solver=backend,zero_shedding,budgets,retry,optimizer_options,seconds=length(factors)>1 ? 180. : 120.)
            push!(rows,run.summary)
            fd_save(joinpath(FM_OUT,"progress-$label.json"),(;rows,budgets,selected))
            if run.accepted;good=run;break;end
            seed=isnothing(run.point) ? anchor : run.point
        end
        if isnothing(good);complete=false;seed=anchor;break;end
        seed=good.point;selected=(;path=relpath(good.folder,S2500_OUT),stage)
        stage in (:shedding,:dr,:emergency) && (budgets[stage]=Float64(good.summary.record.objective))
    end
    result=(;label,factors,solver,complete,selected,budgets,rows,
        loss_objective_completed=complete && :loss in objectives,full_n1_accepted=false)
    fd_save(joinpath(FM_OUT,"summary-$label.json"),result)
    (;point=seed,result)
end

function fm_run(mode)
    confirmation=strip(get(ENV,"FM_CONTROL_CONFIRMATION",""));isempty(confirmation) && error("Campaign equipment confirmation required")
    ENV["NR_ELIMINATION_MODE"]="independent-degree3";mkpath(FM_OUT)
    events=filter(e->e.id in FM_EVENTS,eligible_contingencies(contingency_catalog(el_context().study.case)))
    initial=el_read_point(joinpath(S2500_OUT,"targeted_demand_diagnostics/relief_priority_witness/emergency-10500-round-1-polish-shedding");stage="derived")
    if mode=="105"
        fm_pipeline("finish-105",(1.05,),initial,events;zero_shedding=true)
    elseif mode=="continuation"
        current=initial;rows=Any[]
        prior=joinpath(FM_OUT,"summary-finish-105.json")
        if isfile(prior)
            selected=JSON.parsefile(prior)["selected"]
            isnothing(selected) || (current=el_read_point(joinpath(S2500_OUT,selected["path"]);stage=selected["stage"]))
        end
        for factor in (1.055,1.06,1.0625)
            if factor==1.0625
                current=el_read_point(joinpath(S2500_OUT,"free_droop_continuation/normalized-anchor-polish-1.0625-r05");stage="dr")
            end
            run=fm_pipeline("continue-$(round(Int,factor*10000))",(factor,),current,events;
                solver=:madnlp,stages=(:feasibility,))
            current=run.point;push!(rows,run.result)
        end
        fd_save(joinpath(FM_OUT,"summary-continuation.json"),(;maximum_factor=1.0625,rows))
    elseif mode=="seed"
        upper=el_read_point(joinpath(S2500_OUT,"free_droop_continuation/normalized-anchor-polish-1.0625-r05");stage="dr")
        rows=Any[]
        for factor in (.9,.95,1.,1.05)
            run=fm_attempt("common-controller-seed-$(round(Int,factor*10000))",:feasibility,(factor,),upper,events;
                solver=:ipopt,seconds=90.,fixed_controller=true)
            push!(rows,run.summary)
        end
        fd_save(joinpath(FM_OUT,"summary-common-controller-seeds.json"),(;rows,
            scope="Numerical initialization with controller fixed; multi-demand masters still free all 102 parameters"))
    else
        solver=Symbol(mode);@assert solver in (:ipopt,:madnlp,:ccopt)
        upper=el_read_point(joinpath(S2500_OUT,"free_droop_continuation/normalized-anchor-polish-1.0625-r05");stage="dr")
        for factor in (.9,.95,1.,1.05)
            folder=joinpath(FM_OUT,"common-controller-seed-$(round(Int,factor*10000))")
            if isfile(joinpath(folder,"point-feasibility.json"))
                saved=el_read_point(folder;stage="feasibility")
                @assert DroopOPF._json_data(saved.study.case.controls)==DroopOPF._json_data(upper.study.case.controls)
                merge!(upper.states,saved.states)
            end
        end
        fm_pipeline("multi-$solver",FM_FACTORS,upper,events;solver)
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && fm_run(only(ARGS))
