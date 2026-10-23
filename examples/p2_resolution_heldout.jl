include("p2_completion.jl")
include("p2_resolution_cases.jl")
function heldout()
 d=joinpath(PCROOT,"artifacts/p2_resolution/heldout");ispath(d)&&error("Preserve heldout");mkpath(d)
 inputs=p2_resolution_inputs()
 for x in inputs;write_study(joinpath(d,x.case.id*"-planned.json"),Study(x.case));end
 pcsave(joinpath(d,"protocol.json"),(;runner_sha256=pchash(@__FILE__),source_hashes=Dict(basename(p)=>pchash(p) for p in readdir(joinpath(PCROOT,"src");join=true) if endswith(p,".jl")),generator_sha256=pchash(joinpath(@__DIR__,"p2_resolution_cases.jl")),guard=PCGUARD,options=PCOPT,sizes=[60,84],cohorts=["normal","tight_reactive","saturation"],configuration="Supplied fixed taps/shunts;zero movement;frozen shared droop;equal preventive response",repetitions=3,timing="rotate exhaustive and guarded; warm medians reps2-3; no concurrent solves",gate="all anchors accepted; nonzero screens,zero misses versus union of exhaustive failures; guard time benefit reported separately",ranking="Frozen advisory priority: lower active headroom first then pre-solve contingency_screening_scores order; never safety acceptance",input_hashes=Dict(x.case.id=>pchash(joinpath(d,x.case.id*"-planned.json")) for x in inputs)))
 rows=[]
 for x in inputs
  sub=joinpath(d,x.case.id);mkpath(sub);avr=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in x.case.generators];anchor=nothing
  for k in 1:2
   anchor=solve_opf(x.case;reactive_assignments=avr,PCOPT...);v=isnothing(anchor.state) ? nothing : validate_equilibrium(x.case,anchor;reactive_assignments=avr);pcsave(joinpath(sub,"anchor-$k.json"),(;result=anchor,validation=v));!isnothing(v)&&v.valid&&break
  end
  if isnothing(anchor.state)||!validate_equilibrium(x.case,anchor;reactive_assignments=avr).valid
   push!(rows,(;id=x.case.id,base_valid=false));continue
  end
  c=p2_large_sparse_overlay(x.case,anchor.state;cohort=x.cohort);participation=Dict(g.id=>1. for g in c.generators if g.available);write_study(joinpath(sub,"study.json"),Study(c;participation));pcsave(joinpath(sub,"base.json"),anchor.state)
  pcsave(joinpath(sub,"scores.json"),contingency_screening_scores(c,anchor.state))
  runs=[]
  for rep in 1:3,guarded in circshift([false,true],rep-1)
   phases=Dict{Symbol,Float64}();m=@timed assess_contingency_pipeline(c,anchor.state;PCOPT...,PCGUARD...,participation,screening_enabled=guarded,_phase_timings=phases)
   filename="$rep-$(guarded ? "guarded" : "exhaustive").json";pcsave(joinpath(sub,filename),m.value);push!(runs,(;rep,guarded,seconds=m.time,bytes=m.bytes,phases,path=filename))
  end
  push!(rows,(;id=x.case.id,base_valid=true,runs));pcsave(joinpath(d,"summary.json"),rows);println(x.case.id," heldout complete");flush(stdout)
 end
 pcsave(joinpath(d,"summary.json"),rows)
end
heldout()
