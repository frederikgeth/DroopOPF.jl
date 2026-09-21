include(joinpath(@__DIR__,"..","examples","s1_warm_start.jl"))
@testset "S1 restart mapping and rejection" begin
    function fixture(;lower=0.)
        model=Model(Ipopt.Optimizer);set_silent(model)
        @variable(model,x>=lower,start=1.5)
        @variable(model,0<=y<=2,start=0.5)
        @NLconstraint(model,x^2+y>=4.)
        @objective(model,Min,x^2+3y)
        model
    end
    model=fixture();optimize!(model)
    seed=s1_capture_seed(model,"fixture-epsilon-fixed")
    @test any(abs.(seed["nonlinear_dual"]).>1e-5)
    @test any(abs.(seed["regular_dual"]).>1e-5)
    seed=JSON.parse(JSON.json(seed))
    for mode in (:primal,:zero_dual,:primal_dual)
        target=fixture()
        counts=s1_apply_seed!(target,seed,"fixture-epsilon-fixed";mode)
        @test start_value.(all_variables(target))≈seed["primal"]
        if mode!=:primal
            layout=s1_seed_layout(target,"fixture-epsilon-fixed")
            expected=mode==:zero_dual ? zeros(length(layout.regular)) : seed["regular_dual"]
            @test dual_start_value.(layout.regular)≈expected
            @test nonlinear_dual_start_value(target)≈(mode==:zero_dual ? zeros(length(layout.nonlinear)) : seed["nonlinear_dual"])
            set_optimizer_attribute(target,"warm_start_init_point","yes")
        end
        optimize!(target)
        @test termination_status(target)==JuMP.MOI.LOCALLY_SOLVED
        @test objective_value(target)≈objective_value(model) atol=1e-6
    end
    target=fixture()
    @test_throws ArgumentError s1_apply_seed!(target,seed,"changed-formulation")
    @test_throws ArgumentError s1_apply_seed!(fixture(lower=.1),seed,"fixture-epsilon-fixed")
    @test_throws ArgumentError s1_apply_seed!(target,seed,"fixture-epsilon-fixed";mode=:unknown)
    bad=deepcopy(seed);pop!(bad["primal"])
    @test_throws ArgumentError s1_apply_seed!(target,bad,"fixture-epsilon-fixed")
    bad=deepcopy(seed);bad["regular_dual"][1]=NaN
    @test_throws ArgumentError s1_apply_seed!(target,bad,"fixture-epsilon-fixed")
    @test start_value.(all_variables(target))==[1.5,.5]
end

@testset "S1 OPF seed persistence and physical validation" begin
    case=load_matpower_case(joinpath(@__DIR__,"data","droop2.m"))
    mktempdir() do out
        saved=Ref{Any}(nothing)
        capture=(phase,model)->(phase==:solved && (saved[]=s1_capture_seed(model,"opf"));nothing)
        source,result=s1_attempt(out,"seed",case,s1_flat(case);experiment_hook=capture)
        @test source["valid"]
        @test !isnothing(saved[])
        for mode in (:primal,:zero_dual,:primal_dual)
            hook=(phase,model)->(phase==:built && s1_apply_seed!(model,saved[],"opf";mode);nothing)
            options=mode==:primal ? Dict{String,Any}() : Dict{String,Any}("warm_start_init_point"=>"yes")
            row,restarted=s1_attempt(out,string(mode),case,s1_flat(case);experiment_hook=hook,options)
            @test row["valid"]
            @test validate_joint_design(case,restarted).valid
            @test restarted.opf.objective≈result.opf.objective atol=1e-6
        end
    end
end
