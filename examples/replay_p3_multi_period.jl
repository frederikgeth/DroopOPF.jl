# Replay saved period states with the current library, without optimization.
using DroopOPF, JSON
include("p3_multi_period.jl")
function p3_replay(root)
    rows=Any[]
    for n in (3,14,500),lane in ("fixed","design")
        folder=joinpath(root,string(n),lane)
        k=JSON.parsefile(joinpath(folder,"contract.json"));d=JSON.parsefile(joinpath(folder,"result.json"))
        study=MultiPeriodStudy([read_study(joinpath(folder,"period-$t.json")).case for t in eachindex(k["duration_hours"])];
            duration_hours=k["duration_hours"],ramp_limits=Dict(parse(Int,id)=>Tuple(v) for (id,v) in k["ramp_limits"]),
            angle_limits=Dict(parse(Int,id)=>Tuple(v) for (id,v) in k["angle_limits"]))
        controls=[DroopControl(c["control_id"];slope_bounds=c["bounds"]["slope"],v_ref_bounds=c["bounds"]["v_ref"],
            deadband_low_bounds=c["bounds"]["deadband_low"],deadband_high_bounds=c["bounds"]["deadband_high"]) for c in k["droop_controls"]]
        periods=DroopOPF.ACOPFResult{Float64}[DroopOPF.ACOPFResult{Float64}(isnothing(o["state"]) ? nothing : p3_state(o["state"]),
            isnothing(o["objective"]) ? NaN : o["objective"],Symbol(o["termination_status"]),Symbol(o["primal_status"]),
            o["smooth_epsilon"],o["smooth_reactive_relative_epsilon"],o["smooth_reactive_epsilon"]) for o in d["periods"]]
        droops=Dict(parse(Int,id)=>DroopOPF._droop_settings_from_data(s) for (id,s) in d["droops"])
        r=MultiPeriodResult(periods,droops,controls,d["objective_mwh"],Symbol(d["termination_status"]),Symbol(d["primal_status"]))
        check=validate_multi_period(study,r);@assert check.valid
        push!(rows,(;buses=n,lane,check))
    end
    p3_save(joinpath(root,"julia-replay.json"),(;valid=true,rows))
    println("All 30 saved period states passed fresh Julia replay")
end
length(ARGS)==1 || error("Supply campaign directory")
p3_replay(abspath(ARGS[1]))
