# Audit and score completed P2-02 outputs without starting any optimizer.
using DroopOPF,JSON,SHA
function main()
root=normpath(joinpath(@__DIR__,".."));out=abspath(ARGS[1]);held=joinpath(out,"heldout")
save(p,x)=open(io->JSON.print(io,DroopOPF._json_data(x),2),p,"w")
frozen=JSON.parsefile(joinpath(out,"frozen.json"))
@assert all(bytes2hex(sha256(read(joinpath(root,p))))==h for (p,h) in frozen["code_hashes"])
rows=JSON.parsefile(joinpath(held,"summary.json"));@assert length(rows)==4
directories=Dict(row["id"]=>joinpath(held,row["id"]) for row in rows)
retry_path=joinpath(out,"heldout_retry","summary.json")
if isfile(retry_path)
    for retry in JSON.parsefile(retry_path)
        i=findfirst(row->row["id"]==retry["id"],rows)
        @assert !isnothing(i)
        if retry["base_valid"] && length(retry["attempts"])==16
            rows[i]=retry;directories[retry["id"]]=joinpath(out,"heldout_retry",retry["id"])
        end
    end
end
family_rows=[];inputs=[];discrepancies=[];replayed=0;regimes=Dict{String,Int}()
for row in rows
    dir=directories[row["id"]]
    if !row["base_valid"] || length(row["attempts"])!=16
        push!(inputs,(;id=row["id"],complete=false,error=get(row,"error","incomplete policy/repetition set")));continue
    end
    study=read_study(joinpath(dir,"input.json"));case=study.case;base=JSON.parsefile(joinpath(dir,"base.json"))
    @assert isempty(study.contingencies) && isempty(study.tap_controls) && isempty(study.shunt_controls)
    datasets=Dict{Tuple{Int,String},Any}();unresolved=Set{String}();physical=Set{String}();reference_classes=Dict{String,Set{String}}()
    for attempt in row["attempts"]
        data=JSON.parsefile(joinpath(dir,attempt["path"]));key=(attempt["repetition"],attempt["policy"]);datasets[key]=data
        @assert length(data["assessments"])==length(contingency_catalog(case).entries)
        for a in data["assessments"]
            id=a["entry"]["contingency"]["id"]
            if attempt["policy"]=="exhaustive"
                get!(reference_classes,id,Set{String}())
                push!(reference_classes[id],a["rank"]["classification"])
                a["rank"]["classification"]!="accepted" && push!(unresolved,id)
            end
            exact=a["exact_assessment"]
            isnothing(exact) && continue
            result=DroopOPF._scopf_result_from_data(exact["result"])
            @assert DroopOPF._json_data(result.states[:base])==base
            @assert isempty(result.tap_controls) && isempty(result.shunt_controls)
            @assert all(isempty,values(result.tap_settings)) && all(isempty,values(result.shunt_settings))
            @assert isnothing(result.reactive_assignments)
            contingency=only(filter(c->string(c.id)==id,eligible_contingencies(contingency_catalog(case))))
            report=equilibrium_report(DroopOPF._copy_study(study;contingencies=[contingency]),result)
            replayed+=1
            report.valid==exact["report"]["valid"] || push!(discrepancies,(;input=row["id"],id,attempt=key))
            attempt["policy"]=="exhaustive" && !report.physical_valid && push!(physical,id)
            if attempt["policy"]=="exhaustive" && attempt["repetition"]==1 && report.valid
                scenario=scenario_case(case,contingency);state=result.states[contingency.id]
                for point in droop_operating_points(scenario,state)
                    name=string(point.regime);regimes[name]=get(regimes,name,0)+1
                end
            end
        end
    end
    unstable=[id for (id,values) in reference_classes if length(values)>1]
    for family in ("line","transformer","generator"),policy in ("legacy","reference","guarded","exhaustive")
        first=datasets[(1,policy)]["assessments"]
        chosen=[a for a in first if a["entry"]["device_kind"]==family]
        ids=Set(a["entry"]["contingency"]["id"] for a in chosen)
        screened=Set(a["entry"]["contingency"]["id"] for a in chosen if a["decision"]["action"]=="screened")
        for rep in 2:4
            other=Set(a["entry"]["contingency"]["id"] for a in datasets[(rep,policy)]["assessments"] if a["entry"]["device_kind"]==family && a["decision"]["action"]=="screened")
            @assert screened==other
        end
        push!(family_rows,(;input=row["id"],family,policy,total=length(ids),screened=length(screened),
            unresolved=length(intersect(ids,unresolved)),misses=length(intersect(screened,unresolved)),
            physical_misses=length(intersect(screened,physical)),unstable=length(intersect(ids,Set(unstable)))))
    end
    push!(inputs,(;id=row["id"],complete=true,unstable_reference_ids=unstable,timings=row["attempts"]))
end
@assert isempty(discrepancies)
save(joinpath(out,"heldout_audit.json"),(;inputs,families=family_rows,discrepancies,replayed_states=replayed,accepted_control_regimes=regimes,
    reference="union of unresolved outcomes over four exhaustive repetitions; instability retained",frozen_code_unchanged=true))
println("Audited ",replayed," exact states, discrepancies=",length(discrepancies))

end
main()
