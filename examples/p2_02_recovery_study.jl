# Fresh bounded comparison; experimental methods exist only in this process.
using DroopOPF,JSON,SHA,LinearAlgebra
include("p2_02_recovery_cases.jl")
const ROOT=normpath(joinpath(@__DIR__,".."));const OUT=abspath(ARGS[2])
save(p,x)=open(io->JSON.print(io,DroopOPF._json_data(x),2),p,"w")
hashfile(p)=bytes2hex(sha256(read(p)))
const OPTIONS=(;smooth_epsilon=1e-5,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>500,"max_cpu_time"=>5.))
const POLICY=(;loading_threshold=.8,voltage_guard=.02,reactive_guard=.1,ac_risk_guard=true)
function hashes()
 files=vcat([joinpath(ROOT,"src",p) for p in readdir(joinpath(ROOT,"src")) if endswith(p,".jl")],
 [@__FILE__,joinpath(@__DIR__,"p2_02_recovery_cases.jl"),joinpath(OUT,"candidate_predictor.jl"),joinpath(OUT,"reference_predictor.jl"),joinpath(ROOT,"Project.toml"),joinpath(ROOT,"Manifest.toml")])
 Dict(relpath(p,ROOT)=>hashfile(p) for p in files)
end
function prepare()
 isfile(joinpath(OUT,"frozen.json")) && error("Already frozen; preserve it")
 regression=JSON.parsefile(joinpath(ROOT,"artifacts/p2_02_diagnosis/agreement_regression.json"));@assert regression["candidate_misses"]==0 && regression["outages"]==1110
 inputs=p2_recovery_inputs();@assert length(inputs)==4
 mkpath(joinpath(OUT,"planned_cases"))
 for input in inputs;write_study(joinpath(OUT,"planned_cases",input.case.id*".json"),Study(input.case));end
 save(joinpath(OUT,"plan.json"),(;expected_inputs=4,expected_unique_outages=128,inputs,
  policies=(:legacy,:reference,:guarded,:exhaustive),repetitions=4,warm_repetitions=(2,3,4),options=OPTIONS,policy=POLICY,
  equipment="fixed supplied taps/shunts, zero movement, frozen shared droop, preventive equal-weight active response",
  anchor="New cases: positive-Q cap .6 per generator for stressed inputs; no old bounds repaired. Known-case warmup before fresh anchors.",
  scope="new synthetic 16/32-bus two-chord light/deadband and positive-reactive/proportional cohorts; excludes S2",
  timing="serial, four rotating orders; sum per-input median warm repetitions 2-4, filter and exact phases included, disk excluded",
  endpoints="Any screened unresolved exhaustive outcome is a miss; union all exhaustive repetitions. Invalid anchors remain unassessed, never passes."))
 save(joinpath(OUT,"frozen.json"),(;code_hashes=hashes(),plan_sha256=hashfile(joinpath(OUT,"plan.json")),
  planned_case_hashes=Dict(basename(p)=>hashfile(p) for p in readdir(joinpath(OUT,"planned_cases");join=true)),
  development_regression_sha256=hashfile(joinpath(ROOT,"artifacts/p2_02_diagnosis/agreement_regression.json")),
  frozen_before_any_new_base_or_outage_solve=true,production_library_unchanged=true))
 println("Prepared/frozen four new cases, 128 outages, no optimizer calls")
end
function runstudy()
 length(ARGS)>=3 && ARGS[3]=="standing-fixed-controls" || error("Standing authorization token required")
 frozen=JSON.parsefile(joinpath(OUT,"frozen.json"));@assert frozen["code_hashes"]==hashes()
 @assert frozen["plan_sha256"]==hashfile(joinpath(OUT,"plan.json"))
 @assert all(hashfile(joinpath(OUT,"planned_cases",p))==h for (p,h) in frozen["planned_case_hashes"])
 held=joinpath(OUT,"heldout");ispath(held) && error("Preserve existing study; no overwrite")
 mkpath(held);BLAS.set_num_threads(1)
 include_string(DroopOPF,read(joinpath(OUT,"candidate_predictor.jl"),String),joinpath(OUT,"candidate_predictor.jl"))
 @eval DroopOPF begin
  const _p2_selected_predictor=Ref(:reference)
  function _droop_screening_diagnostics(case::Case,base::ACState,outage::Contingency;participation,voltage_guard,loading_threshold,reactive_guard)
   f=_p2_selected_predictor[]==:candidate ? _p2_candidate_diagnostics : _p2_reference_diagnostics
   f(case,base,outage;participation,voltage_guard,loading_threshold,reactive_guard)
  end
 end
 save(joinpath(held,"authorization.json"),(;configuration="fixed supplied taps/shunts, zero movement, frozen shared droop, preventive equal weights",standing_instruction="2026-10-19: no equipment confirmation until further notice",julia=string(VERSION),threads=Threads.nthreads(),blas_threads=BLAS.get_num_threads(),frozen_sha256=hashfile(joinpath(OUT,"frozen.json"))))
 # Compile on exposed development data; this is not a fresh validation case.
 known=read_study(joinpath(ROOT,"artifacts/p2_02_scale_guard/planned_cases/p2-scale-12-chord-light.json")).case
 assignments=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in known.generators]
 save(joinpath(held,"known_warmup.json"),solve_opf(known;reactive_assignments=assignments,OPTIONS...))
 rows=[]
 for input in p2_recovery_inputs()
  dir=joinpath(held,input.case.id);mkpath(dir);row=Dict{String,Any}("id"=>input.case.id,"base_valid"=>false,"attempts"=>[])
  try
   assignments=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in input.case.generators]
   anchor=solve_opf(input.case;reactive_assignments=assignments,OPTIONS...);save(joinpath(dir,"anchor.json"),anchor)
   physical=isnothing(anchor.state) ? nothing : validate_equilibrium(input.case,anchor;reactive_assignments=assignments)
   save(joinpath(dir,"anchor_validation.json"),physical)
   !isnothing(physical) && physical.valid || error("AVR anchor rejected")
   case=p2_recovery_overlay(input.case,anchor.state;width=input.width,voltage_span=input.voltage_span,anchor_regime=input.anchor_regime)
   participation=Dict(g.id=>1. for g in case.generators if g.available)
   write_study(joinpath(dir,"input.json"),Study(case;participation));save(joinpath(dir,"base.json"),anchor.state);row["base_valid"]=true
   for rep in 1:4,policy in circshift([:legacy,:reference,:guarded,:exhaustive],rep-1)
    DroopOPF._p2_selected_predictor[]=policy==:guarded ? :candidate : :reference
    phases=Dict{Symbol,Float64}()
    measured=@timed Base.invokelatest(assess_contingency_pipeline,case,anchor.state;POLICY...,OPTIONS...,participation,
     droop_response_guard=policy in (:reference,:guarded),screening_enabled=policy!=:exhaustive,_phase_timings=phases)
    name="$rep-$policy.json";pipe=measured.value;save(joinpath(dir,name),pipe)
    push!(row["attempts"],(;repetition=rep,policy,elapsed=measured.time,phases,screened=pipe.checks.screened_count,exact_evaluated=pipe.checks.exact_evaluated_count,complete=pipe.checks.complete,path=name))
    println(input.case.id," ",rep," ",policy," screened=",pipe.checks.screened_count);flush(stdout)
   end
  catch err
   err isa InterruptException && rethrow();row["error"]=sprint(showerror,err)
  end
  push!(rows,row);save(joinpath(dir,"summary.json"),row);save(joinpath(held,"summary.json"),rows)
 end
 @assert frozen["code_hashes"]==hashes()
 save(joinpath(held,"completion.json"),(;attempted_inputs=length(rows),frozen_source_unchanged=true))
end
ARGS[1]=="prepare" ? prepare() : ARGS[1]=="run" ? runstudy() : error("Expected prepare or run")
