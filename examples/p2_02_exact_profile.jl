# Repeated phase measurements on exposed development cases. No library mutation.
using DroopOPF,JSON,SHA,LinearAlgebra
const ROOT=normpath(joinpath(@__DIR__,".."))
const OUT=joinpath(ROOT,"artifacts/p2_02_exact_profile")
const OPTIONS=(;smooth_epsilon=1e-5,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>500,"max_cpu_time"=>5.))
include_string(DroopOPF,read(joinpath(OUT,"profile_solver.jl"),String))
save(p,x)=open(io->JSON.print(io,DroopOPF._json_data(x),2),p,"w")
BLAS.set_num_threads(1)
mode=ARGS[1]; target=joinpath(OUT,mode);ispath(target) && error("Preserve previous measurements");mkpath(target)
rows=[]
for id in ("p2-scale-24-two_chords-light","p2-scale-24-two_chords-reactive_low")
 dir=joinpath(ROOT,"artifacts/p2_02_scale_guard/heldout",id)
 study=read_study(joinpath(dir,"input.json"));d=JSON.parsefile(joinpath(dir,"base.json"));base=ACState((Float64.(d[k]) for k in ("vm","va","pg","qg"))...)
 catalog=contingency_catalog(study.case)
 policies=mode=="baseline" ? [false] : [false,true]
 for rep in 1:4, sparse in circshift(policies,rep-1)
  for entry in catalog.entries
   entry.disposition==:eligible || error("Unexpected island")
   single=DroopOPF._copy_study(study;contingencies=[entry.contingency]);phases=Dict{Symbol,Float64}()
   m=@timed DroopOPF._p2_profile_solve(single;fixed_base_state=base,sparse_balance=sparse,_p2_timing=phases,OPTIONS...)
   v=@timed equilibrium_report(single,m.value);r=only(rank_contingencies(catalog,v.value))
   name="$id-$rep-$sparse-$(entry.contingency.id).json"
   save(joinpath(target,name),(;result=m.value,report=v.value,rank=r))
   push!(rows,(;id,rep,sparse,outage=entry.contingency.id,phases,validation=v.time,elapsed=m.time+v.time,gc=m.gctime+v.gctime,bytes=m.bytes+v.bytes,classification=r.classification,path=name))
  end
  save(joinpath(target,"summary.json"),rows);println(id," rep=",rep," sparse=",sparse);flush(stdout)
 end
end
