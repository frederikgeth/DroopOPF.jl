# Read-only, unscaled residuals of the complete scalar model before NLP wrapping.
function initial_constraint_rows(m)
    rows=Any[]
    for (F,S) in list_of_constraint_types(m), c in all_constraints(m,F,S)
        obj=constraint_object(c)
        push!(rows,(name=isempty(name(c)) ? string(c) : name(c),func=obj.func,set=obj.set))
    end
    rows
end
function initial_constraint_residuals(rows,vars,point,label)
    values=Dict(v=>point[i] for (i,v) in enumerate(vars));details=Any[];nonfinite=0;unsupported=0
    for r in rows
        try
            v=r.func isa Real ? r.func : value(w->values[w],r.func)
            s=r.set
            violation= s isa DiagnosticMOI.EqualTo ? abs(v-s.value) : s isa DiagnosticMOI.LessThan ? max(0.,v-s.upper) :
                s isa DiagnosticMOI.GreaterThan ? max(0.,s.lower-v) : s isa DiagnosticMOI.Interval ? max(0.,s.lower-v,v-s.upper) : nothing
            if violation===nothing
                unsupported+=1;push!(details,Dict("name"=>r.name,"evaluation_error"=>"unsupported constraint set","violation"=>Inf));continue
            end
            if !isfinite(v)||!isfinite(violation);nonfinite+=1;violation=Inf;end
            push!(details,Dict("name"=>r.name,"expression"=>string(r.func),"set"=>string(s),"value"=>v,"violation"=>violation))
        catch err
            nonfinite+=1;push!(details,Dict("name"=>r.name,"evaluation_error"=>sprint(showerror,err),"violation"=>Inf))
        end
    end
    sort!(details;by=r->r["violation"],rev=true)
    safe_diagnostic(Dict("point"=>label,"scaling"=>"unscaled; includes scalar equations, inequalities and variable bounds",
        "constraint_count"=>length(rows),"nonfinite_or_evaluation_error_count"=>nonfinite,"unsupported_count"=>unsupported,
        "max_violation"=>isempty(details) ? 0. : first(details)["violation"],"largest_residuals"=>first(details,min(20,length(details)))))
end
function actual_initial_constraint_residuals(m,rows,requested)
    try
        problem=unsafe_backend(m).inner
        x=zeros(problem.n);zl=similar(x);zu=similar(x);g=zeros(problem.m);lambda=similar(g)
        Ipopt.GetIpoptCurrentIterate(problem,false,problem.n,x,zl,zu,problem.m,g,lambda)
        vars=all_variables(m);point=[x[JuMP.optimizer_index(v).value] for v in vars]
        report=initial_constraint_residuals(rows,vars,point,"first Ipopt callback; unscaled actual iterate")
        changes=[Dict("variable"=>string(v),"requested"=>requested[i],"actual"=>point[i],"absolute_change"=>abs(point[i]-requested[i])) for (i,v) in enumerate(vars)]
        sort!(changes;by=r->r["absolute_change"],rev=true)
        report["largest_start_adjustments"]=safe_diagnostic(first(changes,min(20,length(changes))))
        report
    catch err
        Dict("capture_error"=>sprint(showerror,err),"note"=>"Unavailable diagnostic; model and solver are unchanged")
    end
end
function required_avr_sharing_keys(x,controls)
    plan=regulation_plan(x,controls);keys=Set{String}()
    for (bus,p) in plan["avr_plants"]
        ids=p["ids"]
        length(ids)>1&&sum(x.data["gen"][k]["qmax"] for k in ids)!=sum(x.data["gen"][k]["qmin"] for k in ids)&&push!(keys,"avr_share_$bus")
    end
    for (target,t) in plan["avr_targets"]
        plants=[plan["avr_plants"][key] for key in t["plants"]]
        length(plants)>1&&sum(x.data["gen"][k]["qmax"] for p in plants for k in p["ids"])!=sum(x.data["gen"][k]["qmin"] for p in plants for k in p["ids"])&&push!(keys,"remote_avr_share_$target")
    end
    keys
end
function restored_avr_sharing(x,controls,result)
    saved=get(result,"avr_sharing",Dict())
    Set(keys(saved))==required_avr_sharing_keys(x,controls)||error("Checkpoint lacks complete AVR-sharing variables or has different sharing groups. Rerun feasibility and reserve initialization with the updated code; zero sharing starts are not substituted.")
    all(v->v isa Real&&!(v isa Bool)&&isfinite(v),values(saved))||error("Nonfinite AVR-sharing checkpoint values")
    avr_sharing_residual(x,controls,result,saved)<=1e-6||error("Saved AVR-sharing variables do not reproduce the accepted generator Q outputs")
    saved
end

function avr_sharing_residual(x,controls,result,saved)
    plan=regulation_plan(x,controls);state=result["data"];residual=0.
    for (bus,p) in plan["avr_plants"]
        label="avr_share_$bus";haskey(saved,label)||continue
        ids=p["ids"];lo=[x.data["gen"][k]["qmin"] for k in ids];hi=[x.data["gen"][k]["qmax"] for k in ids]
        pg=[abs(state["gen"][k]["pg"]) for k in ids];mb=[get(x.data["gen"][k],"mbase",0.) for k in ids]
        weights=sum(pg)>1e-12 ? pg : sum(mb)>0 ? mb : ones(length(ids))
        upper=maximum(weights[n]>0 ? hi[n]/weights[n] : -1e20 for n in eachindex(ids))
        lower=minimum(weights[n]>0 ? lo[n]/weights[n] : 1e20 for n in eachindex(ids))
        lambda=saved[label];fallback=max(lambda-upper,0.)+min(lambda-lower,0.)
        for n in eachindex(ids)
            lo[n]==hi[n]&&continue
            expected=clip(weights[n]>0 ? weights[n]*lambda : fallback,lo[n],hi[n])
            residual=max(residual,abs(state["gen"][ids[n]]["qg"]-expected))
        end
    end
    for (target,t) in plan["avr_targets"]
        label="remote_avr_share_$target";haskey(saved,label)||continue
        for key in t["plants"]
            p=plan["avr_plants"][key];ids=p["ids"]
            lo=sum(x.data["gen"][k]["qmin"] for k in ids);hi=sum(x.data["gen"][k]["qmax"] for k in ids)
            lo==hi&&continue
            residual=max(residual,abs(sum(state["gen"][k]["qg"] for k in ids)-clip(p["weight"]*saved[label],lo,hi)))
        end
    end
    residual
end

function require_strict_transition(result)
    get(result,"strict_numerics",false)===true||error("Missing strict transition solver settings")
    get(result,"solver_numerics",nothing)==Dict("tol"=>1e-8,"constr_viol_tol"=>1e-10,"bound_relax_factor"=>0.,"acceptable_iter"=>0)||error("Strict transition numerical settings changed")
    get(result,"initialization_pushes",nothing)==Dict(k=>1e-9 for k in ("bound_push","bound_frac","slack_bound_push","slack_bound_frac"))||error("Strict transition startup settings changed")
    r=get(result,"final_constraint_residuals",Dict());v=get(r,"max_violation",nothing)
    get(result,"strict_model_constraints_passed",false)===true&&v isa Real&&isfinite(v)&&v<=1e-10&&get(r,"unsupported_count",-1)==0&&get(r,"nonfinite_or_evaluation_error_count",-1)==0||error("Returned point does not meet strict model-constraint tolerance")
    true
end
