isdefined(@__MODULE__, :a500_read_policy) || include("audit_s1_arpae500.jl")
function a500_diagnose()
    _,_,angles,costs,_=a500_inputs();rows=[JSON.parsefile(p) for p in readdir(joinpath(A500_OUT,"attempts");join=true)];diagnoses=[]
    for r in rows
        r["accepted"] && continue;haskey(r,"state") || continue
        c=read_study(joinpath(A500_ROOT,r["model_path"])).case;s=a500_state(r["state"])
        c=with_shunt_settings(with_tap_settings(c,a500_settings(r["taps"])),a500_settings(r["susceptances"]))
        bal=power_balance(c,s);dr=droop_residual(c,s)
        bus=sort([Dict("bus"=>b.id,"p_mw"=>bal.active[i]*c.base_power,"q_mvar"=>bal.reactive[i]*c.base_power) for (i,b) in enumerate(c.network.buses)];by=x->-max(abs(x["p_mw"]),abs(x["q_mvar"])))
        droops=sort([Dict("generator"=>a.generator_id,"bus"=>a.location.bus_id,"residual_mvar"=>dr[i]*c.base_power) for (i,a) in enumerate(c.attachments)];by=x->-abs(x["residual_mvar"]))
        bounds=Dict("voltage_upper"=>[b.id for (i,b) in enumerate(c.network.buses) if b.v_max-s.vm[i]<1e-5],"generator_q_upper"=>[g.id for (i,g) in enumerate(c.generators) if g.available && g.q_max-s.qg[i]<1e-5],"generator_q_lower"=>[g.id for (i,g) in enumerate(c.generators) if g.available && s.qg[i]-g.q_min<1e-5])
        push!(diagnoses,Dict("name"=>r["name"],"status"=>get(r,"solver_status","error"),"worst_balance"=>first(bus,min(5,length(bus))),"worst_droop"=>first(droops,min(5,length(droops))),"near_active_bounds"=>bounds,"physical_checks"=>r["point_checks"],"operating_bound_check"=>get(r,"operating_bound_check",nothing)))
    end
    a500_save(joinpath(A500_OUT,"failure_diagnostics.json"),diagnoses);println("DIAGNOSED ",length(diagnoses)," retained unsuccessful states")
end
abspath(PROGRAM_FILE)==(@__FILE__) && a500_diagnose()
