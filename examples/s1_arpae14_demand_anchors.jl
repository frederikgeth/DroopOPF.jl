# Compare demand-matched source OPF seeds under unchanged S1 droop equations.
include("s1_arpae14_gated.jl")
function demand_anchor_matrix(;out=joinpath(GATED_ROOT,"artifacts/s1_arpae14_demand_anchors"),start_label="demand_anchor",seed_objective="source economic cost")
    mkpath(out)
    source,original_anchor,angles,candidates=gated_inputs()
    empty=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
    rows=[];checks=[]
    for factor in GATED_FACTORS
        sol=JSON.parsefile(joinpath(out,"opf-$factor.json"))["solution"]
        seed=ACState([sol["bus"][string(b.id)]["vm"] for b in source.network.buses],
            [sol["bus"][string(b.id)]["va"] for b in source.network.buses],
            [get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"] for g in source.generators],
            [get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"] for g in source.generators])
        scaled=DroopOPF._feasibility_scaled_case(source,factor)
        p=FeasibilityProblem(scaled;angle_limits=angles)
        gate=check_feasibility(p;witnesses=[FeasibilityWitness(seed)],solve_missing=false)
        write_feasibility_result(joinpath(out,"source-$factor-gate.json"),p,gate)
        gate.status==:feasible || error("demand OPF fails independent source replay at $factor")
        write(joinpath(out,"seed-$factor.json"),JSON.json(DroopOPF._json_data(seed);pretty=true))
        for variant in ("no_deadband","with_deadband")
            nominal=candidates[variant];c=DroopOPF._feasibility_scaled_case(nominal,factor)
            initcheck=validate_feasibility_witness(gated_problem(c,empty,angles),FeasibilityWitness(seed))
            push!(checks,Dict("factor"=>factor,"variant"=>variant,"source_gate"=>string(gate.status),"initial_droop_case_check"=>DroopOPF._json_data(initcheck)))
            for solver in (:ipopt,:madnlp,:ccopt)
                name="$variant-$factor-fixed-$start_label-$solver"
                row=gated_cell(out,name,c,seed,solver,empty,angles,original_anchor,nominal;
                    tags=Dict("variant"=>variant,"factor"=>factor,"family"=>"fixed","start"=>start_label,"seed_objective"=>seed_objective,"droop_calibration"=>"original 100% source OPF; unchanged"))
                push!(rows,row)
                write(joinpath(out,"matrix_summary.json"),JSON.json(rows;pretty=true))
            end
        end
    end
    write(joinpath(out,"precursor_checks.json"),JSON.json(checks;pretty=true))
    println("DEMAND ANCHOR COMPLETE ",length(rows)," cells, verified ",count(r->get(r,"point_pass",false),rows));flush(stdout)
end
abspath(PROGRAM_FILE)==(@__FILE__) && demand_anchor_matrix()
