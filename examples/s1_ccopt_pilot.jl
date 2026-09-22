using DroopOPF, JSON
import CCOpt
include("m7_2_case.jl")
include("s1_public_controls.jl")

function s1_ccopt_attempt(out,name,case,start;policies=NamedTuple(),tags=Dict{String,Any}(),
    option_overrides=Dict{String,Any}())
    mkpath(out); diagnostic=Ref{Any}(nothing); encoding_audit=Ref{Any}(nothing)
    options=merge(m5_ccopt_options(),Dict{String,Any}("max_iter"=>1000,"max_wall_time"=>60.),option_overrides)
    row=Dict{String,Any}("name"=>name,"backend"=>"ccopt","encoding"=>"complementarity",
        "valid"=>false,"budget"=>Dict("inner_iterations"=>1000,"wall_seconds"=>60.,
        "outer_iterations"=>nothing,"note"=>"CCOpt does not expose a separate outer-homotopy budget/count through MOI"),
        "tags"=>tags)
    result=nothing
    try
        measured=@timed optimize_joint_design(case;policies...,encoding=:complementarity,
            initial_state=start,optimizer_attributes=options,
            _measurement_hook=(phase,model)->phase==:solved && begin
                diagnostic[]=ccopt_diagnostics(model)
                encoding_audit[]=ccopt_encoding_audit(model)
            end)
        result=measured.value;check=validate_joint_design(case,result)
        exact_audit=exact_droop_audit(case,result)
        write_joint_design(joinpath(out,name*"-design.json"),result)
        merge!(row,Dict("status"=>string(result.opf.termination_status),"valid"=>check.valid,
            "solver_valid"=>check.solver_valid,"policy_valid"=>check.policy_valid,
            "physical_valid"=>!isnothing(check.physical) && check.physical.valid,
            "objective"=>isfinite(result.opf.objective) ? result.opf.objective : nothing,
            "complementarity_residual"=>result.complementarity_residual_max,
            "physical"=>isnothing(check.physical) ? nothing : DroopOPF._json_data(check.physical),
            "exact_droop_audit"=>exact_audit,
            "ccopt"=>diagnostic[],"ccopt_encoding_audit"=>encoding_audit[],"elapsed_seconds"=>measured.time,
            "julia_allocated_bytes"=>measured.bytes))
    catch err
        row["error"]=sprint(showerror,err)
    end
    write(joinpath(out,name*"-diagnostics.json"),JSON.json(row;pretty=true)*"\n")
    println(name,": ",get(row,"status",get(row,"error","unknown"))," valid=",row["valid"]);flush(stdout)
    row,result
end

function s1_ccopt_pilot(out;run_public=true)
    mkpath(out);rows=[]
    synthetic=m72_case();synthetic_start=m5_initial_state(synthetic)
    synthetic_p=(tap_controls=[TapControl(11;lower=.95,upper=1.05)],
        shunt_controls=[ShuntControl(201)],droop_controls=[DroopControl(2;slope_bounds=(.04,.1))])
    for run in 1:2
        p=run==1 ? synthetic_p : s1_reseed(synthetic,synthetic_p;fraction=.8)
        state=run==1 ? synthetic_start : s1_flat(synthetic)
        row,_=s1_ccopt_attempt(out,"synthetic-joint-run$run",synthetic,state;policies=p,
            tags=Dict("matrix"=>"synthetic_joint","start"=>run))
        push!(rows,row)
    end
    if run_public
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case118_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=optimize_joint_design(original;initial_state=s1_flat(original))
        validate_joint_design(original,anchor).valid || error("IEEE 118 anchor failed validation")
        public,policies,metadata=s1_public_overlay(original,anchor,source;bank_count=12)
        write(joinpath(out,"public118-overlay.json"),JSON.json(metadata;pretty=true)*"\n")
        write_study(joinpath(out,"public118-study.json"),Study(public))
        fixed=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
        joint=(tap_controls=policies.tap_controls[1:min(1,end)],
            shunt_controls=policies.shunt_controls[1:min(1,end)],
            droop_controls=policies.droop_controls[1:min(1,end)])
        for (label,p) in (("fixed",fixed),("joint",joint)),run in 1:2
            selected=run==1 ? p : s1_reseed(public,p;fraction=.8)
            state=run==1 ? anchor.opf.state : s1_flat(public)
            row,_=s1_ccopt_attempt(out,"public118-$label-run$run",public,state;policies=selected,
                tags=Dict("matrix"=>"public118_$label","start"=>run,
                    "pilot"=>"excluded from frozen S1 acceptance counts"))
            push!(rows,row)
        end
        tight=Dict{String,Any}(
            "relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),
            "tol"=>1e-11,"acceptable_tol"=>1e-11)
        for run in 1:2
            selected=run==1 ? joint : s1_reseed(public,joint;fraction=.8)
            state=run==1 ? anchor.opf.state : s1_flat(public)
            row,_=s1_ccopt_attempt(out,"public118-joint-tight-run$run",public,state;
                policies=selected,option_overrides=tight,
                tags=Dict("matrix"=>"public118_joint_tight","start"=>run,
                    "follow_up"=>"declared after default joint attempts failed exact-droop validation",
                    "pilot"=>"excluded from frozen S1 acceptance counts"))
            push!(rows,row)
        end

        source300=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case300_ieee.m")
        original300=load_matpower_case(source300;base_frequency=60.)
        anchor300=optimize_joint_design(original300;initial_state=s1_flat(original300),
            optimizer_attributes=Dict("max_iter"=>1000,"max_cpu_time"=>60.))
        validate_joint_design(original300,anchor300).valid || error("IEEE 300 anchor failed validation")
        public300,policies300,metadata300=s1_public_overlay(original300,anchor300,source300;bank_count=32)
        write(joinpath(out,"public300-overlay.json"),JSON.json(metadata300;pretty=true)*"\n")
        write_study(joinpath(out,"public300-study.json"),Study(public300))
        fixed300=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
        joint300=(tap_controls=policies300.tap_controls[1:min(1,end)],
            shunt_controls=policies300.shunt_controls[1:min(1,end)],
            droop_controls=policies300.droop_controls[1:min(1,end)])
        for (label,p) in (("fixed",fixed300),("joint",joint300)),run in 1:2
            selected=run==1 ? p : s1_reseed(public300,p;fraction=.8)
            state=run==1 ? anchor300.opf.state : s1_flat(public300)
            row,_=s1_ccopt_attempt(out,"public300-$label-run$run",public300,state;policies=selected,
                tags=Dict("matrix"=>"public300_$label","start"=>run,
                    "pilot"=>"excluded from frozen S1 acceptance counts"))
            push!(rows,row)
        end
        for run in 1:2
            selected=run==1 ? joint300 : s1_reseed(public300,joint300;fraction=.8)
            state=run==1 ? anchor300.opf.state : s1_flat(public300)
            row,_=s1_ccopt_attempt(out,"public300-joint-tight-run$run",public300,state;
                policies=selected,option_overrides=tight,
                tags=Dict("matrix"=>"public300_joint_tight","start"=>run,
                    "follow_up"=>"same tighter settings declared after IEEE 118 standard joint failures",
                    "pilot"=>"excluded from frozen S1 acceptance counts"))
            push!(rows,row)
        end
    end
    groups=Dict{String,Any}()
    for matrix in unique(get(r["tags"],"matrix","") for r in rows)
        group=filter(r->get(r["tags"],"matrix","")==matrix,rows)
        valid=filter(r->get(r,"valid",false) && !isnothing(get(r,"objective",nothing)),group)
        groups[matrix]=Dict("attempts"=>length(group),"valid"=>length(valid),
            "objective_spread"=>length(valid)>1 ? maximum(r["objective"] for r in valid)-minimum(r["objective"] for r in valid) : nothing)
    end
    summary=Dict("scope"=>"CCOpt S1 pilot; not part of frozen Ipopt/MadNLP acceptance counts",
        "rows"=>rows,"groups"=>groups)
    write(joinpath(out,"summary.json"),JSON.json(summary;pretty=true)*"\n")
    open(joinpath(out,"report.md"),"w") do io
        println(io,"# S1 CCOpt pilot\n\nThis pilot is deliberately separate from the frozen Ipopt/MadNLP acceptance matrix. CCOpt uses a 1000 cumulative inner-iteration and 60-second native wall budget per attempt; its MOI wrapper does not expose a separate outer-homotopy count or budget.\n")
        println(io,"| Case | Status | Valid | Objective | Inner iterations | Complementarity | Primal | Dual | Seconds |\n|---|---|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows
            d=get(r,"ccopt",Dict());println(io,"| ",r["name"]," | ",get(r,"status","ERROR")," | ",r["valid"]," | ",get(r,"objective","—")," | ",get(d,"inner_iterations","—")," | ",get(r,"complementarity_residual","—")," | ",get(d,"primal_feasibility","—")," | ",get(d,"dual_feasibility","—")," | ",get(r,"elapsed_seconds","—")," |")
        end
        println(io,"\nFinal primal/dual figures are CCOpt's relaxed-NLP metrics. They are not an original-MPCC stationarity certificate. Every acceptance decision also requires independent AC, equipment-policy and exact-droop validation.")
    end
    summary
end

abspath(PROGRAM_FILE)==(@__FILE__) && s1_ccopt_pilot(abspath(ARGS[1]))
