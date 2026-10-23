# Independent-demand emergency-policy designs; no import-time optimization.
include("s2_500bus_network_reduction.jl")
const TE_OUT=joinpath(S2500_OUT,"targeted_demand_diagnostics")
const TE_SOURCE=read(@__FILE__,String)

function te_normal_seed()
    folder=joinpath(S2500_OUT,"solver_demand_qualification/ipopt-10500-continuation/round-1/attempt-1")
    study=read_study(joinpath(folder,"controller.json"));r=read_scopf_result(joinpath(folder,"result-1.05.json"))
    states=Dict((1.05,id)=>(;state=s,taps=r.tap_settings[id],banks=r.shunt_settings[id],
        dr=Dict(l.id=>0. for l in study.case.loads),shed=Dict(l.id=>0. for l in study.case.loads),
        delta=get(r.balancing_power,id,nothing)) for(id,s) in r.states if !isnothing(s))
    (;study,states)
end

function te_attempt(x,name,f,events,seed;solver=:madnlp,normalized=false,polish=false)
    prefix="../targeted_demand_diagnostics/"*name;folder=joinpath(EL_OUT,prefix)
    ispath(folder) && error("Preserve previous attempt: $folder")
    lane=nr_solve(x,prefix,(f,),events;output_relative="",seed,
        emergency=true,relief=true,thermal_multiplier=1.1,fixed_controller=false,fixed_base=false,
        restore=false,feasibility_only=!polish,penalty_proxies=polish,
        droop_normalization=normalized,solver,seconds=120.,response_relaxation_cap=0.,
        optimizer_options=solver==:ipopt ? Dict("hessian_approximation"=>"limited-memory") : Dict{String,Any}())
    write(joinpath(folder,"executed_targeted_driver.jl"),TE_SOURCE)
    selected=nr_select_accepted(folder)
    (;lane,selected,folder)
end

function te_run(f)
    confirmation=strip(get(ENV,"TD_CONTROL_CONFIRMATION",""));isempty(confirmation) && error("Equipment confirmation required")
    @assert f in (1.05,1.1)
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    x=el_context();label="emergency-$(round(Int,f*10000))"
    summary=joinpath(TE_OUT,"summary-$label.json");isfile(summary) && error("Preserve previous campaign")
    seed=f==1.05 ? te_normal_seed() : el_read_point(joinpath(EL_OUT,"emergency/zero-shedding-1.1");stage="dr")
    events=eligible_contingencies(contingency_catalog(x.study.case))
    working=Set((:branch_36,:branch_219,:branch_562,:generator_14,:generator_60))
    mkpath(TE_OUT);fd_save(joinpath(TE_OUT,"protocol-$label.json"),(;confirmation,factor=f,
        taps=x.study.tap_controls,shunts=x.study.shunt_controls,policy=x.study.control_policy,
        free_shared_droop_variables=102,exact_active_response=true,base_normal_full_load=true,
        contingency_voltage_extension=.05,thermal_multiplier=1.1,dr_fraction=.01,
        shedding_mw=10.,combined_load_relief_fraction=.1,additional_movement_budget=nothing,
        maximum_rounds=2,maximum_feasibility_attempts_per_round=2,seconds_per_stage=120.,
        maximum_master_native_calls=12,scan_failure_stop=4,physical_remedies=false))
    rounds=Any[];qualified=false;selected_path=nothing;selected_stage=nothing;optimal_stage=false
    for round in 1:2
        master=filter(e->e.id in working,events);attempts=Any[];chosen=nothing
        anchor=seed
        for (i,solver) in enumerate((:madnlp,:ipopt))
            run=te_attempt(x,"$label-round-$round-attempt-$i",f,master,seed;solver,normalized=true)
            push!(attempts,(;path=relpath(run.folder,S2500_OUT),solver,accepted=!isnothing(run.selected)))
            if !isnothing(run.selected);chosen=run;break;end
            seed=isnothing(run.lane.point) ? anchor : run.lane.point
        end
        scan=nothing
        if !isnothing(chosen)
            seed=chosen.selected.point;selected_path=relpath(chosen.folder,S2500_OUT);selected_stage=chosen.selected.stage
            # Preserve the feasibility witness even if a later priority fails.
            polish=te_attempt(x,"$label-round-$round-polish",f,master,seed;normalized=true,polish=true)
            if !isnothing(polish.selected)
                seed=polish.selected.point;selected_path=relpath(polish.folder,S2500_OUT);selected_stage=polish.selected.stage
                optimal_stage=selected_stage=="loss"
            end
            scan=el_emergency_scan(seed,(f,);label="targeted-$label-round-$round",max_failures=4,
                seconds=12.,reuse_master=false)
            qualified=scan.accepted
        end
        push!(rounds,(;round,attempts,selected_path,selected_stage,optimal_stage,
            working=sort(collect(working);by=string),coverage=isnothing(scan) ? nothing :
            (;accepted=scan.accepted,failed=scan.failed,evaluated=sum(length(r.rows) for r in scan.rows),
                exhaustive=all(r.exhaustive for r in scan.rows))))
        fd_save(summary,(;factor=f,qualified,selected_path,selected_stage,optimal_stage,rounds,
            multi_demand=false,full_n1_accepted=false))
        qualified && break
        isnothing(scan) && break
        old=length(working);union!(working,scan.failed);length(working)>old || break
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && te_run(parse(Float64,only(ARGS)))
