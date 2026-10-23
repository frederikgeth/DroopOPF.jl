include("s1_arpae14_joint_sensitivity.jl")
function run_confirmation()
    out=joinpath(GATED_ROOT,"artifacts/s1_arpae14_confirmation")
    source,_,angles,_=gated_inputs();seeds=Dict();checks=[]
    for objective in ("cost","loss"),factor in (.95,1.05)
        path=joinpath(out,"opf-$objective-$factor.json");sol=JSON.parsefile(path)["solution"]
        state=ACState([sol["bus"][string(b.id)]["vm"] for b in source.network.buses],
            [sol["bus"][string(b.id)]["va"] for b in source.network.buses],
            [get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"] for g in source.generators],
            [get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"] for g in source.generators])
        c=DroopOPF._feasibility_scaled_case(source,factor)
        audit=validate_feasibility_witness(FeasibilityProblem(c;angle_limits=angles),FeasibilityWitness(state))
        audit["valid"] || error("source precursor failed")
        push!(checks,Dict("objective"=>objective,"factor"=>factor,"sha256"=>bytes2hex(sha256(read(path))),"check"=>DroopOPF._json_data(audit)))
        seeds[(objective,factor)]=state
    end
    write(joinpath(out,"source_precursors.json"),JSON.json(checks;pretty=true))
    ledger=joinpath(out,"rows.jsonl");rows=isfile(ledger) ? [JSON.parse(s) for s in readlines(ledger)] : Any[]
    done=Set(r["name"] for r in rows)
    for profile in ("uniform8","mixed24842"),width in (0.,.005,.01)
        config="zero_q_shifted-loss-$profile-db$width"
        original=joinpath(GATED_ROOT,"artifacts/s1_arpae14_matched_sensitivity","$config-study.json")
        c=read_study(original).case
        cp(original,joinpath(out,"$config-study.json");force=true)
        for objective in ("cost","loss"),factor in (.95,1.05),solver in (:ipopt,:madnlp,:ccopt)
            name="$config-init$objective-load$factor-$solver";name in done && continue
            tags=Dict("config"=>config,"profile"=>profile,"deadband_total_width_pu"=>width,"factor"=>factor,"initialization_objective"=>objective,"calibration_objective"=>"loss","definition"=>"zero_q_shifted","start"=>"demand_matched_opf")
            row=js_cell(DroopOPF._feasibility_scaled_case(c,factor),seeds[(objective,factor)],angles,solver,tags;reactive_epsilon=1e-6)
            row["name"]=name;row["case_sha256"]=bytes2hex(sha256(read(original)))
            open(ledger,"a") do io;println(io,JSON.json(row));end
            push!(rows,row);push!(done,name)
            println("CONFIRM ",length(rows),"/72 ",name," verified=",row["point_pass"]," accepted=",row["accepted"]);flush(stdout)
        end
    end
    @assert length(rows)==72
    println("CONFIRMATION COMPLETE verified=",count(r->r["point_pass"],rows)," accepted=",count(r->r["accepted"],rows))
end
abspath(PROGRAM_FILE)==(@__FILE__) && run_confirmation()
