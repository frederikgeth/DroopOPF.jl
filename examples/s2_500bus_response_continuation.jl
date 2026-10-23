# Demand continuation and a diagnostic relaxation of active response only.
include("s2_500bus_network_reduction.jl")
const RC_OUT=joinpath(S2500_OUT,"response_continuation")
const RC_DRIVER_SOURCE=read(@__FILE__,String)
const RC_ROWS=Any[]
const RC_MAX_ATTEMPTS=36

function rc_save_status(extra=NamedTuple())
    fd_save(joinpath(RC_OUT,"progress.json"),(;attempts=RC_ROWS,full_n1_accepted=false,
        exact_acceptance_requires_zero_response_relaxation=true,extra...))
end

function rc_solve(x,name,f,events;seed,cap=0.,zero_shedding=true,response_objective=false,
    seconds=90.,solver=:madnlp)
    length(RC_ROWS)<RC_MAX_ATTEMPTS || return nothing
    name=name*"-a"*lpad(string(length(RC_ROWS)+1),2,'0')
    folder=joinpath(RC_OUT,name);mkpath(folder)
    write(joinpath(folder,"executed_driver.jl"),RC_DRIVER_SOURCE)
    lane=nr_solve(x,name,(f,),events;output_relative="../response_continuation/",seed,
        fixed_controller=true,emergency=true,relief=true,thermal_multiplier=1.1,
        restore=false,zero_shedding,feasibility_only=true,penalty_proxies=false,
        response_relaxation_cap=cap,response_objective,solver,seconds)
    stage=last(JSON.parsefile(joinpath(folder,"stages.json")))["stage"]
    network=joinpath(folder,"network-audit-$stage.json")
    ck=isfile(network) ? JSON.parsefile(network) : Dict("accepted"=>false,"diagnostic_accepted"=>false)
    a=isfile(joinpath(folder,"audit-$stage.json")) ? JSON.parsefile(joinpath(folder,"audit-$stage.json")) : nothing
    states=isnothing(a) ? Any[] : a["states"]
    row=(;name,factor=f,cap,zero_shedding,response_objective,solver,stage,
        accepted=ck["accepted"],diagnostic_accepted=get(ck,"diagnostic_accepted",false),
        response_free_physical_valid=get(ck,"response_free_physical_valid",false),
        native_status=last(JSON.parsefile(joinpath(folder,"stages.json")))["status"],
        max_response_mw=maximum((r["response_coupling_max_pu"]*x.study.case.base_power for r in states);init=0.),
        max_response_pmax_fraction=maximum((r["response_error_max_pmax_fraction"] for r in states);init=0.),
        max_balance_pu=maximum((r["power_balance_max_pu"] for r in states);init=0.),
        max_dr_mw=maximum((r["dr_mw"] for r in states);init=0.),
        max_shedding_mw=maximum((r["shedding_mw"] for r in states);init=0.))
    push!(RC_ROWS,row);rc_save_status()
    println("RESPONSE CONTINUATION CHECK ",row);flush(stdout)
    (;lane...,row)
end

function rc_restore(x,f,events,failed;tag)
    # Same physical problem and full relief policy throughout this diagnostic;
    # only Pg_out - Pg_base - alpha*delta is relaxed.
    relaxed=rc_solve(x,"$tag-response-free",f,events;seed=failed.point,cap=1.,
        zero_shedding=false,seconds=120.)
    isnothing(relaxed) && return nothing
    if !relaxed.row.diagnostic_accepted
        retry=rc_solve(x,"$tag-response-free-ipopt",f,events;seed=relaxed.point,cap=1.,
            zero_shedding=false,seconds=120.,solver=:ipopt)
        isnothing(retry) && return nothing
        relaxed=retry
    end
    relaxed.row.diagnostic_accepted || return nothing
    for round in 1:3
        norm=rc_solve(x,"$tag-response-min-$round",f,events;seed=relaxed.point,cap=relaxed.row.cap,
            zero_shedding=false,response_objective=true,seconds=120.)
        isnothing(norm) && return nothing
        if norm.row.diagnostic_accepted || norm.row.response_free_physical_valid
            relaxed=norm
        end
        exact=rc_solve(x,"$tag-exact-restore-$round",f,events;seed=relaxed.point,
            zero_shedding=false,seconds=90.)
        isnothing(exact) && return nothing
        exact.row.accepted && return exact
        rho=max(1e-5,min(relaxed.row.cap/2,.75*relaxed.row.max_response_pmax_fraction))
        next=rc_solve(x,"$tag-response-cap-$round",f,events;seed=relaxed.point,cap=rho,
            zero_shedding=false,response_objective=true,seconds=120.)
        isnothing(next) && return nothing
        next.row.diagnostic_accepted || return nothing
        relaxed=next
    end
    nothing
end

function rc_run()
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    x=el_context();mkpath(RC_OUT)
    fd_save(joinpath(RC_OUT,"protocol.json"),(;
        authorization="User approved demand continuation and response-coupling diagnostic/restoration. Reuse the explicitly confirmed 500-bus controls and bounds for this campaign and retries.",
        tap_controls=x.study.tap_controls,shunt_controls=x.study.shunt_controls,control_policy=x.study.control_policy,
        base_full_load_normal_limits=true,emergency_voltage_extension=.05,thermal_multiplier=1.1,
        dr_fraction=.01,shedding_mw=10.,combined_fraction=.1,shared_controller_fixed_for_isolation=true,
        initial_factor=1.05,target_factor=1.1,initial_step=.005,refined_step=.0025,
        response_relaxation="Only diagnostic Pg_out = Pg_base + alpha*delta + e; |e_g| <= rho*Pmax_g. rho=1 permits any bounded Pg with delta=0. Physical constraints unchanged.",
        zero_relaxation_fresh_model_required_for_acceptance=true,maximum_attempts=RC_MAX_ATTEMPTS,
        phase_one_power_injections=false,physical_remedies=false))
    events=filter(e->e.id in (:branch_36,:branch_219,:branch_562,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    seed=el_read_point(joinpath(NR_OUT,"refined-regression-1.05");stage="feasibility")
    lower=1.05;step=.005;zero_shedding=true;accepted=Any[];failed_factor=nothing
    while lower<1.1-1e-9 && length(RC_ROWS)<RC_MAX_ATTEMPTS
        f=round(min(1.1,lower+step);digits=4);tag="demand-$(round(Int,f*10000))"
        run=rc_solve(x,tag,f,events;seed,zero_shedding)
        isnothing(run) && break
        if !run.row.accepted && step>.0025+1e-9
            step=.0025
            rc_save_status((;last_exact_factor=lower,failed_factor=f,step))
            continue
        end
        if !run.row.accepted && zero_shedding
            run=rc_solve(x,tag*"-full-relief",f,events;seed=run.point,zero_shedding=false)
            isnothing(run) && break
        end
        if !run.row.accepted
            recovered=rc_restore(x,f,events,run;tag)
            if isnothing(recovered)
                failed_factor=f;break
            end
            run=recovered
        end
        push!(accepted,run.row);seed=run.point;lower=f;zero_shedding=run.row.zero_shedding
        fd_save(joinpath(RC_OUT,"selected-exact.json"),(;factor=f,name=run.row.name,stage=run.row.stage))
        rc_save_status((;last_exact_factor=lower,step,accepted_factors=[r.factor for r in accepted]))
    end
    fd_save(joinpath(RC_OUT,"summary.json"),(;accepted,attempts=RC_ROWS,last_exact_factor=lower,failed_factor,
        target_recovered=lower>=1.1-1e-9,maximum_attempts=RC_MAX_ATTEMPTS,
        budget_reached=length(RC_ROWS)>=RC_MAX_ATTEMPTS,exhaustive_qualified=false,
        exact_feasible_boundary_determined=false,full_n1_accepted=false))
end

abspath(PROGRAM_FILE)==(@__FILE__) && rc_run()
