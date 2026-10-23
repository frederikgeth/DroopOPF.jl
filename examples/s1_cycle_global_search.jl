# Reuse exact bound evidence from s1_cycle_feasibility.jl; fixed-control S1 only.
using DroopOPF,SCIP
const CycleGlobalJSON=DroopOPF.JSON
function run_cycle_global_search(;time_limit=60.)
    root=normpath(joinpath(@__DIR__,".."));out=joinpath(root,"artifacts","s1_cycle_feasibility");rows=[]
    for variant in ("no_deadband","with_deadband")
        c=read_study(joinpath(root,"artifacts","s1_arpae14_corrected_comparison","verified",variant*"-study.json")).case
        scope=CycleGlobalJSON.parsefile(joinpath(root,"artifacts","s1_arpae14_feasibility_gate",variant*"-qualification.json"))["data"]["conditions"]["candidate/0.9"]["problem"]
        angles=Dict(parse(Int,k)=>Tuple(Float64.(v)) for (k,v) in scope["angle_limits_rad"])
        p=FeasibilityProblem(DroopOPF._feasibility_scaled_case(c,.9);angle_limits=angles)
        lp=read_feasibility_result(joinpath(out,variant*".json"),p)
        if lp.status==:certified_infeasible
            push!(rows,Dict("variant"=>variant,"gate_status"=>string(lp.status)))
        else
            result=solve_global_feasibility(p;target_bus=8,max_relaxation=0.,voltage_bound_result=lp,
                optimizer_factory=SCIP.Optimizer,time_limit,silent=false,
                optimizer_attributes=Dict("numerics/feastol"=>1e-9,"limits/nodes"=>100000))
            write_feasibility_result(joinpath(out,variant*"-strict-global.json"),p,result.result)
            push!(rows,merge(Dict("variant"=>variant,"gate_status"=>string(result.result.status)),result.ledger))
            println("CYCLE GLOBAL RESULT ",variant," ",result.ledger["termination_status"]," => ",result.result.status);flush(stdout)
        end
        write(joinpath(out,"global_summary.json"),CycleGlobalJSON.json(rows;pretty=true))
    end
end
if abspath(PROGRAM_FILE)==@__FILE__
    run_cycle_global_search()
end
