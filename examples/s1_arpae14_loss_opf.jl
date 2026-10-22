# Fixed-equipment AC OPF minimizing total active network dissipation.
using PowerModelsSecurityConstrained, PowerModels, Ipopt, JuMP, JSON, SHA
root=normpath(joinpath(@__DIR__,".."))
out=joinpath(root,"artifacts/s1_arpae14_loss_anchors");mkpath(out)
dir=joinpath(root,"test/data/arpae/c1_network01")
original=joinpath(dir,"results/scenario_01_pmin0_qsym/opf_ac.json")
before=bytes2hex(sha256(read(original)))
base=build_c1_pm_model(parse_c1_case(joinpath(dir,"inputfiles.ini"),scenario_id="scenario_01_pmin0_qsym"))
@assert isempty(base["dcline"])
rows=[]
for factor in (.9,1.,1.1)
    network=deepcopy(base)
    for l in values(network["load"]);l["pd"]*=factor;l["qd"]*=factor;end
    # Avoid carrying economic piecewise-cost epigraph constraints into the loss problem.
    for g in values(network["gen"]);g["model"]=2;g["ncost"]=2;g["cost"]=[1.,0.];end
    pd=sum(l["pd"] for l in values(network["load"]) if l["status"]==1)
    function build_loss_opf(pm)
        PowerModels.build_opf(pm)
        @objective(pm.model,Min,sum(PowerModels.var(pm,:pg,i) for i in PowerModels.ids(pm,:gen))-pd)
    end
    solver=optimizer_with_attributes(Ipopt.Optimizer,"tol"=>1e-8,"print_level"=>0,"max_iter"=>3000)
    result=PowerModels.solve_model(network,ACPPowerModel,solver,build_loss_opf)
    result["termination_status"]==LOCALLY_SOLVED || error("loss OPF failed at $factor")
    sol=result["solution"];bm=network["baseMVA"]
    generation=sum(g["pg"] for g in values(sol["gen"]))
    branch_loss=sum(b["pf"]+b["pt"] for b in values(sol["branch"]))
    shunt_loss=sum(s["gs"]*sol["bus"][string(s["shunt_bus"])]["vm"]^2 for s in values(network["shunt"]) if s["status"]==1)
    abs((generation-pd)-(branch_loss+shunt_loss))<1e-6 || error("loss accounting mismatch")
    write(joinpath(out,"opf-$factor.json"),JSON.json(result,2))
    push!(rows,Dict("factor"=>factor,"status"=>string(result["termination_status"]),"loss_mw"=>(generation-pd)*bm,"branch_loss_mw"=>branch_loss*bm,"shunt_loss_mw"=>shunt_loss*bm,"load_mw"=>pd*bm,"generation_mw"=>generation*bm))
    println("LOSS OPF ",factor," ",result["termination_status"]," loss MW=",(generation-pd)*bm);flush(stdout)
end
before==bytes2hex(sha256(read(original))) || error("source changed")
write(joinpath(out,"opf_summary.json"),JSON.json(Dict("rows"=>rows,"objective"=>"min sum(Pg) - sum(Pd), pu; total active branch plus fixed-shunt losses","original_sha256"=>before,"original_unchanged"=>true,"taps_shunts"=>"fixed source values"),2))
