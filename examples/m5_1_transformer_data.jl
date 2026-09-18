using DroopOPF
using JSON

"""Generate M5.1 data evidence; this workflow deliberately performs no AC solve."""
function transformer_data_evidence(output)
    mkpath(output)
    fixture = joinpath(@__DIR__, "..", "test", "data", "transformer3.m")
    case = load_matpower_case(fixture)
    outage = Contingency(:transformer_out; branch_ids=[1])
    study = Study(case; contingencies=[outage], participation=Dict(1=>1.))
    write_study(joinpath(output,"study.json"),study)
    restored = read_study(joinpath(output,"study.json"))
    scenarios = [("import",case), ("copy",attach_controls(case,case.controls,case.attachments)),
                 ("JSON round trip",restored.case), ("outage",scenario_case(restored.case,outage))]
    rows = [Dict("stage"=>label,"branch_id"=>1,"from_bus"=>b.from_bus,"to_bus"=>b.to_bus,
        "expected_ratio"=>1.05,"actual_ratio"=>b.tap_ratio,
        "ratio_error"=>abs(b.tap_ratio-1.05),"expected_shift_rad"=>pi/18,
        "actual_shift_rad"=>b.phase_shift,"shift_error_rad"=>abs(b.phase_shift-pi/18),
        "expected_available"=>(label != "outage"),"available"=>b.available,
        "pass"=>(abs(b.tap_ratio-1.05)<=1e-14 && abs(b.phase_shift-pi/18)<=1e-14 &&
                  b.available == (label != "outage")))
        for (label,c) in scenarios for b in [c.network.branches[1]]]
    state = ACState(ones(3),zeros(3),[1.,.2],zeros(2))
    evidence = Dict("milestone"=>"M5.1","fixture"=>"test/data/transformer3.m",
        "provenance"=>"Synthetic data-contract fixture derived from repository case3; not a measured operating point",
        "mode"=>"fixed supplied transformer settings", "ratio_units"=>"dimensionless",
        "phase_units"=>"radians", "tap_side"=>"from", "tolerance"=>1e-14,
        "solver_status"=>"not run", "physical_validity"=>"not evaluated",
        "discrete_implementability"=>"not evaluated; no legal-position data supplied",
        "checks"=>rows,
        "pass"=>all(r["pass"] for r in rows))
    write(joinpath(output,"evidence.json"),JSON.json(evidence;pretty=true)*"\n")
    open(joinpath(output,"report.md"),"w") do io
        println(io,"# M5.1 transformer data verification\n")
        println(io,"Synthetic fixture; fixed supplied settings. Overall data checks: **",evidence["pass"] ? "PASS" : "FAIL","**.\n")
        println(io,"Ratio is dimensionless; phase is in radians. Expected ratio 1.05, phase π/18 (10°). Absolute tolerance: 1e-14.\n")
        println(io,"| Stage | Ratio | Ratio error | Phase (rad) | Phase error | Available | Pass |\n|---|---:|---:|---:|---:|---|---|")
        for r in rows
            println(io,"| ",join([r[k] for k in ("stage","actual_ratio","ratio_error","actual_shift_rad","shift_error_rad","available","pass")]," | ")," |")
        end
        println(io,"\nTransformer physics is supported by M5.2-M5.4 and verified in its separate evidence bundle.\n")
        println(io,"Solver: not run. AC feasibility and operating limits: not evaluated. Discrete implementability: unknown; no tap grid supplied. Outage preservation is checked without claiming transformer-flow validation.\n")
        println(io,"![From-side convention](transformer_orientation.svg)\n")
        println(io,"The diagram shows branch 1 only; the fixture has a third bus and alternate paths so its outage remains connected.")
    end
    write(joinpath(output,"transformer_orientation.svg"), """
    <svg xmlns="http://www.w3.org/2000/svg" width="800" height="230" viewBox="0 0 800 230">
    <rect width="800" height="230" fill="#f8fafc"/>
    <g font-family="sans-serif" fill="#172554">
    <text x="35" y="35" font-size="20">M5.1 · Supplied transformer settings</text>
    <path d="M90 90v75 M90 125h180 M365 125h330 M695 90v75" stroke="#334155" stroke-width="4" fill="none"/>
    <circle cx="295" cy="125" r="30" stroke="#2563eb" stroke-width="3" fill="#eff6ff"/>
    <circle cx="335" cy="125" r="30" stroke="#2563eb" stroke-width="3" fill="none"/>
    <text x="45" y="80" font-size="16">Bus 1 (from)</text><text x="638" y="80" font-size="16">Bus 2 (to)</text>
    <text x="190" y="185" font-size="17">From-side complex tap: a = 1.05 exp(jπ/18)</text>
    <text x="35" y="217" font-size="14">Data and orientation only · AC transformer physics follows in M5.2–M5.4</text>
    </g></svg>
    """)
    evidence["pass"] || error("M5.1 data verification failed; inspect evidence.json")
    return evidence
end

if abspath(PROGRAM_FILE) == @__FILE__
    output = isempty(ARGS) ? mktempdir() : abspath(ARGS[1])
    transformer_data_evidence(output)
    println("M5.1 evidence written to ",output)
end
