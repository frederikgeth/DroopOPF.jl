# S2 shedding-allowance comparison; isolated from the retained zero-shedding runner.
# Same physical model, with the original S2 10 MW shedding ceiling enabled.
@eval P2S2 begin
function md_allowance_attempt(x,folder,factors,events;seed=x.seed,fixed_controller=false,fixed_base=false,seconds=30.,retry=false,zero_shedding=false)
    ispath(folder)&&error("Do not overwrite attempt: $folder");mkpath(folder)
    emergency=x.size==500
    contract=(;case_size=x.size,factors,outages=[e.id for e in events],emergency,relief=emergency,
        thermal_multiplier=emergency ? 1.1 : 1.,fixed_controller,fixed_base,zero_shedding=zero_shedding,zero_dr=!emergency,
        response_relaxation_cap=0.,restore=false,active_response="s2_proportional_v1",
        initial_controller=seed.study.case.controls,objective=fixed_base ? "feasibility" : x.size==14 ? "nominal base active loss" : "feasibility",
        seconds,retry,reference_controls=x.reference.controls,angles=x.angles,
        source_study=joinpath(x.source,x.size==14 ? "controller.json" : "controller-feasibility.json"),
        fixed_base_reference=fixed_base ? [(;factor=f,seed.states[(f,:base)]...) for f in factors] : nothing)
    fd_save(joinpath(folder,"contract.json"),contract)
    t=@timed el_build(x,factors,events;seed,solver=:ipopt,emergency,relief=emergency,
        thermal_multiplier=emergency ? 1.1 : 1.,fixed_controller,fixed_base,restore=false,
        zero_shedding=zero_shedding,zero_dr=!emergency,ac_builder=x.size==500 ? nr_build_ac : p2_ac,penalty_proxies=false,direct_relief=x.size==500)
    built=t.value;m=built.m
    if !fixed_base && x.size==14
        nominal=only(b for b in built.blocks if b.id==:base&&b.factor==1.)
        @objective(m,Min,sum(nominal.v.pg)-sum(l.p for l in nominal.normal.loads))
    else
        @objective(m,Min,0.)
    end
    for key in ("bound_push","bound_frac","slack_bound_push","slack_bound_frac");set_optimizer_attribute(m,key,1e-8);end
    set_optimizer_attribute(m,"mu_init",1e-6)
    set_optimizer_attribute(m,"max_cpu_time",seconds);set_optimizer_attribute(m,"max_iter",retry ? 3000 : 1500)
    set_optimizer_attribute(m,"hessian_approximation",retry ? "limited-memory" : "exact")
    solved=@timed optimize!(m)
    record=(;stage="solve",status=string(termination_status(m)),native_success=termination_status(m) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.OPTIMAL,JuMP.MOI.ALMOST_LOCALLY_SOLVED),
        build_seconds=t.time,solve_seconds=solved.time,variables=num_variables(m),constraints=num_constraints(m;count_variable_in_set_constraints=true),
        allocated_bytes=t.bytes+solved.bytes,objective=has_values(m) ? objective_value(m) : nothing)
    fd_save(joinpath(folder,"stages.json"),[record])
    point=try el_save_point(folder,built,"solve",record) catch err
        fd_save(joinpath(folder,"extraction_error.json"),(;error=sprint(showerror,err)));nothing
    end
    audit=nothing
    if !isnothing(point)
        read(`python3 -B $(joinpath(ROOT,"examples/audit_p2_s2_numerics.py")) $folder`,String)
        audit=JSON.parsefile(joinpath(folder,"audit-solve.json"))
    end
    accepted=!isnothing(audit)&&audit["accepted"]
    summary=(;record,accepted,folder=relpath(folder,ROOT))
    fd_save(joinpath(folder,"summary.json"),summary)
    println("P2 ",x.size," ",basename(folder)," ",record.status," accepted=",accepted);flush(stdout)
    (;point,audit,summary)
end
end
