include("s2_arpae500_loadability.jl")

function el_refine_confirmed()
    x=el_context();events=filter(e->e.id in (:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    seed=el_read_point(joinpath(EL_OUT,"strict/continuation-1.09-retry"));rows=Any[];best_folder=nothing
    for f in (1.09,1.095,1.0975)
        lane=el_solve(x,"strict/feasibility-$f",(f,),events;seed,restore=f!=1.09,
            feasibility_only=true,solver=:ipopt,seconds=90.)
        ck=el_audit(lane.folder)
        push!(rows,(;factor=f,accepted=ck["accepted"],path=relpath(lane.folder,EL_OUT)))
        fd_save(joinpath(EL_OUT,"strict/feasibility-summary.json"),(;rows,scope="Feasibility-first critical-outage continuation; no loss-optimality claim"))
        ck["accepted"] || break
        seed=lane.point;best_folder=lane.folder
    end
    isnothing(best_folder) || el_strict_scan(best_folder)
end

abspath(PROGRAM_FILE)==(@__FILE__) && el_refine_confirmed()
