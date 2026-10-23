# Serial campaign driver; only runs when explicitly executed.
include("s2_arpae500_loadability.jl")

function el_run_confirmed()
    el_protocol("User explicitly confirmed all 131 taps and 11 continuous shunts at previous bounds, corrective per demand/outage, no added movement budget; 51 slopes and references shared. Confirmed N-1 voltage extension 0.05 pu and 110% Rate A study thermal caps. DR limited to 1% of each load; up to 10 MW total shedding only as last resort, combined per-load relief cap 10%, proportional Q reduction. No physical remedies.")
    x=el_context();events=filter(e->e.id in (:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    seed=el_read_point(joinpath(EL_OUT,"strict/continuation-1.09-retry"))
    rows=Any[];best=el_read_point(joinpath(EL_OUT,"strict/continuation-1.075"))
    for f in (1.09,1.095,1.0975)
        name="strict/refined-$f"
        lane=el_solve(x,name,(f,),events;seed,restore=f!=1.09,seconds=120.)
        ck=el_audit(lane.folder)
        push!(rows,(;factor=f,accepted=ck["accepted"],path=relpath(lane.folder,EL_OUT)))
        fd_save(joinpath(EL_OUT,"strict/refined-summary.json"),(;rows,scope="Three critical connected outages only"))
        if ck["accepted"];seed=lane.point;best=lane.point;else;break;end
    end
    seed=best
    lane=el_solve(x,"emergency/continuation-1.1",(1.1,),events;seed,emergency=true,relief=true,
        thermal_multiplier=1.1,reserve_start=true,seconds=180.)
    ck=el_audit(lane.folder)
    if !ck["accepted"]
        lane=el_solve(x,"emergency/continuation-1.1-retry",(1.1,),events;seed=lane.point,emergency=true,
            relief=true,thermal_multiplier=1.1,solver=:ipopt,seconds=180.)
        ck=el_audit(lane.folder)
    end
    fd_save(joinpath(EL_OUT,"emergency/pilot-summary.json"),(;accepted=ck["accepted"],path=relpath(lane.folder,EL_OUT)))
    ck["accepted"] && el_multidemand()
end

abspath(PROGRAM_FILE)==(@__FILE__) && el_run_confirmed()
