include("s1_kkt_matrix.jl")
struct S1GeometryDone <: Exception end
function s1_kkt_geometry(case,p,snapshot)
    result=Dict{String,Any}()
    function hook(phase,model)
        phase==:built || return
        variables=all_variables(model);stored=snapshot["variables"]
        name.(variables)==[v["name"] for v in stored] || error("variable layout mismatch")
        x=Float64[v["value"] for v in stored]
        evaluator=JuMP.NLPEvaluator(model);JuMP.MOI.initialize(evaluator,[:Jac])
        structure=JuMP.MOI.jacobian_structure(evaluator);entries=zeros(length(structure))
        JuMP.MOI.eval_constraint_jacobian(evaluator,entries,x)
        J=sparse(first.(structure),last.(structure),entries,length(snapshot["nonlinear_rows"]),length(x))
        lambda=Float64[r["dual"] for r in snapshot["nonlinear_rows"]]
        magnitude=abs.(J)'*abs.(lambda)+abs.([v["objective_gradient"] for v in stored])
        nlset=Set(all_nonlinear_constraints(model));regular=[c for c in all_constraints(model;include_variable_in_set_constraints=true) if !(c in nlset)]
        length(regular)==length(snapshot["regular_rows"]) || error("regular layout mismatch")
        for (c,r) in zip(regular,snapshot["regular_rows"])
            string(c)==r["constraint"] || error("regular constraint mismatch")
            magnitude .+= abs(r["dual"]).*abs.(s1_polynomial_gradient(constraint_object(c).func,variables,x))
        end
        result["cancellation"]=[Dict("name"=>v["name"],"stationarity"=>v["stationarity"],
            "sum_absolute_terms"=>magnitude[i],"relative_residual"=>abs(v["stationarity"])/max(1.,magnitude[i]),
            "epsilon_times_term_sum"=>eps(Float64)*magnitude[i],"fixed"=>v["fixed"]) for (i,v) in enumerate(stored)]
        droops=[]
        for (i,row) in enumerate(snapshot["nonlinear_rows"])
            row["family"]=="droop" || continue
            gi=findfirst(g->g.id==row["equipment_id"],case.generators)
            j=only(findall(v->v["name"]=="qg[$gi]",stored));v=stored[j]
            off=maximum((abs(J[i,k]) for k in eachindex(x) if k!=j);init=0.)
            push!(droops,Dict("generator_id"=>row["equipment_id"],"control_id"=>row["control_id"],
                "qg_variable"=>v["name"],"qg_derivative"=>J[i,j],"other_derivative_max"=>off,
                "qg_value"=>v["value"],"qg_lower"=>v["lower"],"qg_upper"=>v["upper"],
                "qg_near_bound"=>v["near_bound"],"droop_multiplier"=>row["dual"],
                "numerically_parallel_to_active_q_bound"=>v["near_bound"] && off<=1e-10))
        end
        result["droop_rows"]=droops
        result["scope"]="Re-evaluated final-point Jacobian without solving. Parallel means other droop derivatives <=1e-10 and Q within 1e-6 of a bound; not an exact rank certificate. Relative residual and epsilon*term-sum indicate cancellation sensitivity, not an optimality acceptance rule."
        throw(S1GeometryDone())
    end
    try
        optimize_joint_design(case;p...,initial_state=s1_flat(case),smooth_epsilon=1e-6,_measurement_hook=hook)
    catch err
        err isa S1GeometryDone || rethrow()
    end
    result
end
function s1_geometry_all(out)
    mkpath(out)
    for solver in (:ipopt,:madnlp)
        folder=joinpath(@__DIR__,"..","artifacts","s1_kkt_$solver")
        rows=JSON.parsefile(joinpath(folder,"summary.json"))
        for r in rows
            n=r["buses"];factor=r["tags"]["load_factor"];kind=r["tags"]["start"]
            source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
            original=load_matpower_case(source;base_frequency=60.)
            anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public$n-baseline-design.json"))
            base,p,_=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
            policies=kind=="anchor" ? p : s1_reseed(base,p;fraction=kind=="flat_low" ? .2 : .8)
            snapshot=JSON.parsefile(joinpath(folder,r["kkt_file"]))["final"]
            result=s1_kkt_geometry(s1_load(base,factor),policies,snapshot)
            write(joinpath(out,r["name"]*"-geometry.json"),JSON.json(result;pretty=true))
            println("Geometry ",r["name"]);flush(stdout)
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_geometry_all(abspath(ARGS[1]))
