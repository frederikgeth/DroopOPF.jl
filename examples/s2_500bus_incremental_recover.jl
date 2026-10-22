# Bounded equivalent-bound cleanup and near-point restarts within the confirmed campaign.
include("s2_500bus_incremental_shared.jl")
function rr_joint(solver)
    path=joinpath(RX_OUT,"summary-joint-$solver-3d.json");prior=JSON.parsefile(path)
    !isnothing(prior["selected"]) && return # Never overwrite an accepted existing chain.
    run=fm_attempt("joint-$solver-3d-cap-feasibility",:feasibility,(.9,.95,1.),rx_common_seed(),rx_events(FM_EVENTS);
        solver,seconds=240.,retry=true,optimizer_options=rx_options(solver,2),check_start=true,output_root=RX_OUT,
        direct_relief=true,implied_q_bounds=true,native_call_limit=64)
    write(joinpath(run.folder,"executed_recovery_driver.jl"),read(@__FILE__,String))
    push!(prior["rows"],run.summary)
    if run.accepted
        tail=rx_pipeline("joint-$solver-3d-cap-priorities",(.9,.95,1.),run.point,rx_events(FM_EVENTS);solver,
            stages=(:shedding,:dr,:emergency,:loss),implied_q_bounds=true)
        append!(prior["rows"],tail.result.rows)
        prior["selected"]=isnothing(tail.result.selected) ? (;path=relpath(run.folder,S2500_OUT),stage=:feasibility) : tail.result.selected
        prior["complete"]=tail.result.complete;prior["loss_objective_completed"]=tail.result.loss_objective_completed
        prior["budgets"]=tail.result.budgets
        if tail.result.loss_objective_completed
            scan=rx_scan(tail.point,tail.result.selected,(.9,.95,1.),"incremental-$solver-3d-cap")
            prior["coverage_accepted"]=scan.accepted
        end
    end
    fd_save(path,prior)
    # Record the recovered gate in the lane summary even when no priority completes.
    fd_save(joinpath(RX_OUT,"summary-joint-$solver.json"),(;rows=[prior],full_n1_accepted=false))
end
function rr_105()
    seed=el_read_point(joinpath(RX_OUT,"expanded-105-r1-dr-p1");stage="dr")
    events=rx_events([FM_EVENTS...;RX_EXTRA...])
    run=rx_pipeline("expanded-105-cap-recovery",(1.05,),seed,events;
        zero_shedding=true,stages=(:dr,:emergency,:loss),implied_q_bounds=true)
    if run.result.loss_objective_completed
        scan=rx_scan(run.point,run.result.selected,(1.05,),"incremental-105-cap";zero_shedding=true)
        fd_save(joinpath(RX_OUT,"summary-expanded-105-cap.json"),(;master=run.result,coverage=(;accepted=scan.accepted,failed=scan.failed)))
    end
end
function rr_ccopt()
    seed=rx_cc_seed();events=rx_events(FM_EVENTS)
    folder=joinpath(RX_OUT,"witnesses/ccopt-100-complete-start");mkpath(folder)
    contract=JSON.parsefile(joinpath(RX_OUT,"ccopt-single-100-feasibility-p1/contract.json"))
    contract["fixed_controller"]=true;contract["initial_controller"]=DroopOPF._json_data(seed.study.case.controls)
    record=(;stage="derived",status="DERIVED_COMPLETE_START",native_success=false,native_optimizer_calls=0,artificial_max_pu=0.,artificial_net_max_pu=0.)
    rows=[(;factor=f,id,state=s.state,taps=s.taps,banks=s.banks,dr=s.dr,shed=s.shed,delta=s.delta,artificial_max_pu=0.) for((f,id),s) in seed.states if id in (:base,FM_EVENTS...)]
    fd_save(joinpath(folder,"contract.json"),contract);fd_save(joinpath(folder,"stages.json"),[record])
    fd_save(joinpath(folder,"point-derived.json"),(;record,states=rows));write_study(joinpath(folder,"controller-derived.json"),seed.study)
    python=get(ENV,"NR_PYTHON","/tmp/s214-plot-env/bin/python")
    read(`$python $(joinpath(FD_ROOT,"examples/audit_s2_500bus_loadability.py")) $folder derived`,String)
    @assert JSON.parsefile(joinpath(folder,"audit-derived.json"))["physical_valid"]
    prior=JSON.parsefile(joinpath(RX_OUT,"summary-ccopt-single-100.json"))
    selected=nothing;budgets=Dict{Symbol,Float64}();complete=true
    for stage in (:feasibility,:loss)
        run=fm_attempt("ccopt-100-complete-$stage",stage,(1.,),seed,events;solver=:ccopt,
            zero_shedding=true,zero_dr=true,seconds=180.,retry=false,optimizer_options=rx_options(:ccopt,2),
            output_root=RX_OUT,direct_relief=true,objective_scale=stage==:loss ? 100. : 1.,native_call_limit=64)
        write(joinpath(run.folder,"executed_recovery_driver.jl"),read(@__FILE__,String));push!(prior["rows"],run.summary)
        if !run.accepted;complete=false;break;end
        seed=run.point;selected=(;path=relpath(run.folder,S2500_OUT),stage)
    end
    prior["selected"]=selected;prior["complete"]=complete;prior["loss_objective_completed"]=complete
    fd_save(joinpath(RX_OUT,"summary-ccopt-single-100.json"),prior)
    complete && rx_scan(seed,selected,(1.,),"incremental-ccopt-100-complete";zero_shedding=true)
    rx_joint(:ccopt)
end
function rr_run(mode)
    rx_protocol()
    mode=="105" ? rr_105() : mode=="ccopt" ? rr_ccopt() : rr_joint(Symbol(mode))
end
abspath(PROGRAM_FILE)==(@__FILE__) && rr_run(only(ARGS))
