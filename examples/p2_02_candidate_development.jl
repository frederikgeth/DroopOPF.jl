# Replay uncertain predictions with instrumentation only; no optimizer or routing changes.
using DroopOPF,JSON,SHA,LinearAlgebra
root=normpath(joinpath(@__DIR__,".."));out=abspath(ARGS[1]);old=joinpath(root,"artifacts/p2_02_scale_guard")
BLAS.set_num_threads(1)
include_string(DroopOPF,read(joinpath(out,"candidate_predictor.jl"),String),joinpath(out,"candidate_predictor.jl"))
function diagnose(old,out)
 rows=[]
 for row in JSON.parsefile(joinpath(old,"heldout","summary.json"))
  row["base_valid"] && length(row["attempts"])==9 || continue
  dir=joinpath(old,"heldout",row["id"]);study=read_study(joinpath(dir,"input.json"));d=JSON.parsefile(joinpath(dir,"base.json"));base=ACState(Float64.(d["vm"]),Float64.(d["va"]),Float64.(d["pg"]),Float64.(d["qg"]))
  data=JSON.parsefile(joinpath(dir,"1-guarded.json"));catalog=eligible_contingencies(contingency_catalog(study.case))
  for a in data["assessments"]
   a["decision"]["reason"]=="droop_prediction_uncertain" || continue
   id=a["entry"]["contingency"]["id"];c=only(filter(c->string(c.id)==id,catalog))
   kwargs=(;participation=study.participation,voltage_guard=.02,loading_threshold=.8,reactive_guard=.1)
   reference=DroopOPF._droop_screening_diagnostics(study.case,base,c;kwargs...)
   debug=DroopOPF._p2_candidate_diagnostics(study.case,base,c;kwargs...)
   # Candidate evaluated on exposed development cases; never treat these as fresh holdout.
   push!(rows,(;input=row["id"],id,buses=length(study.case.network.buses),diagnostic=debug))
  end
 end
 open(joinpath(out,"candidate_development.json"),"w") do io;JSON.print(io,DroopOPF._json_data((;rows)),2);end
 println("Reproduced ",length(rows)," previously uncertain decisions with the development candidate")
end
diagnose(old,out)
