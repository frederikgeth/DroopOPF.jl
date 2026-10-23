# Evaluate supplied snapshots only. No solver or optimization campaign is started.
using DroopOPF, JSON
input = JSON.parsefile(ARGS[1])
results = []
for snapshot in input["snapshots"]
    case = load_matpower_case(snapshot["case_path"])
    state = ACState(Float64.(snapshot["vm"]), Float64.(snapshot["va"]), Float64[], Float64[])
    flows = branch_flows(case.network, state)
    shunts = shunt_powers(case.network, state)
    balance = power_balance(case.network, state, Generator[], Load[])
    voltage = state.vm .* cis.(state.va)
    ybus_injection = voltage .* conj.(DroopOPF._admittance_matrix(case.network) * voltage)
    pairs(values) = [[real(x), imag(x)] for x in values]
    push!(results, Dict("id"=>snapshot["id"], "from"=>pairs(flows.from),
        "to"=>pairs(flows.to), "shunts"=>pairs(shunts),
        "ybus_injection"=>pairs(ybus_injection),
        "injection"=>[[-p,-q] for (p,q) in zip(balance.active,balance.reactive)]))
end
open(ARGS[2], "w") do io
    JSON.print(io, Dict("snapshots"=>results, "julia_version"=>string(VERSION)), 2)
end
