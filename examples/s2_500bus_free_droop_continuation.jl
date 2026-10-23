# Free shared droop continuation with the exact original active-response rule.
include("s2_500bus_network_reduction.jl")
const FDC_OUT=joinpath(S2500_OUT,"free_droop_continuation")
const FDC_SOURCE=read(@__FILE__,String)
const FDC_ROWS=Any[]
const FDC_MAX_NATIVE=40

fdc_native_count()=sum(length(r.stages) for r in FDC_ROWS;init=0)
function fdc_solve(x,name,factors,events;seed,solver=:madnlp,seconds=180.,
    zero_shedding=false,polish=false,droop_normalization=false)
    allowance=polish ? (zero_shedding ? 3 : 4) : 1
    fdc_native_count()+allowance<=FDC_MAX_NATIVE || return nothing
    name*= "-r"*lpad(string(length(FDC_ROWS)+1),2,'0')
    folder=joinpath(FDC_OUT,name)
    ispath(folder) && error("Preserve existing campaign records; output already exists: $folder")
    mkpath(folder);write(joinpath(folder,"executed_driver.jl"),FDC_SOURCE)
    lane=nr_solve(x,name,factors,events;output_relative="../free_droop_continuation/",seed,
        fixed_controller=false,fixed_base=false,emergency=true,relief=true,thermal_multiplier=1.1,
        restore=false,zero_shedding,feasibility_only=!polish,penalty_proxies=polish,
        response_relaxation_cap=0.,droop_normalization,solver,seconds)
    stages=JSON.parsefile(joinpath(folder,"stages.json"))
    accepted_stages=String[]
    for stage in stages
        file=joinpath(folder,"network-audit-$(stage["stage"]).json")
        isfile(file) && JSON.parsefile(file)["accepted"] && push!(accepted_stages,stage["stage"])
    end
    stage=isempty(accepted_stages) ? nothing : last(accepted_stages)
    accepted=!isnothing(stage)
    point=accepted ? el_read_point(folder;stage) : lane.point
    row=(;name,factors,solver,zero_shedding,polish,droop_normalization,stages,accepted,selected_stage=stage,
        accepted_stages,free_shared_controller=true,exact_active_response=true,
        outage_ids=[e.id for e in events])
    push!(FDC_ROWS,row)
    fd_save(joinpath(FDC_OUT,"progress.json"),(;rows=FDC_ROWS,native_solves=fdc_native_count(),
        maximum_native_solves=FDC_MAX_NATIVE,full_n1_accepted=false))
    println("FREE DROOP CONTINUATION CHECK ",row);flush(stdout)
    (;row,point,folder)
end

function fdc_target(x,f,events,seed;droop_normalization=false)
    # First retain the full confirmed relief budget, then minimize relief in
    # the separate staged polish. A constant feasibility point is not optimal.
    run=fdc_solve(x,"demand-$(round(Int,f*10000))",(f,),events;seed,droop_normalization)
    isnothing(run) && return nothing
    run.row.accepted && return run
    retry=fdc_solve(x,"demand-$(round(Int,f*10000))-ipopt",(f,),events;
        seed=run.point,solver=:ipopt,droop_normalization)
    isnothing(retry) && return nothing
    retry.row.accepted && return retry
    # A distinct, accepted nearby start avoids relying solely on a failed iterate.
    final=fdc_solve(x,"demand-$(round(Int,f*10000))-accepted-start",(f,),events;
        seed,seconds=240.,droop_normalization)
    isnothing(final) || final.row.accepted || return nothing
    final
end

function fdc_run()
    confirmation=strip(get(ENV,"FDC_CONTROL_CONFIRMATION",""))
    isempty(confirmation) && error("Fresh user confirmation of this campaign's corrective tap/shunt configuration is required before optimization")
    isfile(joinpath(FDC_OUT,"protocol.json")) && error("Campaign exists; preserve the original records before reproduction")
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    x=el_context();mkpath(FDC_OUT)
    @assert length(x.study.tap_controls)==131 && length(x.study.shunt_controls)==11
    @assert all(t.lower==.95 && t.upper==1.05 for t in x.study.tap_controls)
    fd_save(joinpath(FDC_OUT,"protocol.json"),(;confirmation,
        tap_controls=x.study.tap_controls,shunt_controls=x.study.shunt_controls,control_policy=x.study.control_policy,
        selected_controls_corrective=true,continuous_shunts=true,additional_movement_budget=nothing,
        free_shared_slopes=51,free_shared_reference_voltages=51,
        normal_base_full_load=true,contingency_voltage_extension_pu=.05,
        contingency_rate_a_multiplier=1.1,dr_fraction=.01,shedding_mw=10.,combined_relief_fraction=.1,
        exact_active_response=true,artificial_injections=false,physical_remedies=false,
        initial_factor=1.0625,first_target=1.065,target_factor=1.1,step=.0025,
        maximum_native_master_solves=FDC_MAX_NATIVE,
        single_demand_curves_shared_across_outages=true,
        joint_five_demand_factors=(.9,.95,1.,1.05,1.1),
        acceptance="Native convergence, independent original 500-bus physical/policy checks and exact reduction reconstruction. No positive response relaxation.",
        qualification="Only after an accepted joint five-demand master; fixed per-demand base and shared controller, up to four failed connected events before stopping the scan. Unchecked events remain unqualified."))
    events=filter(e->e.id in (:branch_36,:branch_219,:branch_562,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    seed=el_read_point(joinpath(S2500_OUT,"response_continuation/demand-10625-a06");stage="feasibility")
    lower=1.0625;failed_factor=nothing;selected=nothing
    for f in 1.065:.0025:1.100001
        f=round(f;digits=4)
        run=fdc_target(x,f,events,seed)
        if isnothing(run)
            failed_factor=f;break
        end
        seed=run.point;selected=run;lower=f
        fd_save(joinpath(FDC_OUT,"selected-single-demand.json"),(;factor=f,name=run.row.name,stage=run.row.selected_stage))
    end
    # Retain the last accepted feasibility point even if objective polishing fails.
    polished=nothing
    if !isnothing(selected)
        polished=fdc_solve(x,"polish-$lower",(lower,),events;seed,polish=true)
        if !isnothing(polished) && polished.row.accepted
            seed=polished.point;selected=polished
            fd_save(joinpath(FDC_OUT,"selected-single-demand.json"),(;factor=lower,name=selected.row.name,stage=selected.row.selected_stage))
        end
    end
    joint=nothing;coverage=nothing
    if lower>=1.1-1e-9
        factors=(.9,.95,1.,1.05,1.1)
        joint=fdc_solve(x,"joint-five-demand",factors,events;seed,seconds=600.)
        if !isnothing(joint) && !joint.row.accepted
            joint=fdc_solve(x,"joint-five-demand-ipopt",factors,events;
                seed=joint.point,solver=:ipopt,seconds=600.)
        end
        if !isnothing(joint) && joint.row.accepted
            polished_joint=fdc_solve(x,"joint-five-demand-polish",factors,events;
                seed=joint.point,polish=true,seconds=600.)
            if !isnothing(polished_joint) && polished_joint.row.accepted
                joint=polished_joint
            end
            fd_save(joinpath(FDC_OUT,"selected-joint.json"),(;name=joint.row.name,stage=joint.row.selected_stage,factors))
            coverage=el_emergency_scan(joint.point,factors;label="free-droop-continuation",
                max_failures=4,seconds=15.,reuse_master=false)
        end
    end
    fd_save(joinpath(FDC_OUT,"summary.json"),(;rows=FDC_ROWS,last_single_demand_factor=lower,
        failed_factor,target_110_recovered=lower>=1.1-1e-9,
        shared_five_demand_accepted=!isnothing(joint) && joint.row.accepted,
        exhaustive_connected_qualified=!isnothing(coverage) && coverage.accepted,
        native_master_solves=fdc_native_count(),maximum_native_master_solves=FDC_MAX_NATIVE,
        exact_feasible_boundary_determined=false,full_n1_accepted=false,
        constant_objective_is_not_optimal_design=true,physical_remedies=false))
end
abspath(PROGRAM_FILE)==(@__FILE__) && fdc_run()
