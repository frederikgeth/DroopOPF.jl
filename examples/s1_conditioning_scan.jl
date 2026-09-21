include("s1_public_recovery.jl")
struct S1ScanComplete <: Exception end

function s1_jacobian_scan(case,state,policies;epsilon=1e-6)
    report=Dict{String,Any}()
    function capture(phase,model)
        phase==:built || return
        evaluator=JuMP.NLPEvaluator(model);moi=JuMP.MOI
        moi.initialize(evaluator,[:Jac])
        variables=all_variables(model);x=Float64[start_value(v) for v in variables]
        structure=moi.jacobian_structure(evaluator);entries=zeros(length(structure))
        moi.eval_constraint_jacobian(evaluator,entries,x)
        rows=zeros(JuMP.num_nonlinear_constraints(model));columns=zeros(length(variables))
        for ((i,j),v) in zip(structure,entries)
            rows[i]=max(rows[i],abs(v));columns[j]=max(columns[j],abs(v))
        end
        report["columns"]=[Dict("name"=>name(v),"max_absolute_derivative"=>columns[i],
            "fixed"=>is_fixed(v) || (has_lower_bound(v) && has_upper_bound(v) && lower_bound(v)==upper_bound(v))) for (i,v) in enumerate(variables)]
        report["row_max_absolute_derivative"]=rows
        report["jacobian_nonzeros"]=length(entries)
        report["all_finite"]=all(isfinite,entries)
        report["epsilon"]=epsilon
        report["scope"]="Raw nonlinear-constraint Jacobian in physical variable units at this point; derivative scale ranges are not a KKT condition number"
        throw(S1ScanComplete())
    end
    try
        optimize_joint_design(case;initial_state=state,policies...,smooth_epsilon=epsilon,_measurement_hook=capture)
    catch err
        err isa S1ScanComplete || rethrow()
    end
    report
end

function s1_conditioning_scan(out)
    mkpath(out)
    source_out=joinpath(@__DIR__,"..","artifacts","s1_public_controls")
    for n in (118,300)
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(source_out,"public$n-baseline-design.json"))
        case,p,_=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
        selected=n==118 ? "public118-load1.0-ipopt-flat_high-design.json" : "public300-load1.0-madnlp-anchor-design.json"
        solved=read_joint_design(joinpath(source_out,selected))
        for (label,result) in (("anchor",anchor),("validated",solved))
            state=result.opf.state
            policy=label=="anchor" ? p : s1_reseed(case,p;result)
            data=s1_jacobian_scan(case,state,policy)
            physical=with_joint_settings(case,result)
            flows=branch_flows(physical.network,state)
            data["operating_point"]=Dict("bus_ids"=>[b.id for b in case.network.buses],
                "vm"=>state.vm,"vmin"=>[b.v_min for b in case.network.buses],"vmax"=>[b.v_max for b in case.network.buses],
                "max_terminal_loading"=>[max(abs(flows.from[i]),abs(flows.to[i]))/b.thermal_limit for (i,b) in enumerate(physical.network.branches)],
                "source_design"=>label=="anchor" ? "public$n-baseline-design.json" : selected)
            write(joinpath(out,"public$n-$label.json"),JSON.json(data;pretty=true))
            println("Jacobian scan: public$n $label")
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_conditioning_scan(abspath(ARGS[1]))
