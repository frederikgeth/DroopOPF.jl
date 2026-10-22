# One original-policy bounded S1 recovery; no SCOPF or change to physical bounds.
include("s1_zero_deadband_expanded.jl")
function zd_diagnose(c,r)
    result=read_joint_design(joinpath(A500_ROOT,r["result_path"]))
    curve=DroopOPF._joint_droop_case(c,result)
    physical=with_shunt_settings(with_tap_settings(curve,result.taps),result.susceptances)
    balance=power_balance(physical,result.opf.state)
    buses=[Dict("bus"=>b.id,"p_pu"=>balance.active[i],"q_pu"=>balance.reactive[i],
        "p_mw"=>balance.active[i]*c.base_power,"q_mvar"=>balance.reactive[i]*c.base_power)
        for (i,b) in enumerate(c.network.buses)]
    sort!(buses;by=x->-max(abs(x["p_pu"]),abs(x["q_pu"])))
    Dict("worst_balance_buses"=>first(buses,5),"point_checks"=>r["point_checks"],
        "ccopt_diagnostics"=>r["ccopt_diagnostics"],"ccopt_encoding_audit"=>r["ccopt_encoding_audit"])
end
function zero_deadband_recovery()
    _,_,angles,costs,_=a500_inputs()
    base=only(filter(j->j.name=="profile-design-droop_tap_shunt-1.0-ccopt",zd_jobs()))
    failed=JSON.parsefile(joinpath(ZD_EXPANDED,"attempts",base.name*".json"))
    source=joinpath(A500_ROOT,"artifacts/s1_closeout/profile/500/attempts/retry-design-droop_tap_shunt-1.0-ccopt.json")
    old=JSON.parsefile(source);p=zd_policy(old["contract"]["policy"])
    @assert old["contract"]["initial"]==DroopOPF._feasibility_hash(base.s)
    @assert old["contract"]["case"]==DroopOPF._feasibility_case_hash(base.c)
    @assert old["contract"]["policy"]==base.old["contract"]["policy"]
    @assert old["contract"]["mu"]==1e-8 && old["contract"]["iterations"]==3000 && old["contract"]["seconds"]==120.
    out=joinpath(A500_ROOT,"artifacts/s1_zero_deadband/recovery");mkpath(out)
    before=zd_diagnose(base.c,failed);a500_save(joinpath(out,"primary_diagnosis.json"),before)
    println("DIAGNOSIS worst bus ",first(before["worst_balance_buses"]));flush(stdout)
    job=merge(base,(name="recovery-design-droop_tap_shunt-1.0-ccopt",source,old,p,
        kind="closeout-conditioned-retry",mu=old["contract"]["mu"],normalization=Symbol(old["contract"]["normalization"])))
    r=zd_attempt(job,angles,costs)
    after=haskey(r,"result_path") ? zd_diagnose(base.c,r) : nothing
    a500_save(joinpath(out,"summary.json"),Dict("attempt"=>r,"primary_diagnosis"=>before,
        "recovery_diagnosis"=>after,"direct_acceptance"=>"11/12; unchanged by this retry",
        "accepted_combinations_after_recovery"=>11+Int(r["accepted"]),
        "scope"=>"One same-point retry matching historical S1 recovery: mu_init 1e-8, 3000 iterations, 120 native solver seconds; bound push/fraction 1e-8 unchanged; original seed/policy/objective/limits/tolerances",
        "code_hashes"=>Dict(f=>bytes2hex(sha256(read(joinpath(A500_ROOT,f)))) for f in
            ("src/complementarity.jl","src/jump.jl","examples/s1_zero_deadband_recovery.jl","examples/s1_zero_deadband_expanded.jl"))))
end
abspath(PROGRAM_FILE)==(@__FILE__) && zero_deadband_recovery()
