# Necessary active-flow/loss relaxation for the difficult 110% G60 outage.
# Uses the existing optional HiGHS environment. No SCOPF acceptance can follow
# from a feasible relaxed point. Positive infeasibility gaps are rational proofs.
using DroopOPF, SHA
const JuMP=DroopOPF.JuMP
const JSON=DroopOPF.JSON
using .JuMP
import HiGHS
const AL_ROOT=normpath(joinpath(@__DIR__,".."))
const AL_OUT=joinpath(AL_ROOT,"artifacts/s2_scopf/ieee500_native/active_loss_diagnostic")
const FR=DroopOPF._FR
fq=DroopOPF._fq

function active_loss_diagnostic(;factor=1.1,outage=60,max_rounds=60,seconds=60.)
    mkpath(AL_OUT)
    study=read_study(joinpath(AL_ROOT,"artifacts/s2_scopf/ieee500_native/pilot_study.json"))
    case=scenario_case(DroopOPF._feasibility_scaled_case(study.case,factor),Contingency(:diagnostic;generator_ids=[outage]))
    @assert all(s.conductance==0 for s in case.network.shunts)
    @assert all(all(==(0),b.step_conductances) for b in case.network.banks)
    @assert all(b.resistance>=0 for b in case.network.branches)
    d=DroopOPF._FeasibilityLP(Tuple{FR,FR}[],Tuple{Dict{Int,FR},FR}[],Int[],Int[],Int[],Int[],
        Tuple{Int,Int}[],Tuple{Dict{Int,FR},Dict{Int,FR},FR}[])
    var(l,u)=DroopOPF._flp_var!(d,l,u)
    aff(t)=DroopOPF._flp_aff(t)
    eq(a,b)=DroopOPF._flp_eq!(d,a,b)
    branches=filter(b->b.available,case.network.branches)
    pg=[var(g.available ? g.p_min : 0.,g.available ? g.p_max : 0.) for g in case.generators]
    pf=[var(-b.thermal_limit,b.thermal_limit) for b in branches]
    pt=[var(-b.thermal_limit,b.thermal_limit) for b in branches]
    loss=[var(0.,2*b.thermal_limit) for b in branches]
    z=var(0.,sum(2*b.thermal_limit for b in branches)+1.)
    eq(aff([z=>1;[i=>-1 for i in loss]]),0)
    for (k,b) in enumerate(branches);eq(aff([loss[k]=>1,pf[k]=>-1,pt[k]=>-1]),0);end
    for bus in case.network.buses
        terms=Pair{Int,Int}[]
        append!(terms,[pg[i]=>1 for (i,g) in enumerate(case.generators) if g.bus_id==bus.id])
        append!(terms,[pf[k]=>-1 for (k,b) in enumerate(branches) if b.from_bus==bus.id])
        append!(terms,[pt[k]=>-1 for (k,b) in enumerate(branches) if b.to_bus==bus.id])
        demand=sum(fq(l.p) for l in case.loads if l.bus_id==bus.id;init=fq(0))
        eq(aff(terms),demand)
    end
    buses=Dict(b.id=>b for b in case.network.buses);controls=Dict(t.branch_id=>t for t in study.tap_controls)
    coefficients=[(fq(b.resistance)*(haskey(controls,b.id) ? fq(controls[b.id].lower) : fq(b.tap_ratio))^2/fq(buses[b.from_bus].v_max)^2,
                   fq(b.resistance)/fq(buses[b.to_bus].v_max)^2) for b in branches]
    model=Model(HiGHS.Optimizer);set_silent(model)
    @variable(model,DroopOPF._flp_round(d.bounds[i][1],false)<=x[i=1:length(d.bounds)]<=DroopOPF._flp_round(d.bounds[i][2],true))
    @objective(model,Min,x[z])
    refs=[DroopOPF._flp_solver_row!(model,x,d,row) for row in d.rows]
    supports=Any[];history=Any[];multipliers=Any[];gap=nothing;lower=nothing;start=time()
    for round in 1:max_rounds
        remaining=seconds-(time()-start);remaining>0 || break
        set_time_limit_sec(model,remaining);optimize!(model)
        push!(history,(;round,status=string(termination_status(model)),rows=length(d.rows)))
        if dual_status(model)==JuMP.MOI.INFEASIBILITY_CERTIFICATE
            multipliers=Any[[i,string(fq(-y))] for (i,y) in enumerate(dual.(refs)) if y<0]
            gap=DroopOPF._flp_margin(d,multipliers);break
        end
        has_values(model) || break
        multipliers=Any[[i,string(fq(-y))] for (i,y) in enumerate(dual.(refs)) if y<0]
        lower=DroopOPF._flp_margin(d,multipliers;objective_index=z)
        current=value.(x);added=0
        for k in eachindex(branches),side in 1:2
            pvar=side==1 ? pf[k] : pt[k];a=coefficients[k][side];point=current[pvar]
            a* fq(point)^2-fq(current[loss[k]])>fq(1e-8) || continue
            # Any rational support point gives a globally valid quadratic tangent.
            p0=Base.round(BigInt,point*2.0^20)//big(2)^20
            row=(aff([pvar=>2*a*p0,loss[k]=>-1]),a*p0^2)
            push!(d.rows,row);push!(refs,DroopOPF._flp_solver_row!(model,x,d,row))
            push!(supports,(;branch=branches[k].id,side,point=string(p0),coefficient=string(a)));added+=1
        end
        added==0 && break
    end
    payload=(;factor,outage,case= DroopOPF._json_data(case),tap_controls=DroopOPF._json_data(study.tap_controls),
        variable_map=(;pg,pf,pt,loss),variable_bounds=[[string(l),string(u)] for (l,u) in d.bounds],
        rows=[(;coefficients=Dict(string(i)=>string(a) for (i,a) in row),rhs=string(b)) for (row,b) in d.rows],
        objective_index=z,multipliers,supports,history,
        certified_infeasible=!isnothing(gap) && gap>0,strict_gap_exact=isnothing(gap) ? nothing : string(gap),
        verified_loss_lower_pu=isnothing(lower) ? nothing : string(lower),
        remaining_pmax_mw=sum(g.p_max for g in case.generators if g.available)*case.base_power,
        total_load_mw=sum(l.p for l in case.loads)*case.base_power,
        scope="Active nodal balance and terminal-P loss inequalities only; voltage, Q, droop, KVL, angle and demand coupling relaxed. Free tap lower bounds retained conservatively; continuous banks have zero G.",
        limitation="Feasible outer points never establish AC feasibility; only a verified positive rational gap establishes infeasibility.",
        source_sha256=bytes2hex(sha256(read(joinpath(AL_ROOT,"artifacts/s2_scopf/ieee500_native/pilot_study.json")))))
    write(joinpath(AL_OUT,"result.json"),JSON.json(payload;pretty=true))
    println("ACTIVE LOSS certified_infeasible=",payload.certified_infeasible," lower_pu=",payload.verified_loss_lower_pu)
end
abspath(PROGRAM_FILE)==(@__FILE__) && active_loss_diagnostic()
