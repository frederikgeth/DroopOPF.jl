using DroopOPF,HiGHS,SCIP
const TightJSON=DroopOPF.JSON
function run_arpae14_global_tightening(;global_time_limit=60.)
    root=normpath(joinpath(@__DIR__,".."));out=joinpath(root,"artifacts","s1_arpae14_global_feasibility");mkpath(out)
    rows=[]
    for variant in ("no_deadband","with_deadband")
        c=read_study(joinpath(root,"artifacts","s1_arpae14_corrected_comparison","verified",variant*"-study.json")).case
        d=TightJSON.parsefile(joinpath(root,"artifacts","s1_arpae14_feasibility_gate",variant*"-qualification.json"))["data"]["conditions"]["candidate/0.9"]["problem"]
        angles=Dict(parse(Int,k)=>Tuple(Float64.(v)) for (k,v) in d["angle_limits_rad"])
        p=FeasibilityProblem(DroopOPF._feasibility_scaled_case(c,.9);angle_limits=angles)
        lp=certify_feasibility_lp(p;optimizer_factory=HiGHS.Optimizer,time_limit=60.,max_rounds=20,bound_tightening_rounds=3)
        write_feasibility_result(joinpath(out,variant*"-tightened-lp.json"),p,lp)
        bounds=verified_feasibility_voltage_bounds(p,lp)
        println("VERIFIED VOLTAGE BOUNDS ",variant," ",bounds);flush(stdout)
        if lp.status==:certified_infeasible
            push!(rows,Dict("variant"=>variant,"gate_status"=>string(lp.status),"stage"=>"verified_outer_lp"))
        else
            global_result=solve_global_feasibility(p;target_bus=8,max_relaxation=0.,voltage_bound_result=lp,
                optimizer_factory=SCIP.Optimizer,time_limit=global_time_limit,silent=false,
                optimizer_attributes=Dict("numerics/feastol"=>1e-9,"limits/nodes"=>100000))
            write_feasibility_result(joinpath(out,variant*"-strict-global.json"),p,global_result.result)
            push!(rows,merge(Dict("variant"=>variant,"gate_status"=>string(global_result.result.status)),global_result.ledger))
            println("STRICT GLOBAL ",variant," ",global_result.ledger["termination_status"]," => ",global_result.result.status);flush(stdout)
        end
        write(joinpath(out,"tightening_summary.json"),TightJSON.json(rows;pretty=true))
    end
end
if abspath(PROGRAM_FILE)==@__FILE__
    run_arpae14_global_tightening()
end
