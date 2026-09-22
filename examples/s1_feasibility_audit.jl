using JSON

function s1_feasibility_audit(summary_path,out)
    parsed=JSON.parsefile(summary_path)
    rows=parsed isa AbstractVector ? parsed : parsed["rows"]
    groups=Dict{String,Any}()
    for n in (118,300)
        baseline=only(filter(r->r["name"]=="public$n-baseline",rows))
        groups["public$(n)_baseline"]=Dict("attempts"=>1,"validated_witnesses"=>baseline["valid"] ? 1 : 0,
            "feasibility_established"=>baseline["valid"],"witnesses"=>baseline["valid"] ? [baseline["name"]] : String[])
        for load in ("1.0","1.05")
            prefix="public$n-load$load-"
            attempts=filter(r->startswith(r["name"],prefix),rows)
            witnesses=[r["name"] for r in attempts if get(r,"valid",false)]
            solved_invalid=count(r->get(r,"status","") in ("LOCALLY_SOLVED","ALMOST_LOCALLY_SOLVED") && !get(r,"valid",false),attempts)
            numerical=count(r->!(get(r,"status","") in ("LOCALLY_SOLVED","ALMOST_LOCALLY_SOLVED")),attempts)
            key="public$(n)_load$(load)"
            groups[key]=Dict("attempts"=>length(attempts),"validated_witnesses"=>length(witnesses),
                "feasibility_established"=>!isempty(witnesses),"witnesses"=>witnesses,
                "numerical_or_iteration_failures"=>numerical,"converged_but_rejected"=>solved_invalid,
                "stress"=>load=="1.05" ? "+5% active and reactive demand with unchanged generation/control bounds" : "nominal demand")
        end
    end
    all_feasible=all(g["feasibility_established"] for g in values(groups))
    audit=Dict("all_groups_have_validated_witness"=>all_feasible,"groups"=>groups,
        "scope"=>"local feasibility witnesses for the DroopOPF imported-network/dispatch-deviation model",
        "not_claimed"=>["global optimality","uniqueness","reproduction of PGLib generation-cost objective","enforcement of source branch angle limits","feasibility beyond the tested nominal and +5% load points"],
        "interpretation"=>"Once a group has a validated witness, another failed start/backend attempt for the same case is convergence or acceptance sensitivity, not evidence that the case is infeasible.")
    mkpath(out);write(joinpath(out,"summary.json"),JSON.json(audit;pretty=true)*"\n")
    open(joinpath(out,"report.md"),"w") do io
        println(io,"# S1 feasibility and stress audit\n")
        println(io,"Every audited group has an independently validated witness: **",all_feasible,"**. These are local feasibility witnesses for DroopOPF's model, not global-optimality certificates or reproduction of the source PGLib objective.\n")
        println(io,"| Group | Attempts | Validated witnesses | Numerical/iteration failures | Converged but rejected | Feasibility established |\n|---|---:|---:|---:|---:|---:|")
        for key in sort(collect(keys(groups)))
            g=groups[key];println(io,"| ",key," | ",g["attempts"]," | ",g["validated_witnesses"]," | ",get(g,"numerical_or_iteration_failures",0)," | ",get(g,"converged_but_rejected",0)," | ",g["feasibility_established"]," |")
        end
        println(io,"\nThe +5% cases scale both active and reactive demand while retaining the same network, generator bounds and synthetic controller envelopes. They test numerical robustness under reduced operating margin and changed active sets. Because both stressed networks have validated witnesses, failed attempts expose start/backend/formulation sensitivity at that stress point; they do not establish physical infeasibility. The audit does not locate a loadability boundary.")
    end
    all_feasible || error("one or more public groups lacks a validated feasibility witness")
    audit
end

abspath(PROGRAM_FILE)==(@__FILE__) && s1_feasibility_audit(abspath(ARGS[1]),abspath(ARGS[2]))
