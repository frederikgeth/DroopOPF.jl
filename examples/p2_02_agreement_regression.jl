# Development regression over exposed historical, small and scale studies; no optimizer.
using DroopOPF,JSON,LinearAlgebra
out=abspath(ARGS[1]);root=normpath(joinpath(@__DIR__,".."));BLAS.set_num_threads(1)
include_string(DroopOPF,read(joinpath(out,"agreement_candidate.jl"),String),joinpath(out,"agreement_candidate.jl"))
function run(out,root)
 rows=[]
 sources=[joinpath(root,"artifacts/droop_security/filter"),joinpath(root,"artifacts/p2_02_droop_guard/heldout"),joinpath(root,"artifacts/p2_02_droop_guard/heldout_retry"),joinpath(root,"artifacts/p2_02_scale_guard/heldout")]
 for source in sources,dir in sort(readdir(source;join=true))
  isdir(dir) && isfile(joinpath(dir,"input.json")) || continue
  old=isfile(joinpath(dir,"comparison.json"));summary=old ? nothing : JSON.parsefile(joinpath(dir,"summary.json"))
  !old && !(summary["base_valid"] && length(summary["attempts"])==9) && continue
  study=read_study(joinpath(dir,"input.json"));case=study.case
  b=old ? JSON.parsefile(joinpath(dir,"comparison.json"))["base_state"] : JSON.parsefile(joinpath(dir,"base.json"))
  base=ACState((Float64.(b[k]) for k in ("vm","va","pg","qg"))...)
  catalogs=eligible_contingencies(contingency_catalog(case));unresolved=Set{String}()
  datasets=old ? [JSON.parsefile(joinpath(dir,"comparison.json"))["exact"]] : [JSON.parsefile(joinpath(dir,"$rep-exhaustive.json")) for rep in 1:3]
  for data in datasets,a in data["assessments"]
   a["rank"]["classification"]!="accepted" && push!(unresolved,a["entry"]["contingency"]["id"])
  end
  for d in filter_contingencies(case,base;participation=study.participation)
   id=string(d.contingency_id);candidate_safe=false;reference_safe=false
   if d.action==:screened
    c=only(filter(c->c.id==d.contingency_id,catalogs));kw=(;participation=study.participation,voltage_guard=.02,loading_threshold=.8,reactive_guard=.1)
    candidate_safe=DroopOPF._p2_candidate_diagnostics(case,base,c;kw...).safe
    reference_safe=DroopOPF._droop_screening_diagnostics(case,base,c;kw...).safe
   end
   push!(rows,(;source=relpath(dir,root),id,unresolved=id in unresolved,candidate_screened=candidate_safe,reference_screened=reference_safe))
  end
 end
 misses=count(x->x.candidate_screened && x.unresolved,rows)
 open(joinpath(out,"agreement_regression.json"),"w") do io;JSON.print(io,DroopOPF._json_data((;rows,outages=length(rows),candidate_misses=misses,reference_misses=count(x->x.reference_screened && x.unresolved,rows))),2);end
 @assert misses==0
 println("Exposed development outages=",length(rows),"; candidate misses=",misses)
end
run(out,root)
