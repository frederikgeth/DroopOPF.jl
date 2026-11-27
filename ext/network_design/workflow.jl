function DroopOPF.solve_network_design(c::NetworkDesignContract;
    hessian=DroopOPF.NETWORK_DESIGN_DEFAULTS.hessian,
    max_iterations=DroopOPF.NETWORK_DESIGN_DEFAULTS.max_iterations,
    max_seconds=DroopOPF.NETWORK_DESIGN_DEFAULTS.max_seconds,
    initialization_max_iterations=DroopOPF.NETWORK_DESIGN_DEFAULTS.initialization_max_iterations,
    initialization_max_seconds=DroopOPF.NETWORK_DESIGN_DEFAULTS.initialization_max_seconds,
    diagnostics=false,stage_sink=(name,result)->nothing,stage_begin=name->nothing,
    diagnostic_sink_factory=name->nothing)
    hessian in ("exact","limited-memory")||error("Unknown Hessian")
    for (n,t) in ((max_iterations,max_seconds),(initialization_max_iterations,initialization_max_seconds))
        n isa Integer&&!(n isa Bool)&&n>0&&t isa Real&&isfinite(t)&&t>0||error("Invalid stage budget")
    end
    digest=DroopOPF.network_contract_digest(c);stages=Dict{String,Any}();order=String[];floor=0.
    seed=c.data;settings=Dict();signals=Dict();avr=Dict();sharing=Dict()
    previous="prepared_independent_pf_state"
    for label in ("feasibility","initialization","design-feasibility","design")
        stage_begin(label)
        phase=label=="design-feasibility" ? "design" : label
        initialization=label in ("feasibility","initialization")
        r=solve_lane(c,c.controls,seed;phase,floor=phase=="design" ? floor : 0.,
            seed_settings=settings,seed_signals=signals,seed_avr_settings=avr,seed_avr_sharing=sharing,
            strict_numerics=label!="feasibility",start_push=label=="feasibility" ? nothing : 1e-9,
            hessian,objective_policy=label=="design-feasibility" ? "zero" : "loss",
            max_iterations=initialization ? initialization_max_iterations : max_iterations,
            seconds=initialization ? initialization_max_seconds : max_seconds,
            diagnostics,diagnostic_sink=diagnostic_sink_factory(label))
        r["seed_source"]=previous;r["stage"]=label;r["contract_sha256"]=digest
        stages[label]=r;push!(order,label);stage_sink(label,r)
        r["accepted"]||break
        label=="initialization"&&(floor=max(0.,r["replay"]["reserve"]-1e-8))
        seed=r["data"];settings=r["settings"];signals=r["signals"];avr=r["avr_settings"]
        sharing=restored_avr_sharing(c,c.controls,r);previous=label*".json"
    end
    DroopOPF.network_contract_digest(c)==digest||error("Input contract mutated during solve")
    Dict("schema"=>"DroopOPF.NetworkDesignResult.v1","contract_sha256"=>digest,"implementation_sha256"=>KERNEL_DIGEST,"backend_versions"=>backend_signature(),
      "accepted"=>length(order)==4&&stages["design"]["accepted"],
      "stage_order"=>order,"stages"=>stages,"reserve_floor"=>floor)
end

function DroopOPF.replay_network_design(c::NetworkDesignContract,result)
    get(result,"schema",nothing)=="DroopOPF.NetworkDesignResult.v1"||error("Unknown result schema")
    result["implementation_sha256"]==KERNEL_DIGEST&&result["backend_versions"]==backend_signature()||error("Different kernel or solver versions")
    result["contract_sha256"]==DroopOPF.network_contract_digest(c)||error("Different network contract")
    get(result,"accepted",false)===true||error("Unqualified network design")
    result["stage_order"]==["feasibility","initialization","design-feasibility","design"]||error("Incomplete stage sequence")
    floor=0.;previous="prepared_independent_pf_state";sharing=nothing;mode=nothing
    for label in result["stage_order"]
        r=result["stages"][label];phase=label=="design-feasibility" ? "design" : label
        r["phase"]==phase&&r["stage"]==label&&r["contract_sha256"]==result["contract_sha256"]||error("Stage identity changed")
        r["accepted"]&&r["termination"] in ("LOCALLY_SOLVED","OPTIMAL")&&r["primal"]=="FEASIBLE_POINT"||error("Native convergence missing")
        r["seed_source"]==previous||error("Stage provenance changed")
        r["floor"]==(phase=="design" ? floor : 0.)||error("Reserve floor changed")
        expected_objective=label=="feasibility" ? "feasibility" : label=="initialization" ? "reserve" : label=="design-feasibility" ? "zero" : "loss"
        r["objective_policy"]==expected_objective||error("Stage objective changed")
        if label!="feasibility"
            require_strict_transition(r)
            mode===nothing ? (mode=r["hessian_approximation"]) : mode==r["hessian_approximation"]||error("Hessian policy changed")
        end
        equipment_static_fields(r["data"],c.data,c.equipment)==static_fields(c.data)||error("Physical model changed")
        check=replay(c,c.controls,r;phase,floor=phase=="design" ? floor : 0.)
        check["passed"]||error("Independent physical/control replay failed")
        abs(check["reserve"]-r["replay"]["reserve"])<=1e-8||error("Reserve report changed")
        sharing===nothing||r["avr_sharing_start"]==sharing||error("Sharing handoff changed")
        sharing=restored_avr_sharing(c,c.controls,r)
        loss=c.data["baseMVA"]*(sum(g["pg"] for g in values(r["data"]["gen"]) if livegen(g))-sum(l["pd"] for l in values(c.data["load"]) if get(l,"status",1)!=0))
        abs(loss-r["loss_mw"])<=1e-6||error("Loss report changed")
        label=="initialization"&&(floor=max(0.,check["reserve"]-1e-8))
        previous=label*".json"
    end
    result["reserve_floor"]==floor||error("Final reserve floor changed")
    true
end
