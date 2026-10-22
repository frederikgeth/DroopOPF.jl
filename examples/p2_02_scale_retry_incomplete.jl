# Retry only inputs without a full comparison, preserving all original attempts.
# Execute the frozen runner's definitions verbatim, then derive an orchestration-only
# retry function with unchanged numerical statements, settings and input models.
using JSON,SHA
runner=abspath(joinpath(@__DIR__,"p2_02_scale_qualification.jl"))
source=read(runner,String)
definitions=first(split(source,"\nmode=ARGS[1];"))
include_string(Main,definitions,runner)
out=abspath(ARGS[1])
initial=JSON.parsefile(joinpath(out,"heldout","summary.json"))
const P2_RETRY_IDS=Set(row["id"] for row in initial if !row["base_valid"] || length(row["attempts"])!=9)
retry_source=last(split(definitions,"function p2_run(";limit=2))
retry_source="function p2_retry_run("*retry_source
retry_source=replace(retry_source,"joinpath(out,\"heldout\")"=>"joinpath(out,\"heldout_retry\")",
    "enumerate(p2_scale_inputs())"=>"enumerate(filter(input->input.case.id in P2_RETRY_IDS,p2_scale_inputs()))")
include_string(Main,retry_source,runner)
p2save(joinpath(out,"retry_protocol.json"),(;input_ids=sort(collect(P2_RETRY_IDS)),driver_sha256=p2hash(@__FILE__),
    rationale="Retry incomplete inputs after initial compilation; unchanged five-second limits and frozen numerical source/settings. Originals retained.",
    original_summary_sha256=p2hash(joinpath(out,"heldout","summary.json"))))
# Retain an untimed warm-up retry so first-call compilation cannot contaminate
# the subsequent unchanged bounded anchor attempt.
for input in filter(input->input.case.id in P2_RETRY_IDS,p2_scale_inputs())
    assignments=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in input.case.generators]
    warm=solve_opf(input.case;reactive_assignments=assignments,P2_OPTIONS...)
    p2save(joinpath(out,"retry-warmup-"*input.case.id*".json"),warm)
end
p2_retry_run(out,"confirmed-fixed-controls")
