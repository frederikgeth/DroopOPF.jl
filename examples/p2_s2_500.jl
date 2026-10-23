# Canonical P2 benchmark input loader. Importing/loading never starts optimization.
# Keep S2's serialized proportional-response contract intact; do not migrate it
# through read_study, whose current default response semantics differ.
using JSON, SHA
const P2_S2_ROOT = normpath(joinpath(@__DIR__, ".."))
function p2_s2_500_inputs()
    root = joinpath(P2_S2_ROOT, "artifacts", "p2_s2_500")
    contract = JSON.parsefile(joinpath(root, "contract.json"))
    inputs = Dict{String,Any}()
    for (role, ref) in contract["inputs"]
        bytes = read(joinpath(root, ref["snapshot"]))
        bytes == read(joinpath(P2_S2_ROOT, ref["source"])) || error("S2 input drift: $role")
        bytes2hex(sha256(bytes)) == ref["sha256"] || error("S2 input hash mismatch: $role")
        inputs[role] = JSON.parse(String(bytes))
    end
    study = inputs["shared_controller"]["data"]
    for key in ("control_policy", "participation", "redispatch_limits")
        contract[key] == study[key] || error("S2 policy mismatch: $key")
    end
    contract["tap_controls"] == inputs["campaign_protocol"]["taps"] || error("S2 tap mismatch")
    contract["shunt_controls"] == inputs["campaign_protocol"]["shunts"] || error("S2 shunt mismatch")
    physical_keys = ("dr_fraction_per_positive_load", "shedding_mw_per_contingency",
        "combined_fraction_per_load", "proportional_q_relief", "basecase_emergency_or_relief",
        "voltage_extension_pu", "confirmed_thermal_multiplier", "priorities")
    contract["physical_policy"] == Dict(k=>inputs["emergency_protocol"][k] for k in physical_keys) ||
        error("S2 emergency/relief policy mismatch")
    contract["active_response"]["law"] == "Pg_s = Pg_base + alpha_s * delta_s" || error("S2 response mismatch")
    for (rel, expected) in contract["source_hashes"]
        bytes2hex(sha256(read(joinpath(P2_S2_ROOT, rel)))) == expected || error("Source drift: $rel")
        bytes2hex(sha256(read(joinpath(root, "source_snapshot", rel)))) == expected || error("Snapshot drift: $rel")
    end
    (;contract, inputs, case_data=study["case"],
      active_response=:s2_proportional, optimizer_calls=0)
end
if abspath(PROGRAM_FILE) == (@__FILE__)
    x = p2_s2_500_inputs()
    println("S2 inputs verified; P2 benchmark not run. Selected controls: ",
        length(x.contract["tap_controls"]), " taps, ", length(x.contract["shunt_controls"]), " banks.")
end
