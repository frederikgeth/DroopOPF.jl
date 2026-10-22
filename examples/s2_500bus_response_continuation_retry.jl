# Bounded alternate-solver exact-policy retries after the primary sequence.
include("s2_500bus_response_continuation.jl")
function rc_retry()
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    summary=JSON.parsefile(joinpath(RC_OUT,"summary.json"))
    summary["target_recovered"] && return
    isnothing(summary["failed_factor"]) && return
    append!(RC_ROWS,summary["attempts"])
    write(joinpath(RC_OUT,"executed_retry_driver.jl"),read(@__FILE__,String))
    protocol=JSON.parsefile(joinpath(RC_OUT,"protocol.json"))
    protocol["alternate_retry_scope"]="Same campaign, controls, physics and retained controller: two exact Ipopt starts and at most six additional halving/restoration rounds; the total maximum remains 36 native calls."
    fd_save(joinpath(RC_OUT,"protocol.json"),protocol)
    x=el_context()
    events=filter(e->e.id in (:branch_36,:branch_219,:branch_562,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    selected=JSON.parsefile(joinpath(RC_OUT,"selected-exact.json"))
    seed=el_read_point(joinpath(RC_OUT,selected["name"]);stage=selected["stage"])
    f=summary["failed_factor"]
    run=rc_solve(x,"alternate-exact-ipopt",f,events;seed,zero_shedding=false,solver=:ipopt,seconds=120.)
    if !isnothing(run) && !run.row.accepted
        diag=filter(r->r["diagnostic_accepted"],summary["attempts"])
        if !isempty(diag)
            sort!(diag;by=r->(r["cap"],r["max_response_mw"]))
            d=first(diag)
            seed=el_read_point(joinpath(RC_OUT,d["name"]);stage=d["stage"])
            rho=d["cap"]
            # Continue the primary three rounds until a tighter cap stalls,
            # while reserving one call for alternate-solver exact restoration.
            for round in 1:6
                length(RC_ROWS)+2<RC_MAX_ATTEMPTS || break
                rho/=2
                tight=rc_solve(x,"extended-response-cap-$round",f,events;seed,cap=rho,
                    zero_shedding=false,response_objective=true,seconds=120.)
                isnothing(tight) && break
                tight.row.diagnostic_accepted || break
                seed=tight.point
                run=rc_solve(x,"extended-exact-restore-$round",f,events;seed,
                    zero_shedding=false,seconds=90.)
                isnothing(run) && break
                run.row.accepted && break
            end
            if isnothing(run) || !run.row.accepted
                run=rc_solve(x,"alternate-exact-ipopt-diagnostic-seed",f,events;seed,zero_shedding=false,solver=:ipopt,seconds=120.)
            end
        end
    end
    accepted=summary["accepted"];lower=summary["last_exact_factor"]
    while !isnothing(run) && run.row.accepted
        push!(accepted,run.row);lower=run.row.factor
        fd_save(joinpath(RC_OUT,"selected-exact.json"),(;factor=lower,name=run.row.name,stage=run.row.stage))
        lower>=1.1-1e-9 && break
        f=round(min(1.1,lower+.0025);digits=4)
        next=rc_solve(x,"alternate-demand-$(round(Int,f*10000))",f,events;seed=run.point,zero_shedding=false)
        isnothing(next) && break
        if !next.row.accepted
            next=rc_restore(x,f,events,next;tag="alternate-demand-$(round(Int,f*10000))")
        end
        run=next
    end
    fd_save(joinpath(RC_OUT,"summary.json"),(;accepted,attempts=RC_ROWS,last_exact_factor=lower,
        failed_factor=lower>=1.1-1e-9 ? nothing : f,target_recovered=lower>=1.1-1e-9,
        maximum_attempts=RC_MAX_ATTEMPTS,budget_reached=length(RC_ROWS)>=RC_MAX_ATTEMPTS,
        alternate_solver_retries=true,exhaustive_qualified=false,
        exact_feasible_boundary_determined=false,full_n1_accepted=false))
end
abspath(PROGRAM_FILE)==(@__FILE__) && rc_retry()
