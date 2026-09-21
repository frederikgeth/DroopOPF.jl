using DroopOPF, JSON, JuMP
include("scaling_case.jl")

function run_scaling(out;sizes=(1,4,16,32),samples=2,robust=false)
    mkpath(out);seedcase=m72_case()
    seed=solve_opf(seedcase;smooth_epsilon=1e-5,initial_state=m5_initial_state(seedcase))
    validate_equilibrium(seedcase,seed).valid || error("invalid seed")
    # Exclude compilation and first execution for both paths from measured rows.
    for free in (false,true)
        warm=optimize_joint_design(seedcase;initial_state=seed.state,(free ? scaling_policies(1) : NamedTuple())...)
        validate_joint_design(seedcase,warm)
    end
    options=robust ? Dict("max_iter"=>1000,"max_cpu_time"=>60.,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive","tol"=>1e-8) : Dict("max_iter"=>1000,"max_cpu_time"=>60.)
    epsilon=robust ? 1e-6 : 1e-5
    rows=[]
    for n in sizes
        uniform=scaling_case(n);start=scaling_start(seed.state,n)
        validate_equilibrium(uniform,start).valid || error("uniform connected witness failed")
        c=scaling_case(n;heterogeneous=true)
        write_study(joinpath(out,"study-$n.json"),Study(c))
        if robust
            fixed=optimize_joint_design(c;initial_state=start,smooth_epsilon=epsilon,optimizer_attributes=options)
            !isnothing(fixed.opf.state) && (start=fixed.opf.state)
        end
        for free in (false,true), sample in 1:samples
            row=Dict{String,Any}("modules"=>n,"buses"=>3*n,"droops"=>2*n,"transformers"=>n,"banks"=>2*n,
                "free"=>free,"sample"=>sample,"valid"=>false,"start"=>robust ? "solved heterogeneous fixed case" : "replicated feasible uniform seed; heterogeneous load perturbations ±10%")
            stamps=Dict{Symbol,Float64}();size=Dict{String,Int}()
            hook=(phase,model)->begin
                stamps[phase]=time_ns()/1e9
                if phase==:built
                    size["variables"]=num_variables(model)
                    size["constraints"]=num_constraints(model;count_variable_in_set_constraints=true)
                end
            end
            try
                begin_time=time_ns()/1e9
                measured=@timed optimize_joint_design(c;initial_state=start,(free ? scaling_policies(n) : NamedTuple())...,
                    smooth_epsilon=epsilon,optimizer_attributes=options,_measurement_hook=hook)
                r=measured.value
                checked=@timed validate_joint_design(c,r)
                merge!(row,Dict("valid"=>checked.value.valid,"status"=>string(r.opf.termination_status),
                    "build_seconds"=>stamps[:built]-begin_time,"solve_seconds"=>stamps[:solved]-stamps[:built],
                    "extract_seconds"=>stamps[:extracted]-stamps[:solved],"validation_seconds"=>checked.time,
                    "elapsed_seconds"=>measured.time,"allocated_bytes"=>measured.bytes,"process_peak_rss_bytes"=>Sys.maxrss(),
                    "model_size"=>size,"objective"=>isfinite(r.opf.objective) ? r.opf.objective : nothing,
                    "solver_valid"=>checked.value.solver_valid,"policy_valid"=>checked.value.policy_valid,
                    "physical_valid"=>!isnothing(checked.value.physical) && checked.value.physical.valid,
                    "droop_residual"=>isnothing(checked.value.physical) ? nothing : checked.value.physical.droop_residual_max,
                    "violations"=>isnothing(checked.value.physical) ? [] : string.(checked.value.physical.violations),
                    "ac_residual"=>isnothing(checked.value.physical) ? nothing : checked.value.physical.power_balance_max))
                write_joint_design(joinpath(out,"design-$n-$free-$sample.json"),r)
            catch err
                row["error"]=sprint(showerror,err)
            end
            push!(rows,row)
            write(joinpath(out,"evidence.json"),JSON.json(Dict("julia"=>string(VERSION),"package"=>string(pkgversion(DroopOPF)),"solver"=>"Ipopt","synthetic"=>true,"robust_variant"=>robust,"smooth_epsilon"=>epsilon,"optimizer_attributes"=>options,"rows"=>rows);pretty=true))
            println("modules=$n free=$free sample=$sample valid=",row["valid"]);flush(stdout)
        end
    end
    open(joinpath(out,"report.md"),"w") do io
        println(io,"Numerical variant: ",robust ? "robust: epsilon=1e-6, zero bound relaxation, adaptive barrier, heterogeneous fixed-case start" : "baseline: epsilon=1e-5, default bound relaxation/barrier, uniform feasible seed",". Reproduce the revised variant with a trailing `robust` argument.\n")
        println(io,"# S1 initial connected-network scaling experiment\n\nSynthetic connected three-bus modules, 100 MVA base. Each module has two droop generators, one transformer, one simple capacitor and one simple reactor. A chain of ties connects modules; only the first reference angle is fixed. Loads vary by 1+0.1sin(module index), so this is not independent identical island replication. A uniform-load version has an independently validated feasible witness.\n")
        println(io,"| Buses | Free controls | Sample | Valid | Build (s) | Solve (s) | Validate (s) | Variables | AC residual |\n|---|---|---:|---|---:|---:|---:|---:|---:|")
        for r in rows
            println(io,"| ",r["buses"]," | ",r["free"]," | ",r["sample"]," | ",r["valid"]," | ",get(r,"build_seconds","failed")," | ",get(r,"solve_seconds","failed")," | ",get(r,"validation_seconds","failed")," | ",get(get(r,"model_size",Dict()),"variables","—")," | ",get(r,"ac_residual","—")," |")
        end
        println(io,"\n![Scaling timing](timings.png)\n\n![Size and allocations](resources.png)\n\nAll attempts are retained. One excluded warm-up per path; two measured runs use the same declared start, so they measure repeatability, not multi-start robustness. Build includes configuration/parameter construction and model-size sampling overhead; solve includes solver setup and iterations; extraction and independent validation are separate. Allocation bytes are Julia allocations. Peak RSS is a lifetime process high-water mark, not incremental model memory. Solver budget: 1000 iterations / 60 CPU seconds per solve.\n\nThis is an initial structural stress test, not completion of the scalability gate. Next acceptance requires pinned medium public cases, physically justified control overlays, varied load/initial conditions, larger device counts and contingency-count scaling after M9. No general feasibility, runtime or global optimality guarantee follows. Discrete implementability of continuous bank outputs needs legal-state recovery and a fresh physical solve. AVR and complex-bank optimization are deferred.\n\nRun `julia --project=. examples/scaling_workflow.jl artifacts/scaling_initial` and `python3 examples/plot_scaling.py artifacts/scaling_initial`.")
    end
    rows
end
run_scaling(abspath(ARGS[1]);robust=length(ARGS)>1 && ARGS[2]=="robust")
