# Capture actual nonfinite NLP callback evaluations, including rejected trial points.
# Detailed expressions and operating points are confidential local artifacts only.
const DiagnosticMOI=JuMP.MOI
mutable struct EquationDiagnosticEvaluator <: DiagnosticMOI.AbstractNLPEvaluator
    inner::DiagnosticMOI.AbstractNLPEvaluator
    equations::Vector{Any}
    variables::Vector{String}
    report::Dict{String,Any}
    sink::Any
    probes::Dict{String,Any}
end
DiagnosticMOI.features_available(e::EquationDiagnosticEvaluator)=DiagnosticMOI.features_available(e.inner)
DiagnosticMOI.initialize(e::EquationDiagnosticEvaluator,f)=DiagnosticMOI.initialize(e.inner,f)
DiagnosticMOI.jacobian_structure(e::EquationDiagnosticEvaluator)=DiagnosticMOI.jacobian_structure(e.inner)
DiagnosticMOI.hessian_lagrangian_structure(e::EquationDiagnosticEvaluator)=DiagnosticMOI.hessian_lagrangian_structure(e.inner)
diagnostic_number(v)=isfinite(v) ? v : string(v)
# Diagnostic arithmetic only; the optimization equations are not changed.
function avr_clip_probe(total,vs,vm,lo,hi)
    z=total+vs-vm
    function side(t)
        squared=t*t;radicand=squared+1e-16;root=sqrt(radicand)
        Dict("argument"=>t,"squared_argument"=>squared,"radicand"=>radicand,
            "sqrt"=>root,"softplus"=>(t+root)/2,
            "direct_derivative"=>(1+t/root)/2,
            "overflow_resistant_derivative"=>(1+t/hypot(t,1e-8))/2)
    end
    lower=side(z-lo);upper=side(z-hi)
    direct=lo==hi ? 0. : lower["direct_derivative"]-upper["direct_derivative"]
    stable=lo==hi ? 0. : lower["overflow_resistant_derivative"]-upper["overflow_resistant_derivative"]
    clipped=lo==hi ? lo : lo+lower["softplus"]-upper["softplus"]
    Dict("operands"=>Dict("Qtotal"=>total,"Vtarget"=>vs,"Vregulated"=>vm,"Qmin_total"=>lo,"Qmax_total"=>hi),
        "operands_finite"=>all(isfinite,(total,vs,vm,lo,hi)),"ordered_limits"=>lo<=hi,
        "clip_input"=>z,"lower_softplus"=>lower,"upper_softplus"=>upper,
        "clip_output"=>clipped,"equation_residual"=>total-clipped,
        "analytic_partials"=>Dict("Qtotal"=>1-direct,"Vtarget"=>-direct,"Vregulated"=>direct),
        "overflow_resistant_partials"=>Dict("Qtotal"=>1-stable,"Vtarget"=>-stable,"Vregulated"=>stable),
        "note"=>"Analytic partials of Qtotal-clip(Qtotal+Vtarget-Vregulated); hypot comparison is diagnostic only, not a model replacement")
end
safe_diagnostic(v::Real)=diagnostic_number(v)
safe_diagnostic(v::AbstractDict)=Dict(string(k)=>safe_diagnostic(x) for (k,x) in v)
safe_diagnostic(v::AbstractVector)=safe_diagnostic.(v)
safe_diagnostic(v)=v
function record_nonfinite!(e,kind,values,x;exception=nothing)
    bad=findall(v->!isfinite(v),values)
    isempty(bad)&&exception===nothing&&return
    e.report["failure_count"]+=1
    length(e.report["events"])>=3&&return # bound storage, retain earliest failing points
    structure=kind=="jacobian" ? DiagnosticMOI.jacobian_structure(e) : kind=="hessian" ? DiagnosticMOI.hessian_lagrangian_structure(e) : nothing
    entries=Any[]
    for i in Iterators.take(bad,100)
        row,col=structure===nothing ? (i,0) : structure[i]
        entry=Dict{String,Any}("entry_index"=>i,"value"=>diagnostic_number(values[i]))
        if kind in ("constraints","jacobian")
            entry["equation"]=e.equations[row];entry["nonlinear_row_1based"]=row
        end
        if kind=="jacobian"
            entry["variable"]=e.variables[col];entry["variable_column_1based"]=col;entry["variable_value"]=diagnostic_number(x[col])
        elseif kind=="hessian"
            entry["variables"]=[e.variables[row],e.variables[col]]
        end
        push!(entries,entry)
    end
    probes=Any[]
    if kind in ("constraints","jacobian")
        affected=unique(kind=="jacobian" ? [structure[i][1] for i in bad] : bad)
        for row in Iterators.take(affected,100)
            label=e.equations[row]["name"]
            haskey(e.probes,label)||continue
            detail=try
                e.probes[label](x)
            catch err
                Dict("probe_error"=>sprint(showerror,err))
            end
            detail["equation_name"]=label
            if kind=="jacobian"
                detail["automatic_jacobian_entries"]=[Dict("variable"=>e.variables[c],"column_1based"=>c,"derivative"=>values[i]) for (i,(r,c)) in enumerate(structure) if r==row]
            end
            push!(probes,safe_diagnostic(detail))
        end
    end
    push!(e.report["events"],Dict("avr_clip_probes"=>probes,"callback"=>kind,"exception"=>exception,"nonfinite_entry_count"=>length(bad),
        "entries"=>entries,"entries_truncated"=>length(bad)>100,
        "trial_point"=>[Dict("column_1based"=>i,"variable"=>e.variables[i],"value"=>diagnostic_number(x[i])) for i in eachindex(x)]))
    e.sink===nothing||e.sink(e.report) # write before Ipopt may discard this trial point
end
for (method,kind) in ((:eval_constraint,"constraints"),(:eval_constraint_jacobian,"jacobian"),(:eval_hessian_lagrangian,"hessian"))
    @eval function DiagnosticMOI.$method(e::EquationDiagnosticEvaluator,out,x,args...)
        try
            DiagnosticMOI.$method(e.inner,out,x,args...)
        catch err
            record_nonfinite!(e,$kind,Float64[],x;exception=sprint(showerror,err));rethrow()
        end
        record_nonfinite!(e,$kind,out,x)
        return
    end
end
DiagnosticMOI.eval_objective(e::EquationDiagnosticEvaluator,x)=DiagnosticMOI.eval_objective(e.inner,x)
DiagnosticMOI.eval_objective_gradient(e::EquationDiagnosticEvaluator,g,x)=DiagnosticMOI.eval_objective_gradient(e.inner,g,x)
function install_equation_diagnostics!(m;phase="test",sink=nothing,probe_builders=Dict())
    backend=JuMP.backend(m);nl=DiagnosticMOI.Nonlinear.Model();rows=Any[];refs=Any[]
    for (F,S) in list_of_constraint_types(m)
        F<:JuMP.GenericNonlinearExpr||continue
        for c in all_constraints(m,F,S)
            obj=constraint_object(c)
            DiagnosticMOI.Nonlinear.add_constraint(nl,JuMP.moi_function(obj.func),obj.set)
            push!(rows,Dict("name"=>isempty(name(c)) ? "nonlinear_equation_$(length(rows)+1)" : name(c),
                "expression"=>string(obj.func),"set"=>string(obj.set),"equality"=>obj.set isa DiagnosticMOI.EqualTo))
            push!(refs,c)
        end
    end
    vars=all_variables(m)
    inner=DiagnosticMOI.Nonlinear.Evaluator(nl,DiagnosticMOI.Nonlinear.SparseReverseMode(),index.(vars))
    report=Dict{String,Any}("schema"=>"DroopDesign.EquationDiagnostics.v1","phase"=>phase,
        "privacy"=>"PRIVATE: equations, identities and trial points stay on the work machine; not approved for export",
        "scope"=>"actual nonlinear constraint/Jacobian/Hessian callbacks; nonlinear row indices are local to this report, not global Ipopt rows",
        "failure_count"=>0,"events"=>Any[],"equation_count"=>length(rows),"variable_count"=>length(vars))
    columns=Dict(v=>i for (i,v) in enumerate(vars))
    probes=Dict{String,Any}(label=>builder(columns) for (label,builder) in probe_builders)
    evaluator=EquationDiagnosticEvaluator(inner,rows,string.(vars),report,sink,probes)
    block=DiagnosticMOI.NLPBlockData(inner)
    for c in refs;delete(m,c);end
    DiagnosticMOI.set(backend,DiagnosticMOI.NLPBlock(),DiagnosticMOI.NLPBlockData(block.constraint_bounds,evaluator,false))
    sink===nothing||sink(report)
    report
end

# Local sparse diagnostics only: no scaling or constraint changes.
function convergence_summary(trace)
    jumps=Any[]
    for i in 2:length(trace)
        before=trace[i-1];after=trace[i]
        a=before["inf_du"];b=after["inf_du"]
        a isa Real&&b isa Real||continue
        ratio=b/max(abs(a),1e-12)
        ratio>=100&&push!(jumps,Dict("ratio"=>ratio,"before"=>before,"after"=>after))
    end
    sort!(jumps;by=r->r["ratio"],rev=true)
    Dict("dual_jumps_100x_count"=>length(jumps),"largest_dual_jumps"=>first(jumps,min(10,length(jumps))),
        "restoration_iterations"=>count(r->r["restoration"],trace),
        "tiny_primal_steps"=>count(r->r["iteration"]>0&&r["alpha_pr"] isa Real&&r["alpha_pr"]<1e-6,trace),
        "regularized_iterations"=>count(r->r["regularization"] isa Real&&r["regularization"]>0,trace),
        "note"=>"Thresholds describe solver behavior only; they do not diagnose infeasibility or causation")
end
# Optimize directly on the saved PowerModels dictionary. Only control equations
# and design variables are added; there is no RAW/Case representation round trip.
softplus(x)=(x+sqrt(x^2+1e-16))/2
# Keep the offset square factored. An affine square otherwise becomes a quadratic
# polynomial: near saturation its O(1) terms cancel and erase the 1e-16 smoothing.
# An explicit nonlinear power node preserves the same function and its derivatives.
softplus(x::JuMP.AbstractJuMPScalar)=(x+sqrt(JuMP.GenericNonlinearExpr(:^,x,2)+1e-16))/2
clip(x,lo,hi)=lo==hi ? lo : lo+softplus(x-lo)-softplus(x-hi)
function reserve_bounds!(model,qg,qmin,qmax,rho,phase,floor)
    phase=="initialization"||(phase=="design"&&floor>0)||return JuMP.ConstraintRef[]
    [@constraint(model,qg>=qmin+rho*(qmax-qmin)),
     @constraint(model,qg<=qmax-rho*(qmax-qmin))]
end
function design_control_variable(m,lo,hi,start,label)
    start=clamp(start,lo,hi)
    lo==hi&&return lo
    @variable(m,lower_bound=lo,upper_bound=hi,start=start,base_name=label)
end
function solve_lane(x,controls,seed;phase="feasibility",floor=0.,seconds=300.,seed_settings=Dict(),seed_signals=Dict(),seed_avr_settings=Dict(),seed_avr_sharing=Dict(),diagnostics=false,diagnostic_sink=nothing,hessian="limited-memory",max_iterations=STUDY_ITERATION_LIMIT,objective_policy="loss",start_push=nothing,strict_numerics=false)
    phase in ("feasibility","initialization","design")||error("Unknown design phase")
    objective_policy in ("loss","zero")||error("Unknown design objective")
    strict_numerics&&!(phase in ("initialization","design"))&&error("Strict transition settings require initialization or design")
    start_push===nothing||((phase=="design"||(phase=="initialization"&&strict_numerics))&&start_push isa Real&&!(start_push isa Bool)&&isfinite(start_push)&&0<start_push<=.5)||error("Invalid design initialization push")
    push_options=("bound_push","bound_frac","slack_bound_push","slack_bound_frac")
    hessian in ("exact","limited-memory")||error("Unknown Hessian mode")
    max_iterations isa Integer&&!(max_iterations isa Bool)&&max_iterations>0||error("Invalid iteration budget")
    isfinite(seconds)&&seconds>0||error("Invalid time budget")
    data=deepcopy(x.data)
    for (k,b) in data["bus"]
        b["vm_start"]=seed["bus"][k]["vm"];b["va_start"]=seed["bus"][k]["va"]
    end
    for (k,g) in data["gen"]
        g["pg_start"]=seed["gen"][k]["pg"];g["qg_start"]=seed["gen"][k]["qg"]
    end
    equipment=equipment_plan(x);equipment_settings=Dict{String,Any}();equipment_starts=Dict{String,Any}()
    avr_sharing=Dict{String,Any}();avr_sharing_start=Dict{String,Any}()
    function sharing_variable(m,label)
        start=get(seed_avr_sharing,label,0.)
        start isa Real&&!(start isa Bool)&&isfinite(start)||error("Invalid AVR-sharing start")
        avr_sharing_start[label]=start
        avr_sharing[label]=@variable(m,base_name=label,start=start)
    end
    probe_builders=Dict{String,Any}()
    control_coordinates=Any[]
    loss_scale=1.
    settings=Dict{String,Any}();signals=Dict{String,Any}();avr_settings=Dict{String,Any}()
    build=function(pm)
        m=pm.model
        P.variable_bus_voltage(pm);P.variable_gen_power(pm)
        for (id,c) in equipment["selected"]
            start=seed[c["table"]][c["key"]][c["field"]]
            equipment_starts[id]=start
            equipment_settings[id]=phase in ("feasibility","initialization","design") ?
                @variable(m,lower_bound=c["lower"],upper_bound=c["upper"],start=clamp(start,c["lower"],c["upper"]),base_name="equipment_"*replace(id,":"=>"_")) : c["initial"]
        end
        for i in P.ids(pm,:branch)
            if haskey(equipment_settings,"branch:"*string(i))
                equipment_branch!(pm,i,equipment_settings["branch:"*string(i)])
            else
                P.expression_branch_power_ohms_yt_from(pm,i);P.expression_branch_power_ohms_yt_to(pm,i)
            end
            P.constraint_thermal_limit_from(pm,i);P.constraint_thermal_limit_to(pm,i)
            P.constraint_voltage_angle_difference(pm,i)
        end
        P.constraint_model_voltage(pm)
        for i in P.ids(pm,:bus)
            if any(s->haskey(equipment_settings,"shunt:"*string(s)),P.ref(pm,:bus_shunts,i))
                equipment_balance!(pm,i,equipment_settings)
            else
                P.constraint_power_balance(pm,i)
            end
        end
        plan=regulation_plan(x,controls)
        for (j,group) in enumerate(groups(x.data))
            ref=only(i for i in group if x.source["bus"][string(i)]["bus_type"]==3)
            fix(P.var(pm,:va,ref),x.data["bus"][string(ref)]["va"];force=true)
            signal=@variable(m,base_name="island_response_$j",start=get(seed_signals,string(j),0.));signals[string(j)]=signal
            w=response_weights(x.data,group;free_ids=plan["free_dispatch"]);sum(values(w))==0&&fix(signal,0.;force=true)
            for (k,weight) in w
                g=x.data["gen"][k];pg=P.var(pm,:pg,parse(Int,k))
                if weight==0
                    g["pmin"]-1e-8<=g["pg"]<=g["pmax"]+1e-8||error("Fixed source PG is outside its selected-model capability")
                    fix(pg,g["pg"];force=true)
                else
                    set_name(@constraint(m,pg==clip(g["pg"]+weight*signal,g["pmin"],g["pmax"])),"active_response_island_$(j)_gen_$(k)")
                end
            end
        end
        plan=regulation_plan(x,controls)
        for (target,t) in plan["avr_targets"]
            lo,hi=t["vref_bounds"]
            avr_settings[target]=t["optimizable"]&&phase in ("feasibility","initialization","design")&&lo<hi ?
                design_control_variable(m,lo,hi,get(seed_avr_settings,target,t["vs"]),"avr_vref_$target") : t["vs"]
        end
        for (target,group) in plan["shared_droop_groups"]
            k=first(group["ids"]);c=group
            s=design_control_variable(m,c["slope_bounds"]...,get(get(seed_settings,k,Dict()),"slope",c["slope_initial"]),"shared_slope_$target")
            vr=haskey(avr_settings,target) ? avr_settings[target] : c["fixed_vref"]!==nothing ? c["fixed_vref"] : design_control_variable(m,c["vref_bounds"]...,get(get(seed_settings,k,Dict()),"vref",c["vref_initial"]),"shared_vref_$target")
            for id in group["ids"]
                g=data["gen"][id];control=controls[id]
                settings[id]=(;slope=s,vref=vr)
                vm=P.var(pm,:vm,parse(Int,target));qg=P.var(pm,:qg,parse(Int,id))
                set_name(@constraint(m,qg==clip(control["qref"]+(vr-vm)/s,g["qmin"],g["qmax"])),"ibr_droop_gen_$(id)_regulated_bus_$(target)")
            end
        end
        for (bus,plant) in plan["avr_plants"]
            ids=plant["ids"]
            isempty(ids)&&continue
            lo=[data["gen"][k]["qmin"] for k in ids];hi=[data["gen"][k]["qmax"] for k in ids]
            q=[P.var(pm,:qg,parse(Int,k)) for k in ids];p=[P.var(pm,:pg,parse(Int,k)) for k in ids]
            sum(lo)==sum(hi)&&continue # fixed-Q equipment does not impose voltage regulation
            if length(ids)>1
                lambda=sharing_variable(m,"avr_share_$bus")
                ptotal=@expression(m,sum(abs(pi) for pi in p))
                mbases=[get(data["gen"][k],"mbase",0.) for k in ids]
                weights=[@expression(m,ifelse(ptotal>1e-12,abs(p[n]),sum(mbases)>0 ? mbases[n] : 1.)) for n in eachindex(ids)]
                # Zero-weight machines join only after positive-weight capability
                # is exhausted, exactly as Stage 1 bounded_share specifies.
                upper_breaks=[@expression(m,ifelse(weights[n]>0,hi[n]/ifelse(weights[n]>0,weights[n],1.),-1e20)) for n in eachindex(ids)]
                lower_breaks=[@expression(m,ifelse(weights[n]>0,lo[n]/ifelse(weights[n]>0,weights[n],1.),1e20)) for n in eachindex(ids)]
                upper_break=reduce((a,b)->@expression(m,max(a,b)),upper_breaks)
                lower_break=reduce((a,b)->@expression(m,min(a,b)),lower_breaks)
                fallback=@expression(m,max(lambda-upper_break,0.)+min(lambda-lower_break,0.))
                for n in eachindex(ids)
                    lo[n]==hi[n]&&continue
                    target=@expression(m,ifelse(weights[n]>0,weights[n]*lambda,fallback))
                    set_name(@constraint(m,q[n]==clip(target,lo[n],hi[n])),"avr_machine_share_bus_$(bus)_gen_$(ids[n])")
                end
            end
        end
        for (target,t) in plan["avr_targets"]
            plants=[plan["avr_plants"][key] for key in t["plants"]]
            q=[sum(P.var(pm,:qg,parse(Int,k)) for k in plant["ids"]) for plant in plants]
            lo=[sum(data["gen"][k]["qmin"] for k in plant["ids"]) for plant in plants]
            hi=[sum(data["gen"][k]["qmax"] for k in plant["ids"]) for plant in plants]
            sum(lo)==sum(hi)&&continue
            # Plant totals may mix VariableRef and AffExpr; avoid summing an abstract scalar vector.
            total=foldl(+,q;init=0.);vm=P.var(pm,:vm,parse(Int,target));vs=avr_settings[target]
            set_name(@constraint(m,total==clip(total+vs-vm,sum(lo),sum(hi))),"avr_voltage_regulated_bus_$(target)")
            if diagnostics
                # Bind each target's expressions/constants separately for later trial evaluation.
                let total=total,vs=vs,vm=vm,lower=sum(lo),upper=sum(hi)
                    probe_builders["avr_voltage_regulated_bus_$(target)"]=columns->trial->begin
                        at(v)=v isa Real ? v : value(w->trial[columns[w]],v)
                        avr_clip_probe(at(total),at(vs),at(vm),lower,upper)
                    end
                end
            end
            if length(plants)>1
                lambda=sharing_variable(m,"remote_avr_share_$target")
                for n in eachindex(plants)
                    lo[n]==hi[n]&&continue
                    set_name(@constraint(m,q[n]==clip(plants[n]["weight"]*lambda,lo[n],hi[n])),"avr_remote_share_target_$(target)_plant_$(n)")
                end
            end
        end
        for k in plan["fixed_q"]
            fix(P.var(pm,:qg,parse(Int,k)),data["gen"][k]["qg"];force=true)
        end
        linked=Set{Tuple{Any,Any}}()
        for ids in get(plan,"cross_snapshot_droop",Any[])
            leader=settings[first(ids)]
            for k in ids[2:end]
                for field in (:slope,:vref)
                    a=getproperty(settings[k],field);b=getproperty(leader,field)
                    if a isa Real && b isa Real
                        abs(a-b)<=1e-10||error("Conflicting shared snapshot settings")
                    elseif a!=b && !((a,b) in linked || (b,a) in linked)
                        @constraint(m,a==b);push!(linked,(a,b))
                    end
                end
            end
        end
        rho=phase=="initialization" ? @variable(m,lower_bound=0.,upper_bound=.5,start=0.,base_name="reactive_reserve") : floor
        isempty(plan["reserve_participants"])&&phase=="initialization"&&fix(rho,0.;force=true)
        if phase in ("initialization","design")
            for (i,g) in P.ref(pm,:gen)
                string(i) in plan["reserve_participants"]||continue
                width=g["qmax"]-g["qmin"];width>0||continue;qg=P.var(pm,:qg,i)
                reserve_bounds!(m,qg,g["qmin"],g["qmax"],rho,phase,floor)
            end
        end
        if phase=="feasibility";@objective(m,Min,0.)
        elseif phase=="initialization";@objective(m,Max,rho)
        elseif objective_policy=="zero";@objective(m,Min,0.)
        else;@objective(m,Min,loss_scale*data["baseMVA"]*(sum(get(data["gen"][string(i)],"snapshot_weight",1.)*P.var(pm,:pg,i) for i in P.ids(pm,:gen))-sum(get(l,"snapshot_weight",1.)*l["pd"] for l in values(data["load"]) if get(l,"status",1)!=0)));end
    end
    pm=P.instantiate_model(data,P.ACPPowerModel,build)
    isempty(setdiff(keys(seed_avr_sharing),keys(avr_sharing)))||error("AVR-sharing seed contains unknown groups")
    set_optimizer(pm.model,Ipopt.Optimizer)
    if diagnostics
        unset_silent(pm.model)
        set_optimizer_attribute(pm.model,"print_level",5)
        set_optimizer_attribute(pm.model,"check_derivatives_for_naninf","yes")
        println("PRIVATE solver phase: ",phase,"; variables: ",num_variables(pm.model),
            "; constraints including bounds: ",num_constraints(pm.model;count_variable_in_set_constraints=true))
        flush(stdout)
    else
        set_silent(pm.model)
    end
    if phase=="design"||strict_numerics
        set_optimizer_attribute(pm.model,"hessian_approximation",hessian)
        # Do not let Ipopt's numerical bound relaxation consume the certified reserve floor.
        set_optimizer_attribute(pm.model,"bound_relax_factor",0.)
        set_optimizer_attribute(pm.model,"constr_viol_tol",1e-10)
        strict_numerics&&set_optimizer_attribute(pm.model,"acceptable_iter",0)
        if start_push!==nothing
            for option in push_options;set_optimizer_attribute(pm.model,option,Float64(start_push));end
        end
    end
    phase=="feasibility"&&set_optimizer_attribute(pm.model,"mu_strategy","adaptive")
    set_optimizer_attribute(pm.model,"tol",1e-8);set_optimizer_attribute(pm.model,"max_iter",max_iterations)
    set_optimizer_attribute(pm.model,"max_cpu_time",Float64(seconds))
    start_rows=initial_constraint_rows(pm.model)
    requested_start=[something(start_value(v),is_fixed(v) ? fix_value(v) : 0.) for v in all_variables(pm.model)]
    initial_residuals=Dict{String,Any}("requested_start"=>initial_constraint_residuals(start_rows,all_variables(pm.model),requested_start,"supplied start before Ipopt bound adjustments"),"actual_first_iterate"=>nothing)
    equation_report=nothing
    trace=Any[]
    function convergence_callback(mode,iteration,objective,inf_pr,inf_du,mu,step,regularization,alpha_du,alpha_pr,trials)
        push!(trace,safe_diagnostic(Dict("iteration"=>Int(iteration),"restoration"=>mode!=0,
            "objective"=>objective,"inf_pr"=>inf_pr,"inf_du"=>inf_du,"barrier"=>mu,
            "step_norm"=>step,"regularization"=>regularization,"alpha_pr"=>alpha_pr,
            "alpha_du"=>alpha_du,"line_search_trials"=>Int(trials))))
        if initial_residuals["actual_first_iterate"]===nothing
            initial_residuals["actual_first_iterate"]=actual_initial_constraint_residuals(pm.model,start_rows,requested_start)
            initial_residuals["actual_first_iterate"]["iteration"]=Int(iteration)
            initial_residuals["actual_first_iterate"]["restoration"]=mode!=0
            equation_report===nothing||diagnostic_sink===nothing||diagnostic_sink(equation_report)
        end
        true
    end
    JuMP.MOI.set(pm.model,Ipopt.CallbackFunction(),convergence_callback)
    equation_report=diagnostics ? install_equation_diagnostics!(pm.model;phase,sink=diagnostic_sink,probe_builders) : nothing
    if equation_report!==nothing
        equation_report["initial_constraint_residuals"]=initial_residuals
        diagnostic_sink===nothing||diagnostic_sink(equation_report)
    end
    try
        optimize!(pm.model)
    finally
        if diagnostics
            Base.Libc.flush_cstdio();flush(stdout);flush(stderr)
        end
    end
    if diagnostics
        println("Solver phase ",phase,": termination=",termination_status(pm.model),
            "; primal=",primal_status(pm.model),"; raw_status=",raw_status(pm.model))
        flush(stdout)
    end
    result=Dict{String,Any}("phase"=>phase,"accepted"=>false,"termination"=>string(termination_status(pm.model)),"primal"=>string(primal_status(pm.model)),"floor"=>floor,"raw_status"=>raw_status(pm.model),"hessian_approximation"=>(phase=="design"||strict_numerics) ? hessian : "exact",
        "initial_constraint_residuals"=>initial_residuals,"avr_sharing_start"=>avr_sharing_start,
        "unseeded_avr_sharing"=>sort!(collect(setdiff(keys(avr_sharing),keys(seed_avr_sharing)))),
        "initialization_pushes"=>Dict(option=>(start_push===nothing ? "optimizer_default" : Float64(start_push)) for option in push_options),
        "solver_numerics"=>Dict("tol"=>1e-8,"constr_viol_tol"=>(phase=="design"||strict_numerics) ? 1e-10 : "optimizer_default","bound_relax_factor"=>(phase=="design"||strict_numerics) ? 0. : "optimizer_default"),
        "barrier_strategy"=>phase=="feasibility" ? "adaptive" : "optimizer_default",
        "solver_budget"=>Dict("max_iterations"=>max_iterations,"max_cpu_seconds"=>seconds),
        "convergence_trace"=>trace,"final_iteration"=>isempty(trace) ? nothing : last(trace),
        "convergence_summary"=>convergence_summary(trace),
        "objective_policy"=>phase=="feasibility" ? "feasibility" : phase=="initialization" ? "reserve" : objective_policy,"loss_objective_scale"=>loss_scale,"control_coordinates"=>control_coordinates,
        "slope_policy"=>phase in ("feasibility","initialization","design") ? "optimized" : "fixed_initialization")
    result["strict_numerics"]=strict_numerics
    strict_numerics&&(result["solver_numerics"]["acceptable_iter"]=0)
    if equation_report!==nothing
        result["equation_diagnostics"]=equation_report
        diagnostic_sink===nothing||diagnostic_sink(equation_report)
    end
    if has_values(pm.model)
        returned=initial_constraint_residuals(start_rows,all_variables(pm.model),value.(all_variables(pm.model)),"returned model point")
        result["final_constraint_residuals"]=returned
        result["strict_model_constraints_passed"]=returned["max_violation"] isa Real&&returned["max_violation"]<=1e-10&&returned["unsupported_count"]==0&&returned["nonfinite_or_evaluation_error_count"]==0
        out=deepcopy(x.data)
        for i in P.ids(pm,:bus),field in (:vm,:va);out["bus"][string(i)][string(field)]=value(P.var(pm,field,i));end
        for i in P.ids(pm,:gen),field in (:pg,:qg);out["gen"][string(i)][string(field)]=value(P.var(pm,field,i));end
        for (id,c) in equipment["selected"]
            v=equipment_settings[id]
            out[c["table"]][c["key"]][c["field"]]=v isa Real ? v : value(v)
        end
        result["equipment_policy"]=equipment["policy"]
        result["equipment_start"]=equipment_starts
        result["equipment_settings"]=Dict(id=>out[c["table"]][c["key"]][c["field"]] for (id,c) in equipment["selected"])
        result["data"]=out
        getvalue(v)=v isa Real ? Float64(v) : value(v)
        result["settings"]=Dict(k=>Dict("slope"=>getvalue(s.slope),"vref"=>getvalue(s.vref)) for (k,s) in settings)
        result["avr_sharing"]=Dict(k=>value(v) for (k,v) in avr_sharing)
        result["avr_settings"]=Dict(k=>getvalue(v) for (k,v) in avr_settings)
        result["signals"]=Dict(k=>value(v) for (k,v) in signals)
        result["replay"]=replay(x,controls,result;phase,floor)
        for (k,flow) in result["replay"]["flows"];merge!(out["branch"][k],flow);end
        result["accepted"]=result["termination"] in ("LOCALLY_SOLVED","OPTIMAL")&&result["primal"]=="FEASIBLE_POINT"&&result["replay"]["passed"]&&(!strict_numerics||result["strict_model_constraints_passed"])
        result["loss_mw"]=data["baseMVA"]*(sum(g["pg"] for g in values(out["gen"]) if livegen(g))-sum(l["pd"] for l in values(data["load"]) if get(l,"status",1)!=0))
    end
    result
end
