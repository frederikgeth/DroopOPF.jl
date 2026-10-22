# Fresh initialization seeds at demands excluded from the sensitivity grid.
using PowerModelsSecurityConstrained,PowerModels,Ipopt,JuMP,JSON,SHA
root=normpath(joinpath(@__DIR__,".."));out=joinpath(root,"artifacts/s1_arpae14_confirmation");mkpath(out)
dir=joinpath(root,"test/data/arpae/c1_network01")
original=joinpath(dir,"results/scenario_01_pmin0_qsym/opf_ac.json");before=bytes2hex(sha256(read(original)))
base=build_c1_pm_model(parse_c1_case(joinpath(dir,"inputfiles.ini"),scenario_id="scenario_01_pmin0_qsym"))
for objective in ("cost","loss"),factor in (.95,1.05)
    network=deepcopy(base)
    for l in values(network["load"]);l["pd"]*=factor;l["qd"]*=factor;end
    pd=sum(l["pd"] for l in values(network["load"]) if l["status"]==1)
    if objective=="loss"
        for g in values(network["gen"]);g["model"]=2;g["ncost"]=2;g["cost"]=[1.,0.];end
    end
    function build_anchor(pm)
        PowerModels.build_opf(pm)
        if objective=="loss"
            @objective(pm.model,Min,sum(PowerModels.var(pm,:pg,i) for i in PowerModels.ids(pm,:gen))-pd)
        end
    end
    solver=optimizer_with_attributes(Ipopt.Optimizer,"tol"=>1e-8,"print_level"=>0,"max_iter"=>3000)
    result=PowerModels.solve_model(network,ACPPowerModel,solver,build_anchor)
    result["termination_status"]==LOCALLY_SOLVED || error("source OPF failed")
    write(joinpath(out,"opf-$objective-$factor.json"),JSON.json(result,2))
    println("SOURCE ",objective," ",factor," ",result["termination_status"]);flush(stdout)
end
before==bytes2hex(sha256(read(original))) || error("source modified")
