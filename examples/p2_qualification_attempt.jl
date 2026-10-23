# Feasibility polishing: earlier native acceptable convergence, unchanged physical audit.
# No production defaults or physical bounds are changed.
@eval P2S2 begin
function pq_attempt(x,folder,factors,events;seed=x.seed,fixed_controller=false,fixed_base=false,seconds=30.,retry=false,zero_shedding=true,initialization="scenario",objective_kind="feasibility",resource_caps=Dict{String,Float64}())
    ispath(folder)&&error("Do not overwrite attempt: $folder");mkpath(folder)
    emergency=x.size==500
    initialization in ("flat","base","neighbor","scenario")||error("Unknown initialization")
    original_seed=seed
    if initialization!="scenario"
        states=copy(seed.states)
        for (key,old) in seed.states
            f,id=key;id==:base&&continue
            preventive=get(seed.states,(f,:base),old)
            base=preventive
            if initialization=="neighbor"
                keys_at_f=sort([k for k in keys(seed.states) if k[1]==f && k[2]!=:base];by=k->string(k[2]))
                index=findfirst(==(key),keys_at_f)
                if !isnothing(index)&&length(keys_at_f)>1
                    base=seed.states[keys_at_f[mod1(index-1,length(keys_at_f))]]
                end
            end
            ev=findfirst(e->e.id==id,x.events)
            c=isnothing(ev) ? seed.study.case : scenario_case(seed.study.case,x.events[ev])
            pg=[g.available ? base.state.pg[i] : 0. for (i,g) in enumerate(c.generators)]
            qg=[g.available ? base.state.qg[i] : 0. for (i,g) in enumerate(c.generators)]
            vm=initialization=="flat" ? ones(length(base.state.vm)) : copy(base.state.vm)
            va=initialization=="flat" ? zeros(length(base.state.va)) : copy(base.state.va)
            states[key]=(;old...,state=ACState(vm,va,pg,qg),taps=merge(preventive.taps,base.taps),banks=merge(preventive.banks,base.banks),dr=base.dr,shed=base.shed,delta=0.)
        end
        seed=(;study=seed.study,states)
    end
    contract=(;case_size=x.size,factors,outages=[e.id for e in events],emergency,relief=emergency,
        thermal_multiplier=emergency ? 1.1 : 1.,fixed_controller,fixed_base,zero_shedding=zero_shedding,zero_dr=!emergency,
        response_relaxation_cap=0.,restore=false,active_response="s2_proportional_v1",
        initial_controller=seed.study.case.controls,objective=objective_kind,
        seconds,retry,initialization,objective_kind,resource_caps,native_acceptable_iter=1,native_acceptable_tol=1e-6,native_acceptable_constr_viol_tol=1e-7,reference_controls=x.reference.controls,angles=x.angles,
        source_study=joinpath(x.source,x.size==14 ? "controller.json" : "controller-feasibility.json"),
        fixed_base_reference=fixed_base ? [(;factor=f,seed.states[(f,:base)]...) for f in factors] : nothing)
    fd_save(joinpath(folder,"contract.json"),contract)
    t=@timed el_build(x,factors,events;seed,solver=:ipopt,emergency,relief=emergency,
        thermal_multiplier=emergency ? 1.1 : 1.,fixed_controller,fixed_base,restore=false,
        zero_shedding=zero_shedding,zero_dr=!emergency,ac_builder=x.size==500 ? nr_build_ac : p2_ac,penalty_proxies=(objective_kind=="emergency"||haskey(resource_caps,"emergency")),direct_relief=x.size==500)
    built=t.value;m=built.m
    start_rows=Any[]
    for b in built.blocks
        # Record actual independent voltage-variable starts; eliminated buses are expressions.
        vm=[start_value(v) for v in b.v.vm if v isa VariableRef]
        va=[start_value(v) for v in b.v.va if v isa VariableRef]
        push!(start_rows,(;factor=b.factor,id=b.id,vm,va))
    end
    fd_save(joinpath(folder,"initialization.json"),(;policy=initialization,states=start_rows))
    for (kind,cap) in resource_caps
        items=kind=="shedding" ? built.shed_all : kind=="dr" ? built.dr_all : built.departure
        @constraint(m,sum(items;init=0.)<=cap)
    end
    if objective_kind=="shedding"
        @objective(m,Min,sum(built.shed_all;init=0.))
    elseif objective_kind=="dr"
        @objective(m,Min,sum(built.dr_all;init=0.))
    elseif objective_kind=="emergency"
        @objective(m,Min,sum(built.departure;init=0.))
    elseif objective_kind=="loss"
        @objective(m,Min,sum(sum(b.v.pg)-sum(l.p for l in b.normal.loads) for b in built.blocks if b.id==:base))
    elseif !fixed_base && x.size==14 && 1. in factors
        nominal=only(b for b in built.blocks if b.id==:base&&b.factor==1.)
        @objective(m,Min,sum(nominal.v.pg)-sum(l.p for l in nominal.normal.loads))
    else
        @objective(m,Min,0.)
    end
    for key in ("bound_push","bound_frac","slack_bound_push","slack_bound_frac");set_optimizer_attribute(m,key,1e-8);end
    set_optimizer_attribute(m,"mu_init",1e-6)
    set_optimizer_attribute(m,"max_cpu_time",seconds);set_optimizer_attribute(m,"max_iter",retry ? 3000 : 1500)
    set_optimizer_attribute(m,"hessian_approximation",retry ? "limited-memory" : "exact")
    set_optimizer_attribute(m,"acceptable_iter",1)
    set_optimizer_attribute(m,"acceptable_tol",1e-6)
    set_optimizer_attribute(m,"acceptable_constr_viol_tol",1e-7)
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
