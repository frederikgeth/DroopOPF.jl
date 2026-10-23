# Final current-source replay of the chosen candidate and selected outage scans.
# Reads physics and retained policies; never resumes an optimization.
using DroopOPF,JSON,SHA
function replay_reserve(root;aggregate_name="reserve-aggregate-checks.json")
    aggregate=JSON.parsefile(joinpath(root,aggregate_name))
    paths=[joinpath(root,aggregate["candidate"]);[r["path"] for r in aggregate["rows"] if r["valid"]]]
    rows=Any[]
    for folder in unique(paths)
        r=read_multi_period_security(joinpath(folder,"result.json"))
        studies=[read_study(joinpath(folder,"period-$t.json")) for t in eachindex(r.periods)]
        check=validate_multi_period_security(studies,r)
        push!(rows,(;path=folder,valid=check.valid,
            state_instances_including_repeated_bases=sum(length(p.states) for p in r.periods),
            result_sha256=bytes2hex(sha256(read(joinpath(folder,"result.json"))))))
        length(rows)%50==0 && (println("REPLAY ",length(rows));flush(stdout))
    end
    result=(;valid=all(r.valid for r in rows),rows,
        complete_connected_security=aggregate["full_security_qualified"],
        state_instances_including_repeated_bases=sum(r.state_instances_including_repeated_bases for r in rows))
    write(joinpath(root,"final-julia-replay.json"),JSON.json(result;pretty=true)*"\n")
    result.valid || error("current-source replay failed")
    println("CURRENT-SOURCE REPLAY PASSED ",length(rows)," result files")
end
length(ARGS) in (1,2) || error("provide campaign root and optional replay-plan filename")
replay_reserve(abspath(ARGS[1]);aggregate_name=length(ARGS)==2 ? ARGS[2] : "reserve-aggregate-checks.json")
