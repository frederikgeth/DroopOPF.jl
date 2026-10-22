# Twelve serial S1 base-case replays; no SCOPF campaign or equipment-policy change.
include("s1_zero_deadband_replay.jl")
const ZD_EXPANDED=joinpath(A500_ROOT,"artifacts/s1_zero_deadband/expanded")
function zd_policy(d)
    e=a500_read_policy(d)
    ds=[DroopControl(Int(x["control_id"]);
        slope_bounds=x["bounds"]["slope"],v_ref_bounds=x["bounds"]["v_ref"],
        deadband_low_bounds=x["bounds"]["deadband_low"],deadband_high_bounds=x["bounds"]["deadband_high"],
        initial=isnothing(x["initial"]) ? nothing : DroopOPF._droop_settings_from_data(x["initial"]))
        for x in get(d,"droop_controls",[])]
    (;e...,droop_controls=ds)
end
function zd_jobs()
    jobs=Any[]
    for factor in (.9,.95),init in ("cost","loss","joint")
        name="frozen-$factor-$init-ccopt"
        source=joinpath(A500_OUT,"attempts",name*".json");old=JSON.parsefile(source)
        seedpath=init=="joint" ? joinpath(A500_OUT,"selected_reference.json") : joinpath(A500_OUT,"attempts","source-$init-$factor-ipopt.json")
        seed=JSON.parsefile(seedpath);c=read_study(joinpath(A500_ROOT,old["model_path"])).case
        p=zd_policy(old["policy"]);s=a500_state(seed["state"])
        @assert DroopOPF._feasibility_hash(s)==old["contract"]["initial"]
        push!(jobs,(name="starts-"*name,source,seedpath,old,c,p,s,kind="original-start",mu=nothing,normalization=:none))
    end
    profile=joinpath(A500_ROOT,"artifacts/s1_closeout/profile/500")
    failures=[(path,JSON.parsefile(path)) for path in sort(readdir(joinpath(profile,"attempts");join=true))]
    filter!(x->!x[2]["accepted"] && !startswith(x[2]["name"],"retry-") && x[2]["solver"]=="ccopt",failures)
    @assert length(failures)==6
    for (source,old) in failures
        seedpath=joinpath(A500_ROOT,"artifacts/s1_free_droop/500/attempts",old["tags"]["seed"]*".json")
        seed=JSON.parsefile(seedpath);c=read_study(joinpath(A500_ROOT,old["base_model_path"])).case
        p=zd_policy(old["contract"]["policy"]);s=a500_state(seed["state"])
        @assert DroopOPF._feasibility_hash(s)==old["contract"]["initial"]
        @assert DroopOPF._feasibility_case_hash(c)==old["contract"]["case"]
        @assert DroopOPF._feasibility_hash(a500_json(p))==DroopOPF._feasibility_hash(old["contract"]["policy"])
        push!(jobs,(name="profile-"*old["name"],source,seedpath,old,c,p,s,kind="closeout-profile",mu=old["contract"]["mu"],normalization=Symbol(old["contract"]["normalization"])))
    end
    jobs
end
function zd_attempt(job,angles,costs)
    (;name,source,seedpath,old,c,p,s,kind,mu,normalization)=job
    contract=old["contract"]
    fp=feasibility_fingerprint(FeasibilityProblem(c;tap_controls=p.tap_controls,shunt_controls=p.shunt_controls,angle_limits=angles))
    kind=="original-start" && @assert fp==contract["model"]
    r=Dict{String,Any}("name"=>name,"kind"=>kind,"source_attempt"=>relpath(source,A500_ROOT),
        "seed_path"=>relpath(seedpath,A500_ROOT),"original_contract"=>contract,"model_fingerprint"=>fp,
        "source_sha256"=>bytes2hex(sha256(read(source))),"seed_sha256"=>bytes2hex(sha256(read(seedpath))),
        "original_status"=>old["solver_status"],"original_accepted"=>old["accepted"],
        "original_loss_mw"=>get(old,"loss_mw",nothing),"original_solve_wall_seconds"=>get(old,"solve_wall_seconds",nothing),
        "original_iterations"=>get(get(old,"ccopt_diagnostics",Dict()),"inner_iterations",get(old,"iterations",nothing)),
        "accepted"=>false,"point_pass"=>false,"solver_success"=>false)
    modelpath=joinpath(ZD_EXPANDED,"models",DroopOPF._feasibility_case_hash(c)*".json")
    mkpath(dirname(modelpath));isfile(modelpath)||write_study(modelpath,Study(c))
    r["base_model_path"]=relpath(modelpath,A500_ROOT);r["policy"]=a500_json(p)
    opts=Dict{String,Any}("relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),
        "tol"=>1e-11,"acceptable_tol"=>1e-11,"bound_relax_factor"=>0.,
        "max_iter"=>contract["iterations"],"max_wall_time"=>contract["seconds"])
    if !isnothing(mu)
        b=MadNLP.MonotoneUpdate(1e-11,10.);b.mu_init=mu;opts["barrier"]=b
        opts["bound_push"]=1e-8;opts["bound_fac"]=1e-8
    end
    println("START ",name);flush(stdout)
    start=time();built=Ref(start)
    try
        measured=@timed optimize_joint_design(c;p...,initial_state=s,encoding=:complementarity,
            optimizer_attributes=opts,control_normalization=normalization,
            _measurement_hook=(phase,m)->begin
                if phase==:built
                    idx=DroopOPF._bus_indices(c.network)
                    for b in c.network.branches
                        b.available || continue;lo,hi=angles[b.id]
                        vf=variable_by_name(m,"va[$(idx[b.from_bus])]");vt=variable_by_name(m,"va[$(idx[b.to_bus])]")
                        @constraint(m,lo<=vf-vt<=hi)
                    end
                    pg=[variable_by_name(m,"pg[$i]") for i in eachindex(c.generators)]
                    @objective(m,Min,sum(pg)-sum(l.p for l in c.loads))
                    r["variables"]=num_variables(m);built[]=time();r["build_seconds"]=built[]-start
                elseif phase==:solved
                    r["solve_wall_seconds"]=time()-built[]
                    r["ccopt_diagnostics"]=ccopt_diagnostics(m);r["ccopt_encoding_audit"]=ccopt_encoding_audit(m)
                end
            end)
        result=measured.value;r["total_optimizer_seconds"]=measured.time;r["julia_allocated_bytes"]=measured.bytes
        r["solver_status"]=string(result.opf.termination_status)
        r["solver_success"]=result.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
        if !isnothing(result.opf.state)
            resultpath=joinpath(ZD_EXPANDED,"results",name*".json");mkpath(dirname(resultpath));write_joint_design(resultpath,result)
            r["result_path"]=relpath(resultpath,A500_ROOT)
            check=validate_joint_design(c,result);r["design_policy_valid"]=check.policy_valid
            curve=DroopOPF._joint_droop_case(c,result)
            r["state"]=a500_json(result.opf.state);r["taps"]=a500_json(result.taps);r["susceptances"]=a500_json(result.susceptances)
            r["droops"]=a500_json(result.droops);r["objective"]=result.opf.objective
            a500_details(curve,r,angles,(tap_controls=p.tap_controls,shunt_controls=p.shunt_controls),costs)
            r["objective_replay_error"]=abs(result.opf.objective-r["loss_mw"]/c.base_power)
            r["point_pass"] &= check.policy_valid && r["objective_replay_error"]<1e-5
            r["accepted"]=r["point_pass"] && r["solver_success"]
        end
    catch err
        err isa InterruptException && rethrow()
        r["error"]=sprint(showerror,err);r["accepted"]=false
    end
    mkpath(joinpath(ZD_EXPANDED,"attempts"));a500_save(joinpath(ZD_EXPANDED,"attempts",name*".json"),r)
    println("END ",name," status=",get(r,"solver_status",get(r,"error","unknown"))," accepted=",r["accepted"]);flush(stdout)
    r
end
function zero_deadband_expanded()
    _,_,angles,costs,_=a500_inputs();jobs=zd_jobs();@assert length(jobs)==12
    # Validate all saved configurations before any numerical work.
    rows=Any[]
    for job in jobs;push!(rows,zd_attempt(job,angles,costs));end
    a500_save(joinpath(ZD_EXPANDED,"summary.json"),Dict("attempts"=>rows,
        "scope"=>"Six original 90/95% OPF starts and six failed closeout-profile primaries; unchanged starts, equipment policy, objective, budgets and tolerances; serial; no retries",
        "julia_version"=>string(VERSION),"cpu"=>Sys.CPU_NAME,"julia_threads"=>Threads.nthreads(),
        "solver_versions"=>Dict("CCOpt"=>string(Base.pkgversion(CCOpt)),"MadNLP"=>string(Base.pkgversion(MadNLP))),
        "code_hashes"=>Dict(f=>bytes2hex(sha256(read(joinpath(A500_ROOT,f)))) for f in
            ("src/complementarity.jl","src/jump.jl","examples/s1_zero_deadband_expanded.jl","examples/s1_arpae500_campaign.jl"))))
end
abspath(PROGRAM_FILE)==(@__FILE__) && zero_deadband_expanded()
