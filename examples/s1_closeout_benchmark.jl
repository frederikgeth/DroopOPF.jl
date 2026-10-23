# Serial S1 closeout profile; no SCOPF. Start from each solver's verified point.
include("s1_free_droop.jl")
const SC_OUT=joinpath(FD_ROOT,"artifacts/s1_closeout/profile")
function sc_attempt(size,c,s,p,x,name,tags;solver=:ipopt,iterations=size==14 ? 600 : 1000,seconds=size==14 ? 20. : 60.,mu=nothing,normalization=:none)
    out=joinpath(SC_OUT,string(size));path=joinpath(out,"attempts",name*".json")
    contract=Dict("case"=>DroopOPF._feasibility_case_hash(c),"policy"=>a500_json(p),"initial"=>DroopOPF._feasibility_hash(s),"solver"=>string(solver),"iterations"=>iterations,"seconds"=>seconds,"mu"=>mu,"normalization"=>string(normalization),"epsilon"=>1e-6,"objective"=>"loss")
    hash=DroopOPF._feasibility_hash(contract)
    if isfile(path);r=JSON.parsefile(path);@assert r["contract_hash"]==hash "changed resume contract $name";return r;end
    basepath=joinpath(out,"models",contract["case"]*".json");mkpath(dirname(basepath));isfile(basepath)||write_study(basepath,Study(c))
    r=Dict{String,Any}("name"=>name,"size"=>size,"tags"=>tags,"solver"=>string(solver),"objective_kind"=>"loss","contract"=>contract,"contract_hash"=>hash,"base_model_path"=>relpath(basepath,FD_ROOT),"policy"=>a500_json(fd_equipment(p)),"droop_policy"=>a500_json(p.droop_controls),"accepted"=>false,"point_pass"=>false,"solver_success"=>false)
    println("START ",size," ",name);flush(stdout)
    validation_start=time()
    try
        opts=solver==:ipopt ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>iterations,"max_cpu_time"=>seconds,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive","print_level"=>0) : solver==:madnlp ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>iterations,"max_wall_time"=>seconds,"bound_relax_factor"=>0.) : Dict{String,Any}("relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),"tol"=>1e-11,"acceptable_tol"=>1e-11,"max_iter"=>iterations,"max_wall_time"=>seconds,"bound_relax_factor"=>0.)
        if !isnothing(mu);@assert solver==:ccopt;b=MadNLP.MonotoneUpdate(1e-11,10.);b.mu_init=mu;opts["barrier"]=b;opts["bound_push"]=1e-8;opts["bound_fac"]=1e-8;end
        kw=solver==:ccopt ? (encoding=:complementarity,) : (optimizer_factory=solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer,)
        t=Ref(time())
        built=Ref(time()); solved=Ref(time()); measured=@timed optimize_joint_design(c;initial_state=s,p...,kw...,optimizer_attributes=opts,smooth_epsilon=1e-6,smooth_reactive_epsilon=1e-6,control_normalization=normalization,_measurement_hook=(phase,m)->begin
            if phase==:built
                idx=DroopOPF._bus_indices(c.network)
                for b in c.network.branches
                    b.available||continue;lo,hi=x.angles[b.id];vf=variable_by_name(m,"va[$(idx[b.from_bus])]");vt=variable_by_name(m,"va[$(idx[b.to_bus])]");@constraint(m,lo<=vf-vt<=hi)
                end
                pg=[variable_by_name(m,"pg[$i]") for i in eachindex(c.generators)];@objective(m,Min,sum(pg)-sum(l.p for l in c.loads));r["build_seconds"]=time()-built[];r["variables"]=num_variables(m);r["constraints"]=num_constraints(m;count_variable_in_set_constraints=true);t[]=time()
            elseif phase==:solved
                r["solve_wall_seconds"]=time()-t[];solved[]=time()
                try;r["iterations"]=JuMP.barrier_iterations(m);catch;end
                if solver==:ccopt;try;r["ccopt_diagnostics"]=ccopt_diagnostics(m);catch;end;end
            elseif phase==:extracted
                r["extraction_seconds"]=time()-solved[]
            end
        end)
        result=measured.value;r["total_optimizer_seconds"]=measured.time;r["julia_allocated_bytes"]=measured.bytes;r["gc_seconds"]=measured.gctime;r["process_highwater_rss_bytes"]=Sys.maxrss(); validation_start=time()
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
    r["validation_and_packaging_seconds"]=haskey(r,"state") ? time()-validation_start : nothing;fd_save(path,r);println("END ",size," ",name," accepted=",r["accepted"]," status=",get(r,"solver_status",get(r,"error","unknown")));flush(stdout);r
end

function sc_run()
    mkpath(SC_OUT)
    fd_save(joinpath(SC_OUT,"environment.json"),Dict("julia"=>string(VERSION),"cpu"=>Sys.CPU_NAME,"cpu_threads"=>Sys.CPU_THREADS,"julia_threads"=>Threads.nthreads(),"word_size"=>Sys.WORD_SIZE,"kernel"=>string(Sys.KERNEL),"architecture"=>string(Sys.ARCH),"total_memory_bytes"=>Sys.total_memory(),"solver_versions"=>Dict("Ipopt"=>string(Base.pkgversion(Ipopt)),"MadNLP"=>string(Base.pkgversion(MadNLP)),"CCOpt"=>string(Base.pkgversion(CCOpt))),"memory_scope"=>"Sys.maxrss is whole-process high-water RSS including warmup/JIT and earlier cells; not incremental or per-solve peak. @timed bytes are Julia allocations only, excluding native allocations."))
    for size in (14,500)
        x=fd_inputs(size);prior=[JSON.parsefile(p) for p in readdir(joinpath(FD_OUT,string(size),"attempts");join=true)]
        for solver in (:ipopt,:madnlp,:ccopt)
            r=first(filter(r->r["accepted"] && r["solver"]==string(solver) && r["tags"]["stage"]=="frozen" && r["tags"]["family"]=="droop" && r["tags"]["factor"]==1.,prior))
            c=read_study(joinpath(FD_ROOT,r["base_model_path"])).case;p=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
            sc_attempt(size,c,a500_state(r["state"]),p,x,"warmup-$solver",Dict("stage"=>"warmup");solver,mu=solver==:ccopt ? 1e-6 : nothing)
        end
        for stage in ("design","frozen"),family in FD_FAMILIES,f in (1.,.9),solver in (:ipopt,:madnlp,:ccopt)
            good=filter(r->r["accepted"] && r["solver"]==string(solver) && r["tags"]["family"]==family && r["tags"]["factor"]==f && (r["tags"]["stage"]==stage || get(r["tags"],"target_stage","")==stage),prior)
            seed=first(sort(good;by=r->r["loss_mw"]))
            base,p=stage=="design" ? fd_model(x,family) : (read_study(joinpath(FD_OUT,string(size),"selected-$family-study.json")).case,(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[]))
            c=DroopOPF._feasibility_scaled_case(base,f);p=fd_warm_policy(c,p,seed)
            tags=Dict("stage"=>stage,"family"=>family,"factor"=>f,"seed"=>seed["name"],"purpose"=>"serial warmed known-witness replay; not new-start generalization")
            r=sc_attempt(size,c,a500_state(seed["state"]),p,x,"$stage-$family-$f-$solver",tags;solver,mu=solver==:ccopt ? 1e-6 : nothing)
            if !r["accepted"]
                sc_attempt(size,c,a500_state(seed["state"]),p,x,"retry-$stage-$family-$f-$solver",merge(tags,Dict("retry"=>true));solver,iterations=3000,seconds=120.,mu=solver==:ccopt ? 1e-8 : nothing,normalization=solver==:ccopt ? :none : :bounds)
            end
        end
    end
end
if abspath(PROGRAM_FILE)==(@__FILE__);sc_run();end
