# Source OPF precursors for isolated original P/Q limit variants.
using PowerModelsSecurityConstrained,PowerModels,Ipopt,JuMP,JSON,SHA
root=normpath(joinpath(@__DIR__,".."));out=joinpath(root,"artifacts/s1_arpae14_original_limits");mkpath(out)
dir=joinpath(root,"test/data/arpae/c1_network01")
base=build_c1_pm_model(parse_c1_case(joinpath(dir,"inputfiles.ini"),scenario_id="scenario_01_pmin0_qsym"))
original=JSON.parsefile(joinpath(dir,"results/scenario_01/network_model.json"))
for variant in ("original_p","original_q","original_pq"),objective in ("cost","loss"),factor in (.9,.95,1.,1.05,1.1)
    network=deepcopy(base)
    for (id,g) in network["gen"]
        o=original["gen"][id];@assert g["gen_bus"]==o["gen_bus"] && g["gen_status"]==o["gen_status"]
        for axis in (variant=="original_p" ? ("p",) : variant=="original_q" ? ("q",) : ("p","q")),side in ("min","max")
            g[axis*side]=o[axis*side]
        end
    end
    for l in values(network["load"]);l["pd"]*=factor;l["qd"]*=factor;end
    pd=sum(l["pd"] for l in values(network["load"]) if l["status"]==1)
    if objective=="loss"
        for g in values(network["gen"]);g["model"]=2;g["ncost"]=2;g["cost"]=[1.,0.];end
    end
    function build_anchor(pm)
        PowerModels.build_opf(pm)
        if objective=="loss";@objective(pm.model,Min,sum(PowerModels.var(pm,:pg,i) for i in PowerModels.ids(pm,:gen))-pd);end
    end
    solver=optimizer_with_attributes(Ipopt.Optimizer,"tol"=>1e-8,"print_level"=>0,"max_iter"=>3000,"bound_relax_factor"=>0.)
    r=PowerModels.solve_model(network,ACPPowerModel,solver,build_anchor)
    r["termination_status"]==LOCALLY_SOLVED || error("source OPF failed $variant $objective $factor")
    write(joinpath(out,"opf-$variant-$objective-$factor.json"),JSON.json(r,2))
    println("SOURCE ",variant," ",objective," ",factor);flush(stdout)
end
