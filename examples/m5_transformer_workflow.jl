using DroopOPF, JSON, MadNLP
include("m5_transformer_case.jl")

# Independent scalar polar reference, separate from both Ybus and current evaluation.
function m5_polar_reference(r,x,bc,tau,phi,vf,vt,delta)
    g,b=r/(r*r+x*x),-x/(r*r+x*x)
    d=delta-phi; cross=vf*vt/tau
    pf=g*vf^2/tau^2-cross*(g*cos(d)+b*sin(d))
    qf=-(b+bc/2)*vf^2/tau^2-cross*(g*sin(d)-b*cos(d))
    pt=g*vt^2-cross*(g*cos(d)-b*sin(d))
    qt=-(b+bc/2)*vt^2+cross*(g*sin(d)+b*cos(d))
    return [pf,qf,pt,qt]
end

function m5_transformer_workflow(output; python=get(ENV,"PYTHON","python3"))
    mkpath(output)
    sweeps=Dict{String,Any}()
    for (name,grid) in (("ratio",collect(range(.9,1.1;length=21))),
                          ("phase",collect(range(-.15,.15;length=21))))
        rows=[]
        for value in grid
            tau,phi=name=="ratio" ? (value,0.) : (1.02,value)
            branch=Branch(1,1,2;resistance=.01,reactance=.1,charging=.02,
                thermal_limit=3.,tap_ratio=tau,phase_shift=phi)
            net=ACNetwork([Bus(1),Bus(2)],[branch])
            state=ACState([1.03,.98],[.07,0.],Float64[],Float64[])
            f=branch_flows(net,state)
            actual=[real(f.from[1]),imag(f.from[1]),real(f.to[1]),imag(f.to[1])]
            expected=m5_polar_reference(.01,.1,.02,tau,phi,1.03,.98,.07)
            push!(rows,Dict("x"=>value,"actual"=>actual,"reference"=>expected,
                "max_error"=>maximum(abs,actual-expected),"pass"=>maximum(abs,actual-expected)<1e-12))
        end
        sweeps[name]=rows
    end
    study=m5_transformer_study()
    write_study(joinpath(output,"study.json"),study)
    records=[]; panels=[]
    for (label,st,kwargs) in [("preventive_ipopt",study,(;)),
        ("preventive_madnlp",study,(optimizer_factory=MadNLP.Optimizer,)),
        ("preventive_ccopt",study,(encoding=:complementarity,optimizer_attributes=m5_ccopt_options())),
        ("corrective_ipopt",m5_transformer_study(mode=:corrective),(;))]
        try
            result=solve_scopf(st;smooth_epsilon=1e-5,initial_states=m5_initial_states(st),kwargs...)
            report=equilibrium_report(st,result)
            write_scopf_result(joinpath(output,label*"_result.json"),result)
            write_scopf_report(joinpath(output,label*"_validation.json"),report)
            write(joinpath(output,label*"_report.md"),markdown_report(report))
            push!(records,Dict("name"=>label,"status"=>string(result.termination_status),
                "pass"=>report.valid,"objective"=>result.objective,
                "ac_max"=>maximum(r.power_balance_max for r in values(report.scenarios)),
                "exact_droop_max"=>maximum(r.droop_residual_max for r in values(report.scenarios))))
            if label=="preventive_ipopt" && all(!isnothing(s) for s in values(result.states))
                write_scopf_voltage_plot(joinpath(output,"voltage.svg"),st,result;title="M5 fixed-transformer SCOPF voltages")
                write_scopf_droop_plot(joinpath(output,"droop.svg"),st,result;title="M5 exact droop validation")
                write_scopf_residual_plot(joinpath(output,"residuals.svg"),st,result;title="M5 independent residual checks")
                for (id,c) in zip([:base;[x.id for x in st.contingencies]],
                                  [st.case;[scenario_case(st.case,x) for x in st.contingencies]])
                    state=result.states[id]; f=branch_flows(c.network,state)
                    push!(panels,Dict("scenario"=>string(id),"vm"=>state.vm,
                        "bus_ids"=>[b.id for b in c.network.buses],
                        "branch_ids"=>[b.id for b in c.network.branches],
                        "from_abs"=>abs.(f.from),"to_abs"=>abs.(f.to),
                        "ratings"=>[b.thermal_limit for b in c.network.branches]))
                end
                design=optimize_droop_parameters(st,2;slope_bounds=(.04,.10),
                    reference_result=result,smooth_epsilon=1e-5)
                write_droop_design(joinpath(output,"droop_design.json"),design)
                push!(records,Dict("name"=>"bounded_slope_design","status"=>string(design.result.termination_status),
                    "pass"=>validate_droop_design(st,design).valid &&
                        with_droop_settings(st,design).case.network.branches == st.case.network.branches,
                    "slope"=>design.settings.slope))
                for (corruption_label,bad) in (("wrong_ratio",m5_transformer_case(tap=1.)),
                                    ("wrong_phase_sign",m5_transformer_case(phase=-.02)))
                    invalid=validate_equilibrium(bad,result.states[:base])
                    push!(records,Dict("name"=>corruption_label,"status"=>"deliberate corruption",
                        "pass"=>!invalid.valid && invalid.power_balance_max>1e-3,
                        "ac_max"=>invalid.power_balance_max))
                end
            end
        catch error
            push!(records,Dict("name"=>label,"status"=>"ERROR","pass"=>false,"error"=>sprint(showerror,error)))
        end
    end
    evidence=Dict("milestone"=>"M5.2-M5.4","provenance"=>"Synthetic analytical and meshed droop fixtures; not measured data",
        "convention"=>"a=tau*exp(j*phi) on from side; terminal powers positive into branch",
        "initialization"=>"Declared proportional-regime starts: vm=[.98,.98,.95], va=[0,-.01,-.04]; available-generation sharing with exact droop Q at .98 pu. Not a measured state.",
        "settings"=>Dict("tap_ratio"=>1.02,"phase_shift_rad"=>.02,"mode"=>"fixed"),
        "ccopt_configuration"=>Dict("relaxation"=>"ProportionalRelaxationUpdate","sigma_min"=>1e-12,"tol"=>1e-9,"acceptable_tol"=>1e-9,"bound_relax_factor"=>0.),
        "tolerances"=>Dict("analytical"=>1e-12,"ac"=>1e-6,"exact_droop"=>1e-5),
        "sweeps"=>sweeps,"runs"=>records,"scenarios"=>panels,
        "pass"=>all(r["pass"] for r in records) && all(r["pass"] for rows in values(sweeps) for r in rows))
    write(joinpath(output,"evidence.json"),JSON.json(evidence;pretty=true)*"\n")
    open(joinpath(output,"report.md"),"w") do io
        println(io,"# M5 transformer validation\n\nSynthetic fixtures; fixed ratio and phase. Overall numerical checks: **",evidence["pass"] ? "PASS" : "FAIL","**.\n")
        println(io,"M5.2 compares both terminal P/Q against a scalar polar reference over 21 ratios; M5.3 repeats over 21 signed phase shifts. Absolute tolerance: 1e-12 pu.\n")
        println(io,"| Run/check | Status | Pass |\n|---|---|---|")
        for r in records
            println(io,"| ",r["name"]," | ",r["status"]," | ",r["pass"]," |")
            haskey(r,"error") && println(io,"\nFailure: ",r["error"],"\n")
        end
        println(io,"\nM5.4 checks base, transformer-outage, line-outage and generator-outage states; exact droop tolerance 1e-5, AC tolerance 1e-6. Both terminal apparent powers are checked against the same rating. Wrong-ratio and wrong-phase-sign checks pass only when the corrupted model fails validation.\n")
        println(io,"![Analytical comparisons](reference_sweeps.png)\n\n![Both terminal loadings](terminal_loadings.png)\n\n![Voltages](voltage.svg)\n\n![Exact droop](droop.svg)\n\n![Residuals](residuals.svg)\n")
        println(io,"CCOpt uses ProportionalRelaxationUpdate with sigma_min=1e-12, tol=acceptable_tol=1e-9 and bound_relax_factor=0; the default relaxation failed exact-droop validation on this fixture. Validation tolerances are unchanged.\n")
        println(io,"Declared proportional-regime starts are used for all runs. Flat 1 pu starts can stall in the droop deadband; convergence from arbitrary starts is not established.\n")
        println(io,"Fixed settings are supplied data, not optimized schedules. No tap grid, automatic AVR, switching trajectory, global optimality or dynamic security is claimed. JSON records retain numerical results and failed attempts. Analytical fixtures and both-end thermal rejection tests are in test/test_transformer_physics.jl.")
    end
    # Plotting dependency stays outside the package core. Set PYTHON to a Python
    # installation with Matplotlib; numerical JSON is retained if plotting fails.
    run(`$python $(joinpath(@__DIR__,"plot_m5_transformer.py")) $output`)
    evidence["pass"] || error("M5 validation failed; inspect report.md and evidence.json")
    return evidence
end

if abspath(PROGRAM_FILE)==@__FILE__
    output=isempty(ARGS) ? mktempdir() : abspath(ARGS[1])
    m5_transformer_workflow(output)
    println("M5 evidence written to ",output)
end
