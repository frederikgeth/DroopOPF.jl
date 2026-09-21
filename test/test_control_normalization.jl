using JuMP, LinearAlgebra
isdefined(@__MODULE__,:m72_case) || include(joinpath(@__DIR__,"..","examples","m7_2_case.jl"))
struct S1NormalizationBuilt <: Exception end
function normalization_model(case,policies,mode)
    captured=Ref{Any}(nothing)
    function hook(phase,model)
        if phase==:built;captured[]=model;throw(S1NormalizationBuilt());end
    end
    try
        optimize_joint_design(case;policies...,control_normalization=mode,initial_state=m5_initial_state(case),_measurement_hook=hook)
    catch err
        err isa S1NormalizationBuilt || rethrow()
    end
    captured[]
end
function normalization_derivatives(model,x)
    moi=JuMP.MOI;e=JuMP.NLPEvaluator(model);moi.initialize(e,[:Jac,:Hess])
    n=length(x);m=num_nonlinear_constraints(model)
    c=zeros(m);moi.eval_constraint(e,c,x)
    js=moi.jacobian_structure(e);jv=zeros(length(js));moi.eval_constraint_jacobian(e,jv,x)
    J=zeros(m,n);for ((i,j),v) in zip(js,jv);J[i,j]=v;end
    hs=moi.hessian_lagrangian_structure(e);hv=zeros(length(hs))
    moi.eval_hessian_lagrangian(e,hv,x,0.,sin.(collect(1:m)))
    H=zeros(n,n);for ((i,j),v) in zip(hs,hv);H[i,j]=H[j,i]=v;end
    objective=value(v->x[index(v).value],objective_function(model))
    c,J,H,objective
end
@testset "Equivalent controller coordinates, derivatives and fixed settings" begin
    for capacitor in (true,false)
        case=m72_case(;capacitor)
        p=(tap_controls=[TapControl(11;lower=.95,upper=1.05)],
            shunt_controls=[ShuntControl(201),ShuntControl(202)],
            droop_controls=[DroopControl(2;slope_bounds=(.04,.1),v_ref_bounds=(.995,1.005),
                deadband_low_bounds=(.005,.015),deadband_high_bounds=(.005,.015))])
        original=normalization_model(case,p,:none);normalized=normalization_model(case,p,:bounds)
        maps=normalized.ext[:control_normalization_maps]
        @test length(maps)==7
        @test num_variables(original)==num_variables(normalized)
        n=num_variables(original);d=ones(n);offset=zeros(n)
        for a in maps
            i=index(a.coordinate).value;d[i]=a.width;offset[i]=a.lower
            @test lower_bound(a.coordinate)==0 && upper_bound(a.coordinate)==1
            @test name(all_variables(original)[i])==a.name
        end
        initial=start_value.(all_variables(normalized))
        @test offset+d.*initial≈start_value.(all_variables(original)) atol=1e-14
        for fraction in (0.,.37,1.),voltage in (.96,1.,1.04)
            z=copy(initial)
            for a in maps;z[index(a.coordinate).value]=fraction;end
            for v in all_variables(normalized)
                occursin("vm[",name(v)) && (z[index(v).value]=voltage)
            end
            x=offset+d.*z
            c,J,H,f=normalization_derivatives(original,x)
            cn,Jn,Hn,fn=normalization_derivatives(normalized,z)
            @test cn≈c atol=1e-10 rtol=1e-10
            @test Jn≈J*Diagonal(d) atol=1e-8 rtol=1e-9
            @test Hn≈Diagonal(d)*H*Diagonal(d) atol=1e-7 rtol=1e-8
            @test fn≈f atol=1e-14
        end
    end
    c=m72_case();m=c.controls[2].slope
    fixed=(tap_controls=[TapControl(11;lower=1.,upper=1.,initial=1.)],
        shunt_controls=[ShuntControl(201;lower=.02,upper=.02,initial=.02)],
        droop_controls=[DroopControl(2;slope_bounds=(m,m))])
    model=normalization_model(c,fixed,:bounds)
    @test isempty(get(model.ext,:control_normalization_maps,[]))
    @test_throws ArgumentError optimize_joint_design(c;control_normalization=:bad)
end
@testset "Normalized joint results remain physical and serializable" begin
    c=m72_case();p=(tap_controls=[TapControl(11;lower=.95,upper=1.05)],
        shunt_controls=[ShuntControl(201)],droop_controls=[DroopControl(2;slope_bounds=(.04,.1))])
    result=optimize_joint_design(c;p...,initial_state=m5_initial_state(c),control_normalization=:bounds)
    @test validate_joint_design(c,result).valid
    @test .95<=result.taps[11]<=1.05
    @test .04<=result.droops[2].slope<=.1
    @test joint_design_metrics(c,result).objective_recomputed≈result.opf.objective atol=1e-10
    mktempdir() do dir
        path=joinpath(dir,"normalized.json");write_joint_design(path,result)
        @test validate_joint_design(c,read_joint_design(path)).valid
    end
end
