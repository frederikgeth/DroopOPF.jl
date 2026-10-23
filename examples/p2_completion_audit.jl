# Solve-free replay of saved public outcomes, including retained island components.
include("p2_completion.jl")
function pcaudit()
 rows=JSON.parsefile(joinpath(PCOUT,"public_run/summary.json"));replayed=0;islands=0;errors=[]
 for row in rows
  row["base_valid"]||continue
  d=joinpath(PCOUT,"public_run",row["id"]);study=read_study(joinpath(d,"study.json"));case=study.case
  raw=JSON.parsefile(joinpath(d,"base.json"));base=ACState((Float64.(raw[k]) for k in ("vm","va","pg","qg"))...)
  @assert validate_equilibrium(case,base).valid
  @assert isempty(study.tap_controls)&&isempty(study.shunt_controls)
  @assert all(==(1.),values(study.participation))
  catalog=contingency_catalog(case)
  for attempt in row["attempts"]
   data=JSON.parsefile(joinpath(d,attempt["path"]));@assert length(data["assessments"])==length(catalog.entries)
   for a in data["assessments"]
    id=Symbol(a["entry"]["contingency"]["id"]);entry=only(filter(e->e.contingency.id==id,catalog.entries));exact=a["exact_assessment"];island=a["island_assessment"]
    if !isnothing(exact)
     result=DroopOPF._scopf_result_from_data(exact["result"])
     @assert DroopOPF._json_data(result.states[:base])==raw
     @assert isempty(result.tap_controls)&&isempty(result.shunt_controls)
     report=equilibrium_report(DroopOPF._copy_study(study;contingencies=[entry.contingency]),result);replayed+=1
     report.valid==exact["report"]["valid"]&&report.physical_valid==exact["report"]["physical_valid"]||push!(errors,(;case=row["id"],id,path=attempt["path"]))
    elseif !isnothing(island)
     scenario=islanded_scenario_case(case,entry.contingency,base);saved=island["result"];state=saved["state"]
     if !isnothing(state)
      s=ACState((Float64.(state[k]) for k in ("vm","va","pg","qg"))...);v=validate_equilibrium(scenario.case,s);islands+=1
      v.valid==island["report"]["validation"]["valid"]||push!(errors,(;case=row["id"],id,path=attempt["path"]))
     end
    end
   end
  end
 end
 pcsave(joinpath(PCOUT,"replay_audit.json"),(;replayed_exact=replayed,replayed_island=islands,discrepancies=errors));@assert isempty(errors)
 println("Replayed ",replayed," exact and ",islands," island results")
end
pcaudit()
