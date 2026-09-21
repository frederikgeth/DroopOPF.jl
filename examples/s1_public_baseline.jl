include("s1_diagnostics.jl")
using SHA

function s1_public_baseline(out)
    source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case118_ieee.m")
    case=load_matpower_case(source;base_frequency=60.)
    text=read(source,String)
    buses=DroopOPF._matpower_array(text,"bus")
    branches=DroopOPF._matpower_array(text,"branch")
    # Match the successful smoke test: flat voltage/angle and imported dispatch.
    start=ACState(ones(length(case.network.buses)),zeros(length(case.network.buses)),
        [g.initial_p for g in case.generators],[g.initial_q for g in case.generators])
    row=s1_solve(out,"pglib118-fixed",case,start)
    write_study(joinpath(out,"study.json"),Study(case))
    r=read_joint_design(joinpath(out,"pglib118-fixed-design.json"))
    state=r.opf.state
    indices=Dict(b.id=>i for (i,b) in enumerate(case.network.buses))
    angles=[rad2deg(state.va[indices[b.from_bus]]-state.va[indices[b.to_bus]]) for b in case.network.branches]
    angle_violation=maximum(max(branches[i,12]-angles[i],angles[i]-branches[i,13],0.) for i in eachindex(angles) if branches[i,11]>0)
    flows=branch_flows(case.network,state)
    result=Dict("buses"=>length(case.network.buses),"generators"=>length(case.generators),"branches"=>length(case.network.branches),
        "fixed_shunts"=>length(case.network.shunts),"controls"=>0,"banks"=>0,
        "source_sha256"=>bytes2hex(sha256(read(source))),"source"=>"https://raw.githubusercontent.com/power-grid-lib/pglib-opf/v23.07/pglib_opf_case118_ieee.m",
        "status"=>row["status"],"valid"=>row["valid"],"objective"=>row["objective"],"physical"=>row["physical"],
        "source_angle_violation_degrees"=>angle_violation,"angles_enforced_in_optimizer"=>false,
        "source_cost_objective_used"=>false,"overlay"=>"none; fixed supplied equipment, no droop attachments",
        "bus_ids"=>[b.id for b in case.network.buses],"vm"=>state.vm,"vmin"=>[b.v_min for b in case.network.buses],"vmax"=>[b.v_max for b in case.network.buses],
        "loading_from"=>[abs(flows.from[i])/b.thermal_limit for (i,b) in enumerate(case.network.branches)],
        "loading_to"=>[abs(flows.to[i])/b.thermal_limit for (i,b) in enumerate(case.network.branches)],
        "angle_degrees"=>angles,"angle_min_degrees"=>branches[:,12],"angle_max_degrees"=>branches[:,13])
    write(joinpath(out,"summary.json"),JSON.json(result;pretty=true))
    row["valid"] || error("118-bus baseline did not validate; retained diagnostics")
end

abspath(PROGRAM_FILE)==(@__FILE__) && s1_public_baseline(abspath(ARGS[1]))
