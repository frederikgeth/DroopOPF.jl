# Instrumented, bounded CCOpt attempt from the qualified nominal Ipopt design.
include("s2_500bus_scaled_mpcc.jl")
const TD_OUT=joinpath(S2500_OUT,"targeted_demand_diagnostics")

function td_snapshot(m,blocks,parameters,stage,out)
    has_values(m) || return
    finite(x)=x isa Real && isfinite(x) ? Float64(x) : nothing
    variables=[(;index=JuMP.index(v).value,name=JuMP.name(v),value=finite(value(v)),
        lower=has_lower_bound(v) ? finite(lower_bound(v)) : nothing,
        upper=has_upper_bound(v) ? finite(upper_bound(v)) : nothing) for v in all_variables(m)]
    fd_save(joinpath(out,"variables-$stage.json"),(;variables,status=string(termination_status(m))))
    constraints=Any[]
    for c in all_constraints(m;include_variable_in_set_constraints=true)
        d=try finite(dual(c)) catch; nothing end
        cname=try JuMP.name(c) catch; "" end
        expression=try isnothing(d) || abs(d)<1e-4 ? nothing : string(constraint_object(c)) catch; nothing end
        push!(constraints,(;index=string(JuMP.index(c)),name=cname,dual=d,expression))
    end
    states=[(;factor=f,id,state=ACState((Float64.(value.(getproperty(v,k))) for k in (:vm,:va,:pg,:qg))...),
        taps=Dict(i=>value(x) for(i,x) in v.taps),banks=Dict(i=>value(x) for(i,x) in v.shunts),
        delta=haskey(b.deltas,id) ? value(b.deltas[id]) : nothing) for(f,b) in blocks for(id,v) in zip(b.ids,b.vars)]
    settings=Dict(id=>DroopSettings((DroopOPF._droop_design_value(getfield(p,k)) for k in keys(p))...) for(id,p) in parameters)
    fd_save(joinpath(out,"snapshot-$stage.json"),(;stage,status=string(termination_status(m)),
        objective=finite(objective_value(m)),variables,constraints,states,settings,
        diagnostics=ccopt_diagnostics(m),scope="Diagnostic stage snapshot; not a qualified design"))
end

function td_ccopt()
    confirmation=strip(get(ENV,"TD_CONTROL_CONFIRMATION",""));isempty(confirmation) && error("Equipment confirmation required")
    label=get(ENV,"TD_CCOPT_LABEL","ccopt-100-instrumented")
    prefix="targeted_demand_diagnostics/"*label
    folder=joinpath(S2500_OUT,prefix);ispath(folder) && error("Preserve prior attempt")
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    seedpath=joinpath(SDQ_OUT,"ipopt-10000/round-1/attempt-1-buildretry-1")
    seedstudy=read_study(joinpath(seedpath,"controller.json"))
    master=read_study(joinpath(seedpath,"optimized-1.0.json"))
    small=get(ENV,"TD_CCOPT_SMALL","false")=="true"
    regularization=parse(Float64,get(ENV,"TD_CCOPT_REGULARIZATION","0.0"))
    small && (master=DroopOPF._copy_study(master;contingencies=filter(e->e.id in (:generator_14,:generator_60),master.contingencies)))
    seed=read_scopf_result(joinpath(seedpath,"result-1.0.json"))
    controls=s214_multi_controls(fd_inputs(500).base);angles=fd_inputs(500).angles
    mkpath(TD_OUT);fd_save(joinpath(TD_OUT,"protocol-$label.json"),(;confirmation,
        master=relpath(seedpath,S2500_OUT),small_master=small,regularization,
        maximum_native_calls=2,seconds_per_stage=120.,
        taps=master.tap_controls,shunts=master.shunt_controls,policy=master.control_policy,
        free_shared_droop_variables=102,normal_limits=true,relief=false,exact_active_response=true))
    mkpath(folder);write(joinpath(folder,"loaded_targeted_driver.jl"),read(@__FILE__,String))
    lane=s2500_targeted_attempt(prefix,master,controls,seedstudy,Dict(1.0=>seed),angles;
        solver=:ccopt,retry=true,droop_normalization=!small,seconds_budget=120.,
        ac_builder=sdq_reduced,cc_builder=sdq_scaled_mpcc,mpcc_implied_q_bounds=true,
        linear_solver=MadNLP.UmfpackSolver,mu=nothing,scheduled=false,
        feasibility_first=true,stage_observer=td_snapshot,feasibility_regularization=regularization)
    cp(@__FILE__,joinpath(folder,"executed_targeted_driver.jl"))
    fd_save(joinpath(folder,"free-controls.json"),controls)
    python=get(ENV,"SDQ_PYTHON","/tmp/s214-plot-env/bin/python")
    read(`$python $(joinpath(@__DIR__,"audit_s2_500bus_solver_demand.py")) $folder`,String)
    accepted=lane.record["accepted"] && JSON.parsefile(joinpath(folder,"independent-audit.json"))["accepted"]
    scan=nothing
    if accepted
        full=DroopOPF._copy_study(lane.study;contingencies=eligible_contingencies(contingency_catalog(lane.study.case)))
        scan=s2500_scan(prefix*"-coverage",full,lane.results[1.],angles;solver=:ipopt,max_failures=4)
    end
    fd_save(joinpath(TD_OUT,"summary-ccopt.json"),(;master_accepted=accepted,
        qualified=!isnothing(scan) && scan.accepted,record=lane.record,
        coverage=isnothing(scan) ? nothing : (;accepted=scan.accepted,exhaustive=scan.exhaustive,failed=scan.failed)))
end
abspath(PROGRAM_FILE)==(@__FILE__) && td_ccopt()
