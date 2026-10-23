# Retain failed separator iterates only as numerical starts, never acceptance.
function sdq_separator_starts(controller,seed,directory,factor)
    scanfile=joinpath(dirname(directory),"demand-$factor","scan.json")
    isfile(scanfile) || return (;controller,seed,added=Symbol[],sources=String[])
    scan=JSON.parsefile(scanfile);failed=Set(Symbol.(scan["failed"]))
    isempty(failed) && return (;controller,seed,added=Symbol[],sources=String[])
    original_case=JSON.parsefile(joinpath(directory,"optimized-$factor.json"))["data"]["case"]
    states=copy(seed.states);taps=copy(seed.tap_settings);banks=copy(seed.shunt_settings);deltas=copy(seed.balancing_power)
    sources=String[]
    for row in scan["attempts"]
        id=Symbol(row["event"]);id in failed || continue
        folder=joinpath(S2500_OUT,row["final"]["name"])
        JSON.parsefile(joinpath(folder,"input.json"))["data"]["case"]==original_case || error("Separator controller/source mismatch")
        isfile(joinpath(folder,"result.json")) || continue
        result=read_scopf_result(joinpath(folder,"result.json"))
        @assert result.states[:base].vm==seed.states[:base].vm && result.states[:base].va==seed.states[:base].va
        @assert result.states[:base].pg==seed.states[:base].pg && result.states[:base].qg==seed.states[:base].qg
        @assert result.tap_settings[:base]==seed.tap_settings[:base] && result.shunt_settings[:base]==seed.shunt_settings[:base]
        state=get(result.states,id,nothing)
        isnothing(state) && continue
        all(isfinite,[state.vm;state.va;state.pg;state.qg]) && all(>(0),state.vm) || continue
        states[id]=state;taps[id]=result.tap_settings[id];banks[id]=result.shunt_settings[id]
        haskey(result.balancing_power,id) && (deltas[id]=result.balancing_power[id])
        push!(sources,relpath(folder,S2500_OUT))
    end
    eligible=eligible_contingencies(contingency_catalog(controller.case))
    included=union(Set(c.id for c in controller.contingencies),failed)
    controller=DroopOPF._copy_study(controller;contingencies=filter(c->c.id in included,eligible))
    point=SCOPFResult(states,deltas,seed.objective,:NOT_RUN,:NO_SOLUTION,seed.mode,seed.encoding,
        seed.smooth_epsilon,seed.smooth_reactive_relative_epsilon,seed.smooth_reactive_epsilon,
        "Numerical start from accepted master and unresolved separator iterates",seed.reactive_assignments,
        taps,banks,seed.tap_controls,seed.shunt_controls,seed.control_policy)
    (;controller,seed=point,added=sort(collect(failed);by=string),sources)
end
