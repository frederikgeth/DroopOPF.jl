# Explicit follow-up: optimize preventive dispatch without changing frozen curves.
include("p2_completion.jl")
function pcdesign()
 d=joinpath(PCOUT,"public_design");ispath(d)&&error("Preserve prior design attempt");mkpath(d)
 source=joinpath(PCOUT,"public_run/pglib_opf_case39_epri")
 study=read_study(joinpath(source,"study.json"));raw=JSON.parsefile(joinpath(source,"base.json"));base=ACState((Float64.(raw[k]) for k in ("vm","va","pg","qg"))...)
 pcsave(joinpath(d,"protocol.json"),(;configuration="Supplied fixed taps/shunts, zero movement, unchanged frozen public-study droop, equal preventive active response; base active dispatch may optimize",reason="Test whether preventive redispatch resolves the unresolved fixed-OPF-base outcomes on the 39-bus public network",input_sha256=pchash(joinpath(source,"study.json")),runner_sha256=pchash(@__FILE__),scope="development follow-up, not fresh held-out guard qualification",bounds="Full enumeration and max 5 scenario-addition rounds, batch4, max 1000 iterations and 60 CPU seconds per solve"))
 options=(;smooth_epsilon=1e-5,sparse_balance=true,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>1000,"max_cpu_time"=>60.))
 full=DroopOPF._copy_study(study;contingencies=eligible_contingencies(contingency_catalog(study.case)))
 m=@timed solve_scopf(full;options...,initial_states=Dict(id=>base for id in [:base;[c.id for c in full.contingencies]]))
 pcsave(joinpath(d,"full_enumeration.json"),(;result=m.value,report=equilibrium_report(full,m.value),seconds=m.time,bytes=m.bytes))
 locked=[DroopControl(i;slope_bounds=(control.slope,control.slope)) for (i,control) in enumerate(study.case.controls)]
 m=@timed optimize_droop_security(study,locked;max_rounds=5,batch_size=4,initial_states=Dict(:base=>base),solver_kwargs=options,evaluation_kwargs=(;optimizer_attributes=options.optimizer_attributes))
 pcsave(joinpath(d,"scenario_addition.json"),(;result=m.value,seconds=m.time,bytes=m.bytes))
 println("Public 39-bus preventive dispatch follow-up complete")
end
pcdesign()
