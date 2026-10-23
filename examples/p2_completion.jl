# Frozen public-network qualification; no equipment or droop optimization.
using DroopOPF, JSON, SHA, LinearAlgebra
include("p2_s2_500.jl")
# The large benchmark is loaded from the exact S2 contract; no P2 overlay.
pc_large_benchmark_inputs() = p2_s2_500_inputs()
const PCROOT=normpath(joinpath(@__DIR__,".."))
const PCOUT=joinpath(PCROOT,"artifacts/p2_completion")
const PCOPT=(;smooth_epsilon=1e-5,sparse_balance=true,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>500,"max_cpu_time"=>5.))
const PCGUARD=(;loading_threshold=.8,voltage_guard=.02,reactive_guard=.1,ac_risk_guard=true,droop_response_guard=true)
pcsave(p,x)=open(io->JSON.print(io,DroopOPF._json_data(x),2),p,"w")
pchash(p)=bytes2hex(sha256(read(p)))
function pcoverlay(c,s)
 controls=VoltVarDroop[];attachments=GeneratorControlAttachment[];idx=Dict(b.id=>i for (i,b) in enumerate(c.network.buses))
 for (i,g) in enumerate(c.generators)
  g.available || continue
  v=s.vm[idx[g.bus_id]];q=clamp(s.qg[i],g.q_min,g.q_max)
  push!(controls,VoltVarDroop(VoltageSchedule(v;v_db_low=v-.003,v_db_high=v+.003),.04,q,ReactiveCapability(p_min=g.p_min,p_max=g.p_max,q_min=g.q_min,q_max=g.q_max)))
  push!(attachments,GeneratorControlAttachment(g.id,length(controls),RegulatedLocation(:bus,g.bus_id)))
 end
 case=Case(c.id*"-p2-frozen";base_power=c.base_power,base_frequency=c.base_frequency,network=c.network,generators=c.generators,loads=c.loads,controls,attachments)
 validate_equilibrium(case,s).valid || error("Frozen overlay rejected")
 case
end
function pcprepare()
 path=joinpath(PCOUT,"protocol.json");isfile(path)&&error("Preserve frozen protocol")
 pcsave(path,(;configuration="Fixed supplied taps/shunts; zero equipment movement; frozen shared droop; preventive equal weights on all available generators; S2 excluded",options=PCOPT,guard=PCGUARD,
 anchor="AVR at 1 pu; one identical retry; no relaxation or case replacement",overlay="Anchor voltage centred deadband +/-0.003 pu, slope 0.04, anchor Q reference clamped to source limits; frozen before outages",repetitions=3,
 policies=["serial_exhaustive","threaded_exhaustive","serial_guarded"],timing="Rotate policies; first repetition warmup, report medians of 2 and 3; no other solver jobs; BLAS=1; Julia=2; allocations are cumulative, RSS process high-water mark",
 warm_starts="First 12 structurally eligible catalogue entries, flat/base/previous validated neighbour; fixed solver settings and base dispatch; no cherry picking",
 scenario_addition="All eligible outages on smallest accepted public case; max 5 rounds, batch 4, fixed-bound slopes; full enumeration reference; 30 second CPU bound per solve",
 gates="Zero guard misses versus union of exhaustive unresolved outcomes; parallel classifications agree; ranking remains advisory; no infeasibility claim from solver failure; public import/anchor rejection retained",
 hashes=Dict(relpath(p,PCROOT)=>pchash(p) for p in vcat([@__FILE__],readdir(joinpath(PCROOT,"src");join=true),filter(p->endswith(p,".m"),readdir(joinpath(PCOUT,"public_sources");join=true))))))
end
function pcrun()
 protocol=JSON.parsefile(joinpath(PCOUT,"protocol.json"));@assert all(pchash(joinpath(PCROOT,p))==h for (p,h) in protocol["hashes"])
 dir=joinpath(PCOUT,"public_run");ispath(dir)&&error("Preserve prior run");mkpath(dir);BLAS.set_num_threads(1)
 pcsave(joinpath(dir,"environment.json"),(;julia=string(VERSION),threads=Threads.nthreads(),blas=BLAS.get_num_threads()))
 rows=[];scenario_done=false
 for path in sort(filter(p->endswith(p,".m"),readdir(joinpath(PCOUT,"public_sources");join=true));by=p->parse(Int,match(r"case(\d+)",basename(p)).captures[1]))
  name=splitext(basename(path))[1];d=joinpath(dir,name);mkpath(d);row=Dict{String,Any}("id"=>name,"attempts"=>[],"base_valid"=>false)
  try
   c=load_matpower_case(path);row["buses"]=length(c.network.buses);row["zero_active_generators"]=[g.id for g in c.generators if g.available&&g.p_min==g.p_max]
   avr=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in c.generators if g.available]
   anchor=nothing
   for attempt in 1:2
    anchor=solve_opf(c;reactive_assignments=avr,smooth_epsilon=1e-5,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>1000,"max_cpu_time"=>30.))
    pcsave(joinpath(d,"anchor-$attempt.json"),anchor)
    v=isnothing(anchor.state) ? nothing : validate_equilibrium(c,anchor;reactive_assignments=avr);pcsave(joinpath(d,"anchor-$attempt-validation.json"),v)
    !isnothing(v)&&v.valid&&break
   end
   isnothing(anchor.state)&&error("No anchor state")
   validate_equilibrium(c,anchor;reactive_assignments=avr).valid||error("Rejected anchor after identical retry")
   case=pcoverlay(c,anchor.state);base=anchor.state;participation=Dict(g.id=>1. for g in case.generators if g.available);row["base_valid"]=true
   write_study(joinpath(d,"study.json"),Study(case;participation));pcsave(joinpath(d,"base.json"),base)
   pcsave(joinpath(d,"scores.json"),contingency_screening_scores(case,base))
   for rep in 1:3,policy in circshift([:serial_exhaustive,:threaded_exhaustive,:serial_guarded],rep-1)
    m=@timed assess_contingency_pipeline(case,base;participation,PCOPT...,PCGUARD...,workers=policy==:threaded_exhaustive ? 2 : 1,screening_enabled=policy==:serial_guarded)
    filename="$rep-$policy.json";pcsave(joinpath(d,filename),m.value)
    push!(row["attempts"],(;rep,policy,seconds=m.time,bytes=m.bytes,gc_seconds=m.gctime,maxrss=Sys.maxrss(),path=filename));pcsave(joinpath(d,"summary.json"),row)
    println(name," ",rep," ",policy);flush(stdout)
   end
   entries=filter(e->e.disposition==:eligible,contingency_catalog(case).entries);warm=[];previous=base
   for entry in entries[1:min(12,length(entries))]
    study=Study(case;contingencies=[entry.contingency],participation);id=entry.contingency.id
    for policy in (:flat,:base,:neighbour)
     start=policy==:flat ? ACState(ones(length(base.vm)),zeros(length(base.va)),copy(base.pg),copy(base.qg)) : policy==:base ? base : previous
     m=@timed evaluate_contingencies(study,base;PCOPT...,initial_states=Dict(id=>start));report=equilibrium_report(study,m.value)
     pcsave(joinpath(d,"warm-$id-$policy.json"),(;result=m.value,report))
     push!(warm,(;id,policy,seconds=m.time,bytes=m.bytes,valid=report.valid,status=m.value.termination_status))
     if policy==:neighbour&&report.valid;previous=m.value.states[id];end
    end
   end
   pcsave(joinpath(d,"warm_summary.json"),warm)
   if !scenario_done
    scenario_done=true
    locked=[DroopControl(i;slope_bounds=(control.slope,control.slope)) for (i,control) in enumerate(case.controls)]
    options=(;smooth_epsilon=1e-5,sparse_balance=true,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>500,"max_cpu_time"=>30.))
    full=Study(case;contingencies=eligible_contingencies(contingency_catalog(case)),participation)
    m=@timed solve_scopf(full;options...,initial_states=Dict(id=>base for id in [:base;[c.id for c in full.contingencies]]))
    pcsave(joinpath(d,"full_enumeration.json"),(;result=m.value,report=equilibrium_report(full,m.value),seconds=m.time,bytes=m.bytes))
    m=@timed optimize_droop_security(Study(case;participation),locked;max_rounds=5,batch_size=4,initial_states=Dict(:base=>base),solver_kwargs=options,evaluation_kwargs=(;optimizer_attributes=options.optimizer_attributes))
    pcsave(joinpath(d,"scenario_addition.json"),(;result=m.value,seconds=m.time,bytes=m.bytes))
   end
  catch err
   err isa InterruptException&&rethrow();row["error"]=sprint(showerror,err);println(name," ERROR ",row["error"]);flush(stdout)
  end
  push!(rows,row);pcsave(joinpath(d,"summary.json"),row);pcsave(joinpath(dir,"summary.json"),rows)
 end
end
abspath(PROGRAM_FILE)==(@__FILE__)&&(ARGS[1]=="prepare" ? pcprepare() : pcrun())
