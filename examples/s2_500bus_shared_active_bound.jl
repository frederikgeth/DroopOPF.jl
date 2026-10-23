# Necessary active-network relaxation coupling the same preventive dispatch
# across the two largest generator outages and the failing line-36 outage.
# Every numerical acceptance tolerance is enlarged, never tightened.
using DroopOPF,SHA
const JuMP=DroopOPF.JuMP
const JSON=DroopOPF.JSON
using .JuMP
import HiGHS
const SB_ROOT=normpath(joinpath(@__DIR__,".."))
const SB_OUT=joinpath(SB_ROOT,"artifacts/s2_scopf/ieee500_native/emergency_loadability/shared_active_bound")
const SB_FR=DroopOPF._FR
sbq(x::Real)=DroopOPF._fq(x)
function sbq(s::AbstractString)
    occursin("//",s) && return parse(SB_FR,s)
    parts=split(s,'.';keepempty=true)
    length(parts)==1 && return parse(BigInt,s)//big(1)
    scale=big(10)^length(parts[2]);whole=isempty(parts[1]) ? big(0) : parse(BigInt,parts[1])
    (whole*scale+parse(BigInt,parts[2]))//scale
end

function sb_case(c,post)
    n=c.network
    buses=[Bus(b.id;v_min=b.v_min-(post ? .05 : 0.),v_max=b.v_max+(post ? .05 : 0.),reference=b.reference) for b in n.buses]
    branches=[Branch(b.id,b.from_bus,b.to_bus;resistance=b.resistance,reactance=b.reactance,charging=b.charging,
        thermal_limit=b.thermal_limit*(post ? 1.1 : 1.),available=b.available,tap_ratio=b.tap_ratio,phase_shift=b.phase_shift,kind=b.kind) for b in n.branches]
    Case(c.id;base_power=c.base_power,base_frequency=c.base_frequency,network=ACNetwork(buses,branches;shunts=n.shunts,banks=n.banks),
        loads=c.loads,generators=c.generators,controls=c.controls,attachments=c.attachments)
end

function shared_active_bound(factor;seconds=90.,max_rounds=50,normal_targeted=false,
    include_b562=normal_targeted,output_directory=SB_OUT)
    source=joinpath(SB_ROOT,"artifacts/s2_scopf/ieee500_native/pilot_study.json")
    study=read_study(source)
    events=[Contingency(:generator_14;generator_ids=[14]),Contingency(:generator_60;generator_ids=[60]),Contingency(:branch_36;branch_ids=[36])]
    include_b562 && push!(events,Contingency(:branch_562;branch_ids=[562]))
    original=DroopOPF._feasibility_scaled_case(study.case,factor)
    cases=[sb_case(original,false);[sb_case(scenario_case(original,e),!normal_targeted) for e in events]]
    @assert all(s.conductance==0 for s in original.network.shunts)
    @assert all(all(==(0),b.step_conductances) for b in original.network.banks)
    @assert all(get(study.participation,g.id,0.)==g.p_max for g in original.generators if g.available)
    d=DroopOPF._FeasibilityLP(Tuple{SB_FR,SB_FR}[],Tuple{Dict{Int,SB_FR},SB_FR}[],Int[],Int[],Int[],Int[],
        Tuple{Int,Int}[],Tuple{Dict{Int,SB_FR},Dict{Int,SB_FR},SB_FR}[])
    rows_meta=Any[];blocks=Any[];supports=Any[]
    var(l,u)=DroopOPF._flp_var!(d,l,u)
    aff(t)=DroopOPF._flp_aff(t)
    function le(a,b,meta)
        push!(d.rows,(a,sbq(b)));push!(rows_meta,meta)
    end
    function eq(a,b,meta;tolerance=sbq(0))
        le(a,sbq(b)+tolerance,(;meta...,sign=1))
        le(Dict(i=>-v for(i,v) in a),-sbq(b)+tolerance,(;meta...,sign=-1))
    end
    tol=sbq("0.000002");small=sbq("0.00000002");response_tol=tol+sbq("0.000000001")
    taps=Dict(t.branch_id=>t for t in study.tap_controls)
    for (index,c) in enumerate(cases)
        post=index>1;bs=filter(b->b.available,c.network.branches);buses=Dict(b.id=>b for b in c.network.buses)
        pg=[var(g.available ? sbq(g.p_min)-tol : -small,g.available ? sbq(g.p_max)+tol : small) for g in c.generators]
        pf=[var(-sbq(b.thermal_limit)-tol,sbq(b.thermal_limit)+tol) for b in bs]
        pt=[var(-sbq(b.thermal_limit)-tol,sbq(b.thermal_limit)+tol) for b in bs]
        loss_upper=SB_FR[]
        for b in bs
            rate=sbq(b.thermal_limit)+tol;vf=buses[b.from_bus];vt=buses[b.to_bus]
            tmin=haskey(taps,b.id) ? sbq(taps[b.id].lower)-tol : sbq(b.tap_ratio)
            tmax=haskey(taps,b.id) ? sbq(taps[b.id].upper)+tol : sbq(b.tap_ratio)
            charge=abs(sbq(b.charging))/2
            # I_series = conj(t)*I_from - I_charging_from
            #          = -I_to + I_charging_to. Triangle inequalities and the
            # terminal |S| caps give globally valid resistive-loss ceilings.
            from=sbq(b.resistance)*(tmax*rate/(sbq(vf.v_min)-tol)+charge*(sbq(vf.v_max)+tol)/tmin)^2
            to=sbq(b.resistance)*(rate/(sbq(vt.v_min)-tol)+charge*(sbq(vt.v_max)+tol))^2
            push!(loss_upper,min(2*rate,from,to)+tol)
        end
        loss=[var(0,u) for u in loss_upper]
        dr=post && !normal_targeted ? [var(-small,sbq(".01")*sbq(l.p)+small) for l in c.loads] : Int[]
        shed=post && !normal_targeted ? [var(-small,sbq(".1")*sbq(l.p)+small) for l in c.loads] : Int[]
        if post && !normal_targeted
            for (i,l) in enumerate(c.loads)
                le(aff([dr[i]=>1,shed[i]=>1]),sbq(".1")*sbq(l.p)+small,(;family="combined_relief",state=index,load=l.id))
            end
            le(aff([i=>1 for i in shed]),sbq(10)/sbq(c.base_power)+small,(;family="shedding_budget",state=index))
        end
        for (k,b) in enumerate(bs)
            eq(aff([loss[k]=>1,pf[k]=>-1,pt[k]=>-1]),0,(;family="loss_identity",state=index,branch=b.id);tolerance=tol)
        end
        for bus in c.network.buses
            terms=Pair{Int,Int}[]
            append!(terms,[pg[i]=>1 for(i,g) in enumerate(c.generators) if g.bus_id==bus.id])
            append!(terms,[pf[k]=>-1 for(k,b) in enumerate(bs) if b.from_bus==bus.id])
            append!(terms,[pt[k]=>-1 for(k,b) in enumerate(bs) if b.to_bus==bus.id])
            if post && !normal_targeted
                append!(terms,[dr[i]=>1 for(i,l) in enumerate(c.loads) if l.bus_id==bus.id])
                append!(terms,[shed[i]=>1 for(i,l) in enumerate(c.loads) if l.bus_id==bus.id])
            end
            demand=sum((sbq(l.p) for l in c.loads if l.bus_id==bus.id);init=sbq(0))
            eq(aff(terms),demand,(;family="nodal_balance",state=index,bus=bus.id);tolerance=tol)
        end
        cap=sum((sbq(g.p_max) for g in c.generators if g.available);init=sbq(0))
        delta=post ? var(-2*cap-1,2*cap+1) : nothing
        alpha=[g.available ? sbq(study.participation[g.id])/cap : sbq(0) for g in c.generators]
        if post
            basepg=blocks[1].pg
            for (i,g) in enumerate(c.generators)
                g.available || continue
                eq(aff([pg[i]=>sbq(1),basepg[i]=>sbq(-1),delta=>-alpha[i]]),0,
                    (;family="preventive_response",state=index,generator=g.id);tolerance=response_tol)
            end
        end
        coefficients=[(sbq(b.resistance)*(haskey(taps,b.id) ? sbq(taps[b.id].lower)-tol : sbq(b.tap_ratio))^2/(sbq(buses[b.from_bus].v_max)+tol)^2,
                       sbq(b.resistance)/(sbq(buses[b.to_bus].v_max)+tol)^2) for b in bs]
        push!(blocks,(;case=c,pg,pf,pt,loss,dr,shed,delta,alpha,coefficients,branch_ids=[b.id for b in bs]))
    end
    total_loss=var(0,sum(d.bounds[i][2] for b in blocks for i in b.loss)+1)
    eq(aff([total_loss=>1;[i=>-1 for b in blocks for i in b.loss]]),0,(;family="total_loss_identity"))
    m=Model(HiGHS.Optimizer);set_silent(m)
    @variable(m,DroopOPF._flp_round(d.bounds[i][1],false)<=x[i=1:length(d.bounds)]<=DroopOPF._flp_round(d.bounds[i][2],true))
    @objective(m,Min,x[total_loss])
    refs=[DroopOPF._flp_solver_row!(m,x,d,row) for row in d.rows]
    history=Any[];multipliers=Any[];gap=nothing;start=time()
    for iteration in 1:max_rounds
        remaining=seconds-(time()-start);remaining>0 || break
        set_time_limit_sec(m,remaining);optimize!(m)
        push!(history,(;iteration,status=string(termination_status(m)),rows=length(d.rows)))
        if dual_status(m)==JuMP.MOI.INFEASIBILITY_CERTIFICATE
            multipliers=Any[[i,string(sbq(-v))] for(i,v) in enumerate(dual.(refs)) if v<0]
            gap=DroopOPF._flp_margin(d,multipliers);break
        end
        has_values(m) || break
        values=value.(x);added=0
        for (index,b) in enumerate(blocks),k in eachindex(b.branch_ids),side in 1:2
            pvar=side==1 ? b.pf[k] : b.pt[k];a=b.coefficients[k][side]
            a*sbq(values[pvar])^2-sbq(values[b.loss[k]])>sbq("0.00000001") || continue
            p0=round(BigInt,values[pvar]*2.0^20)//big(2)^20
            le(aff([pvar=>2*a*p0,b.loss[k]=>-1]),a*p0^2,
                (;family="loss_tangent",state=index,branch=b.branch_ids[k],side,point=string(p0)))
            push!(refs,DroopOPF._flp_solver_row!(m,x,d,last(d.rows)));added+=1
        end
        added==0 && break
    end
    folder=joinpath(output_directory,"factor-$factor");mkpath(folder)
    isfile(joinpath(folder,"result.json")) && error("Preserve prior relaxation result")
    saved_blocks=[(;case=b.case,pg=b.pg,pf=b.pf,pt=b.pt,loss=b.loss,dr=b.dr,shed=b.shed,delta=b.delta,
        alpha=string.(b.alpha),coefficients=[[string(a),string(bb)] for(a,bb) in b.coefficients],branch_ids=b.branch_ids) for b in blocks]
    write(joinpath(folder,"executed_shared_active_bound.jl"),read(@__FILE__,String))
    payload=(;factor,normal_targeted,include_b562,blocks=saved_blocks,events,source_sha256=bytes2hex(sha256(read(source))),
        source_adapter_sha256=bytes2hex(sha256(read(@__FILE__))),participation=study.participation,tap_controls=study.tap_controls,
        variable_bounds=[[string(l),string(u)] for(l,u) in d.bounds],
        rows=[(;coefficients=Dict(string(i)=>string(a) for(i,a) in r),rhs=string(b),meta=meta) for((r,b),meta) in zip(d.rows,rows_meta)],
        multipliers,total_loss,history,seconds_budget=seconds,elapsed_seconds=time()-start,
        certified_infeasible=!isnothing(gap) && gap>0,strict_gap_exact=isnothing(gap) ? nothing : string(gap),
        power_tolerance="0.000002",relief_tolerance="0.00000002",response_tolerance=string(response_tol),
        terminal_current_loss_upper_bounds=true,
        scope=normal_targeted ? "Joint necessary active-flow/loss relaxation for G14/G60/B36/B562; common preventive Pg and exact Pmax-weighted response. Original normal limits and full demand, no relief. Q, droop, angles and KVL omitted." : "Joint necessary active-flow/loss relaxation with terminal-current-derived loss ceilings; common preventive Pg with Pmax-weighted response. Base normal limits; N-1 +/-0.05 pu voltage, 110% Rate A, 1% DR and 10 MW shedding with 10% per-load combined cap. Q, droop, angles and KVL omitted.",
        limitation="A feasible relaxation is inconclusive; only a replayed positive exact gap certifies infeasibility. No remedies investigated.")
    write(joinpath(folder,"result.json"),JSON.json(DroopOPF._json_data(payload);pretty=true))
    println("SHARED ACTIVE factor=",factor," certified=",payload.certified_infeasible," rounds=",length(history)," seconds=",payload.elapsed_seconds)
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    if length(ARGS)==2 && ARGS[2]=="build-only"
        shared_active_bound(parse(Float64,ARGS[1]);max_rounds=0)
    else
        shared_active_bound(parse(Float64,only(ARGS)))
    end
end
