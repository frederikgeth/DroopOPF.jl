using DroopOPF, JSON
include("m6_shunt_case.jl")
out=abspath(ARGS[1]); mkpath(out)
rows=[]; runs=[]
for counts in m6_bank().legal_states, v in (.9,1.,1.1)
    bank=with_bank_state(m6_bank(),counts)
    net=ACNetwork([Bus(30;reference=true)],Branch[];banks=[bank])
    actual=only(bank_powers(net,ACState([v],[.2],Float64[],Float64[])))
    expected=complex(.001*counts[1]+.0005*counts[2],-(.02*counts[1]-.01*counts[2]))*v^2
    push!(rows,Dict("state"=>collect(counts),"v"=>v,"p"=>real(actual),"q"=>imag(actual),"error"=>abs(actual-expected)))
end
for counts in ((0,0),(1,0),(2,0))
    study=m6_shunt_study(state=counts)
    result=solve_scopf(study;smooth_epsilon=1e-5,initial_states=m5_initial_states(study))
    report=equilibrium_report(study,result)
    tag=join(counts,"-")
    write_study(joinpath(out,"study-$tag.json"),study)
    write_scopf_result(joinpath(out,"result-$tag.json"),result)
    scenarios=[]
    for (id,c) in zip([:base;[o.id for o in study.contingencies]], [study.case;[scenario_case(study.case,o) for o in study.contingencies]])
        s=result.states[id]; f=branch_flows(c.network,s)
        qload=sum(l.q for l in c.loads)
        fixed=imag(sum(shunt_powers(c.network,s))); bank=imag(sum(bank_powers(c.network,s)))
        branch=imag(sum(f.from)+sum(f.to)); gen=sum(s.qg)
        push!(scenarios,Dict("id"=>string(id),"vm"=>s.vm,"qgen"=>gen,"qload"=>qload,"qfixed"=>fixed,"qbank"=>bank,"qbranch"=>branch,
            "qerror"=>abs(gen-qload-fixed-bank-branch),"ac_residual"=>maximum(abs,power_balance(c,s).vector)))
    end
    push!(runs,Dict("state"=>collect(counts),"status"=>string(result.termination_status),"objective"=>result.objective,"valid"=>report.valid,"scenarios"=>scenarios))
end
passed=all(r["error"]<1e-14 for r in rows) && all(r["valid"] && r["status"] in ("LOCALLY_SOLVED","ALMOST_LOCALLY_SOLVED") for r in runs)
write(joinpath(out,"evidence.json"),JSON.json(Dict("pass"=>passed,"bank_sweep"=>rows,"runs"=>runs);pretty=true))
open(joinpath(out,"report.md"),"w") do io
    println(io,"# M6 shunt reference verification\n\nOverall numerical checks: **",passed ? "PASS" : "FAIL","**. Synthetic three-bus system, 100 MVA base. Fixed transformer ratios and fixed droop settings are identical across compared bank states. Each SCOPF covers base, transformer outage, line outage and generator outage.\n")
    println(io,"Supplied bank states are step-count tuples. Legal states: (0,0), (1,0), (2,0), (0,1), (1,1). Step admittances: 0.001+j0.02 and 0.0005−j0.01 pu. Nominal state: (1,0). Fixed shunt: 0.002+j0.01 pu. Positive Q below denotes consumption. No switching trajectory or optimized bank schedule is claimed.\n")
    println(io,"![Legal bank states](bank_states.png)\n\n![Matched SCOPF voltages](voltage_profiles.png)\n\n![Reactive accounting](reactive_balance.png)\n")
    println(io,"| Bank state | Solver status | Objective | Independent valid | Maximum AC residual (pu) |\n|---|---|---:|---|---:|")
    for r in runs
        println(io,"| ",r["state"]," | ",r["status"]," | ",r["objective"]," | ",r["valid"]," | ",maximum(s["ac_residual"] for s in r["scenarios"])," |")
    end
    println(io,"\nAnalytical bank sweep tolerance: 1e-14 pu; independent AC tolerance: 1e-6 pu. Ipopt smooth droop epsilon: 1e-5; declared proportional-regime starts from `m5_initial_states`. Study and result JSON files accompany each run.\n\nThe regression suite additionally checks invalid/unavailable states, immutable metadata, schema migration, zero-shunt equivalence, omitted bank rejection, MadNLP and CCOpt agreement, corrective SCOPF and bounded droop design. See [regression log](regression-tests.txt) and [fixed-shunt/import evidence](../m6_1/report.md). Equipment optimization remains M7; automatic controls remain later milestones.")
end
passed || error("M6 numerical checks failed")

println("Numerical report written to ", out, ". Generate plots with: python3 examples/plot_m6_shunts.py ", out)
