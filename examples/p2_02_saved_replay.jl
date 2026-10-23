# Saved-state replay and guard discovery diagnostics only: no optimizer is called.
using DroopOPF,JSON,SHA
root=normpath(joinpath(@__DIR__,".."));source=joinpath(root,"artifacts/droop_security/filter");out=abspath(ARGS[1]);mkpath(out)
function save(path,x);open(io->JSON.print(io,DroopOPF._json_data(x),2),path,"w");end
paths=sort([joinpath(d,f) for (d,_,fs) in walkdir(source) for f in fs if f in ("input.json","base.json","comparison.json","protocol.json","results.json","report.md")])
manifest=Dict(relpath(p,root)=>bytes2hex(sha256(read(p))) for p in paths)
save(joinpath(out,"preservation.json"),manifest)
rows=[];discrepancies=[]
for dir in sort(readdir(source;join=true))
    isfile(joinpath(dir,"comparison.json")) || continue
    study=read_study(joinpath(dir,"input.json"));case=study.case
    d=JSON.parsefile(joinpath(dir,"comparison.json"));b=d["base_state"]
    base=ACState((Float64.(b[k]) for k in ("vm","va","pg","qg"))...)
    @assert validate_equilibrium(case,base).valid
    legacy=filter_contingencies(case,base);enhanced=filter_contingencies(case,base;droop_response_guard=true,participation=study.participation)
    lmap=Dict(string(x.contingency_id)=>x for x in legacy);emap=Dict(string(x.contingency_id)=>x for x in enhanced)
    expected=Dict(x["contingency_id"]=>x for x in d["decisions"])
    for entry in d["exact"]["assessments"]
        id=entry["entry"]["contingency"]["id"];exact=entry["exact_assessment"]
        @assert !isnothing(exact)
        result=DroopOPF._scopf_result_from_data(exact["result"])
        contingency=only(filter(c->string(c.id)==id,eligible_contingencies(contingency_catalog(case))))
        report=equilibrium_report(DroopOPF._copy_study(study;contingencies=[contingency]),result)
        report.valid==exact["report"]["valid"] || push!(discrepancies,(;case=case.id,id,old=exact["report"]["valid"],current=report.valid))
        @assert string(lmap[id].action)==expected[id]["action"]
        unresolved=entry["rank"]["classification"]!="accepted"
        diag=lmap[id].action==:screened ? DroopOPF._droop_screening_diagnostics(case,base,contingency;
            participation=study.participation,voltage_guard=.02,loading_threshold=.8,reactive_guard=.1) : nothing
        push!(rows,(;input=basename(dir),split=startswith(basename(dir),"discovery") ? "discovery" : "old_heldout",
            id,family=entry["entry"]["device_kind"],unresolved,physical_valid=report.physical_valid,
            legacy_action=lmap[id].action,enhanced_action=emap[id].action,reason=emap[id].reason,
            original_false_screen=lmap[id].action==:screened && unresolved,
            enhanced_false_screen=emap[id].action==:screened && unresolved,diagnostic=diag))
    end
    println(basename(dir)," complete");flush(stdout)
end
@assert length(rows)==168 && count(r->r.original_false_screen,rows)==12 && isempty(discrepancies)
@assert all(bytes2hex(sha256(read(joinpath(root,p))))==hash for (p,hash) in manifest)
save(joinpath(out,"RESULTS.json"),(;rows,discrepancies,original_false_screens=count(r->r.original_false_screen,rows),
    enhanced_false_screens=count(r->r.enhanced_false_screen,rows),source_hashes_unchanged=true,new_optimizer_runs=0,
    guard_sha256=bytes2hex(sha256(read(joinpath(root,"src/droop_screening.jl"))))))
println("Saved misses=",count(r->r.original_false_screen,rows),"; remaining=",count(r->r.enhanced_false_screen,rows),"; screened=",count(r->r.enhanced_action==:screened,rows))
