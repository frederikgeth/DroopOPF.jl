function equipment_static_fields(data,reference,plan)
    out=deepcopy(data)
    for c in values(plan["selected"])
        out[c["table"]][c["key"]][c["field"]]=reference[c["table"]][c["key"]][c["field"]]
    end
    static_fields(out)
end
function equipment_replay_model(x,state)
    plan=equipment_plan(x);model=deepcopy(x.data);violation=0.
    equipment_static_fields(state,x.data,plan)==static_fields(x.data)||(violation=Inf)
    for c in values(plan["selected"])
        v=state[c["table"]][c["key"]][c["field"]]
        v isa Real&&isfinite(v)||error("Nonfinite equipment setting")
        violation=max(violation,c["lower"]-v,v-c["upper"])
        model[c["table"]][c["key"]][c["field"]]=v
    end
    model,violation
end
# Both terminal powers use the selected dictionary's admittances and fixed phase.
function equipment_branch!(pm,i,t)
    get!(P.var(pm),:p,Dict{Tuple{Int,Int,Int},Any}());get!(P.var(pm),:q,Dict{Tuple{Int,Int,Int},Any}())
    b=P.ref(pm,:branch,i);m=pm.model;f=b["f_bus"];to=b["t_bus"]
    u=P.var(pm,:vm,f);v=P.var(pm,:vm,to)
    delta=@expression(m,P.var(pm,:va,f)-P.var(pm,:va,to)-b["shift"])
    y=inv(complex(b["br_r"],b["br_x"]));g=real(y);h=imag(y)
    P.var(pm,:p)[(i,f,to)]=@expression(m,(g+b["g_fr"])*u^2/t^2-u*v/t*(g*cos(delta)+h*sin(delta)))
    P.var(pm,:q)[(i,f,to)]=@expression(m,-(h+b["b_fr"])*u^2/t^2-u*v/t*(g*sin(delta)-h*cos(delta)))
    P.var(pm,:p)[(i,to,f)]=@expression(m,(g+b["g_to"])*v^2-u*v/t*(g*cos(delta)-h*sin(delta)))
    P.var(pm,:q)[(i,to,f)]=@expression(m,-(h+b["b_to"])*v^2+u*v/t*(g*sin(delta)+h*cos(delta)))
end
function equipment_balance!(pm,i,settings)
    m=pm.model;vm=P.var(pm,:vm,i);arcs=P.ref(pm,:bus_arcs,i);gens=P.ref(pm,:bus_gens,i)
    loads=P.ref(pm,:bus_loads,i);shunts=P.ref(pm,:bus_shunts,i)
    bs(k)=get(settings,"shunt:"*string(k),P.ref(pm,:shunt,k)["bs"])
    set_name(@constraint(m,sum(P.var(pm,:p,a) for a in arcs)==sum(P.var(pm,:pg,g) for g in gens)-sum(P.ref(pm,:load,l)["pd"] for l in loads)-sum(P.ref(pm,:shunt,s)["gs"] for s in shunts)*vm^2),"equipment_p_balance_bus_$i")
    set_name(@constraint(m,sum(P.var(pm,:q,a) for a in arcs)==sum(P.var(pm,:qg,g) for g in gens)-sum(P.ref(pm,:load,l)["qd"] for l in loads)+sum(bs(s) for s in shunts)*vm^2),"equipment_q_balance_bus_$i")
end
