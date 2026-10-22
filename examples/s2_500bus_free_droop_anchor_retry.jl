# Same confirmed campaign: free-droop anchor polishing and equivalent scaling.
include("s2_500bus_free_droop_continuation.jl")
function fdc_anchor_retry()
    summary=JSON.parsefile(joinpath(FDC_OUT,"summary.json"))
    summary["shared_five_demand_accepted"] && return
    check=JSON.parsefile(joinpath(FDC_OUT,"scaling_checks.json"))
    @assert check["passed"] && check["optimizer_calls"]==0
    confirmation=JSON.parsefile(joinpath(FDC_OUT,"protocol.json"))
    @assert !isempty(strip(confirmation["confirmation"]))
    confirmation["anchor_recovery"]="Within the same confirmed controls/bounds and 40-native-master-stage budget: normalized free droop coordinates, accepted-demand anchor and staged anchor polishing, then exact-response continuation. A previously physically valid response-relaxed point may be a numerical start only; all new models enforce zero relaxation. No physical remedy."
    fd_save(joinpath(FDC_OUT,"protocol.json"),confirmation)
    write(joinpath(FDC_OUT,"executed_anchor_retry.jl"),read(@__FILE__,String))
    append!(FDC_ROWS,[(; (Symbol(k)=>v for (k,v) in r)...) for r in summary["rows"]])
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    x=el_context()
    events=filter(e->e.id in (:branch_36,:branch_219,:branch_562,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    lower=summary["last_single_demand_factor"]
    selected_file=joinpath(FDC_OUT,"selected-single-demand.json")
    if isfile(selected_file)
        s=JSON.parsefile(selected_file)
        seed=el_read_point(joinpath(FDC_OUT,s["name"]);stage=s["stage"])
    else
        seed=el_read_point(joinpath(S2500_OUT,"response_continuation/demand-10625-a06");stage="feasibility")
    end
    anchor=fdc_solve(x,"normalized-anchor-$lower",(lower,),events;seed,droop_normalization=true)
    if !isnothing(anchor) && anchor.row.accepted
        seed=anchor.point
        fd_save(selected_file,(;factor=lower,name=anchor.row.name,stage=anchor.row.selected_stage))
        polish=fdc_solve(x,"normalized-anchor-polish-$lower",(lower,),events;
            seed,droop_normalization=true,polish=true)
        if !isnothing(polish) && polish.row.accepted
            seed=polish.point
            fd_save(selected_file,(;factor=lower,name=polish.row.name,stage=polish.row.selected_stage))
        end
    end
    # Also try the scaled target directly when anchor stationarity stalls.
    failed_factor=summary["failed_factor"];selected=nothing
    for f in round(lower+.0025;digits=4):.0025:1.100001
        f=round(f;digits=4)
        run=fdc_target(x,f,events,seed;droop_normalization=true)
        if isnothing(run) && f==1.065
            path=joinpath(S2500_OUT,"response_continuation/extended-response-cap-4-a25")
            old_audit=JSON.parsefile(joinpath(path,"audit-feasibility.json"))
            old_map=JSON.parsefile(joinpath(path,"network-audit-feasibility.json"))
            @assert old_audit["response_free_physical_valid"] && old_map["reduction_valid"]
            # The old point has policy deviations, but no artificial injections.
            # It is never accepted here: a fresh exact/free model must converge.
            diagnostic=el_read_point(path;stage="feasibility")
            trial=fdc_solve(x,"normalized-closest-physical-start",(f,),events;
                seed=diagnostic,droop_normalization=true)
            if !isnothing(trial) && !trial.row.accepted
                trial=fdc_solve(x,"normalized-closest-physical-start-ipopt",(f,),events;
                    seed=diagnostic,droop_normalization=true,solver=:ipopt)
            end
            !isnothing(trial) && trial.row.accepted && (run=trial)
        end
        if isnothing(run);failed_factor=f;break;end
        seed=run.point;selected=run;lower=f;failed_factor=nothing
        fd_save(selected_file,(;factor=f,name=run.row.name,stage=run.row.selected_stage))
    end
    if !isnothing(selected)
        polish=fdc_solve(x,"normalized-target-polish-$lower",(lower,),events;
            seed,droop_normalization=true,polish=true)
        if !isnothing(polish) && polish.row.accepted
            seed=polish.point
            fd_save(selected_file,(;factor=lower,name=polish.row.name,stage=polish.row.selected_stage))
        end
    end
    joint=nothing;coverage=nothing
    if lower>=1.1-1e-9
        factors=(.9,.95,1.,1.05,1.1)
        joint=fdc_solve(x,"normalized-joint-five-demand",factors,events;
            seed,droop_normalization=true,seconds=600.)
        if !isnothing(joint) && !joint.row.accepted
            joint=fdc_solve(x,"normalized-joint-five-demand-ipopt",factors,events;
                seed=joint.point,droop_normalization=true,solver=:ipopt,seconds=600.)
        end
        if !isnothing(joint) && joint.row.accepted
            polish=fdc_solve(x,"normalized-joint-polish",factors,events;
                seed=joint.point,droop_normalization=true,polish=true,seconds=600.)
            if !isnothing(polish) && polish.row.accepted;joint=polish;end
            fd_save(joinpath(FDC_OUT,"selected-joint.json"),(;name=joint.row.name,stage=joint.row.selected_stage,factors))
            coverage=el_emergency_scan(joint.point,factors;label="free-droop-continuation-normalized",
                max_failures=4,seconds=15.,reuse_master=false)
        end
    end
    fd_save(joinpath(FDC_OUT,"summary.json"),(;rows=FDC_ROWS,last_single_demand_factor=lower,
        failed_factor,target_110_recovered=lower>=1.1-1e-9,
        shared_five_demand_accepted=!isnothing(joint) && joint.row.accepted,
        exhaustive_connected_qualified=!isnothing(coverage) && coverage.accepted,
        native_master_solves=fdc_native_count(),maximum_native_master_solves=FDC_MAX_NATIVE,
        exact_feasible_boundary_determined=false,full_n1_accepted=false,
        anchor_recovery_attempted=true,constant_objective_is_not_optimal_design=true,physical_remedies=false))
end
abspath(PROGRAM_FILE)==(@__FILE__) && fdc_anchor_retry()
