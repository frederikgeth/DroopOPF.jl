using DroopOPF, JSON

"""Export reusable standard files and independently replay every retained witness."""
function replay_droop_retained(directory)
    retained=joinpath(directory,"retained")
    metadata=JSON.parsefile(joinpath(retained,"acceptance.json"))
    design=JSON.parsefile(joinpath(retained,"design.json"))["data"]
    study=read_study(joinpath(retained,"input.json"))
    for (id,s) in design["settings"]
        study=with_droop_settings(study,parse(Int,id),DroopSettings(
            s["slope"],s["v_ref"],s["deadband_low"],s["deadband_high"]))
    end
    result=DroopOPF._scopf_result_from_data(design["result"])
    @assert equilibrium_report(study,result).valid
    write_study(joinpath(retained,"optimized-study.json"),study)
    write_scopf_result(joinpath(retained,"master-result.json"),result)
    # Exercise public round-trip readers, not just the in-memory deserialisation.
    study=read_study(joinpath(retained,"optimized-study.json"))
    result=read_scopf_result(joinpath(retained,"master-result.json"))
    @assert equilibrium_report(study,result).valid
    write_scopf_evaluation_report(joinpath(retained,"master-evaluation.md"),study,result;
        context="Retained validated master only; independent accepted branch witnesses listed in acceptance.json.")
    round=JSON.parsefile(joinpath(directory,"design","round-$(metadata["iteration"])","audit.json"))
    by_id=Dict(string(e.contingency.id)=>e.contingency for e in contingency_catalog(study.case).entries)
    accepted=Set(metadata["accepted_ids"])
    reports=Dict{String,Any}()
    for a in round["assessments"]
        id=a["contingency"]["id"]
        id in accepted || continue
        single=DroopOPF._copy_study(study;contingencies=[by_id[id]])
        replay=DroopOPF._scopf_result_from_data(a["result"])
        @assert a["result"]["states"]["base"] == design["result"]["states"]["base"]
        report=equilibrium_report(single,replay)
        @assert report.valid
        reports[id]=DroopOPF._json_data(report)
    end
    @assert Set(keys(reports)) == accepted
    write(joinpath(retained,"replayed-witnesses.json"),JSON.json(reports;pretty=true)*"\n")
    println("$(study.case.id): retained master round-trip and $(length(reports)) branch witnesses independently replayed successfully.")
end

"""Preserve prior accepted branch witnesses separately, without scoring them as fresh successes."""
function replay_prior_branch_witnesses(previous,directory)
    original=JSON.parsefile(joinpath(previous,"protocol.json"))
    current=JSON.parsefile(joinpath(directory,"protocol.json"))
    @assert original["base"] == current["base"]
    @assert original["study"] == current["study"]
    study=read_study(joinpath(previous,"input.json"))
    catalog=Dict(string(e.contingency.id)=>e.contingency for e in contingency_catalog(study.case).entries)
    campaign=JSON.parsefile(joinpath(previous,"exhaustive","campaign.json"))["data"]
    target=mkpath(joinpath(directory,"prior-accepted-branches"))
    write_study(joinpath(target,"study.json"),study)
    accepted=String[]
    for a in campaign["assessments"]
        a["entry"]["disposition"] == "eligible" || continue
        isempty(a["entry"]["contingency"]["generator_ids"]) || continue
        a["rank"]["classification"] == "accepted" || continue
        id=a["entry"]["contingency"]["id"]
        single=DroopOPF._copy_study(study;contingencies=[catalog[id]])
        result=DroopOPF._scopf_result_from_data(a["exact_assessment"]["result"])
        report=equilibrium_report(single,result)
        @assert report.valid
        write_study(joinpath(target,"$id-input.json"),single)
        write_scopf_result(joinpath(target,"$id-result.json"),result)
        write(joinpath(target,"$id-validation.json"),JSON.json(DroopOPF._json_data(report);pretty=true)*"\n")
        push!(accepted,id)
    end
    metadata=(;accepted_ids=accepted,source=abspath(previous),
        scope="Previously accepted branch states, independently replayed without re-solving, at the original fixed base and original droop settings. Not fresh-run passes and not transferred to the optimized master.")
    write(joinpath(target,"acceptance.json"),JSON.json(metadata;pretty=true)*"\n")
    println("$(study.case.id): preserved and independently replayed $(length(accepted)) previously accepted fixed-base branch witnesses.")
end

if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    if !isempty(ARGS) && ARGS[1]=="--prior"
        length(ARGS)==3 || error("usage: --prior PREVIOUS_DIRECTORY NEW_DIRECTORY")
        replay_prior_branch_witnesses(ARGS[2],ARGS[3])
    else
        foreach(replay_droop_retained,ARGS)
    end
end
