# Match absolute reactive smoothing across Q-offset definitions; reuse exact CCOpt cells.
include("s1_arpae14_joint_sensitivity.jl")
function run_matched_sensitivity()
    out=joinpath(GATED_ROOT,"artifacts/s1_arpae14_matched_sensitivity");mkpath(out)
    ledger=joinpath(out,"rows.jsonl")
    source=joinpath(JS_OUT,"rows.jsonl")
    if !isfile(ledger)
        open(ledger,"w") do io
            for line in readlines(source)
                r=JSON.parse(line);r["solver"]=="ccopt" || continue
                r["reused_from"]=relpath(source,GATED_ROOT)
                println(io,JSON.json(r))
            end
        end
    end
    run_joint_sensitivity(out;reactive_epsilon=1e-6)
end
abspath(PROGRAM_FILE)==(@__FILE__) && run_matched_sensitivity()
