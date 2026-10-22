# Solve-free reconstruction of frozen overlays and intended cohort coverage.
using DroopOPF,JSON
include("p2_02_large_sparse_cases.jl")
function main()
 root=normpath(joinpath(@__DIR__,".."));out=joinpath(root,"artifacts/p2_02_large_sparse");rows=[]
 for input in p2_large_sparse_inputs()
  dir=joinpath(out,"heldout",input.case.id);summary=JSON.parsefile(joinpath(dir,"summary.json"))
  if !summary["base_valid"];push!(rows,(;id=input.case.id,valid=false));continue;end
  study=read_study(joinpath(dir,"input.json"));d=JSON.parsefile(joinpath(dir,"base.json"));base=ACState((Float64.(d[k]) for k in ("vm","va","pg","qg"))...)
  rebuilt=p2_large_sparse_overlay(input.case,base;cohort=input.cohort)
  @assert DroopOPF._json_data(rebuilt)==DroopOPF._json_data(study.case)
  points=droop_operating_points(study.case,base);regimes=Dict{String,Int}()
  for point in points;name=string(point.regime);regimes[name]=get(regimes,name,0)+1;end
  reserve=minimum(min(base.qg[i]-c.capability.q_min,c.capability.q_max-base.qg[i])/(c.capability.q_max-c.capability.q_min) for (i,c) in enumerate(study.case.controls))
  coverage=input.cohort==:saturation ? get(regimes,"saturation_qmax",0)==length(study.case.generators)÷4 && get(regimes,"proportional",0)==3length(study.case.generators)÷4 : input.cohort==:tight_reactive ? get(regimes,"proportional",0)==length(study.case.generators) && -1e-6<=reserve<=.1 : get(regimes,"proportional",0)==length(study.case.generators)
  saved=JSON.parsefile(joinpath(dir,"base_regimes.json"));@assert [string(p.regime) for p in points]==[p["regime"] for p in saved]
  push!(rows,(;id=input.case.id,valid=true,cohort=input.cohort,buses=length(study.case.network.buses),regimes,minimum_individual_q_reserve_fraction=reserve,overlay_reconstruction_equal=true,coverage))
 end
 open(io->JSON.print(io,rows,2),joinpath(out,"cohort_audit.json"),"w")
 println("Reconstructed ",count(r->r.valid,rows)," frozen overlays")
end
main()
