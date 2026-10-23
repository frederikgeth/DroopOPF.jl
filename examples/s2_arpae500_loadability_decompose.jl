# Demand decomposition preserves exactly one controller, with independent
# preventive Pg and corrective equipment states at each demand.
include("s2_arpae500_loadability.jl")

function el_decompose_confirmed()
    x=el_context();events=filter(e->e.id in (:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    nominal_states=Dict((1.,id)=>(;state=s,taps=x.result.tap_settings[id],banks=x.result.shunt_settings[id],
        dr=Dict(l.id=>0. for l in x.study.case.loads),shed=Dict(l.id=>0. for l in x.study.case.loads)) for (id,s) in x.result.states)
    seed=(;study=x.study,states=nominal_states)
    lane=el_solve(x,"decomposition/nominal-controller-1.1",(1.1,),events;seed,emergency=true,relief=true,
        thermal_multiplier=1.1,zero_shedding=true,fixed_controller=true,solver=:ipopt,seconds=180.)
    chosen=el_select_accepted(lane.folder)
    nominal_controller=!isnothing(chosen)
    if isnothing(chosen)
        seed=el_read_point(joinpath(EL_OUT,"emergency/polish-1.1"))
        lane=el_solve(x,"emergency/zero-shedding-1.1",(1.1,),events;seed,emergency=true,relief=true,
            thermal_multiplier=1.1,zero_shedding=true,restore=false,solver=:ipopt,seconds=180.)
        chosen=el_select_accepted(lane.folder)
        if isnothing(chosen)
            chosen=el_select_accepted(joinpath(EL_OUT,"emergency/polish-1.1"))
        end
    end
    isnothing(chosen) && error("No accepted emergency seed")
    seed=chosen.point;controller=seed.study;combined=copy(seed.states)
    nominal_controller && merge!(combined,nominal_states)
    firstfolder=isfile(joinpath(lane.folder,"selected_feasible_stage.json")) ? lane.folder : joinpath(EL_OUT,"emergency/polish-1.1")
    rows=Any[(;factor=1.1,path=relpath(firstfolder,EL_OUT),stage=chosen.stage,accepted=true)]
    for f in (1.,1.05,.95,.9)
        lane=el_solve(x,"decomposition/demand-$f",(f,),events;seed=(;study=controller,states=combined),
            emergency=true,relief=true,thermal_multiplier=1.1,zero_shedding=true,zero_dr=true,
            fixed_controller=true,fixed_base=nominal_controller && f==1.,solver=:ipopt,seconds=120.)
        chosen=el_select_accepted(lane.folder)
        if isnothing(chosen)
            lane=el_solve(x,"decomposition/demand-$f-retry",(f,),events;seed=lane.point,
                emergency=true,relief=true,thermal_multiplier=1.1,fixed_controller=true,solver=:madnlp,seconds=180.)
            chosen=el_select_accepted(lane.folder)
        end
        push!(rows,(;factor=f,path=relpath(lane.folder,EL_OUT),stage=isnothing(chosen) ? nothing : chosen.stage,accepted=!isnothing(chosen)))
        fd_save(joinpath(EL_OUT,"decomposition/summary.json"),(;rows,accepted=length(rows)==5 && all(r.accepted for r in rows),
            controller_fixed_across_demands=true,nominal_controller_reused=nominal_controller,
            shared_controller_training_objective=nominal_controller ? "Nominal-qualified design reused; no joint multi-demand optimality claim" : "Designed at 110%; no joint multi-demand optimality claim",
            critical_outages=[e.id for e in events],exhaustive_connected_qualified=false,full_n1_accepted=false))
        isnothing(chosen) && break
        @assert DroopOPF._json_data(controller.case.controls)==DroopOPF._json_data(chosen.point.study.case.controls)
        merge!(combined,chosen.point.states)
    end
    write_study(joinpath(EL_OUT,"decomposition/shared-controller.json"),controller)
    fd_save(joinpath(EL_OUT,"decomposition/shared-states.json"),
        [(;factor=f,id,state=s.state,taps=s.taps,banks=s.banks,dr=s.dr,shed=s.shed) for ((f,id),s) in combined])
    if length(rows)==5 && all(r.accepted for r in rows)
        point=(;study=controller,states=combined)
        el_emergency_scan(point,(1.1,1.05,1.,.95,.9);label="decomposed-five-demand")
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && el_decompose_confirmed()
