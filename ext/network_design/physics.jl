# Independent complex-current replay of the *selected dictionary*, not a Case.
function physics(model,state;limits=true)
    buses=model["bus"];voltage=Dict(parse(Int,k)=>b["vm"]*cis(b["va"]) for (k,b) in state["bus"] if buses[k]["bus_type"]!=4)
    residual=Dict(i=>0.0im for i in keys(voltage));margin=Inf;flows=Dict{String,Any}();bound=0.
    for (k,g) in model["gen"]
        livegen(g)||continue;s=state["gen"][k]
        residual[g["gen_bus"]]+=complex(s["pg"],s["qg"])
        bound=max(bound,g["pmin"]-s["pg"],s["pg"]-g["pmax"],g["qmin"]-s["qg"],s["qg"]-g["qmax"])
    end
    for l in values(get(model,"load",Dict()))
        get(l,"status",1)==0&&continue
        residual[l["load_bus"]]-=complex(l["pd"],l["qd"])
    end
    for s in values(get(model,"shunt",Dict()))
        get(s,"status",1)==0&&continue
        residual[s["shunt_bus"]]-=complex(s["gs"],-s["bs"])*abs2(voltage[s["shunt_bus"]])
    end
    for (k,b) in model["branch"]
        get(b,"br_status",1)==0&&continue
        i,j=b["f_bus"],b["t_bus"];a=b["tap"]*cis(b["shift"])
        u=voltage[i]/a;w=voltage[j];current=(u-w)/complex(b["br_r"],b["br_x"])
        sf=u*conj(current+complex(b["g_fr"],b["b_fr"])*u)
        st=w*conj(-current+complex(b["g_to"],b["b_to"])*w)
        residual[i]-=sf;residual[j]-=st
        angle=state["bus"][string(i)]["va"]-state["bus"][string(j)]["va"]
        bound=max(bound,get(b,"angmin",-Inf)-angle,angle-get(b,"angmax",Inf))
        rate=get(b,"rate_a",nothing)
        if limits;rate isa Real&&isfinite(rate)&&rate>0||error("Selected model lacks a finite branch rating; no substitute is invented");end
        rate===nothing||(margin=min(margin,rate-max(abs(sf),abs(st))))
        flows[k]=Dict("pf"=>real(sf),"qf"=>imag(sf),"pt"=>real(st),"qt"=>imag(st))
    end
    for (k,b) in buses
        b["bus_type"]==4&&continue;v=state["bus"][k]["vm"]
        bound=max(bound,b["vmin"]-v,v-b["vmax"])
    end
    mismatch=maximum((max(abs(real(v)),abs(imag(v))) for v in values(residual));init=0.)
    finite=all(isfinite,values(voltage))&&all(isfinite,values(residual))&&isfinite(bound)
    pmax=maximum((abs(real(v)) for v in values(residual));init=0.)
    qmax=maximum((abs(imag(v)) for v in values(residual));init=0.)
    ranked=sort!(collect(residual);by=pair->(-max(abs(real(last(pair))),abs(imag(last(pair)))),first(pair)))
    worst=[Dict("model_bus"=>i,"source_identity"=>get(buses[string(i)],"source_id",nothing),
        "p_residual_pu"=>real(v),"q_residual_pu"=>imag(v),
        "p_residual_mw"=>real(v)*model["baseMVA"],"q_residual_mvar"=>imag(v)*model["baseMVA"])
        for (i,v) in first(ranked,min(20,length(ranked)))]
    Dict("base_mva"=>model["baseMVA"],"p_balance_max_pu"=>pmax,"q_balance_max_pu"=>qmax,
        "p_balance_max_mw"=>pmax*model["baseMVA"],"q_balance_max_mvar"=>qmax*model["baseMVA"],
        "worst_bus_residuals"=>worst,"passed"=>finite&&mismatch<=1e-6&&(!limits||(bound<=1e-6&&margin>=-1e-6)),
        "power_balance_max_pu"=>mismatch,"bound_violation_pu"=>bound,"thermal_margin_pu"=>isfinite(margin) ? margin : nothing,"flows"=>flows)
end
function groups(d)
    sort!([sort!(collect(g)) for g in P.calc_connected_components(d;edges=["branch"])];by=first)
end
function response_weights(d,group;free_ids=Set(k for (k,g) in d["gen"] if get(g,"study_device_policy","")=="free_pq"))
    ids=sort([k for (k,g) in d["gen"] if livegen(g)&&g["gen_bus"] in group&&!(k in free_ids)]);w=Dict{String,Float64}(k=>boundary(d["gen"][k]) ? 0. : max(0.,d["gen"][k]["pmax"]-d["gen"][k]["pmin"]) for k in ids)
    total=sum(values(w));total>0&&foreach(k->w[k]/=total,ids)
    w
end
function replay(x,controls,result;phase,floor=0.)
    d=result["data"];model,equipment_error=equipment_replay_model(x,d)
    report=physics(model,d);report["equipment_bound_violation"]=equipment_error
    error=equipment_error;settings=result["settings"]
    plan_equipment=equipment_plan(x)
    if !isempty(plan_equipment["selected"])
        expected=Dict(id=>d[c["table"]][c["key"]][c["field"]] for (id,c) in plan_equipment["selected"])
        get(result,"equipment_policy",nothing)==plan_equipment["policy"]&&get(result,"equipment_settings",nothing)==expected||(error=Inf)
    end
    plan=regulation_plan(x,controls)
    for (k,g) in x.data["gen"]
        if get(g,"study_device_policy","") in ("disabled","fixed_signed_load")
            error=max(error,abs(d["gen"][k]["pg"]),abs(d["gen"][k]["qg"]))
        end
    end
    for (j,group) in enumerate(groups(x.data))
        signal=result["signals"][string(j)];w=response_weights(x.data,group;free_ids=plan["free_dispatch"])
        for (k,weight) in w
            g=x.data["gen"][k];expected=weight==0 ? g["pg"] : clamp(g["pg"]+weight*signal,g["pmin"],g["pmax"])
            error=max(error,abs(d["gen"][k]["pg"]-expected))
        end
        ref=only(i for i in group if x.source["bus"][string(i)]["bus_type"]==3)
        error=max(error,abs(d["bus"][string(ref)]["va"]-x.data["bus"][string(ref)]["va"]))
    end
    plan=regulation_plan(x,controls)
    for (target,group) in plan["shared_droop_groups"]
        leader=settings[first(group["ids"])]
        for k in group["ids"]
            s=settings[k]
            error=max(error,abs(s["slope"]-leader["slope"]),abs(s["vref"]-leader["vref"]))
            error=max(error,group["slope_bounds"][1]-s["slope"],s["slope"]-group["slope_bounds"][2],group["vref_bounds"][1]-s["vref"],s["vref"]-group["vref_bounds"][2])
            haskey(plan["avr_targets"],target)&&(error=max(error,abs(s["vref"]-result["avr_settings"][target])))
            group["fixed_vref"]===nothing||(error=max(error,abs(s["vref"]-group["fixed_vref"])))
        end
    end
    for (k,c) in controls
        s=settings[k];g=x.data["gen"][k];v=d["bus"][string(c["regulated_model_bus"])]["vm"]
        error=max(error,c["slope_bounds"][1]-s["slope"],s["slope"]-c["slope_bounds"][2],c["vref_bounds"][1]-s["vref"],s["vref"]-c["vref_bounds"][2])
        expected=clamp(c["qref"]+(s["vref"]-v)/s["slope"],g["qmin"],g["qmax"])
        error=max(error,abs(d["gen"][k]["qg"]-expected))
    end
    totals=Dict{String,Float64}()
    for (plant,p) in plan["avr_plants"]
        ids=p["ids"]
        isempty(ids)&&continue
        q=[d["gen"][k]["qg"] for k in ids];lo=[x.data["gen"][k]["qmin"] for k in ids];hi=[x.data["gen"][k]["qmax"] for k in ids]
        weights=[abs(d["gen"][k]["pg"]) for k in ids];sum(weights)<=1e-12&&(weights=[get(x.data["gen"][k],"mbase",0.) for k in ids])
        # Project only the allocation query; actual Q and its violation remain
        # unchanged in physics and the residual below (including solver overshoot).
        expected=bounded_share(clamp(sum(q),sum(lo),sum(hi)),weights,lo,hi)
        error=max(error,maximum(abs.(q.-expected);init=0.))
        totals[plant]=sum(q)
    end
    for (target,t) in plan["avr_targets"]
        vs=result["avr_settings"][target]
        error=max(error,t["vref_bounds"][1]-vs,vs-t["vref_bounds"][2])
        (!t["optimizable"])&&(error=max(error,abs(vs-t["vs"])))
        ps=[plan["avr_plants"][p] for p in t["plants"]]
        q=[totals[p] for p in t["plants"]]
        lo=[sum(x.data["gen"][k]["qmin"] for k in p["ids"]) for p in ps]
        hi=[sum(x.data["gen"][k]["qmax"] for k in p["ids"]) for p in ps]
        expected=bounded_share(clamp(sum(q),sum(lo),sum(hi)),[p["weight"] for p in ps],lo,hi)
        error=max(error,maximum(abs.(q.-expected);init=0.))
        error=max(error,abs(sum(q)-clamp(sum(q)+vs-d["bus"][target]["vm"],sum(lo),sum(hi))))
    end
    for k in plan["fixed_q"]
        error=max(error,abs(d["gen"][k]["qg"]-x.data["gen"][k]["qg"]))
    end
    for ids in get(plan,"cross_snapshot_droop",Any[])
        first_setting=settings[first(ids)]
        for k in ids[2:end],field in ("slope","vref")
            error=max(error,abs(settings[k][field]-first_setting[field]))
        end
    end
    headroom=Dict(k=>min(d["gen"][k]["qg"]-x.data["gen"][k]["qmin"],x.data["gen"][k]["qmax"]-d["gen"][k]["qg"])/(x.data["gen"][k]["qmax"]-x.data["gen"][k]["qmin"]) for k in plan["reserve_participants"])
    reserve=isempty(headroom) ? 0. : minimum(values(headroom))
    report["reserve_headroom"]=headroom
    report["reserve_participants"]=plan["reserve_participants"]
    report["control_residual_pu"]=error;report["reserve"]=reserve
    report["passed"]&=isfinite(error)&&error<=1e-6&&(phase=="feasibility"||reserve>=floor-1e-8)
    report
end
