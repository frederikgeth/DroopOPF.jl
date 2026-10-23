# Independent solve-free replay of scale and preventive-design follow-ups.
include("p2_completion.jl")
function pcscaleaudit()
 records=Ref(0);states=Ref(0);discrepancies=[]
 function replay(study,data,label)
  r=DroopOPF._scopf_result_from_data(data["result"])
  @assert isempty(r.tap_controls)&&isempty(r.shunt_controls)
  report=equilibrium_report(study,r);records[]+=1;states[]+=length(r.states)
  report.valid==data["report"]["valid"]&&report.physical_valid==data["report"]["physical_valid"]||push!(discrepancies,label)
 end
 function from_states(study,data)
  ids=Set(Symbol.(keys(data["result"]["states"])))
  DroopOPF._copy_study(study;contingencies=[c for c in eligible_contingencies(contingency_catalog(study.case)) if c.id in ids])
 end
 function auditdesign(study,path)
  isfile(path)||return
  raw=JSON.parsefile(path)["result"]
  for iteration in raw["iterations"]
   design=iteration["design"]
   for (id,settings) in design["settings"],(key,v) in settings
    @assert abs(v-design["reference_settings"][id][key])<=1e-8
   end
   if !isnothing(iteration["report"])
    data=Dict("result"=>design["result"],"report"=>iteration["report"])
    replay(from_states(study,data),data,path)
   end
   for a in iteration["assessments"]
    replay(from_states(study,a),a,path)
   end
  end
 end
 for n in (48,96)
  d=joinpath(PCOUT,"scale_run",string(n));study=read_study(joinpath(d,"study.json"))
  for rep in 1:3,worker in (1,2)
   file=joinpath(d,"$rep-workers$worker.json");data=JSON.parsefile(file)
   for a in data["assessments"]
    exact=a["exact_assessment"];isnothing(exact)&&continue
    replay(from_states(study,exact),exact,file)
   end
  end
  for file in filter(p->startswith(basename(p),"warm-")&&endswith(p,".json"),readdir(d;join=true))
   data=JSON.parsefile(file);replay(from_states(study,data),data,file)
  end
  f=joinpath(d,"full_enumeration.json")
  if isfile(f);data=JSON.parsefile(f);replay(from_states(study,data),data,f);end
  auditdesign(study,joinpath(d,"scenario_addition.json"))
  target=joinpath(d,"design_warm_study.json")
  if isfile(target)
   targetstudy=read_study(target)
   @assert DroopOPF._json_data(targetstudy.case.controls)==DroopOPF._json_data(study.case.controls)
   @assert DroopOPF._json_data(targetstudy.case.network)==DroopOPF._json_data(study.case.network)
   for file in filter(p->startswith(basename(p),"design-warm-")&&endswith(p,".json"),readdir(d;join=true))
    replay(targetstudy,JSON.parsefile(file),file)
   end
  end
 end
 challenge=joinpath(PCOUT,"scale_challenge")
 if isfile(joinpath(challenge,"study.json"))
  study=read_study(joinpath(challenge,"study.json"));f=joinpath(challenge,"full_enumeration.json")
  if isfile(f);data=JSON.parsefile(f);replay(from_states(study,data),data,f);end
  auditdesign(study,joinpath(challenge,"scenario_addition.json"))
 end
 study=read_study(joinpath(PCOUT,"public_run/pglib_opf_case39_epri/study.json"))
 f=joinpath(PCOUT,"public_design/full_enumeration.json")
 if isfile(f);data=JSON.parsefile(f);replay(from_states(study,data),data,f);end
 auditdesign(study,joinpath(PCOUT,"public_design/scenario_addition.json"))
 pcsave(joinpath(PCOUT,"scale_replay_audit.json"),(;records=records[],scenario_states=states[],discrepancies));@assert isempty(discrepancies)
 println("Replayed ",records[]," records containing ",states[]," scenario states")
end
pcscaleaudit()
