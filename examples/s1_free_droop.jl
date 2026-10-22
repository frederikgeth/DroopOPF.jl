# S1 only: independently optimized slopes/references, then frozen-design validation.
include("s1_arpae500_campaign.jl")
const FD_ROOT=A500_ROOT
const FD_OUT=joinpath(FD_ROOT,"artifacts/s1_free_droop")
const FD_FACTORS=(1.,.9,1.1,.95,1.05)
const FD_FAMILIES=("droop","droop_tap","droop_shunt","droop_tap_shunt")
fd_save(p,x)=(mkpath(dirname(p));a500_save(p,x))
function fd_inputs(size)
    if size==500
        source,_,angles,costs,_=a500_inputs();base=read_study(joinpath(A500_OUT,"calibrated-study.json")).case
        ref=JSON.parsefile(joinpath(A500_OUT,"selected_reference.json"))
        seeds=Dict((init,f)=>a500_state(JSON.parsefile(joinpath(A500_OUT,"attempts","source-$init-$f-ipopt.json"))["state"]) for init in ("loss","cost") for f in FD_FACTORS)
        witnesses=JSON.parsefile(joinpath(A500_OUT,"demand_witnesses.json"))
        fixed=Dict(f=>witnesses["fixed-$f"] for f in FD_FACTORS)
    else
        source=read_study(joinpath(FD_ROOT,"artifacts/s1_arpae14_stress/source-study.json")).case
        base=read_study(joinpath(FD_ROOT,"artifacts/s1_arpae14_joint_reference/relative5-study.json")).case
        ref=JSON.parsefile(joinpath(FD_ROOT,"artifacts/s1_arpae14_closeout/calibration_reference.json"))
        ad=JSON.parsefile(joinpath(FD_ROOT,"artifacts/s1_arpae14_closeout/angle_limits.json"));angles=Dict(parse(Int,k)=>Tuple(Float64.(v)) for (k,v) in ad)
        n=JSON.parsefile(joinpath(FD_ROOT,"test/data/arpae/c1_network01/results/scenario_01_pmin0_qsym/network_model.json"));costs=Dict{Int,Vector{Tuple{Float64,Float64}}}()
        for (id,g) in n["gen"]
            g["gen_status"]==1 || continue;@assert g["model"]==1;v=g["cost"];segs=Tuple{Float64,Float64}[]
            for i in 1:g["ncost"]-1;x,y,xx,yy=Float64.(v[2i-1:2i+2]);m=(yy-y)/(xx-x);push!(segs,(m,y-m*x));end
            @assert issorted(first.(segs));costs[parse(Int,id)]=segs
        end
        seeds=Dict{Tuple{String,Float64},ACState}()
        for init in ("cost","loss"),f in FD_FACTORS
            folder=init=="cost" ? "s1_arpae14_demand_anchors" : "s1_arpae14_loss_anchors"
            path=f in (.95,1.05) ? joinpath(FD_ROOT,"artifacts/s1_arpae14_confirmation","opf-$init-$f.json") : joinpath(FD_ROOT,"artifacts",folder,"opf-$f.json")
            sol=JSON.parsefile(path)["solution"]
            seeds[(init,f)]=ACState([sol["bus"][string(b.id)]["vm"] for b in source.network.buses],[sol["bus"][string(b.id)]["va"] for b in source.network.buses],[get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"] for g in source.generators],[get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"] for g in source.generators])
        end
        fixed=Dict(r["tags"]["factor"]=>r for r in JSON.parsefile(joinpath(FD_ROOT,"artifacts/s1_arpae14_closeout/demand_witnesses.json")))
    end
    @assert length(base.network.buses)==size
    for g in base.generators;@assert g.p_min==0 && isapprox(g.q_min,-g.q_max;atol=1e-10);end
    (source=source,base=base,ref=ref,seeds=seeds,angles=angles,costs=costs,fixed=fixed)
end
function fd_model(x,family)
    taps=occursin("tap",family);shunts=occursin("shunt",family)
    c=x.base
    taps || (c=with_tap_settings(c,a500_settings(x.ref["taps"])))
    shunts || (c=with_shunt_settings(c,a500_settings(x.ref["susceptances"])))
    e=a500_policy(c,taps && shunts ? "tap_shunt" : taps ? "tap" : shunts ? "shunt" : "fixed";reference=x.ref)
    ds=[DroopControl(i;slope_bounds=(.02/(d.capability.q_max-d.capability.q_min),.08/(d.capability.q_max-d.capability.q_min)),v_ref_bounds=(d.schedule.v_ref-.02,d.schedule.v_ref+.02)) for (i,d) in enumerate(c.controls)]
    c,(;e...,droop_controls=ds)
end
fd_equipment(p)=(tap_controls=p.tap_controls,shunt_controls=p.shunt_controls)
function fd_warm_policy(c,p,r)
    e=(tap_controls=[TapControl(t.branch_id;lower=t.lower,upper=t.upper,nominal=t.nominal,initial=clamp(r["taps"][string(t.branch_id)],t.lower,t.upper)) for t in p.tap_controls],shunt_controls=[ShuntControl(t.bank_id;lower=t.lower,upper=t.upper,nominal=t.nominal,initial=clamp(r["susceptances"][string(t.bank_id)],t.lower,t.upper)) for t in p.shunt_controls])
    ds=DroopControl[]
    for d in p.droop_controls
        s=haskey(get(r,"droops",Dict()),string(d.control_id)) ? DroopOPF._droop_settings_from_data(r["droops"][string(d.control_id)]) : DroopSettings(c.controls[d.control_id])
        b=d.bounds;initial=DroopSettings(clamp(s.slope,b.slope...),clamp(s.v_ref,b.v_ref...),0.,0.)
        push!(ds,DroopControl(d.control_id;slope_bounds=b.slope,v_ref_bounds=b.v_ref,initial))
    end
    (;e...,droop_controls=ds)
end
function fd_attempt(size,c,s,p,x,name,tags;solver=:ipopt,iterations=size==14 ? 600 : 1000,seconds=size==14 ? 20. : 60.,mu=nothing,normalization=:none)
    out=joinpath(FD_OUT,string(size));path=joinpath(out,"attempts",name*".json")
    contract=Dict("case"=>DroopOPF._feasibility_case_hash(c),"policy"=>a500_json(p),"initial"=>DroopOPF._feasibility_hash(s),"solver"=>string(solver),"iterations"=>iterations,"seconds"=>seconds,"mu"=>mu,"normalization"=>string(normalization),"epsilon"=>1e-6,"objective"=>"loss")
    hash=DroopOPF._feasibility_hash(contract)
    if isfile(path);r=JSON.parsefile(path);@assert r["contract_hash"]==hash "changed resume contract $name";return r;end
    basepath=joinpath(out,"models",contract["case"]*".json");mkpath(dirname(basepath));isfile(basepath)||write_study(basepath,Study(c))
    r=Dict{String,Any}("name"=>name,"size"=>size,"tags"=>tags,"solver"=>string(solver),"objective_kind"=>"loss","contract"=>contract,"contract_hash"=>hash,"base_model_path"=>relpath(basepath,FD_ROOT),"policy"=>a500_json(fd_equipment(p)),"droop_policy"=>a500_json(p.droop_controls),"accepted"=>false,"point_pass"=>false,"solver_success"=>false)
    println("START ",size," ",name);flush(stdout)
    try
        opts=solver==:ipopt ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>iterations,"max_cpu_time"=>seconds,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive","print_level"=>0) : solver==:madnlp ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>iterations,"max_wall_time"=>seconds,"bound_relax_factor"=>0.) : Dict{String,Any}("relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),"tol"=>1e-11,"acceptable_tol"=>1e-11,"max_iter"=>iterations,"max_wall_time"=>seconds,"bound_relax_factor"=>0.)
        if !isnothing(mu);@assert solver==:ccopt;b=MadNLP.MonotoneUpdate(1e-11,10.);b.mu_init=mu;opts["barrier"]=b;opts["bound_push"]=1e-8;opts["bound_fac"]=1e-8;end
        kw=solver==:ccopt ? (encoding=:complementarity,) : (optimizer_factory=solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer,)
        t=Ref(time())
        result=optimize_joint_design(c;initial_state=s,p...,kw...,optimizer_attributes=opts,smooth_epsilon=1e-6,smooth_reactive_epsilon=1e-6,control_normalization=normalization,_measurement_hook=(phase,m)->begin
            if phase==:built
                idx=DroopOPF._bus_indices(c.network)
                for b in c.network.branches
                    b.available||continue;lo,hi=x.angles[b.id];vf=variable_by_name(m,"va[$(idx[b.from_bus])]");vt=variable_by_name(m,"va[$(idx[b.to_bus])]");@constraint(m,lo<=vf-vt<=hi)
                end
                pg=[variable_by_name(m,"pg[$i]") for i in eachindex(c.generators)];@objective(m,Min,sum(pg)-sum(l.p for l in c.loads));t[]=time()
            elseif phase==:solved
                r["solve_wall_seconds"]=time()-t[]
                try;r["iterations"]=JuMP.barrier_iterations(m);catch;end
                if solver==:ccopt;try;r["ccopt_diagnostics"]=ccopt_diagnostics(m);catch;end;end
            end
        end)
        r["solver_status"]=string(result.opf.termination_status);r["solver_success"]=result.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
        if result.opf.state!==nothing
            rp=joinpath(out,"results",name*".json");mkpath(dirname(rp));write_joint_design(rp,result);r["result_path"]=relpath(rp,FD_ROOT)
            check=validate_joint_design(c,result);r["design_policy_valid"]=check.policy_valid
            curve=DroopOPF._joint_droop_case(c,result);mp=joinpath(out,"models",DroopOPF._feasibility_case_hash(curve)*".json");isfile(mp)||write_study(mp,Study(curve));r["model_path"]=relpath(mp,FD_ROOT)
            r["state"]=a500_json(result.opf.state);r["taps"]=a500_json(result.taps);r["susceptances"]=a500_json(result.susceptances);r["droops"]=a500_json(result.droops)
            r["objective"]=isfinite(result.opf.objective) ? result.opf.objective : nothing
            a500_details(curve,r,x.angles,fd_equipment(p),x.costs)
            r["point_pass"] &= check.policy_valid;r["accepted"]=r["point_pass"] && r["solver_success"]
            r["slopes_percent"]=[100*d.slope*(d.capability.q_max-d.capability.q_min) for d in curve.controls]
            r["vrefs"]=[d.schedule.v_ref for d in curve.controls]
            r["reference_movements"]=[curve.controls[i].schedule.v_ref-c.controls[i].schedule.v_ref for i in eachindex(c.controls)]
            r["objective_replay_error"]=abs(result.opf.objective-r["loss_mw"]/c.base_power)
            r["accepted"] && @assert r["objective_replay_error"]<1e-5
        end
    catch err
        err isa InterruptException && rethrow();r["error"]=sprint(showerror,err);r["accepted"]=false
    end
    fd_save(path,r);println("END ",size," ",name," accepted=",r["accepted"]," status=",get(r,"solver_status",get(r,"error","unknown")));flush(stdout);r
end
function fd_precursors(size,x)
    out=joinpath(FD_OUT,string(size));checks=[]
    for f in FD_FACTORS,init in ("cost","loss")
        c=DroopOPF._feasibility_scaled_case(x.source,f);a=validate_feasibility_witness(FeasibilityProblem(c;angle_limits=x.angles),FeasibilityWitness(x.seeds[(init,f)]));@assert a["valid"]
        push!(checks,Dict("factor"=>f,"init"=>init,"valid"=>true))
    end
    for family in FD_FAMILIES,f in FD_FACTORS
        c,p=fd_model(x,family);c=DroopOPF._feasibility_scaled_case(c,f);r=x.fixed[f]
        taps=Dict(t.branch_id=>x.ref["taps"][string(t.branch_id)] for t in p.tap_controls);bs=Dict(t.bank_id=>x.ref["susceptances"][string(t.bank_id)] for t in p.shunt_controls)
        a=validate_feasibility_witness(FeasibilityProblem(c;fd_equipment(p)...,angle_limits=x.angles),FeasibilityWitness(a500_state(r["state"]);taps,susceptances=bs));@assert a["valid"]
        for d in p.droop_controls;DroopOPF._joint_droop_policy(c,d);end
        push!(checks,Dict("family"=>family,"factor"=>f,"gate"=>"feasible","evidence"=>"verified incumbent fixed-8% design lies inside free-design bounds"))
    end
    fd_save(joinpath(out,"precursors.json"),checks);fd_save(joinpath(out,"angle_limits.json"),x.angles)
end
function fd_recover(size,c,p,x,tags,direct,fallback=nothing)
    bad=filter(r->!r["accepted"],direct);isempty(bad)&&return Any[]
    good=filter(r->r["point_pass"],direct);seed=isempty(good) ? fallback : first(sort(good;by=r->r["loss_mw"]))
    isnothing(seed)&&return Any[]
    pp=fd_warm_policy(c,p,seed);s=a500_state(seed["state"]);rows=[]
    for solver in unique(r["solver"] for r in bad)
        names=[r["name"] for r in bad if r["solver"]==solver]
        stem=tags["stage"]*"-"*tags["family"]*"-"*string(tags["factor"])*"-"*solver
        rt=merge(tags,Dict("stage"=>"recovery","target_stage"=>tags["stage"],"failed_attempts"=>names,"seed"=>seed["name"]))
        r=fd_attempt(size,c,s,pp,x,"retry-"*stem*"-warm",merge(rt,Dict("method"=>"verified warm start"));solver=Symbol(solver));push!(rows,r)
        if !r["accepted"]
            r=fd_attempt(size,c,s,pp,x,"retry-"*stem*"-conditioned",merge(rt,Dict("method"=>solver=="ccopt" ? "small barrier and bound push, expanded budget" : "bounds normalization, expanded budget"));solver=Symbol(solver),iterations=3000,seconds=size==14 ? 60. : 120.,mu=solver=="ccopt" ? 1e-8 : nothing,normalization=solver=="ccopt" ? :none : :bounds);push!(rows,r)
        end
    end
    rows
end
function fd_run(size;stage="all")
    x=fd_inputs(size);out=joinpath(FD_OUT,string(size));fd_precursors(size,x)
    if stage in ("all","design")
        for family in FD_FAMILIES,f in FD_FACTORS
            base,p=fd_model(x,family);c=DroopOPF._feasibility_scaled_case(base,f);tags=Dict("stage"=>"design","family"=>family,"factor"=>f);rows=[]
            for init in ("joint","loss","cost"),solver in (:ipopt,:madnlp,:ccopt)
                s=init=="joint" ? a500_state(x.ref["state"]) : x.seeds[(init,f)]
                push!(rows,fd_attempt(size,c,s,p,x,"design-$family-$f-$init-$solver",merge(tags,Dict("init"=>init));solver))
            end
            r=deepcopy(x.fixed[f]);r["name"]="incumbent-fixed-$f";r["taps"]=x.ref["taps"];r["susceptances"]=x.ref["susceptances"]
            fd_recover(size,c,p,x,tags,rows,r)
        end
    end
    if stage in ("all","frozen")
        allrows=[JSON.parsefile(p) for p in readdir(joinpath(out,"attempts");join=true)];selected=[]
        for family in FD_FAMILIES
            good=filter(r->r["accepted"] && r["tags"]["family"]==family && r["tags"]["factor"]==1. && (r["tags"]["stage"]=="design" || get(r["tags"],"target_stage","")=="design"),allrows);@assert !isempty(good)
            bestloss=minimum(r["loss_mw"] for r in good);near=filter(r->r["loss_mw"]<=bestloss+1e-6,good)
            distance(r)=sum(((r["slopes_percent"][i]-8.)/6)^2+(r["reference_movements"][i]/.02)^2 for i in eachindex(x.base.controls))
            chosen=first(sort(near;by=r->(distance(r),r["name"])));base,_=fd_model(x,family);result=read_joint_design(joinpath(FD_ROOT,chosen["result_path"]));frozen=with_joint_settings(base,result)
            path=joinpath(out,"selected-$family-study.json");write_study(path,Study(frozen));push!(selected,Dict("family"=>family,"chosen"=>chosen["name"],"nominal_loss_mw"=>chosen["loss_mw"],"tie_tolerance_mw"=>1e-6,"distance"=>distance(chosen),"path"=>relpath(path,FD_ROOT)))
            p=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
            for f in FD_FACTORS
                c=DroopOPF._feasibility_scaled_case(frozen,f);tags=Dict("stage"=>"frozen","family"=>family,"factor"=>f,"selected"=>chosen["name"]);rows=[]
                for init in ("joint","loss","cost"),solver in (:ipopt,:madnlp,:ccopt)
                    s=init=="joint" ? a500_state(x.ref["state"]) : x.seeds[(init,f)]
                    push!(rows,fd_attempt(size,c,s,p,x,"frozen-$family-$f-$init-$solver",merge(tags,Dict("init"=>init));solver))
                end
                fd_recover(size,c,p,x,tags,rows)
            end
        end
        fd_save(joinpath(out,"selected.json"),selected)
    end
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    fd_run(parse(Int,ARGS[1]);stage=length(ARGS)>1 ? ARGS[2] : "all")
end
