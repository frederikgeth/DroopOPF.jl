using DroopOPF,JSON
const ROOT=normpath(joinpath(@__DIR__,".."));const OUT=joinpath(ROOT,"artifacts/p2_02_exact_profile")
function main()
 replayed=0;discrepancies=[]
 for mode in ("baseline","comparison")
  for row in JSON.parsefile(joinpath(OUT,mode,"summary.json"))
   dir=joinpath(ROOT,"artifacts/p2_02_scale_guard/heldout",row["id"])
   study=read_study(joinpath(dir,"input.json"));catalog=contingency_catalog(study.case)
   entry=only(filter(e->string(e.contingency.id)==row["outage"],catalog.entries))
   single=DroopOPF._copy_study(study;contingencies=[entry.contingency]);data=JSON.parsefile(joinpath(OUT,mode,row["path"]))
   result=DroopOPF._scopf_result_from_data(data["result"]);report=equilibrium_report(single,result);rank=only(rank_contingencies(catalog,report))
   @assert DroopOPF._json_data(result.states[:base])==JSON.parsefile(joinpath(dir,"base.json"))
   @assert isempty(result.tap_controls) && isempty(result.shunt_controls)
   @assert all(isempty,values(result.tap_settings)) && all(isempty,values(result.shunt_settings))
   @assert isnothing(result.reactive_assignments) && all(==(1.),values(study.participation))
   replayed+=1
   if report.valid!=data["report"]["valid"] || report.physical_valid!=data["report"]["physical_valid"] || string(rank.classification)!=row["classification"]
    push!(discrepancies,(;mode,path=row["path"]))
   end
  end
 end
 @assert isempty(discrepancies)
 open(io->JSON.print(io,(;replayed_states=replayed,discrepancies),2),joinpath(OUT,"development_audit.json"),"w")
 println("Replayed ",replayed," development states with ",length(discrepancies)," discrepancies")
end
main()
