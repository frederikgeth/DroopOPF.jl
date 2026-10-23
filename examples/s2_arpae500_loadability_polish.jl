include("s2_arpae500_loadability_refine.jl")

function el_polish_confirmed()
    x=el_context();events=filter(e->e.id in (:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    seed=el_read_point(joinpath(EL_OUT,"emergency/continuation-1.1-retry"))
    lane=el_solve(x,"emergency/polish-1.1",(1.1,),events;seed,restore=false,emergency=true,relief=true,
        thermal_multiplier=1.1,solver=:ipopt,seconds=180.)
    ck=el_audit(lane.folder)
    if ck["accepted"]
        el_multidemand(;seed_directory=lane.folder)
    end
    el_refine_confirmed()
end

abspath(PROGRAM_FILE)==(@__FILE__) && el_polish_confirmed()
