# Exact zero-injection voltage elimination with original-equipment constraints.
# Study adapter only; the source Case and original branch identities are kept.
include("s2_arpae500_loadability.jl")
using LinearAlgebra
const NR_OUT=joinpath(S2500_OUT,"network_reduction")
const NR_SOURCE=read(@__FILE__,String)
const NR_CACHE=Dict{Tuple,Any}()

function nr_keep_ids(study)
    c=study.case;n=c.network
    keep=Set(l.bus_id for l in c.loads if l.p!=0 || l.q!=0)
    union!(keep,(g.bus_id for g in c.generators))
    union!(keep,(a.location.bus_id for a in c.attachments))
    union!(keep,(b.id for b in n.buses if b.reference))
    union!(keep,(s.bus_id for s in n.shunts));union!(keep,(b.bus_id for b in n.banks))
    taps=Set(t.branch_id for t in study.tap_controls)
    for b in n.branches
        b.id in taps && union!(keep,(b.from_bus,b.to_bus))
    end
    mode=get(ENV,"NR_ELIMINATION_MODE","all")
    if mode=="independent-degree3"
        adj=Dict(b.id=>Set{Int}() for b in n.buses)
        for b in n.branches
            b.available || continue
            push!(adj[b.from_bus],b.to_bus);push!(adj[b.to_bus],b.from_bus)
        end
        score(i)=sum(!(k in adj[j]) for j in adj[i] for k in adj[i] if j<k)
        candidates=sort([b.id for b in n.buses if !(b.id in keep) && length(adj[b.id])==3];by=i->(score(i),i))
        selected=Set{Int}()
        for i in candidates
            isempty(intersect(adj[i],selected)) && push!(selected,i)
        end
        union!(keep,(b.id for b in n.buses if !(b.id in selected)))
    else
        mode=="all" || error("Unknown reduction mode")
    end
    keep
end

function nr_map(c)
    # The partition comes from the unmodified source, including offline units
    # and both ends of controls outaged in this particular scenario.
    online=Tuple(b.id for b in c.network.branches if b.available)
    mode=get(ENV,"NR_ELIMINATION_MODE","all");key=(mode,online)
    map=get!(NR_CACHE,key) do
        original=read_study(joinpath(S2500_OUT,"pilot_study.json"))
        keep=nr_keep_ids(original);ids=[b.id for b in c.network.buses]
        r=findall(id->id in keep,ids);e=findall(id->!(id in keep),ids)
        Y=DroopOPF._admittance_matrix(c.network)
        H=-(Y[e,e]\Y[e,r])
        @assert maximum(abs.(Y[e,e]*H+Y[e,r]);init=0.)<1e-10
        (;r,e,H,metadata=(;elimination_mode=mode,retained_bus_ids=ids[r],eliminated_bus_ids=ids[e],
            reconstruction=[(;row=i,column=j,real=real(H[i,j]),imag=imag(H[i,j]))
                for i in axes(H,1) for j in axes(H,2) if !iszero(H[i,j])],
            map_residual_max=maximum(abs.(Y[e,e]*H+Y[e,r]);init=0.),
            original_online_branch_ids=collect(online),
            original_branch_ratings=Dict(b.id=>b.thermal_limit for b in c.network.branches if b.available)))
    end
    # Emergency ratings differ even when topology (and H) is unchanged.
    (;map...,metadata=(;map.metadata...,original_branch_ratings=Dict(b.id=>b.thermal_limit for b in c.network.branches if b.available)))
end

function nr_build_ac(c;voltage_epsilon,reactive_relative_epsilon,reactive_epsilon,silent,
    shared_model,scenario_prefix,set_objective,initial_state,reactive_assignments,
    tap_controls,shunt_controls,normalize_controls,droop_parameter_variables,power_balance_slacks,
    include_droop_equations=true,load_relief=nothing)
    isnothing(reactive_assignments) || error("Reduction adapter currently requires native droop attachments")
    set_objective && error("The study harness owns the objective")
    m=shared_model;prefix=scenario_prefix;net=c.network;n=length(net.buses);ng=length(c.generators)
    map=nr_map(c);r,e,H=map.r,map.e,map.H;idx=DroopOPF._bus_indices(net)
    eset=Set(e)
    # Ensure every optimized admittance lies in Y_RR, so H is constant for
    # every allowed tap/bank setting, rather than frozen at a chosen setting.
    for t in tap_controls
        b=only(filter(b->b.id==t.branch_id,net.branches))
        @assert !(idx[b.from_bus] in eset) && !(idx[b.to_bus] in eset)
    end
    for s in shunt_controls
        b=only(filter(b->b.id==s.bank_id,net.banks));@assert !(idx[b.bus_id] in eset)
    end
    vm=Any[nothing for _ in 1:n];va=Any[nothing for _ in 1:n]
    vr=Any[nothing for _ in 1:n];vi=Any[nothing for _ in 1:n]
    for i in r
        b=net.buses[i]
        vm[i]=@variable(m,lower_bound=b.v_min,upper_bound=b.v_max,base_name=prefix*"vm[$i]",start=initial_state.vm[i])
        va[i]=@variable(m,lower_bound=-pi,upper_bound=pi,base_name=prefix*"va[$i]",start=initial_state.va[i])
        b.reference && fix(va[i],0.;force=true)
        vr[i]=@NLexpression(m,vm[i]*cos(va[i]));vi[i]=@NLexpression(m,vm[i]*sin(va[i]))
    end
    for (k,i) in enumerate(e)
        js=findall(j->!iszero(H[k,j]),axes(H,2));rr=real.(H[k,:]);ii=imag.(H[k,:])
        vr[i]=@NLexpression(m,sum(rr[j]*vr[r[j]]-ii[j]*vi[r[j]] for j in js))
        vi[i]=@NLexpression(m,sum(ii[j]*vr[r[j]]+rr[j]*vi[r[j]] for j in js))
        vm[i]=@NLexpression(m,sqrt(vr[i]^2+vi[i]^2))
        va[i]=@NLexpression(m,atan(vi[i],vr[i]))
        b=net.buses[i]
        @NLconstraint(m,b.v_min^2<=vr[i]^2+vi[i]^2<=b.v_max^2)
    end
    pg=@variable(m,[1:ng],base_name=prefix*"pg");qg=@variable(m,[1:ng],base_name=prefix*"qg")
    for (i,g) in enumerate(c.generators)
        DroopOPF._set_bound!(pg[i],g.p_min,g.p_max);DroopOPF._set_bound!(qg[i],g.q_min,g.q_max)
        set_start_value(pg[i],initial_state.pg[i]);set_start_value(qg[i],initial_state.qg[i])
        if !g.available;fix(pg[i],0.;force=true);fix(qg[i],0.;force=true);end
    end
    taps=Dict{Int,Any}()
    for control in tap_controls
        normalize_controls && error("Use physical controls in the first reduction comparison")
        t=@variable(m,lower_bound=control.lower,upper_bound=control.upper,
            base_name=prefix*"tap_$(control.branch_id)",start=control.initial)
        taps[control.branch_id]=t
    end
    banks=DroopOPF._shunt_variables!(m,c,shunt_controls,nothing;normalize_controls)
    ps=[Any[] for _ in 1:n];qs=[Any[] for _ in 1:n];terminal=Dict{Tuple{Int,Bool},Any}()
    for b in net.branches
        b.available || continue
        f,t=idx[b.from_bus],idx[b.to_bus];tau=get(taps,b.id,b.tap_ratio)
        yff,yft,ytf,ytt=DroopOPF._branch_admittances(b)
        for (i,j,self,mutual,from) in ((f,t,yff*b.tap_ratio^2,yft*b.tap_ratio,true),(t,f,ytt,ytf*b.tap_ratio,false))
            gs,bs,gm,bm=real(self),imag(self),real(mutual),imag(mutual)
            scale=from ? @NLexpression(m,1/tau^2) : 1.
            p=@NLexpression(m,(vr[i]^2+vi[i]^2)*gs*scale+
                ((vr[i]*vr[j]+vi[i]*vi[j])*gm+(vi[i]*vr[j]-vr[i]*vi[j])*bm)/tau)
            q=@NLexpression(m,-(vr[i]^2+vi[i]^2)*bs*scale+
                ((vi[i]*vr[j]-vr[i]*vi[j])*gm-(vr[i]*vr[j]+vi[i]*vi[j])*bm)/tau)
            @NLconstraint(m,p^2+q^2<=b.thermal_limit^2)
            push!(ps[i],p);push!(qs[i],q);terminal[(b.id,from)]=(p,q)
        end
    end
    shunt=zeros(ComplexF64,n)
    for s in net.shunts;s.available && (shunt[idx[s.bus_id]]+=complex(s.conductance,s.susceptance));end
    for b in net.banks;haskey(banks,b.id) || (shunt[idx[b.bus_id]]+=DroopOPF.bank_admittance(b));end
    loadp=zeros(n);loadq=zeros(n)
    for l in c.loads;loadp[idx[l.bus_id]]+=l.p;loadq[idx[l.bus_id]]+=l.q;end
    for i in r
        pgen=sum(pg[k] for(k,g) in enumerate(c.generators) if idx[g.bus_id]==i;init=0.)
        qgen=sum(qg[k] for(k,g) in enumerate(c.generators) if idx[g.bus_id]==i;init=0.)
        pp,qq=ps[i],qs[i];g,b=real(shunt[i]),imag(shunt[i])
        selected=[a for a in net.banks if haskey(banks,a.id) && idx[a.bus_id]==i]
        gv=sum(only(a.step_conductances)/only(a.step_susceptances)*banks[a.id] for a in selected;init=0.)
        bv=sum(banks[a.id] for a in selected;init=0.)
        ppos=power_balance_slacks ? @variable(m,lower_bound=0.,base_name=prefix*"p_balance_pos[$i]") : 0.
        pneg=power_balance_slacks ? @variable(m,lower_bound=0.,base_name=prefix*"p_balance_neg[$i]") : 0.
        qpos=power_balance_slacks ? @variable(m,lower_bound=0.,base_name=prefix*"q_balance_pos[$i]") : 0.
        qneg=power_balance_slacks ? @variable(m,lower_bound=0.,base_name=prefix*"q_balance_neg[$i]") : 0.
        rp=isnothing(load_relief) ? 0. : load_relief.p[i]
        rq=isnothing(load_relief) ? 0. : load_relief.q[i]
        @NLconstraint(m,pgen-loadp[i]+ppos-pneg+rp==sum(pp[k] for k in eachindex(pp))+(g+gv)*vm[i]^2)
        @NLconstraint(m,qgen-loadq[i]+qpos-qneg+rq==sum(qq[k] for k in eachindex(qq))-(b+bv)*vm[i]^2)
    end
    gids=Dict(g.id=>i for(i,g) in enumerate(c.generators))
    for a in c.attachments
        i=gids[a.generator_id];c.generators[i].available || continue
        d=c.controls[a.control_id];v=vm[idx[a.location.bus_id]]
        DroopOPF._set_bound!(pg[i],max(c.generators[i].p_min,d.capability.p_min),min(c.generators[i].p_max,d.capability.p_max))
        include_droop_equations || continue
        eps=DroopOPF.reactive_smoothing_epsilon(d,reactive_relative_epsilon;absolute_epsilon=reactive_epsilon)
        parameters=get(droop_parameter_variables,a.control_id,nothing)
        name=Symbol(prefix,"droop_response_",a.control_id)
        expr=if isnothing(parameters)
            JuMP.register(m,name,1,z->DroopOPF._smooth_droop_value(d,z,voltage_epsilon,eps);autodiff=true)
            Expr(:call,name,v)
        else
            DroopOPF._smooth_droop_expression!(m,name,d,v,parameters,voltage_epsilon,eps)
        end
        JuMP.add_nonlinear_constraint(m,Expr(:call,:(==),qg[i],expr))
    end
    m,(;vm,va,pg,qg,taps,shunts=banks,eliminated_indices=eset,terminal_powers=terminal,reduction=map.metadata)
end

function nr_solve(x,name,factors,events;output_relative="../network_reduction/",kwargs...)
    folder=joinpath(EL_OUT,output_relative*name);mkpath(folder)
    write(joinpath(folder,"executed_network_reduction.jl"),NR_SOURCE)
    lane=el_solve(x,output_relative*name,factors,events;
        ac_builder=nr_build_ac,model_label="exact-zero-injection-Kron/original-branch-constraints",kwargs...)
    if isfile(joinpath(folder,"stages.json"))
        stages=JSON.parsefile(joinpath(folder,"stages.json"))
        for r in stages
            isfile(joinpath(folder,"point-$(r["stage"]).json")) || continue
            script=joinpath(FD_ROOT,"examples/audit_s2_500bus_network_reduction.py")
            python=get(ENV,"NR_PYTHON","python3")
            read(`$python $script $folder $(r["stage"])`,String)
        end
    end
    lane
end

function nr_select_accepted(folder)
    selected=el_select_accepted(folder)
    isnothing(selected) && return nothing
    ck=JSON.parsefile(joinpath(folder,"network-audit-$(selected.stage).json"))
    ck["accepted"] ? selected : nothing
end
