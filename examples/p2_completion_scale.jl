# Additional scale qualification on previously accepted synthetic cases.
# Reuse is explicit; these are regression/throughput cases, not fresh held-out data.
include("p2_completion.jl")
function pcdesignwarm(source,reference,dir)
 accepted=equilibrium_report(source,reference).valid
 pcsave(joinpath(dir,"design_warm_protocol.json"),(;source_accepted=accepted,load_factor=1.01,scope="48-bus first 12 eligible contingencies; active dispatch design; unchanged equipment and shared droop",policies=["flat","base_scenario","neighbouring_design"],repetitions=3,warm_repetitions=[2,3],source="Accepted preceding full-enumeration state map; no design controls changed"))
 accepted||return
 c=source.case
 target=Case(c.id*"-load101";base_power=c.base_power,base_frequency=c.base_frequency,network=c.network,generators=c.generators,loads=[Load(l.id,l.bus_id;p=1.01l.p,q=1.01l.q) for l in c.loads],controls=c.controls,attachments=c.attachments)
 study=Study(target;contingencies=source.contingencies[1:min(12,length(source.contingencies))],participation=source.participation)
 write_study(joinpath(dir,"design_warm_study.json"),study)
 ids=[:base;[c.id for c in study.contingencies]];base=reference.states[:base];rows=[]
 options=(;smooth_epsilon=1e-5,sparse_balance=true,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>500,"max_cpu_time"=>30.))
 for rep in 1:3,policy in circshift([:flat,:base_scenario,:neighbouring_design],rep-1)
  flat=ACState(ones(length(base.vm)),zeros(length(base.va)),copy(base.pg),copy(base.qg))
  initial=Dict(id=>(policy==:flat ? flat : policy==:base_scenario ? base : reference.states[id]) for id in ids)
  m=@timed solve_scopf(study;options...,initial_states=initial);report=equilibrium_report(study,m.value)
  pcsave(joinpath(dir,"design-warm-$rep-$policy.json"),(;result=m.value,report))
  push!(rows,(;rep,policy,seconds=m.time,bytes=m.bytes,valid=report.valid,objective=m.value.objective,status=m.value.termination_status))
 end
 pcsave(joinpath(dir,"design_warm_summary.json"),rows)
end
function pcchallengedesign()
 d=joinpath(PCOUT,"scale_challenge");ispath(d)&&error("Preserve prior challenge");mkpath(d)
 source=joinpath(PCROOT,"artifacts/p2_02_large_sparse/heldout/p2-large-sparse-48-saturation")
 study=read_study(joinpath(source,"input.json"));raw=JSON.parsefile(joinpath(source,"base.json"));base=ACState((Float64.(raw[k]) for k in ("vm","va","pg","qg"))...)
 pcsave(joinpath(d,"protocol.json"),(;source_sha256=pchash(joinpath(source,"input.json")),script_sha256=pchash(@__FILE__),configuration="Fixed equipment, frozen shared droop, equal preventive response",scope="Previously studied 48-bus saturation case with four unresolved fixed-base outages; development regression, not new held-out data",options="Full enumeration and max5 scenario-addition rounds, batch4, 500 iterations and 30 CPU seconds per solve"))
 write_study(joinpath(d,"study.json"),study)
 options=(;smooth_epsilon=1e-5,sparse_balance=true,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>500,"max_cpu_time"=>30.))
 full=DroopOPF._copy_study(study;contingencies=eligible_contingencies(contingency_catalog(study.case)))
 m=@timed solve_scopf(full;options...,initial_states=Dict(id=>base for id in [:base;[c.id for c in full.contingencies]]))
 pcsave(joinpath(d,"full_enumeration.json"),(;result=m.value,report=equilibrium_report(full,m.value),seconds=m.time,bytes=m.bytes))
 locked=[DroopControl(i;slope_bounds=(control.slope,control.slope)) for (i,control) in enumerate(study.case.controls)]
 m=@timed optimize_droop_security(study,locked;max_rounds=5,batch_size=4,initial_states=Dict(:base=>base),solver_kwargs=options,evaluation_kwargs=(;optimizer_attributes=options.optimizer_attributes))
 pcsave(joinpath(d,"scenario_addition.json"),(;result=m.value,seconds=m.time,bytes=m.bytes))
 println("Completed 48-bus saturation design challenge");flush(stdout)
end
function pcscale()
 d=joinpath(PCOUT,"scale_run");ispath(d)&&error("Preserve prior scale attempt");mkpath(d);BLAS.set_num_threads(1)
 pcsave(joinpath(d,"protocol.json"),(;configuration="fixed supplied taps/shunts; zero movement; frozen shared droop; equal preventive active response",cases=[48,96],source="Previously accepted p2_02_large_sparse normal cases; regression, not fresh held-out",script_sha256=pchash(@__FILE__),source_hashes=Dict("$n/$name"=>pchash(joinpath(PCROOT,"artifacts/p2_02_large_sparse/heldout/p2-large-sparse-$n-normal",name)) for n in (48,96) for name in ("input.json","base.json")),scenario_addition="48-bus: full enumeration versus fixed-control scenario addition, max 5 rounds, batch4, 30 CPU seconds per solve",warm_start="First 12 eligible catalogue entries at both sizes; three rotated repetitions of flat/base/previous accepted neighbour; warm medians repetitions 2-3",threading="3 rotated serial/threaded exhaustive repetitions; wall time and allocations, process high-water RSS",options=PCOPT))
 for n in (48,96)
  source=joinpath(PCROOT,"artifacts/p2_02_large_sparse/heldout/p2-large-sparse-$n-normal")
  study=read_study(joinpath(source,"input.json"));case=study.case;raw=JSON.parsefile(joinpath(source,"base.json"));base=ACState((Float64.(raw[k]) for k in ("vm","va","pg","qg"))...)
  @assert validate_equilibrium(case,base).valid
  sub=joinpath(d,string(n));mkpath(sub);write_study(joinpath(sub,"study.json"),study);pcsave(joinpath(sub,"base.json"),base)
  timings=[]
  for rep in 1:3,workers in circshift([1,2],rep-1)
   m=@timed assess_contingency_pipeline(case,base;participation=study.participation,PCOPT...,screening_enabled=false,workers)
   pcsave(joinpath(sub,"$rep-workers$workers.json"),m.value)
   push!(timings,(;rep,workers,seconds=m.time,bytes=m.bytes,maxrss=Sys.maxrss()));pcsave(joinpath(sub,"timings.json"),timings)
  end
  warm=[];entries=filter(e->e.disposition==:eligible,contingency_catalog(case).entries)
  for rep in 1:3
   previous=base
   for entry in entries[1:min(12,length(entries))]
    one=DroopOPF._copy_study(study;contingencies=[entry.contingency]);id=entry.contingency.id
    for policy in circshift([:flat,:base,:neighbour],rep-1)
     start=policy==:flat ? ACState(ones(length(base.vm)),zeros(length(base.va)),copy(base.pg),copy(base.qg)) : policy==:base ? base : previous
     m=@timed evaluate_contingencies(one,base;PCOPT...,initial_states=Dict(id=>start));report=equilibrium_report(one,m.value)
     pcsave(joinpath(sub,"warm-$rep-$id-$policy.json"),(;result=m.value,report))
     push!(warm,(;rep,id,policy,seconds=m.time,bytes=m.bytes,valid=report.valid,status=m.value.termination_status))
     policy==:neighbour&&report.valid&&(previous=m.value.states[id])
    end
   end
  end
  pcsave(joinpath(sub,"warm_summary.json"),warm)
  if n==48
   options=(;smooth_epsilon=1e-5,sparse_balance=true,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>500,"max_cpu_time"=>30.))
   full=DroopOPF._copy_study(study;contingencies=eligible_contingencies(contingency_catalog(case)))
   m=@timed solve_scopf(full;options...,initial_states=Dict(id=>base for id in [:base;[c.id for c in full.contingencies]]))
   pcsave(joinpath(sub,"full_enumeration.json"),(;result=m.value,report=equilibrium_report(full,m.value),seconds=m.time,bytes=m.bytes,maxrss=Sys.maxrss()))
   pcdesignwarm(full,m.value,sub)
   locked=[DroopControl(i;slope_bounds=(control.slope,control.slope)) for (i,control) in enumerate(case.controls)]
   m=@timed optimize_droop_security(study,locked;max_rounds=5,batch_size=4,initial_states=Dict(:base=>base),solver_kwargs=options,evaluation_kwargs=(;optimizer_attributes=options.optimizer_attributes))
   pcsave(joinpath(sub,"scenario_addition.json"),(;result=m.value,seconds=m.time,bytes=m.bytes,maxrss=Sys.maxrss()))
  end
  println("Completed ",n," bus scale regression");flush(stdout)
 end
 pcchallengedesign()
end
pcscale()
