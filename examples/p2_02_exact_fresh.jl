# Frozen fresh qualification of existing sparse_balance option, with unchanged guard.
using DroopOPF,JSON,SHA,LinearAlgebra
include("p2_02_exact_fresh_cases.jl")
const ROOT=normpath(joinpath(@__DIR__,".."));const OUT=joinpath(ROOT,"artifacts/p2_02_exact_profile/fresh")
const OPTIONS=(;smooth_epsilon=1e-5,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>500,"max_cpu_time"=>5.))
const POLICY=(;loading_threshold=.8,voltage_guard=.02,reactive_guard=.1,ac_risk_guard=true,droop_response_guard=true)
const POLICIES=[:dense_exhaustive,:sparse_exhaustive,:dense_guarded,:sparse_guarded]
save(p,x)=open(io->JSON.print(io,DroopOPF._json_data(x),2),p,"w")
hashfile(p)=bytes2hex(sha256(read(p)))
function hashes()
 files=vcat([joinpath(ROOT,"src",p) for p in readdir(joinpath(ROOT,"src")) if endswith(p,".jl")],
 [@__FILE__,joinpath(@__DIR__,"p2_02_exact_fresh_cases.jl"),joinpath(ROOT,"Project.toml"),joinpath(ROOT,"Manifest.toml")])
 Dict(relpath(p,ROOT)=>hashfile(p) for p in files)
end
function prepare()
 ispath(OUT) && error("Preserve prior freeze");mkpath(joinpath(OUT,"planned_cases"))
 for input in p2_exact_fresh_inputs();write_study(joinpath(OUT,"planned_cases",input.case.id*".json"),Study(input.case));end
 save(joinpath(OUT,"plan.json"),(;inputs=4,outages=128,policies=POLICIES,repetitions=4,warm_repetitions=[2,3,4],options=OPTIONS,policy=POLICY,
  configuration="fixed supplied taps/shunts, zero movement, frozen shared droop, preventive equal-weight active response; S2 excluded",
  candidate="existing sparse_balance=true; only exact-zero admittance terms removed; production defaults unchanged",
  endpoints="misses against union of unresolved dense AND sparse exhaustive outcomes across all repetitions; independent saved-state validation; paired classifications and accepted state differences; sum per-case median warm elapsed time",
  promotion_gate="all anchors valid; zero guard misses; identical paired exhaustive classifications; maximum common accepted vm/va/pg/qg difference <= 1e-5; candidate faster in summed medians for both exhaustive and guarded; finite-scope recommendation only",
  timing="serial BLAS=1 Julia=1; rotate four policy orders; disk excluded; no concurrent solver workloads; no tuning after freeze"))
 save(joinpath(OUT,"frozen.json"),(;code_hashes=hashes(),plan_sha256=hashfile(joinpath(OUT,"plan.json")),planned_case_hashes=Dict(basename(p)=>hashfile(p) for p in readdir(joinpath(OUT,"planned_cases");join=true)),before_any_fresh_solve=true))
 println("Frozen four fresh cases, 128 outages")
end
function runstudy()
 f=JSON.parsefile(joinpath(OUT,"frozen.json"));@assert f["code_hashes"]==hashes()
 @assert f["plan_sha256"]==hashfile(joinpath(OUT,"plan.json"))
 @assert all(hashfile(joinpath(OUT,"planned_cases",p))==h for (p,h) in f["planned_case_hashes"])
 held=joinpath(OUT,"heldout");ispath(held) && error("Preserve prior run");mkpath(held);BLAS.set_num_threads(1)
 save(joinpath(held,"environment.json"),(;julia=string(VERSION),threads=Threads.nthreads(),blas_threads=BLAS.get_num_threads(),standing_authorization="2026-10-19 fixed controls; no reconfirmation until further notice"))
 known=read_study(joinpath(ROOT,"artifacts/p2_02_scale_guard/planned_cases/p2-scale-12-chord-light.json")).case
 save(joinpath(held,"known_warmup.json"),solve_opf(known;reactive_assignments=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in known.generators],OPTIONS...))
 rows=[]
 for input in p2_exact_fresh_inputs()
  dir=joinpath(held,input.case.id);mkpath(dir);row=Dict{String,Any}("id"=>input.case.id,"base_valid"=>false,"attempts"=>[])
  try
   assignments=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in input.case.generators]
   anchor=solve_opf(input.case;reactive_assignments=assignments,OPTIONS...);save(joinpath(dir,"anchor.json"),anchor)
   validation=isnothing(anchor.state) ? nothing : validate_equilibrium(input.case,anchor;reactive_assignments=assignments)
   save(joinpath(dir,"anchor_validation.json"),validation)
   !isnothing(validation) && validation.valid || error("Rejected anchor")
   case=p2_exact_fresh_overlay(input.case,anchor.state;width=input.width,voltage_span=input.voltage_span,anchor_regime=input.anchor_regime)
   participation=Dict(g.id=>1. for g in case.generators if g.available)
   write_study(joinpath(dir,"input.json"),Study(case;participation));save(joinpath(dir,"base.json"),anchor.state);row["base_valid"]=true
   for rep in 1:4,policy in circshift(POLICIES,rep-1)
    phases=Dict{Symbol,Float64}();sparse=policy in (:sparse_exhaustive,:sparse_guarded);screening=policy in (:dense_guarded,:sparse_guarded)
    measured=@timed assess_contingency_pipeline(case,anchor.state;OPTIONS...,POLICY...,participation,sparse_balance=sparse,screening_enabled=screening,_phase_timings=phases)
    pipe=measured.value;name="$rep-$policy.json";save(joinpath(dir,name),pipe)
    push!(row["attempts"],(;repetition=rep,policy,elapsed=measured.time,gc_seconds=measured.gctime,bytes=measured.bytes,phases,screened=pipe.checks.screened_count,exact_evaluated=pipe.checks.exact_evaluated_count,complete=pipe.checks.complete,path=name))
    println(input.case.id," ",rep," ",policy," screened=",pipe.checks.screened_count);flush(stdout)
   end
  catch err
   err isa InterruptException && rethrow();row["error"]=sprint(showerror,err)
  end
  push!(rows,row);save(joinpath(dir,"summary.json"),row);save(joinpath(held,"summary.json"),rows)
 end
 @assert f["code_hashes"]==hashes()
end
ARGS[1]=="prepare" ? prepare() : ARGS[1]=="run" ? runstudy() : error("Expected prepare or run")
