include("s2_500bus_network_reduction_run.jl")

function nr_compact()
    x=el_context()
    events=filter(e->e.id in (:branch_36,:branch_562,:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    known=el_read_point(joinpath(EL_OUT,"dispatch-recovery/demand-1.05/zero-shedding");stage="feasibility")
    first=nr_solve(x,"compact-regression-1.05",(1.05,),events;seed=known,fixed_controller=true,
        emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
        feasibility_only=true,penalty_proxies=false,solver=:madnlp,seconds=60.)
    seed=nr_initial(x)
    rows=Any[]
    # Identical original physical starts and native budgets. Removing unused
    # penalty proxies is common to both models, and cannot relax physical caps.
    for reduced in (true,false)
        name=reduced ? "compact-recovery-1.1" : "full-compact-recovery-1.1"
        lane=if reduced
            nr_solve(x,name,(1.1,),events;seed,fixed_controller=true,
                emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
                feasibility_only=true,penalty_proxies=false,solver=:madnlp,seconds=90.)
        else
            el_solve(x,"../network_reduction/"*name,(1.1,),events;seed,fixed_controller=true,
                emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
                feasibility_only=true,penalty_proxies=false,solver=:madnlp,seconds=90.)
        end
        reduced || el_audit(lane.folder)
        selected=reduced ? nr_select_accepted(lane.folder) : el_select_accepted(lane.folder)
        push!(rows,(;name,reduced,accepted=!isnothing(selected),native_seconds=90.))
        fd_save(joinpath(NR_OUT,"compact-comparison.json"),(;rows,identical_physical_seed_recipe=true,
            no_unused_departure_proxies=true,hard_emergency_caps_retained=true,exhaustive_qualified=false))
    end
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    for f in (1.05,1.1)
        partial=nr_solve(x,"partial-compact-$f",(f,),events;seed=f==1.05 ? known : seed,fixed_controller=true,
            emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
            feasibility_only=true,penalty_proxies=false,solver=:madnlp,seconds=f==1.05 ? 60. : 90.)
        selected=nr_select_accepted(partial.folder)
        push!(rows,(;name="partial-compact-$f",reduced=true,accepted=!isnothing(selected),native_seconds=f==1.05 ? 60. : 90.))
        fd_save(joinpath(NR_OUT,"compact-comparison.json"),(;rows,identical_physical_seed_recipe=true,
            no_unused_departure_proxies=true,hard_emergency_caps_retained=true,exhaustive_qualified=false))
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && nr_compact()
