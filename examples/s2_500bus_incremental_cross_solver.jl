# Same final loss NLP as Ipopt, with all shared droops and corrective controls free.
include("s2_500bus_incremental_shared.jl")
const RC_SOURCE=read(@__FILE__,String)
function rc_madnlp()
    rx_protocol()
    reference=joinpath(RX_OUT,"joint-ipopt-3d-cap-priorities-loss-p1")
    contract=JSON.parsefile(joinpath(reference,"contract.json"))
    budgets=Dict{Symbol,Float64}(Symbol(k)=>v for(k,v) in contract["budgets"])
    seed=el_read_point(joinpath(RX_OUT,"joint-ipopt-3d-cap-priorities-emergency-p1");stage="emergency")
    prior=JSON.parsefile(joinpath(RX_OUT,"summary-joint-madnlp-3d.json"))
    fd_save(joinpath(RX_OUT,"cross-solver-priority-contract.json"),(;source=relpath(reference,S2500_OUT),budgets,
        meaning="Identical Ipopt final-loss constraints and priority bounds; MadNLP still optimizes all 102 droop parameters and all corrective hardware independently"))
    selected=nothing;accepted=false
    for profile in 1:2
        # Prefer a validated Ipopt loss point once available; otherwise use its accepted emergency point.
        if isfile(joinpath(reference,"summary.json")) && JSON.parsefile(joinpath(reference,"summary.json"))["accepted"]
            seed=el_read_point(reference;stage="loss")
        end
        run=fm_attempt("joint-madnlp-3d-cross-loss-p$profile",:loss,(.9,.95,1.),seed,rx_events(FM_EVENTS);
            solver=:madnlp,budgets,retry=true,seconds=240.,optimizer_options=rx_options(:madnlp,profile),
            check_start=profile==1,output_root=RX_OUT,direct_relief=true,implied_q_bounds=true,objective_scale=100.,native_call_limit=64)
        write(joinpath(run.folder,"executed_cross_solver_driver.jl"),RC_SOURCE);push!(prior["rows"],run.summary)
        if run.accepted
            selected=(;path=relpath(run.folder,S2500_OUT),stage=:loss);seed=run.point;accepted=true;break
        end
        audit=JSON.parsefile(joinpath(run.folder,"audit-loss.json"))
        audit["physical_valid"] && !isnothing(run.point) && (seed=run.point)
    end
    if accepted
        prior["selected"]=selected;prior["complete"]=true;prior["loss_objective_completed"]=true
        prior["budgets"]=budgets;prior["priority_budget_source"]=relpath(reference,S2500_OUT)
        prior["emergency_priority_backend"]="ipopt"
    end
    fd_save(joinpath(RX_OUT,"summary-joint-madnlp-3d.json"),prior)
    fd_save(joinpath(RX_OUT,"summary-joint-madnlp.json"),(;rows=[prior],full_n1_accepted=false))
    if accepted
        scan=rx_scan(seed,selected,(.9,.95,1.),"incremental-madnlp-3d-cross")
        fd_save(joinpath(RX_OUT,"summary-joint-madnlp-cross-coverage.json"),(;accepted=scan.accepted,failed=scan.failed))
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && rc_madnlp()
