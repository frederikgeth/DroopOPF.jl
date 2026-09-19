using DroopOPF, JSON

function m61_case(shunts)
    Case("m61-one-bus";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(10;reference=true,v_min=.8,v_max=1.2)],Branch[];shunts=shunts),
        generators=[Generator(7,10;p_min=0.,p_max=2.,q_min=-1.,q_max=1.,initial_p=.5,initial_q=.1)],
        loads=[Load(3,10;p=.5,q=.3)],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
end

"""M6.1 analytical/import evidence. No switched banks or security study is claimed."""
function fixed_shunt_evidence(output;python=get(ENV,"PYTHON","python3"))
    mkpath(output)
    rows=[]; negative=[]
    for (name,b) in (("capacitor",.2),("reactor",-.2),("conductance",0.)), v in range(.8,1.2;length=21)
        shunt=FixedShunt(8,10;conductance=.04,susceptance=b)
        case=m61_case([shunt])
        state=ACState([v],[0.],[.5+.04*v^2],[.3-b*v^2])
        actual=only(shunt_powers(case.network,state))
        expected=complex(.04*v^2,-b*v^2)
        report=validate_equilibrium(case,state)
        push!(rows,Dict("equipment"=>name,"voltage_pu"=>v,"g_pu"=>.04,"b_pu"=>b,
            "expected_p"=>real(expected),"actual_p"=>real(actual),
            "expected_q"=>imag(expected),"actual_q"=>imag(actual),
            "absolute_error"=>abs(actual-expected),"ac_residual"=>report.power_balance_max,
            "pass"=>abs(actual-expected)<1e-14 && report.valid))
    end
    shunt=FixedShunt(8,10;conductance=.04,susceptance=.2)
    state=ACState([1.],[0.],[.54],[.1])
    for (name,shunts) in (("omitted",FixedShunt[]),
        ("double-counted",[shunt,FixedShunt(9,10;conductance=.04,susceptance=.2)]),
        ("wrong B sign",[FixedShunt(8,10;conductance=.04,susceptance=-.2)]))
        report=validate_equilibrium(m61_case(shunts),state)
        push!(negative,Dict("case"=>name,"ac_residual"=>report.power_balance_max,
            "violations"=>string.(report.violations),"pass"=>!report.valid && report.power_balance_max>1e-6))
    end
    unavailable=m61_case([FixedShunt(8,10;conductance=.04,susceptance=.2,available=false)])
    off=validate_equilibrium(unavailable,ACState([1.],[0.],[.5],[.3]))
    fixture=joinpath(@__DIR__,"..","test","data","shunt3.m")
    imported=load_matpower_case(fixture)
    imports=[]
    for (s,gs,bs) in zip(imported.network.shunts,[2.,0.],[10.,-5.])
        push!(imports,Dict("bus_id"=>s.bus_id,"shunt_id"=>s.id,"GS_MW_at_1pu"=>gs,
            "BS_MVAr_at_1pu"=>bs,"baseMVA"=>100.,"expected_g"=>gs/100,
            "expected_b"=>bs/100,"actual_g"=>s.conductance,"actual_b"=>s.susceptance,
            "pass"=>s.conductance==gs/100 && s.susceptance==bs/100))
    end
    write_study(joinpath(output,"study.json"),Study(imported))
    preservation=read_study(joinpath(output,"study.json")).case.network.shunts == imported.network.shunts
    example=m61_case([shunt]); solved=solve_opf(example)
    solver_report=validate_equilibrium(example,solved)
    evidence=Dict("milestone"=>"M6.1","provenance"=>"Synthetic analytical one-bus and MATPOWER three-bus fixtures",
        "convention"=>"P=G*V^2 and Q=-B*V^2 are consumption; B>0 is capacitive injection",
        "tolerances"=>Dict("analytical"=>1e-14,"ac"=>1e-6),
        "fixed_mode"=>true,"banks"=>"not modeled","sweeps"=>rows,
        "negative_checks"=>negative,"imports"=>imports,"round_trip_pass"=>preservation,
        "unavailable_pass"=>off.valid && only(shunt_powers(unavailable.network,state))==0,
        "opf"=>Dict("status"=>string(solved.termination_status),"pass"=>solver_report.valid,
            "ac_residual"=>solver_report.power_balance_max),
        "pass"=>all(x["pass"] for x in rows) && all(x["pass"] for x in negative) &&
            all(x["pass"] for x in imports) && preservation && off.valid && solver_report.valid &&
            solved.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED))
    write(joinpath(output,"evidence.json"),JSON.json(evidence;pretty=true)*"\n")
    open(joinpath(output,"report.md"),"w") do io
        println(io,"# M6.1 fixed-shunt verification\n\nOverall checks: **",evidence["pass"] ? "PASS" : "FAIL","**.\n")
        println(io,"Fixed admittance is separate from loads and branch charging. Consumption is P=GV², Q=−BV²; B>0 is capacitive. All powers and admittances below are per unit unless labelled otherwise. No discrete positions are inferred.\n")
        println(io,"## Import conversion\n\nBase power: 100 MVA. GS is MW consumed at 1 pu; BS is MVAr injected at 1 pu.\n")
        println(io,"| Bus / shunt ID | GS | BS | Expected / actual G | Expected / actual B | Pass |\n|---|---:|---:|---|---|---|")
        for row in imports
            println(io,"| ",row["bus_id"]," | ",row["GS_MW_at_1pu"]," | ",row["BS_MVAr_at_1pu"]," | ",row["expected_g"]," / ",row["actual_g"]," | ",row["expected_b"]," / ",row["actual_b"]," | ",row["pass"]," |")
        end
        println(io,"\n63 voltage/equipment checks over 0.8–1.2 pu; maximum analytical error: ",maximum(r["absolute_error"] for r in rows)," pu (tolerance 1e-14). Independent AC residual tolerance: 1e-6 pu.\n")
        println(io,"![Voltage-squared power curves](shunt_voltage_curves.png)\n")
        println(io,"## Adversarial accounting checks\n\nThese cases must fail physical validation; a passing test means the error was detected.\n")
        println(io,"| Corruption | AC residual | Detected |\n|---|---:|---|")
        for row in negative
            println(io,"| ",row["case"]," | ",row["ac_residual"]," | ",row["pass"]," |")
        end
        println(io,"\n![Corruption detection](accounting_checks.png)\n")
        println(io,"Unavailable-device check: ",evidence["unavailable_pass"],". Study v4 round trip: ",preservation,". Basic one-bus OPF: ",solved.termination_status,", physical validation: ",solver_report.valid,".\n")
        println(io,"The OPF check exercises the shared fixed-admittance Ybus path. It does not complete M6.3 security-constrained/matched-study validation. Switched-bank evidence is in the M6.2/M6.3 workflow; optimization and AVR remain later milestones. Inputs are synthetic, not observations of a real system.")
    end
    run(`$python $(joinpath(@__DIR__,"plot_m6_1_shunts.py")) $output`)
    evidence["pass"] || error("M6.1 verification failed; inspect evidence.json")
    evidence
end

if abspath(PROGRAM_FILE)==@__FILE__
    output=isempty(ARGS) ? mktempdir() : abspath(ARGS[1])
    fixed_shunt_evidence(output)
    println("M6.1 evidence written to ",output)
end
