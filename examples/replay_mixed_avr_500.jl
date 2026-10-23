# Final-current-source physical replay, without optimization.
using DroopOPF,JSON,SHA
include("p2_mixed_avr_500.jl")
function replay_mixed_campaign(folder)
    rows=Any[];skipped=String[]
    for (directory,_,files) in walkdir(folder)
        "summary.json" in files && "result.json" in files || continue
        summary=JSON.parsefile(joinpath(directory,"summary.json"))
        haskey(summary,"status")&&get(summary,"accepted",false)||continue
        raw=JSON.parsefile(joinpath(directory,"result.json"))
        if get(raw,"kind",nothing)!="DroopOPF.MultiPeriodSecurityResult"
            push!(skipped,relpath(directory,folder));continue
        end
        result=read_multi_period_security(joinpath(directory,"result.json"))
        studies=[read_study(joinpath(directory,"period-$t.json")) for t in eachindex(result.periods)]
        audit=validate_multi_period_security(studies,result)
        mix_save(joinpath(directory,"julia-final-replay.json"),audit)
        push!(rows,(;path=relpath(directory,folder),valid=audit.valid,
            periods=length(result.periods),state_instances=sum(length(p.states) for p in result.periods),
            result_sha256=bytes2hex(sha256(read(joinpath(directory,"result.json"))))))
        length(rows)%50==0&&(println("FINAL REPLAY ",length(rows));flush(stdout))
    end
    final=(;valid=all(r.valid for r in rows),rows,skipped_early_unversioned_prototypes=skipped,
        state_instances_including_repeated_frozen_bases=sum(r.state_instances for r in rows))
    mix_save(joinpath(folder,"final-julia-replay.json"),final)
    final.valid||error("Final-source replay failed")
    mixed_protocol(folder)
    println("FINAL REPLAY PASSED: ",length(rows)," result files")
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1||error("supply campaign folder")
    replay_mixed_campaign(abspath(ARGS[1]))
end
