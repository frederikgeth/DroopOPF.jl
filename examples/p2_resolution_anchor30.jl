include("p2_completion.jl")
using MadNLP
function anchor30()
 d=joinpath(PCROOT,"artifacts/p2_resolution/anchor30_polish");ispath(d)&&error("Preserve prior study");mkpath(d);src=joinpath(PCOUT,"public_sources/pglib_opf_case30_as.m");c=load_matpower_case(src);avr=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in c.generators if g.available];raw=JSON.parsefile(joinpath(PCOUT,"public_run/pglib_opf_case30_as/anchor-2.json"))["state"];old=ACState((Float64.(raw[k]) for k in ("vm","va","pg","qg"))...)
 pcsave(joinpath(d,"protocol.json"),(;runner_sha256=pchash(@__FILE__),source_sha256=pchash(src),configuration="Fixed supplied taps/shunts;zero movement;AVR1pu anchor;any admitted overlay uses original predetermined P2 rule and is frozen before outages;equal preventive response",attempts="MadNLP default and failed-iterate starts; Ipopt adaptive barrier failed-iterate start; smoothing1e-7/absolute reactive1e-8;1500iterations/60 seconds",scope="Development anchor recovery; MATPOWER adapter retains documented source-cost and angle-constraint exclusions"))
 rows=[];accepted=nothing
 for (label,start,solver) in (("mad-default",nothing,:madnlp),("mad-saved",old,:madnlp),("ipopt-adaptive",old,:ipopt))
  opts=Dict{String,Any}("tol"=>1e-9,"max_iter"=>1500,(solver==:ipopt ? "max_cpu_time" : "max_wall_time")=>60.);solver==:ipopt&&(opts["mu_strategy"]="adaptive")
  m=@timed solve_opf(c;reactive_assignments=avr,initial_state=start,sparse_balance=true,smooth_epsilon=1e-7,smooth_reactive_epsilon=1e-8,optimizer_factory=solver==:ipopt ? DroopOPF.Ipopt.Optimizer : MadNLP.Optimizer,optimizer_attributes=opts);v=isnothing(m.value.state) ? nothing : validate_equilibrium(c,m.value;reactive_assignments=avr);valid=!isnothing(v)&&v.valid&&m.value.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
  pcsave(joinpath(d,label*".json"),(;result=m.value,validation=v,valid,seconds=m.time));push!(rows,(;label,valid,status=m.value.termination_status));valid&&isnothing(accepted)&&(accepted=m.value.state)
 end
 pcsave(joinpath(d,"summary.json"),rows)
 if !isnothing(accepted)
  target=pcoverlay(c,accepted);participation=Dict(g.id=>1. for g in target.generators if g.available);write_study(joinpath(d,"study.json"),Study(target;participation));pcsave(joinpath(d,"base.json"),accepted)
  m=@timed assess_contingency_pipeline(target,accepted;participation,PCOPT...,screening_enabled=false);pcsave(joinpath(d,"exhaustive.json"),(;result=m.value,seconds=m.time))
 end
 println("30 bus anchor mitigation complete: ",rows)
end
anchor30()
