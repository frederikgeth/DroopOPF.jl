const SERIES_POLICY="shared_ibr_curves_mixed_avr_targets; scheduled_pure_avr_and_equipment; common_online_selection; no_energy_coupling"
# Independent operating snapshots, not a storage trajectory or commitment model.
function generator_identity(g)
    sid=get(g,"source_id",nothing)
    sid isa AbstractVector&&length(sid)>=3||error("Generator lacks stable source bus/ID")
    id=uppercase(strip(string(sid[3])));numeric=match(r"^([0-9]+)(?:\.0+)?$",id)
    numeric===nothing||(id=replace(numeric.captures[1],r"^0+(?=[0-9])"=>""))
    string(Int(sid[2]))*"/"*id
end
function snapshot_registry(c)
    rows=Dict{String,String}()
    for (k,g) in c.data["gen"]
        boundary(g)&&continue
        id=generator_identity(g);haskey(rows,id)&&error("Ambiguous snapshot generator identity: $id")
        rows[id]=k
    end
    rows
end
function assemble_series(contracts,labels,weights)
    length(contracts)>=2||error("At least two snapshots required")
    length(labels)==length(contracts)==length(weights)&&length(unique(labels))==length(labels)||error("Invalid snapshot labels/weights")
    all(x->x isa Real&&isfinite(x)&&x>0,weights)||error("Positive finite snapshot weights required")
    abs(sum(weights)-1)<=1e-12||error("Snapshot weights must sum to one")
    all(c->c.data["baseMVA"]==first(contracts).data["baseMVA"],contracts)||error("Different system bases; explicit conversion required")
    registries=snapshot_registry.(contracts)
    selected=[Set(id for (id,k) in registry if haskey(c.controls,k)&&livegen(c.data["gen"][k])) for (c,registry) in zip(contracts,registries)]
    common=sort!(collect(reduce(intersect,selected)))
    isempty(common)&&error("No designed IBR is available in every snapshot")
    role(c,k)=haskey(c.controls,k) ? "ibr" : any(k in p["ids"] for p in values(c.regulation["avr_plants"])) ? "avr" : k in c.regulation["free_dispatch"] ? "free_pq" : "fixed_q"
    allids=sort!(collect(union([Set(keys(r)) for r in registries]...)))
    for id in allids
        roles=[role(c,r[id]) for (c,r) in zip(contracts,registries) if haskey(r,id)&&livegen(c.data["gen"][r[id]])]
        length(unique(roles))<=1||error("Online control role changes across snapshots: $id")
    end
    # A stable generator must keep its physical regulated source bus.
    for id in common
        targets=[c.controls[registry[id]]["regulated_source_bus"] for (c,registry) in zip(contracts,registries)]
        length(unique(targets))==1||error("Regulated source bus changes across snapshots: $id")
    end
    data=deepcopy(first(contracts).data);source=deepcopy(data)
    for table in ("bus","gen","branch","load","shunt","dcline","storage","switch")
        data[table]=Dict{String,Any}();source[table]=Dict{String,Any}()
    end
    controls=Dict{String,Any}()
    plan=Dict{String,Any}("free_dispatch"=>String[],"reserve_participants"=>String[],"fixed_q"=>String[],
        "avr_plants"=>Dict{String,Any}(),"avr_targets"=>Dict{String,Any}(),"shared_droop_groups"=>Dict{String,Any}(),
        "cross_snapshot_droop"=>Any[],"controller_inventory"=>Any[])
    equipment=Dict{String,Any}("policy"=>"snapshot_specific_source_bounds","selected"=>Dict{String,Any}())
    maps=Any[];effective=NetworkDesignContract[]
    for (s,c) in enumerate(contracts)
        any(!isempty(get(c.data,t,Dict())) for t in ("dcline","storage","switch"))&&error("Unadapted device table in prepared snapshot")
        # Preserve online non-common IBRs with their supplied group settings.
        cc=deepcopy(c);registry=registries[s]
        for (target,group) in cc.regulation["shared_droop_groups"]
            noncommon=[k for k in group["ids"] if !(generator_identity(cc.data["gen"][k]) in common)]
            if !isempty(noncommon)
                slope=group["slope_initial"];vref=group["vref_initial"]
                for k in group["ids"]
                    q=cc.controls[k]
                    q["slope_bounds"][1]<=slope<=q["slope_bounds"][2]&&q["vref_bounds"][1]<=vref<=q["vref_bounds"][2]||error("Supplied non-common curve conflicts with group bounds")
                    q["slope_bounds"]=[slope,slope];q["vref_bounds"]=[vref,vref]
                end
                group["slope_bounds"]=[slope,slope];group["vref_bounds"]=[vref,vref]
                if haskey(cc.regulation["avr_targets"],target)
                    t=cc.regulation["avr_targets"][target];t["vref_bounds"]=[vref,vref];t["vs"]=vref
                end
            end
        end
        push!(effective,cc)
        map=Dict{String,Any}()
        for table in ("bus","gen","branch","load","shunt")
            offset=length(data[table]);ids=sort!(collect(keys(cc.data[table]));by=x->parse(Int,x))
            map[table]=Dict(k=>string(offset+i) for (i,k) in enumerate(ids))
        end
        bus(i)=parse(Int,map["bus"][string(i)])
        for table in ("bus","gen","branch","load","shunt"),(key,row) in cc.data[table]
            r=deepcopy(row);newkey=map[table][key];r["index"]=parse(Int,newkey)
            if table=="bus";r["bus_i"]=bus(row["bus_i"])
            elseif table=="gen";r["gen_bus"]=bus(row["gen_bus"]);r["snapshot_weight"]=weights[s]
            elseif table=="branch";r["f_bus"]=bus(row["f_bus"]);r["t_bus"]=bus(row["t_bus"])
            elseif table=="load";r["load_bus"]=bus(row["load_bus"]);r["snapshot_weight"]=weights[s]
            else;r["shunt_bus"]=bus(row["shunt_bus"]);end
            data[table][newkey]=r;source[table][newkey]=deepcopy(r)
            if table=="bus"
                source[table][newkey]["bus_type"]=cc.source["bus"][key]["bus_type"]
            end
        end
        plantkeys=Dict(k=>"snapshot_$(s)_"*k for k in keys(cc.regulation["avr_plants"]))
        map["plants"]=plantkeys
        for (key,q) in cc.controls
            v=deepcopy(q);v["model_bus"]=bus(q["model_bus"]);v["regulated_model_bus"]=bus(q["regulated_model_bus"])
            controls[map["gen"][key]]=v
        end
        for name in ("free_dispatch","reserve_participants","fixed_q")
            append!(plan[name],[map["gen"][k] for k in cc.regulation[name]])
        end
        for (key,p) in cc.regulation["avr_plants"]
            v=deepcopy(p);v["connection_bus"]=bus(p["connection_bus"]);v["target"]=bus(p["target"])
            v["ids"]=[map["gen"][k] for k in p["ids"]]
            plan["avr_plants"][plantkeys[key]]=v
        end
        for (target,t) in cc.regulation["avr_targets"]
            v=deepcopy(t);v["plants"]=[plantkeys[k] for k in t["plants"]]
            plan["avr_targets"][string(bus(target))]=v
        end
        for (target,g) in cc.regulation["shared_droop_groups"]
            v=deepcopy(g);v["ids"]=[map["gen"][k] for k in g["ids"]]
            plan["shared_droop_groups"][string(bus(target))]=v
        end
        map["equipment"]=Dict{String,String}()
        for (id,e) in cc.equipment["selected"]
            v=deepcopy(e);v["key"]=map[e["table"]][e["key"]]
            newid=e["table"]*":"*v["key"];map["equipment"][id]=newid
            equipment["selected"][newid]=v
        end
        push!(maps,map)
    end
    for id in common
        push!(plan["cross_snapshot_droop"],[maps[s]["gen"][registries[s][id]] for s in eachindex(contracts)])
    end
    # Intersections are checked before optimization, including shared mixed targets.
    for ids in plan["cross_snapshot_droop"],field in ("slope_bounds","vref_bounds")
        maximum(controls[k][field][1] for k in ids)<=minimum(controls[k][field][2] for k in ids)||
            error("Empty cross-snapshot $field intersection")
    end
    combined=NetworkDesignContract(data,controls,plan,equipment;reference=source)
    availability=[Dict("identity"=>id,"present"=>[haskey(r,id) for r in registries],
      "online"=>[haskey(r,id)&&livegen(c.data["gen"][r[id]]) for (c,r) in zip(contracts,registries)],
      "source_pg"=>[haskey(r,id) ? c.data["gen"][r[id]]["pg"] : nothing for (c,r) in zip(contracts,registries)],
      "bidirectional_active_capability"=>[haskey(r,id)&&c.data["gen"][r[id]]["pmin"]<0 for (c,r) in zip(contracts,registries)],
      "control_role"=>[haskey(r,id)&&livegen(c.data["gen"][r[id]]) ? role(c,r[id]) : "offline_or_absent" for (c,r) in zip(contracts,registries)],
      "common_design"=>id in common) for id in allids]
    (;combined,effective,maps,common,availability)
end
function split_snapshot(c,map,combined,r,global_groups)
    d=deepcopy(c.data)
    for (table,fields) in (("bus",("vm","va")),("gen",("pg","qg")),("branch",("pf","qf","pt","qt")))
        for (key,newkey) in map[table],field in fields
            haskey(r["data"][table][newkey],field)&&(d[table][key][field]=r["data"][table][newkey][field])
        end
    end
    for (id,e) in c.equipment["selected"]
        d[e["table"]][e["key"]][e["field"]]=r["equipment_settings"][map["equipment"][id]]
    end
    sharing=Dict{String,Any}()
    for key in required_avr_sharing_keys(c,c.controls)
        prefix="avr_share_"
        mapped=startswith(key,prefix) ? prefix*map["plants"][key[length(prefix)+1:end]] :
          "remote_avr_share_"*map["bus"][key[length("remote_avr_share_")+1:end]]
        sharing[key]=r["avr_sharing"][mapped]
    end
    signals=Dict{String,Any}()
    for (j,g) in enumerate(groups(c.data))
        newbus=parse(Int,map["bus"][string(first(g))])
        index=only(i for (i,gg) in enumerate(global_groups) if newbus in gg)
        signals[string(j)]=r["signals"][string(index)]
    end
    out=Dict{String,Any}("phase"=>r["phase"],"floor"=>r["floor"],"data"=>d,
      "settings"=>Dict(k=>r["settings"][map["gen"][k]] for k in keys(c.controls)),
      "avr_settings"=>Dict(k=>r["avr_settings"][map["bus"][k]] for k in keys(c.regulation["avr_targets"])),
      "avr_sharing"=>sharing,"signals"=>signals,"equipment_policy"=>c.equipment["policy"],
      "equipment_settings"=>Dict(id=>r["equipment_settings"][map["equipment"][id]] for id in keys(c.equipment["selected"])),
      "joint_native_termination"=>r["termination"],"joint_native_primal"=>r["primal"])
    out["replay"]=replay(c,c.controls,out;phase=r["phase"],floor=r["floor"])
    out["loss_mw"]=c.data["baseMVA"]*(sum(g["pg"] for g in values(d["gen"]) if livegen(g))-sum(l["pd"] for l in values(d["load"]) if get(l,"status",1)!=0))
    out
end
function DroopOPF.solve_network_series(contracts::AbstractVector{NetworkDesignContract};
    labels=["snapshot_$i" for i in eachindex(contracts)],weights=fill(1/length(contracts),length(contracts)),kwargs...)
    x=assemble_series(contracts,labels,weights)
    joint=DroopOPF.solve_network_design(x.combined;kwargs...)
    snapshots=Dict{String,Any}()
    if haskey(joint["stages"],"design")
        final=joint["stages"]["design"]
        for i in eachindex(contracts)
            snapshots[labels[i]]=split_snapshot(x.effective[i],x.maps[i],x.combined,final,groups(x.combined.data))
        end
    end
    Dict("schema"=>"DroopOPF.NetworkSeriesResult.v1","accepted"=>joint["accepted"]&&all(s["replay"]["passed"] for s in values(snapshots)),
        "contract_sha256"=>DroopOPF.network_contract_digest.(contracts),"labels"=>labels,"weights"=>weights,
        "policy"=>SERIES_POLICY,
        "availability"=>x.availability,"common_design"=>x.common,"joint"=>joint,"snapshots"=>snapshots,
        "weighted_loss_mw"=>isempty(snapshots) ? nothing : sum(weights[i]*snapshots[labels[i]]["loss_mw"] for i in eachindex(labels)))
end
function DroopOPF.replay_network_series(contracts::AbstractVector{NetworkDesignContract},r)
    r["schema"]=="DroopOPF.NetworkSeriesResult.v1"&&r["accepted"]||error("Unqualified snapshot design")
    DroopOPF.network_contract_digest.(contracts)==r["contract_sha256"]||error("Snapshot inputs changed")
    r["policy"]==SERIES_POLICY||error("Snapshot policy changed")
    x=assemble_series(contracts,r["labels"],r["weights"])
    r["availability"]==x.availability&&r["common_design"]==x.common||error("Selection/availability changed")
    DroopOPF.replay_network_design(x.combined,r["joint"])
    final=r["joint"]["stages"]["design"];expected=Dict{String,Any}()
    for i in eachindex(contracts)
        expected[r["labels"][i]]=split_snapshot(x.effective[i],x.maps[i],x.combined,final,groups(x.combined.data))
    end
    expected==r["snapshots"]||error("Snapshot result differs from joint solution")
    all(s["replay"]["passed"] for s in values(expected))||error("Snapshot replay failed")
    abs(sum(r["weights"][i]*expected[r["labels"][i]]["loss_mw"] for i in eachindex(contracts))-r["weighted_loss_mw"])<=1e-6||error("Weighted loss changed")
    true
end
