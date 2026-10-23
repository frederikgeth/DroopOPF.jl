include("s2_500bus_network_reduction_run.jl")

function nr_refine()
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    x=el_context();events=filter(e->e.id in (:branch_36,:branch_562,:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    known=el_read_point(joinpath(EL_OUT,"dispatch-recovery/demand-1.05/zero-shedding");stage="feasibility")
    nr_solve(x,"refined-regression-1.05",(1.05,),events;seed=known,fixed_controller=true,
        emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
        feasibility_only=true,penalty_proxies=false,solver=:madnlp,seconds=60.)
    seed=nr_initial(x)
    lane=nr_solve(x,"refined-fixed-1.1",(1.1,),events;seed,fixed_controller=true,
        emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
        feasibility_only=true,penalty_proxies=false,solver=:madnlp,seconds=90.)
    selected=nr_select_accepted(lane.folder)
    full=el_solve(x,"../network_reduction/full-refined-fixed-1.1",(1.1,),events;seed,fixed_controller=true,
        emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
        feasibility_only=true,penalty_proxies=false,solver=:madnlp,seconds=90.)
    el_audit(full.folder)
    if isnothing(selected)
        # Last bounded shared-design retry: do not mistake a fixed controller
        # restriction for the full, confirmed free shared droop design problem.
        nr_solve(x,"refined-free-last-resort-1.1",(1.1,),events;seed,fixed_controller=false,
            emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=false,
            feasibility_only=true,penalty_proxies=false,solver=:madnlp,seconds=90.)
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && nr_refine()
