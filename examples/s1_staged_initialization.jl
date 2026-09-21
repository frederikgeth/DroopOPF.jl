isdefined(@__MODULE__,:s1_run_policy) || include("s1_restart_policy.jl")

function s1_hold_controls(case,p;equipment=true)
    taps=equipment ? [begin
        b=only(b for b in case.network.branches if b.id==c.branch_id)
        x=isnothing(c.initial) ? b.tap_ratio : c.initial
        TapControl(c.branch_id;lower=x,upper=x,initial=x,nominal=c.nominal)
    end for c in p.tap_controls] : p.tap_controls
    shunts=equipment ? [begin
        x=DroopOPF._shunt_policy(case,c).initial
        ShuntControl(c.bank_id;lower=x,upper=x,initial=x,nominal=c.nominal)
    end for c in p.shunt_controls] : p.shunt_controls
    droops=[begin
        x=DroopOPF._joint_droop_policy(case,c).initial
        DroopControl(c.control_id;slope_bounds=(x.slope,x.slope),v_ref_bounds=(x.v_ref,x.v_ref),
            deadband_low_bounds=(x.deadband_low,x.deadband_low),deadband_high_bounds=(x.deadband_high,x.deadband_high),initial=x)
    end for c in p.droop_controls]
    (tap_controls=taps,shunt_controls=shunts,droop_controls=droops)
end
function s1_stage_free_counts(case,p)
    Dict("tap"=>count(c->c.lower<c.upper,p.tap_controls),
        "shunt"=>count(c->(q=DroopOPF._shunt_policy(case,c);q.lower<q.upper),p.shunt_controls),
        "droop"=>count(c->any(lo<hi for (lo,hi) in values(DroopOPF._joint_droop_policy(case,c).ranges)),p.droop_controls))
end
function s1_stage_seed(case,p,row,result)
    get(row,"valid",false) || return nothing
    proposed=s1_reseed(case,p;result)
    DroopOPF._check_tap_controls(case,proposed.tap_controls)
    DroopOPF._check_shunt_controls(case,proposed.shunt_controls)
    foreach(c->DroopOPF._joint_droop_policy(case,c),proposed.droop_controls)
    (state=result.opf.state,policies=proposed)
end

"""Two preparatory solves plus the existing final policy, sharing one budget."""
function s1_run_staged(out,name,base,start;policies,solver=:ipopt,strategy=:release,
    factor=1.,total_iterations=2000,total_seconds=120.,preparation_iterations=500,tags=Dict{String,Any}())
    strategy in (:release,:load) || throw(ArgumentError("unknown staging strategy"))
    strategy==:load && !(factor>1) && throw(ArgumentError("load continuation requires increased demand"))
    total_iterations>=4 && total_seconds>0 && isfinite(total_seconds) && preparation_iterations>0 || throw(ArgumentError("invalid stage budget"))
    target=s1_load(base,factor);mkpath(out)
    began=time_ns();deadline=began+UInt64(round(total_seconds*1e9))
    state=start;current=policies;source="declared_initialization";preparations=[];used=0;fallbacks=[]
    for stage in 1:2
        remaining=(Float64(deadline)-Float64(time_ns()))/1e9
        remaining>0 || break
        stage_factor=strategy==:release ? factor : stage==1 ? 1. : (1.0 + factor)/2
        case=s1_load(base,stage_factor)
        controls=strategy==:release ? s1_hold_controls(case,current;equipment=stage==1) : current
        cap=min(preparation_iterations,fld(total_iterations,4))
        seconds=min(total_seconds/4,remaining)
        opts=Dict{String,Any}("max_iter"=>cap,"bound_push"=>1e-8,"bound_frac"=>1e-8,
            (solver==:ipopt ? "max_cpu_time" : "max_wall_time")=>seconds)
        row,result=s1_attempt(out,name*"-prep$stage",case,state;policies=controls,solver,epsilon=1e-6,
            options=opts,deadline_ns=min(deadline,time_ns()+UInt64(round(seconds*1e9))),
            tags=Dict("study"=>"staged_initialization","strategy"=>string(strategy),"stage"=>stage,
                "load_factor"=>stage_factor,"target_factor"=>factor,"seed_source"=>source))
        row["selected_counts"]=row["free_counts"];row["free_counts"]=s1_stage_free_counts(case,controls)
        used+=isnothing(get(row,"iterations",nothing)) ? cap : row["iterations"]
        row["seed_transferred"]=false
        try
            candidate=s1_stage_seed(case,policies,row,result)
            if !isnothing(candidate)
                state=candidate.state;current=candidate.policies;source=row["name"];row["seed_transferred"]=true
            end
        catch err
            row["seed_transfer_error"]=sprint(showerror,err)
        end
        if row["valid"] && stage_factor==factor
            # A restricted optimum can be target-feasible without joint-design stationarity.
            push!(fallbacks,Dict("attempt"=>row["name"],"objective"=>row["objective"],
                "role"=>"validated restricted-stage operating point; not an accepted joint-design optimum"))
        end
        write(joinpath(out,row["name"]*"-diagnostics.json"),JSON.json(row;pretty=true))
        push!(preparations,Dict(k=>v for (k,v) in row if k ∉ ("trace","bounds")))
    end
    remaining=(Float64(deadline)-Float64(time_ns()))/1e9
    final=nothing;result=nothing
    if remaining>0 && used<total_iterations
        final,result=s1_run_policy(out,name*"-joint",target,state;policies=current,solver,
            total_iterations=total_iterations-used,total_seconds=remaining,outer_deadline_ns=deadline,
            tags=Dict("study"=>"staged_final","strategy"=>string(strategy),"load_factor"=>factor,"seed_source"=>source))
        used+=final["iterations"]
    end
    summary=Dict("name"=>name,"solver"=>string(solver),"strategy"=>string(strategy),"buses"=>length(base.network.buses),
        "tags"=>tags,"load_factor"=>factor,"preparations"=>preparations,"final"=>final,
        "valid"=>!isnothing(final) && final["valid"],"iterations"=>used,
        "elapsed_seconds"=>(time_ns()-began)/1e9,"restricted_feasible_fallbacks"=>fallbacks,
        "budget"=>Dict("iterations"=>total_iterations,"seconds"=>total_seconds,"preparation_cap"=>min(preparation_iterations,fld(total_iterations,4)),
            "clock"=>"shared cooperative wall deadline; preparation and final attempts included"),
        "budget_exceeded"=>Dict("iterations"=>used>total_iterations,"wall"=>(time_ns()-began)/1e9>total_seconds))
    write(joinpath(out,name*"-staged.json"),JSON.json(summary;pretty=true))
    summary,result
end
