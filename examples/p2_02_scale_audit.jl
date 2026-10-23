# Solve-free scale-study audit, including all rejected and retried AVR anchors.
include("p2_02_audit_heldout.jl")
out=abspath(ARGS[1]);anchor_rows=[]
for attempt_dir in ("heldout","heldout_retry")
    summary_path=joinpath(out,attempt_dir,"summary.json")
    isfile(summary_path) || continue
    for row in JSON.parsefile(summary_path)
        path=joinpath(out,attempt_dir,row["id"],"anchor.json")
        isfile(path) || continue
        data=JSON.parsefile(path);physical=nothing
        if !isnothing(data["state"])
            case=read_study(joinpath(out,"planned_cases",row["id"]*".json")).case
            assignments=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in case.generators]
            d=data["state"];state=ACState(Float64.(d["vm"]),Float64.(d["va"]),Float64.(d["pg"]),Float64.(d["qg"]))
            physical=validate_equilibrium(case,state;reactive_assignments=assignments,smooth_epsilon=1e-5)
            get(row,"error","")=="AVR anchor rejected" && @assert !physical.valid
        end
        push!(anchor_rows,(;id=row["id"],attempt=attempt_dir,termination_status=data["termination_status"],
            primal_status=data["primal_status"],comparison_complete=row["base_valid"] && length(row["attempts"])==9,
            error=get(row,"error",nothing),physical_validation=physical))
    end
end
open(joinpath(out,"anchor_audit.json"),"w") do io
    JSON.print(io,DroopOPF._json_data((;rows=anchor_rows)),2)
end
println("Audited ",length(anchor_rows)," initial/retried anchors without optimization")
# Explain conservative routing using saved decisions, without rerunning predictors.
initial_rows=Dict(r["id"]=>r for r in JSON.parsefile(joinpath(out,"heldout","summary.json")))
routes=[];configuration_rows=[]
for row in JSON.parsefile(joinpath(out,"heldout_audit.json"))["inputs"]
    row["complete"] || continue
    initial=initial_rows[row["id"]]
    source=initial["base_valid"] && length(initial["attempts"])==9 ? "heldout" : "heldout_retry"
    dir=joinpath(out,source,row["id"])
    study=read_study(joinpath(dir,"input.json"));raw=read_study(joinpath(out,"planned_cases",row["id"]*".json")).case
    @assert DroopOPF._json_data(study.case.network)==DroopOPF._json_data(raw.network)
    @assert DroopOPF._json_data(study.case.generators)==DroopOPF._json_data(raw.generators)
    @assert study.participation==Dict(g.id=>1. for g in study.case.generators if g.available)
    checked=[]
    for rep in 1:3,policy in ("legacy","guarded","exhaustive")
        pipeline=JSON.parsefile(joinpath(dir,"$rep-$policy.json"))
        for a in pipeline["assessments"]
            isnothing(a["exact_assessment"]) && continue
            r=a["exact_assessment"]["result"]
            @assert isempty(r["tap_controls"]) && isempty(r["shunt_controls"])
            @assert all(isempty,values(r["tap_settings"])) && all(isempty,values(r["shunt_settings"]))
            @assert isnothing(r["reactive_assignments"])
            push!(checked,a["entry"]["contingency"]["id"])
        end
    end
    push!(configuration_rows,(;id=row["id"],exact_results_checked=length(checked),fixed_equipment=true,equal_preventive_participation=true,frozen_legacy_droop=true))
    data=JSON.parsefile(joinpath(dir,"1-guarded.json"))
    reasons=Dict{String,Int}()
    for a in data["assessments"]
        reason=a["decision"]["reason"];reasons[reason]=get(reasons,reason,0)+1
    end
    push!(routes,(;id=row["id"],reasons))
end
open(joinpath(out,"routing_audit.json"),"w") do io
    JSON.print(io,DroopOPF._json_data((;inputs=routes)),2)
end

open(joinpath(out,"configuration_audit.json"),"w") do io
    JSON.print(io,DroopOPF._json_data((;inputs=configuration_rows)),2)
end
