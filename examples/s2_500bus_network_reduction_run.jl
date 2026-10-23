include("s2_500bus_network_reduction.jl")

function nr_initial(x)
    controller=read_study(joinpath(EL_OUT,"decomposition/shared-controller.json"))
    states=Dict()
    for r in JSON.parsefile(joinpath(EL_OUT,"decomposition/shared-states.json"))
        states[(Float64(r["factor"]),Symbol(r["id"]))]=(;state=a500_state(r["state"]),
            taps=a500_settings(r["taps"]),banks=a500_settings(r["banks"]),dr=a500_settings(r["dr"]),shed=a500_settings(r["shed"]))
    end
    for id in (:branch_36,:branch_562)
        nominal=read_scopf_result(joinpath(S2500_QUAL,"expanded-madnlp-reserve/round-1/demand-1.0",string(id),"result.json"))
        s=nominal.states[id]
        states[(1.1,id)]=(;state=ACState(copy(s.vm),copy(s.va),s.pg.*1.1,copy(s.qg)),
            taps=nominal.tap_settings[id],banks=nominal.shunt_settings[id],
            dr=Dict(l.id=>0. for l in controller.case.loads),shed=Dict(l.id=>0. for l in controller.case.loads))
    end
    (;study=controller,states)
end

function nr_run()
    x=el_context();mkpath(NR_OUT)
    fd_save(joinpath(NR_OUT,"protocol.json"),(;
        authorization="User requested use of network reduction after the proposed corrective tap/shunt configuration question; retain proposed controls and all confirmed absolute bounds, no added movement budget.",
        tap_controls=x.study.tap_controls,shunt_controls=x.study.shunt_controls,control_policy=x.study.control_policy,
        emergency_voltage_extension=.05,emergency_thermal_multiplier=1.1,dr_fraction=.01,shedding_mw=10.,
        combined_relief_fraction=.1,full_network_validation_required=true,
        rating_policy="Every original branch, both ends; reconstructed original voltages. No equivalent-line rating relaxation.",
        proof_scope="Exact zero-injection elimination does not change physical feasibility. Local time limits are inconclusive."))
    events=filter(e->e.id in (:branch_36,:branch_562,:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    known=el_read_point(joinpath(EL_OUT,"dispatch-recovery/demand-1.05/zero-shedding");stage="feasibility")
    rows=Any[]
    folder=joinpath(NR_OUT,"regression-1.05")
    regression=if isfile(joinpath(folder,"network-audit-feasibility.json"))
        (;folder,point=el_read_point(folder;stage="feasibility"))
    else
        nr_solve(x,"regression-1.05",(1.05,),events;seed=known,fixed_controller=true,
            emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
            feasibility_only=true,solver=:madnlp,seconds=60.)
    end
    good=nr_select_accepted(regression.folder)
    push!(rows,(;name="regression-1.05",accepted=!isnothing(good),factor=1.05))
    fd_save(joinpath(NR_OUT,"summary.json"),(;rows,exhaustive_qualified=false))
    if isnothing(good)
        ck=JSON.parsefile(joinpath(folder,"network-audit-feasibility.json"))
        ck["original_full_network_valid"] && ck["reduction_valid"] || error("Reduction physics regression failed")
        retry=nr_solve(x,"regression-1.05-ipopt",(1.05,),events;seed=regression.point,fixed_controller=true,
            emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
            feasibility_only=true,solver=:ipopt,seconds=90.)
        good=nr_select_accepted(retry.folder)
        push!(rows,(;name="regression-1.05-ipopt",accepted=!isnothing(good),factor=1.05))
        fd_save(joinpath(NR_OUT,"summary.json"),(;rows,exhaustive_qualified=false))
    end
    seed=nr_initial(x)
    for solver in (:madnlp,:ipopt)
        lane=nr_solve(x,"recovery-1.1-$solver",(1.1,),events;seed,fixed_controller=true,
            emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
            feasibility_only=true,solver,seconds=90.)
        selected=nr_select_accepted(lane.folder)
        push!(rows,(;name="recovery-1.1-$solver",accepted=!isnothing(selected),factor=1.1))
        fd_save(joinpath(NR_OUT,"summary.json"),(;rows,exhaustive_qualified=false))
        if !isnothing(selected)
            penalty=nr_solve(x,"recovery-1.1-$solver-penalty",(1.1,),events;seed=selected.point,fixed_controller=true,
                emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
                separator=true,solver,seconds=90.)
            break
        end
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && nr_run()
