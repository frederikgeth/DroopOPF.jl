# Deterministic preventive recovery: supplied tap ratios and nearest legal bank state.
include("p2_preventive_controls.jl")
function pr_discrete(root)
    parent=joinpath(root,"bank_fixture");out=joinpath(parent,"rounded_candidate")
    ispath(out) && error("Preserve prior recovery evidence");mkpath(out)
    source=read_study(joinpath(parent,"source.json")).case
    selected=read_study(joinpath(parent,"preventive/primary/study-1.0.json"))
    witness=read_scopf_result(joinpath(parent,"preventive/primary/result-1.0.json"))
    taps=Dict(b.id=>b.tap_ratio for b in source.network.branches if haskey(witness.tap_settings[:base],b.id))
    bank_states=Dict{Int,Any}();susceptance=Dict{Int,Float64}()
    for bank in source.network.banks
        haskey(witness.shunt_settings[:base],bank.id) || continue
        values=[sum(n*b for (n,b) in zip(state,bank.step_susceptances)) for state in bank.legal_states]
        index=argmin(abs.(values.-witness.shunt_settings[:base][bank.id]))
        bank_states[bank.id]=bank.legal_states[index];susceptance[bank.id]=values[index]
    end
    fixed=with_shunt_settings(with_tap_settings(selected.case,taps),susceptance)
    prsave(joinpath(out,"protocol.json"),(;rule="supplied taps; nearest legal bank state by susceptance, chosen without held-out outcomes",
        taps,bank_states,susceptance,factors=sort([PR_TRAIN;PR_HOLD]),source_hash=prhash(@__FILE__),
        controls="accepted preventive curves frozen; no per-demand or post-outage equipment changes"))
    rows=Any[]
    for factor in sort([PR_TRAIN;PR_HOLD])
        study=Study(DroopOPF._feasibility_scaled_case(fixed,factor);contingencies=selected.contingencies)
        nearest=PR_TRAIN[argmin(abs.(PR_TRAIN.-factor))]
        seed=read_scopf_result(joinpath(parent,"preventive/primary/result-$nearest.json"))
        result=solve_scopf(study;smooth_epsilon=PR_EPS,sparse_balance=true,initial_states=seed.states,
            optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>1500,"max_cpu_time"=>30.,"bound_relax_factor"=>0.))
        report=equilibrium_report(study,result)
        dir=joinpath(out,string(factor),"primary");mkpath(dir)
        write_study(joinpath(dir,"study.json"),study);write_scopf_result(joinpath(dir,"result.json"),result)
        prsave(joinpath(dir,"validation.json"),report)
        row=(;factor,valid=report.valid,status=result.termination_status,
            loss_mw=isnothing(result.states[:base]) ? NaN : (sum(result.states[:base].pg)-sum(l.p for l in study.case.loads))*study.case.base_power)
        push!(rows,row);prsave(joinpath(out,"summary.json"),rows)
        println("ROUND ",factor," ",row.status," ",row.valid);flush(stdout)
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && pr_discrete(abspath(ARGS[1]))
