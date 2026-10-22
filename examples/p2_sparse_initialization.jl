# Experimental numerical initializer for the exact S2 compatibility benchmark.
# Import never solves. A converged Newton point is a start, never acceptance.
using SparseArrays, LinearAlgebra
function p2_sparse_start(study,preventive,event;factor=1.,flat=true,maxiter=60,pv_preparation=false)
    D=P2S2.DroopOPF
    normal=D._feasibility_scaled_case(study.case,factor)
    c=D.scenario_case(normal,event)
    c=D.with_shunt_settings(D.with_tap_settings(c,preventive.taps),preventive.banks)
    n=length(c.network.buses);idx=D._bus_indices(c.network)
    ref=only(findall(b->b.reference,c.network.buses));angles=[i for i in 1:n if i!=ref]
    Y=sparse(D._admittance_matrix(c.network))
    active=findall(g->g.available,c.generators)
    weights=[g.available ? get(study.participation,g.id,0.) : 0. for g in c.generators]
    sum(weights)>0 || error("No surviving participant")
    weights ./=sum(weights)
    alpha=zeros(n);pload=zeros(n);qload=zeros(n)
    for (i,g) in enumerate(c.generators);alpha[idx[g.bus_id]]+=weights[i];end
    for l in c.loads;pload[idx[l.bus_id]]+=l.p;qload[idx[l.bus_id]]+=l.q;end
    attachments=Dict(a.generator_id=>a for a in c.attachments)
    freeq=Dict{Int,Vector{Int}}()
    for i in active
        !pv_preparation && haskey(attachments,c.generators[i].id) && continue
        push!(get!(freeq,idx[c.generators[i].bus_id],Int[]),i)
    end
    pvtargets=Dict{Int,Float64}()
    for (j,gens) in freeq
        targets=Float64[]
        for i in gens
            g=c.generators[i]
            if haskey(attachments,g.id)
                ctrl=c.controls[attachments[g.id].control_id];q=preventive.state.qg[i]
                edge=q>=ctrl.q_at_deadband ? ctrl.schedule.v_db_low : ctrl.schedule.v_db_high
                push!(targets,edge-ctrl.slope*(q-ctrl.q_at_deadband))
            else
                push!(targets,1.)
            end
        end
        pvtargets[j]=sum(targets)/length(targets)
    end
    lost=sum(preventive.state.pg[i] for (i,g) in enumerate(c.generators) if !g.available)
    z=vcat(flat ? zeros(n-1) : preventive.state.va[angles],flat ? ones(n) : preventive.state.vm,lost)
    function evaluate(z; jacobian=false)
        va=zeros(n);va[angles]=z[1:n-1];vm=z[n:2n-1]
        pg=zeros(length(c.generators));qg=copy(pg);p=-copy(pload);q=-copy(qload);dq=zeros(n)
        for i in active
            g=c.generators[i];j=idx[g.bus_id]
            pg[i]=preventive.state.pg[i]+weights[i]*z[end]
            if !pv_preparation && haskey(attachments,g.id)
                ctrl=c.controls[attachments[g.id].control_id]
                law(v)=clamp(D.evaluate(D.droop_curve(ctrl),v),max(g.q_min,ctrl.capability.q_min),min(g.q_max,ctrl.capability.q_max))
                qg[i]=law(vm[j]);dq[j]+=(law(vm[j]+1e-7)-law(vm[j]-1e-7))/2e-7
            else
                qg[i]=preventive.state.qg[i]
            end
            p[j]+=pg[i];q[j]+=qg[i]
        end
        V=vm.*cis.(va);I=Y*V;S=V.*conj.(I);r=vcat(p-real.(S),q-imag.(S))
        # PV treatment is an initialization device only. Free-Q generators absorb
        # their local reactive residual; the native NLP later enforces all Q bounds.
        for (j,gens) in freeq
            correction=-r[n+j]/length(gens)
            for i in gens;qg[i]+=correction;end
            r[n+j]=vm[j]-(pv_preparation ? pvtargets[j] : preventive.state.vm[j])
        end
        if !jacobian;return (;r,state=D.ACState(vm,va,pg,qg));end
        diagV=spdiagm(0=>V);diagI=spdiagm(0=>I);diagU=spdiagm(0=>cis.(va))
        dtheta=im*diagV*conj.(diagI-Y*diagV)
        dvm=diagV*conj.(Y*diagU)+conj.(diagI)*diagU
        J=[-real.(dtheta[:,angles]) -real.(dvm) sparse(reshape(alpha,:,1));
           -imag.(dtheta[:,angles]) -imag.(dvm)+spdiagm(0=>dq) spzeros(n,1)]
        for j in keys(freeq)
            J[n+j,:].=0.;J[n+j,n-1+j]=1.
        end
        dropzeros!(J)
        (;r,J,state=D.ACState(vm,va,pg,qg))
    end
    history=Float64[];reason="iteration_limit";started=time()
    offset=evaluate(z).r;lambda=0.;increment=.05;stages=Any[]
    for stage in 1:250
        target=min(1.,lambda+increment);saved=copy(z);converged=false
        for iteration in 1:maxiter
            e=evaluate(z;jacobian=true);r=e.r-(1-target)*offset
            err=maximum(abs,r);push!(history,err)
            if err<=1e-8;converged=true;break;end
            step=try -(e.J\r) catch;reason="singular_jacobian";break;end
            all(isfinite,step)||(reason="nonfinite_step";break)
            scale=min(1.,.08/max(maximum(abs,step[n:2n-1]),1e-12),.5/max(maximum(abs,step[1:n-1]),1e-12))
            accepted=false
            for damp in (1.,.5,.25,.125,.0625,.03125)
                trial=z+scale*damp*step
                minimum(trial[n:2n-1])>0 || continue
                if maximum(abs,evaluate(trial).r-(1-target)*offset)<err
                    z=trial;accepted=true;break
                end
            end
            accepted||(reason="line_search_stalled";break)
        end
        push!(stages,(;target,converged))
        if converged
            lambda=target;increment=min(.15,increment*1.4)
            if lambda==1.;reason="converged";break;end
        else
            z=saved;increment/=2
            if increment<1e-4;reason="continuation_stalled";break;end
        end
    end
    e=evaluate(z);physical_balance=maximum(abs,D.power_balance(c,e.state).vector)
    (;entry=(;preventive...,state=e.state,delta=z[end]),diagnostic=(;reason,converged=maximum(abs,e.r)<=1e-8,
        history,stages,lambda,continuation="Artificial balance-offset homotopy used only for initialization; zero at final target",residual=maximum(abs,e.r),independent_balance=physical_balance,seconds=time()-started,
        flat_voltage=flat,pv_preparation,post_outage_oracle_used=false,held_equipment="preventive settings",reactive_preparation=pv_preparation ? "PV targets inferred from preventive Q and inverse droop; no preventive voltage/angle values copied; full Q/droop model restored in native solve" : "Mixed fixed-Q/droop Newton preparation",
        acceptance="Initializer only: native optimization and full independent audit still required"))
end
function p2_sparse_cold_trial(x,seed,events,folder;rep=1,pv_preparation=false,seconds=60.)
    # Deliberately discard every stored post-outage state before preparation.
    preventive=seed.states[(1.,:base)]
    states=Dict{Tuple{Float64,Symbol},Any}((1.,:base)=>preventive);diagnostics=Any[];started=time()
    for e in events
        p=p2_sparse_start(seed.study,preventive,e;flat=true,pv_preparation)
        states[(1.,e.id)]=p.entry;push!(diagnostics,(;event=e.id,p.diagnostic...))
    end
    fresh=(;study=seed.study,states)
    P2S2.fd_save(joinpath(folder,"preparation.json"),(;rep,diagnostics,seconds=time()-started,post_outage_oracle_used=false))
    a=P2S2.pq_attempt(x,joinpath(folder,"primary"),(1.,),events;seed=fresh,fixed_controller=true,fixed_base=true,zero_shedding=false,seconds)
    paths=[a.summary.folder]
    if !a.summary.accepted
        a=P2S2.pq_attempt(x,joinpath(folder,"retry"),(1.,),events;seed=fresh,fixed_controller=true,fixed_base=true,zero_shedding=false,seconds=2*seconds,retry=true)
        push!(paths,a.summary.folder)
    end
    row=(;rep,accepted=a.summary.accepted,events=[e.id for e in events],wall_seconds=time()-started,paths,post_outage_oracle_used=false)
    P2S2.fd_save(joinpath(folder,"RESULTS.json"),row);row
end
