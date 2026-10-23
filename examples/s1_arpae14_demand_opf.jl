# Source economic AC OPF only: fixed source taps/shunts; no contingencies.
using PowerModelsSecurityConstrained, PowerModels, Ipopt, JuMP, JSON, SHA
root=normpath(joinpath(@__DIR__,".."))
out=joinpath(root,"artifacts/s1_arpae14_demand_anchors");mkpath(out)
dir=joinpath(root,"test/data/arpae/c1_network01")
original=joinpath(dir,"results/scenario_01_pmin0_qsym/opf_ac.json")
before=bytes2hex(sha256(read(original)))
base=build_c1_pm_model(parse_c1_case(joinpath(dir,"inputfiles.ini"),scenario_id="scenario_01_pmin0_qsym"))
rows=[]
for factor in (.9,1.,1.1)
    network=deepcopy(base)
    for l in values(network["load"]);l["pd"]*=factor;l["qd"]*=factor;end
    solver=optimizer_with_attributes(Ipopt.Optimizer,"tol"=>1e-8,"print_level"=>0,"max_iter"=>3000)
    result=PowerModels.solve_opf(network,ACPPowerModel,solver)
    result["termination_status"]==LOCALLY_SOLVED || error("OPF failed at $factor")
    write(joinpath(out,"opf-$factor.json"),JSON.json(result,2))
    push!(rows,Dict("factor"=>factor,"status"=>string(result["termination_status"]),"economic_objective"=>result["objective"]))
    println("DEMAND OPF ",factor," ",result["termination_status"]," cost=",result["objective"]);flush(stdout)
end
before==bytes2hex(sha256(read(original))) || error("source changed")
write(joinpath(out,"opf_summary.json"),JSON.json(Dict("rows"=>rows,"original_sha256"=>before,"original_unchanged"=>true,"taps_shunts"=>"fixed source values"),2))
