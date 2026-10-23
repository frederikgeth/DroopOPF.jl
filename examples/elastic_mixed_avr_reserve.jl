# Phase-I power-balance restoration only. Artificial injections never qualify.
include("p2_mixed_avr_500.jl")
using JuMP
function elastic_period(study,base,parent,t,id,path;seconds=90.)
    mkpath(path);raw=scenario_case(study.case,only(study.contingencies));c=DroopOPF._security_emergency_case(raw)
    nb=length(c.network.buses);nl=length(c.loads);lid=maximum(l.id for l in c.loads)
    loads=[c.loads;[Load(lid+i,b.id;p=0.,q=0.) for (i,b) in enumerate(c.network.buses)]]
    temp=Case(c.id;base_power=c.base_power,base_frequency=c.base_frequency,network=c.network,
        loads,generators=c.generators,controls=c.controls,attachments=c.attachments)
    physical=with_shunt_settings(with_tap_settings(c,parent.tap_settings[:base]),parent.shunt_settings[:base])
    residual=DroopOPF.power_balance(physical,base)
    model=Model(DroopOPF.Ipopt.Optimizer);set_silent(model)
    @variable(model,ep[1:nb]>=0);@variable(model,en[1:nb]>=0)
    @variable(model,qp[1:nb]>=0);@variable(model,qn[1:nb]>=0)
    for i in 1:nb
        set_start_value(ep[i],max(-residual.active[i],0.));set_start_value(en[i],max(residual.active[i],0.))
        set_start_value(qp[i],max(-residual.reactive[i],0.));set_start_value(qn[i],max(residual.reactive[i],0.))
    end
    dr=VariableRef[];shed=VariableRef[]
    for l in c.loads
        d=@variable(model,lower_bound=0.,upper_bound=.01max(l.p,0.),start=0.)
        h=@variable(model,lower_bound=0.,upper_bound=.1max(l.p,0.),start=0.)
        @constraint(model,d+h<=.1max(l.p,0.));push!(dr,d);push!(shed,h)
    end
    @constraint(model,sum(shed)<=10/c.base_power)
    relief=(;p=[Any[dr[i]+shed[i] for i in 1:nl];[ep[i]-en[i] for i in 1:nb]],
        q=[Any[l.p>0 ? (dr[i]+shed[i])*l.q/l.p : 0. for (i,l) in enumerate(c.loads)];[qp[i]-qn[i] for i in 1:nb]])
    tc=[TapControl(a.branch_id;lower=a.lower,upper=a.upper,nominal=a.nominal,
        initial=parent.tap_settings[:base][a.branch_id]) for a in DroopOPF._scenario_tap_controls(study,c)]
    sc=[ShuntControl(a.bank_id;lower=a.lower,upper=a.upper,nominal=a.nominal,
        initial=parent.shunt_settings[:base][a.bank_id]) for a in study.shunt_controls]
    _,v=DroopOPF._build_acopf_model(temp;shared_model=model,set_objective=false,silent=true,
        voltage_epsilon=1e-5,reactive_relative_epsilon=1e-5,reactive_epsilon=nothing,
        reactive_assignments=study.reactive_assignments,initial_state=base,tap_controls=tc,shunt_controls=sc,
        normalize_controls=true,sparse_balance=true,load_relief=relief)
    alpha=DroopOPF._participation(study,c);delta=@variable(model,start=0.)
    for (i,g) in enumerate(c.generators)
        g.available || continue
        @constraint(model,v.pg[i]==base.pg[i]+alpha[i]*delta)
        if haskey(study.redispatch_limits,g.id)
            cap=study.redispatch_limits[g.id];@constraint(model,-cap<=v.pg[i]-base.pg[i]<=cap)
        end
    end
    angles=JSON.parsefile(joinpath(MIX_ROOT,"artifacts/s1_free_droop/500/angle_limits.json"));idx=DroopOPF._bus_indices(c.network)
    for b in c.network.branches
        b.available && haskey(angles,string(b.id)) || continue
        lo,hi=angles[string(b.id)];@constraint(model,lo<=v.va[idx[b.from_bus]]-v.va[idx[b.to_bus]]<=hi)
    end
    @objective(model,Min,sum(ep)+sum(en)+sum(qp)+sum(qn))
    for (k,x) in Dict("tol"=>1e-8,"acceptable_tol"=>1e-7,"max_cpu_time"=>seconds,"max_iter"=>1200,
        "bound_relax_factor"=>0.,"output_file"=>joinpath(path,"ipopt.log"));set_optimizer_attribute(model,k,x);end
    optimize!(model)
    artificial=has_values(model) ? objective_value(model) : Inf
    mix_save(joinpath(path,"preparation.json"),(;role="initializer only; artificial injections forbidden in final native solve",
        status=string(termination_status(model)),artificial_pq_l1_pu=isfinite(artificial) ? artificial : nothing,native_security_accepted=false))
    has_values(model)||return nothing
    state=ACState(value.(v.vm),value.(v.va),value.(v.pg),value.(v.qg))
    equipment=(;taps=Dict(k=>value(x) for (k,x) in v.taps),shunts=Dict(k=>value(x) for (k,x) in v.shunts))
    mix_save(joinpath(path,"point.json"),(;state,equipment,artificial))
    println("ELASTIC ",id," period ",t," artificial=",artificial);flush(stdout)
    (;state,equipment,artificial)
end
function elastic_reserve(root,event_id)
    id=Symbol(event_id);candidate="security-master-guard";factors=[.9,1.,1.05,1.,.9]
    parent=read_multi_period_security(joinpath(root,candidate,"result.json"));x=mix_inputs(joinpath(root,"preflight-elastic-"*event_id))
    event=only(e for e in x.events if e.contingency.id==id)
    scan=only(p for p in readdir(root;join=true) if startswith(basename(p),"scan-"*candidate)&&isdir(joinpath(p,event_id*"-retry")))
    studies=[read_study(joinpath(scan,event_id*"-retry","period-$t.json")) for t in 1:5]
    out=joinpath(root,"resolutions-elastic-"*event_id);mkpath(out);points=Any[]
    for t in 1:5
        p=elastic_period(studies[t],parent.periods[t].states[:base],parent.periods[t],t,id,joinpath(out,"prepare-$t"))
        isnothing(p)&&return
        push!(points,p)
        p.artificial<=1e-3 || return
    end
    starts=[Dict(:base=>parent.periods[t].states[:base],id=>points[t].state) for t in 1:5]
    path=joinpath(out,"joint-native")
    result=mix_attempt(x,path,factors,[event];studies,starts,initial_equipment=[p.equipment for p in points],
        fixed_bases=parent.periods,seconds=90.)
    mix_save(joinpath(out,"summary.json"),(;candidate,rows=[(;event=id,accepted=result.summary.accepted,path,status=result.summary.status)]))
end
length(ARGS)==2||error("provide root and event")
elastic_reserve(abspath(ARGS[1]),ARGS[2])
