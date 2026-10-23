# Isolated compatibility adapter: exact saved S2 proportional response.
# Does not change DroopOPF defaults, migrate legacy files, or run on import.
module P2S2
function read_study end
function read_scopf_result end
function write_study end
using DroopOPF, JSON, SHA, JuMP, Ipopt
const ROOT=normpath(joinpath(@__DIR__,".."))
function legacy_data(path,kind)
    raw=JSON.parsefile(path)
    raw["kind"]==kind || error("Wrong S2 payload kind")
    get(raw,"active_response","s2_proportional_v1") in ("s2_proportional_v1",) ||
        error("This isolated adapter requires the exact S2 proportional contract")
    raw["data"]
end
# Reuse structural decoding only. The response semantics are implemented below.
source=read(joinpath(ROOT,"src/scopf_io.jl"),String)
a=findfirst("function read_study(path::AbstractString)",source).start
b=findnext("function _scopf_result_from_data",source,a).start
body=source[a:prevind(source,b)]
body=replace(body,"_read_scopf_json(path, \"DroopOPF.Study\")"=>"legacy_data(path, \"DroopOPF.Study\")")
for name in ("_reactive_assignments_from_data","_tap_controls_from_data","_shunt_controls_from_data","_control_policy_from_data")
    global body=replace(body,name=>"DroopOPF."*name)
end
include_string(@__MODULE__,body,"p2_structural_study_decoder")
read_scopf_result(path)=DroopOPF._scopf_result_from_data(legacy_data(path,"DroopOPF.SCOPFResult"))
function write_study(path,study)
    open(path,"w") do io
        JSON.print(io,Dict("schema_version"=>1,"kind"=>"DroopOPF.Study",
            "active_response"=>"s2_proportional_v1","data"=>DroopOPF._json_data(study)),2)
    end
end
include("s2_500bus_network_reduction.jl")
# Scoped override of the S2 model-builder hook. No global library method changes.
function el_response!(m,study,c,base,v,prefix,cap,prior,scale)
    cap==0 || error("P2 acceptance never permits response relaxation")
    total=sum(get(study.participation,g.id,0.) for g in c.generators if g.available)
    total>0 || error("No surviving S2 participant")
    initial=isnothing(prior) || isnothing(prior.delta) ? 0. : prior.delta*scale
    delta=@variable(m,base_name=prefix*"s2_response_signal",start=initial)
    for (i,g) in enumerate(c.generators)
        g.available || continue
        alpha=get(study.participation,g.id,0.)/total
        @constraint(m,v.pg[i]==base.pg[i]+alpha*delta)
        if haskey(study.redispatch_limits,g.id)
            limit=study.redispatch_limits[g.id]
            @constraint(m,-limit<=v.pg[i]-base.pg[i]<=limit)
        end
    end
    delta,VariableRef[]
end
p2_ac(c;kwargs...)=DroopOPF._build_acopf_model(c;sparse_balance=true,kwargs...)
function p2_context(size)
    if size==14
        d=joinpath(ROOT,"artifacts/s2_scopf/ieee14_native/multidemand/design-ipopt")
        study=read_study(joinpath(d,"controller.json"));result=read_scopf_result(joinpath(d,"result-1.0.json"))
        reference=read_study(joinpath(ROOT,"artifacts/s1_arpae14_joint_reference/relative5-study.json")).case
        raw=JSON.parsefile(joinpath(ROOT,"artifacts/s1_arpae14_closeout/angle_limits.json"))
        states=Dict()
        for f in (.9,.95,1.,1.05,1.1)
            r=read_scopf_result(joinpath(d,"result-$f.json"));zeros=Dict(l.id=>0. for l in study.case.loads)
            for (id,state) in r.states
                states[(f,id)]=(;state,taps=r.tap_settings[id],banks=r.shunt_settings[id],dr=copy(zeros),shed=copy(zeros),delta=get(r.balancing_power,id,nothing))
            end
        end
    elseif size==500
        d=joinpath(ROOT,"artifacts/s2_scopf/ieee500_native/incremental_shared_recovery/expanded-105-r1-feasibility-p1")
        seed=el_read_point(d;stage="feasibility");study=seed.study;states=seed.states
        reference=read_study(joinpath(ROOT,"artifacts/s1_arpae500/calibrated-study.json")).case
        raw=JSON.parsefile(joinpath(ROOT,"artifacts/s1_free_droop/500/angle_limits.json"))
        result=(;states=Dict(:base=>states[(1.05,:base)].state),tap_settings=Dict(:base=>states[(1.05,:base)].taps),shunt_settings=Dict(:base=>states[(1.05,:base)].banks))
    else;error("Supported S1/S2 cases: 14 or 500");end
    controls=s214_multi_controls(reference)
    angles=Dict(parse(Int,k)=>Tuple(Float64.(v)) for (k,v) in raw)
    events=eligible_contingencies(contingency_catalog(study.case))
    @assert length(events)==(size==14 ? 24 : 389)
    (;study,result,controls,angles,events,reference,seed=(;study,states),size,source=d)
end
function p2_attempt(x,folder,factors,events;seed=x.seed,fixed_controller=false,fixed_base=false,seconds=30.,retry=false)
    ispath(folder)&&error("Do not overwrite attempt: $folder");mkpath(folder)
    emergency=x.size==500
    contract=(;case_size=x.size,factors,outages=[e.id for e in events],emergency,relief=emergency,
        thermal_multiplier=emergency ? 1.1 : 1.,fixed_controller,fixed_base,zero_shedding=true,zero_dr=!emergency,
        response_relaxation_cap=0.,restore=false,active_response="s2_proportional_v1",
        initial_controller=seed.study.case.controls,objective=fixed_base ? "feasibility" : x.size==14 ? "nominal base active loss" : "feasibility",
        seconds,retry,reference_controls=x.reference.controls,angles=x.angles,
        source_study=joinpath(x.source,x.size==14 ? "controller.json" : "controller-feasibility.json"),
        fixed_base_reference=fixed_base ? [(;factor=f,seed.states[(f,:base)]...) for f in factors] : nothing)
    fd_save(joinpath(folder,"contract.json"),contract)
    t=@timed el_build(x,factors,events;seed,solver=:ipopt,emergency,relief=emergency,
        thermal_multiplier=emergency ? 1.1 : 1.,fixed_controller,fixed_base,restore=false,
        zero_shedding=true,zero_dr=!emergency,ac_builder=x.size==500 ? nr_build_ac : p2_ac,penalty_proxies=false,direct_relief=x.size==500)
    built=t.value;m=built.m
    if !fixed_base && x.size==14
        nominal=only(b for b in built.blocks if b.id==:base&&b.factor==1.)
        @objective(m,Min,sum(nominal.v.pg)-sum(l.p for l in nominal.normal.loads))
    else
        @objective(m,Min,0.)
    end
    for key in ("bound_push","bound_frac","slack_bound_push","slack_bound_frac");set_optimizer_attribute(m,key,1e-8);end
    set_optimizer_attribute(m,"mu_init",1e-6)
    set_optimizer_attribute(m,"max_cpu_time",seconds);set_optimizer_attribute(m,"max_iter",retry ? 3000 : 1500)
    set_optimizer_attribute(m,"hessian_approximation",retry ? "limited-memory" : "exact")
    solved=@timed optimize!(m)
    record=(;stage="solve",status=string(termination_status(m)),native_success=termination_status(m) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.OPTIMAL,JuMP.MOI.ALMOST_LOCALLY_SOLVED),
        build_seconds=t.time,solve_seconds=solved.time,variables=num_variables(m),constraints=num_constraints(m;count_variable_in_set_constraints=true),
        allocated_bytes=t.bytes+solved.bytes,objective=has_values(m) ? objective_value(m) : nothing)
    fd_save(joinpath(folder,"stages.json"),[record])
    point=try el_save_point(folder,built,"solve",record) catch err
        fd_save(joinpath(folder,"extraction_error.json"),(;error=sprint(showerror,err)));nothing
    end
    audit=nothing
    if !isnothing(point)
        read(`python3 -B $(joinpath(ROOT,"examples/audit_p2_s2_numerics.py")) $folder`,String)
        audit=JSON.parsefile(joinpath(folder,"audit-solve.json"))
    end
    accepted=!isnothing(audit)&&audit["accepted"]
    summary=(;record,accepted,folder=relpath(folder,ROOT))
    fd_save(joinpath(folder,"summary.json"),summary)
    println("P2 ",x.size," ",basename(folder)," ",record.status," accepted=",accepted);flush(stdout)
    (;point,audit,summary)
end
end # module
