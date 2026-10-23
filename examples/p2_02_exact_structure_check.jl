using DroopOPF,JSON,Test,Random,LinearAlgebra
using JuMP
const ROOT=normpath(joinpath(@__DIR__,".."));const OUT=joinpath(ROOT,"artifacts/p2_02_exact_profile")
function check_structure()
 dir=joinpath(ROOT,"artifacts/p2_02_scale_guard/heldout/p2-scale-24-two_chords-light")
 study=read_study(joinpath(dir,"input.json"));d=JSON.parsefile(joinpath(dir,"base.json"));base=ACState((Float64.(d[k]) for k in ("vm","va","pg","qg"))...)
 case=scenario_case(study.case,first(eligible_contingencies(contingency_catalog(study.case))))
 models=[first(DroopOPF._build_acopf_model(case;voltage_epsilon=1e-5,reactive_relative_epsilon=1e-5,reactive_epsilon=nothing,silent=true,initial_state=base,sparse_balance=s)) for s in (false,true)]
 evaluators=JuMP.NLPEvaluator.(models);moi=JuMP.MOI
 for e in evaluators;moi.initialize(e,[:Jac]);end
 structures=moi.jacobian_structure.(evaluators)
 n=num_variables(models[1]);m=num_nonlinear_constraints(models[1]);x=start_value.(all_variables(models[1]));rng=MersenneTwister(20261019)
 max_residual_difference=0.;max_jacobian_difference=0.
 @testset "Dense and sparse droop expressions" begin
  @test num_variables(models[2])==n
  @test num_nonlinear_constraints(models[2])==m
  @test length(structures[2])<length(structures[1])
  for sample in 1:10
   z=x+0.005randn(rng,n)
   residuals=[zeros(m),zeros(m)];jacobians=[zeros(m,n),zeros(m,n)]
   for k in 1:2
    moi.eval_constraint(evaluators[k],residuals[k],z)
    vals=zeros(length(structures[k]));moi.eval_constraint_jacobian(evaluators[k],vals,z)
    for ((i,j),v) in zip(structures[k],vals);jacobians[k][i,j]+=v;end
   end
   rd=maximum(abs.(residuals[1]-residuals[2]));jd=maximum(abs.(jacobians[1]-jacobians[2]));max_residual_difference=max(max_residual_difference,rd);max_jacobian_difference=max(max_jacobian_difference,jd)
   @test rd<1e-10
   @test jd<1e-10
  end
 end
 open(io->JSON.print(io,(;samples=10,dense_jacobian_entries=length(structures[1]),sparse_jacobian_entries=length(structures[2]),max_residual_difference,max_jacobian_difference),2),joinpath(OUT,"structure_check.json"),"w")
end
check_structure()
include(joinpath(ROOT,"test/test_sparse_balance.jl"))
include(joinpath(ROOT,"test/test_droop_screening.jl"))
