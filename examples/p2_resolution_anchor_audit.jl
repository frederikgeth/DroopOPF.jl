include("p2_completion.jl")
function anchors()
 d=joinpath(PCROOT,"artifacts/p2_resolution");c=load_matpower_case(joinpath(PCOUT,"public_sources/pglib_opf_case30_as.m"));avr=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in c.generators if g.available];errors=[];n=0;details=[]
 files=[joinpath(d,"anchor30-$x.json") for x in ("saved","flat","default")];append!(files,[joinpath(d,"anchor30_polish",x*".json") for x in ("mad-default","mad-saved","ipopt-adaptive")])
 for p in files
  saved=JSON.parsefile(p);r=saved["result"];raw=r["state"];isnothing(raw)&&continue;state=ACState((Float64.(raw[k]) for k in ("vm","va","pg","qg"))...)
  v=validate_equilibrium(c,state;reactive_assignments=avr,smooth_epsilon=r["smooth_epsilon"],smooth_reactive_epsilon=r["smooth_reactive_epsilon"],smooth_reactive_relative_epsilon=r["smooth_reactive_relative_epsilon"])
  v.valid==saved["validation"]["valid"]||push!(errors,p);n+=1;bal=power_balance(c,state);i=argmax(abs.(bal.vector));j=mod1(i,length(c.network.buses));push!(details,(;file=basename(p),bus=c.network.buses[j].id,axis=i<=length(c.network.buses) ? :active : :reactive,residual=bal.vector[i],violations=v.violations))
 end
 pcsave(joinpath(d,"anchor_replay.json"),(;anchors=n,errors,largest_balance_residuals=details));@assert isempty(errors);println("Replayed ",n," rejected anchors with zero discrepancies")
end
anchors()
