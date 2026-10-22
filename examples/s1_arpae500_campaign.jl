# S1 only. Preserve all imported OPF/SCOPF references; checkpoint every new attempt.
using DroopOPF, JSON, JuMP, Ipopt, MadNLP, SHA, LinearAlgebra
import CCOpt
const A500_ROOT=normpath(joinpath(@__DIR__,".."))
const A500_DATA=joinpath(A500_ROOT,"test/data/arpae/c1_network01/results/scenario_02_pmin0_qsym")
const A500_OUT=joinpath(A500_ROOT,"artifacts/s1_arpae500")
a500_json(x)=DroopOPF._json_data(x)
a500_save(path,x)=write(path,JSON.json(a500_json(x);pretty=true))
a500_state(d)=ACState(Float64.(d["vm"]),Float64.(d["va"]),Float64.(d["pg"]),Float64.(d["qg"]))
a500_settings(d)=Dict(parse(Int,k)=>Float64(v) for (k,v) in d)
a500_order(d)=sort(collect(d);by=p->parse(Int,first(p)))
function a500_inputs()
    n=JSON.parsefile(joinpath(A500_DATA,"network_model.json"));sol=JSON.parsefile(joinpath(A500_DATA,"opf_ac.json"))["solution"]
    @assert length(n["bus"])==500 && isempty(n["dcline"])
    buses=[Bus(parse(Int,k);v_min=b["vmin"],v_max=b["vmax"],reference=b["bus_type"]==3) for (k,b) in a500_order(n["bus"]) if b["bus_type"]!=4]
    ids=Set(b.id for b in buses);branches=Branch[]
    for (k,b) in a500_order(n["branch"])
        @assert b["f_bus"] in ids && b["t_bus"] in ids
        @assert abs(b["g_fr"])+abs(b["g_to"])+abs(b["b_fr"]-b["b_to"])<1e-12
        @assert b["rate_a"]>0
        push!(branches,Branch(parse(Int,k),b["f_bus"],b["t_bus"];resistance=b["br_r"],reactance=b["br_x"],charging=b["b_fr"]+b["b_to"],thermal_limit=b["rate_a"],available=b["br_status"]==1,tap_ratio=b["tap"],phase_shift=b["shift"],kind=b["transformer"] ? :transformer : :line))
    end
    gens=Generator[]
    for (k,g) in a500_order(n["gen"])
        @assert g["pmin"]==0 && isapprox(g["qmin"],-g["qmax"];atol=1e-10)
        push!(gens,Generator(parse(Int,k),g["gen_bus"];available=g["gen_status"]==1,p_min=g["pmin"],p_max=g["pmax"],q_min=g["qmin"],q_max=g["qmax"],initial_p=clamp(g["pg"],g["pmin"],g["pmax"]),initial_q=clamp(g["qg"],g["qmin"],g["qmax"])))
    end
    loads=[Load(parse(Int,k),l["load_bus"];p=l["pd"],q=l["qd"]) for (k,l) in a500_order(n["load"]) if l["status"]==1]
    banks=ShuntBank[]
    for (k,b) in a500_order(n["shunt"])
        @assert b["dispatchable"] && b["bs"]==0 && b["gs"]==0 && b["bmin"]==0 && b["bmax"]>0
        push!(banks,ShuntBank(parse(Int,k),b["shunt_bus"];step_susceptances=(b["bmax"],),legal_states=((0,),(1,)),state=(0,),available=b["status"]==1))
    end
    c=Case("arpae500-study";base_power=n["baseMVA"],base_frequency=60.,network=ACNetwork(buses,branches;banks),generators=gens,loads,controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    s=ACState([sol["bus"][string(b.id)]["vm"] for b in buses],[sol["bus"][string(b.id)]["va"] for b in buses],[get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"] for g in gens],[get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"] for g in gens])
    angles=Dict(parse(Int,k)=>(Float64(b["angmin"]),Float64(b["angmax"])) for (k,b) in n["branch"])
    costs=Dict{Int,Vector{Tuple{Float64,Float64}}}()
    for (k,g) in n["gen"]
        g["gen_status"]==1 || continue
        @assert g["model"]==1
        v=g["cost"];segments=Tuple{Float64,Float64}[]
        for i in 1:g["ncost"]-1
            x1,y1,x2,y2=Float64.(v[2i-1:2i+2]);@assert x2>x1
            m=(y2-y1)/(x2-x1);push!(segments,(m,y1-m*x1))
        end
        @assert issorted(first.(segments));costs[parse(Int,k)]=segments
    end
    c,s,angles,costs,n
end
function a500_policy(c,family;reference=nothing,frozen=false)
    taps=TapControl[];shunts=ShuntControl[]
    for b in c.network.branches
        b.available && b.kind==:transformer || continue
        v=isnothing(reference) ? b.tap_ratio : reference["taps"][string(b.id)]
        if frozen || family in ("tap","tap_shunt")
            push!(taps,TapControl(b.id;lower=frozen ? v : .95*b.tap_ratio,upper=frozen ? v : 1.05*b.tap_ratio,initial=v,nominal=b.tap_ratio))
        end
    end
    for b in c.network.banks
        b.available || continue
        v=isnothing(reference) ? 0. : reference["susceptances"][string(b.id)]
        if frozen || family in ("shunt","tap_shunt")
            push!(shunts,ShuntControl(b.id;lower=frozen ? v : 0.,upper=frozen ? v : only(b.step_susceptances),initial=v))
        end
    end
    (tap_controls=taps,shunt_controls=shunts)
end
function a500_details(c,r,angles,p,costs)
    haskey(r,"state") || return r
    s=a500_state(r["state"]);taps=a500_settings(r["taps"]);bs=a500_settings(r["susceptances"])
    audit=validate_feasibility_witness(FeasibilityProblem(c;p...,angle_limits=angles),FeasibilityWitness(s;taps,susceptances=bs))
    r["point_checks"]=a500_json(audit);r["point_pass"]=audit["valid"];r["accepted"]=r["solver_success"] && r["point_pass"]
    physical=with_shunt_settings(with_tap_settings(c,taps),bs);flows=branch_flows(physical.network,s);idx=DroopOPF._bus_indices(c.network);bm=c.base_power
    r["loss_mw"]=(sum(s.pg)-sum(l.p for l in c.loads))*bm
    r["economic_cost"]=sum(maximum(m*s.pg[i]+b for (m,b) in costs[g.id]) for (i,g) in enumerate(c.generators) if g.available)
    if haskey(r,"operating_bounds")
        violations=[];margins=[]
        for (i,g) in enumerate(c.generators)
            g.available || continue
            d=r["operating_bounds"][string(g.id)]
            for axis in ("p","q")
                haskey(d,axis*"min") || continue
                v=axis=="p" ? s.pg[i] : s.qg[i];lo=d[axis*"min"];hi=d[axis*"max"]
                push!(margins,Dict("generator"=>g.id,"axis"=>axis,"value"=>v,"min"=>lo,"max"=>hi,"lower_margin"=>v-lo,"upper_margin"=>hi-v))
                lo-1e-6<=v<=hi+1e-6 || push!(violations,"g$(g.id)-$axis")
            end
        end
        r["operating_bound_check"]=Dict("valid"=>isempty(violations),"violations"=>violations,"margins"=>margins)
        r["point_pass"] &= isempty(violations);r["accepted"]=r["solver_success"] && r["point_pass"]
    end
    r["buses"]=[Dict("id"=>b.id,"vm"=>s.vm[i],"vmin"=>b.v_min,"vmax"=>b.v_max,"lower_margin"=>s.vm[i]-b.v_min,"upper_margin"=>b.v_max-s.vm[i]) for (i,b) in enumerate(c.network.buses)]
    r["generators"]=[Dict("id"=>g.id,"bus"=>g.bus_id,"available"=>g.available,"pg_mw"=>s.pg[i]*bm,"qg_mvar"=>s.qg[i]*bm,"pmin_mw"=>g.p_min*bm,"pmax_mw"=>g.p_max*bm,"qmin_mvar"=>g.q_min*bm,"qmax_mvar"=>g.q_max*bm) for (i,g) in enumerate(c.generators)]
    r["branches"]=[Dict("id"=>b.id,"kind"=>string(b.kind),"from"=>b.from_bus,"to"=>b.to_bus,"rating_mva"=>b.thermal_limit*bm,"from_mva"=>abs(flows.from[i])*bm,"to_mva"=>abs(flows.to[i])*bm,"pf_mw"=>real(flows.from[i])*bm,"pt_mw"=>real(flows.to[i])*bm,"qf_mvar"=>imag(flows.from[i])*bm,"qt_mvar"=>imag(flows.to[i])*bm,"thermal_margin_mva"=>(b.thermal_limit-max(abs(flows.from[i]),abs(flows.to[i])))*bm,"angle_rad"=>s.va[idx[b.from_bus]]-s.va[idx[b.to_bus]],"angle_min_rad"=>angles[b.id][1],"angle_max_rad"=>angles[b.id][2],"tap"=>b.tap_ratio) for (i,b) in enumerate(physical.network.branches) if b.available]
    r
end
function a500_attempt(c,s,angles,costs,p,name;solver=:ipopt,objective="loss",tags=Dict(),iterations=1000,seconds=60.,qform=:explicit,normalization=:none,epsilon=1e-6,extra=Dict{String,Any}(),operating_bounds=nothing,ccopt_mu_init=nothing)
    mkpath(joinpath(A500_OUT,"attempts"));path=joinpath(A500_OUT,"attempts",name*".json")
    fp=feasibility_fingerprint(FeasibilityProblem(c;p...,angle_limits=angles))
    contract=Dict("model"=>fp,"initial"=>DroopOPF._feasibility_hash(s),"solver"=>string(solver),"objective"=>objective,"iterations"=>iterations,"seconds"=>seconds,"qform"=>string(qform),"normalization"=>string(normalization),"epsilon"=>epsilon,"extra"=>extra)
    isnothing(operating_bounds) || (contract["operating_bounds"]=operating_bounds)
    isnothing(ccopt_mu_init) || (contract["ccopt_mu_init"]=ccopt_mu_init)
    hash=DroopOPF._feasibility_hash(contract)
    if isfile(path)
        r=JSON.parsefile(path);@assert r["contract_hash"]==hash "resume contract changed: $name";return r
    end
    casepath=joinpath(A500_OUT,"models",fp*".json");mkpath(dirname(casepath));isfile(casepath) || write_study(casepath,Study(c))
    r=Dict{String,Any}("name"=>name,"tags"=>tags,"solver"=>string(solver),"objective_kind"=>objective,"contract_hash"=>hash,"contract"=>contract,"model_path"=>relpath(casepath,A500_ROOT),"policy"=>a500_json(p),"accepted"=>false,"point_pass"=>false,"solver_success"=>false)
    isnothing(operating_bounds) || (r["operating_bounds"]=operating_bounds)
    println("START ",name);flush(stdout)
    try
        opts=solver==:ipopt ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>iterations,"max_cpu_time"=>seconds,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive","print_level"=>0) : solver==:madnlp ? Dict{String,Any}("tol"=>1e-8,"max_iter"=>iterations,"max_wall_time"=>seconds,"bound_relax_factor"=>0.) : Dict{String,Any}("relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),"tol"=>1e-11,"acceptable_tol"=>1e-11,"bound_relax_factor"=>0.,"max_iter"=>iterations,"max_wall_time"=>seconds)
        merge!(opts,extra)
        if !isnothing(ccopt_mu_init)
            @assert solver==:ccopt && ccopt_mu_init>0
            barrier=MadNLP.MonotoneUpdate(1e-11,10.);barrier.mu_init=ccopt_mu_init
            opts["barrier"]=barrier
        end
        kwargs=solver==:ccopt ? (encoding=:complementarity,) : (optimizer_factory=solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer,)
        t0=time();built=Ref(0.)
        measured=@timed optimize_joint_design(c;initial_state=s,p...,kwargs...,smooth_epsilon=epsilon,smooth_reactive_epsilon=epsilon,droop_q_formulation=qform,control_normalization=normalization,optimizer_attributes=opts,_measurement_hook=(phase,m)->begin
            if phase==:built
                idx=DroopOPF._bus_indices(c.network)
                for b in c.network.branches
                    b.available || continue
                    lo,hi=angles[b.id];f=variable_by_name(m,"va[$(idx[b.from_bus])]");t=variable_by_name(m,"va[$(idx[b.to_bus])]");@constraint(m,lo<=f-t<=hi)
                end
                if !isnothing(operating_bounds)
                    for (i,g) in enumerate(c.generators)
                        g.available || continue
                        d=operating_bounds[string(g.id)]
                        for axis in ("p","q")
                            haskey(d,axis*"min") || continue
                            x=variable_by_name(m,"$(axis)g[$i]")
                            set_lower_bound(x,max(lower_bound(x),d[axis*"min"]))
                            set_upper_bound(x,min(upper_bound(x),d[axis*"max"]))
                        end
                    end
                end
                pg=[variable_by_name(m,"pg[$i]") for i in eachindex(c.generators)]
                if objective=="loss"
                    pd=sum(l.p for l in c.loads);@objective(m,Min,sum(pg)-pd)
                elseif objective=="cost"
                    zs=VariableRef[]
                    for (i,g) in enumerate(c.generators)
                        g.available || continue
                        z=@variable(m,base_name="economic_cost_$(g.id)");set_start_value(z,maximum(a*s.pg[i]+b for (a,b) in costs[g.id])/1e5)
                        for (a,b) in costs[g.id];@constraint(m,z>=(a*pg[i]+b)/1e5);end
                        push!(zs,z)
                    end
                    @objective(m,Min,sum(zs))
                elseif objective=="feasibility"
                    @objective(m,Min,0.)
                end
                built[]=time();r["build_seconds"]=built[]-t0;r["variables"]=num_variables(m)
            elseif phase==:solved
                r["solve_wall_seconds"]=time()-built[]
                if solver==:ccopt
                    try;r["ccopt_diagnostics"]=ccopt_diagnostics(m);catch;end
                    try;r["ccopt_encoding_audit"]=ccopt_encoding_audit(m);catch;end
                end
                try;r["iterations"]=JuMP.barrier_iterations(m);catch;end
            end
        end)
        result=measured.value;r["elapsed_seconds"]=measured.time;r["allocated_bytes"]=measured.bytes;r["solver_status"]=string(result.opf.termination_status)
        r["solver_success"]=result.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
        r["objective"]=isfinite(result.opf.objective) ? result.opf.objective : nothing
        if result.opf.state!==nothing
            r["state"]=a500_json(result.opf.state);r["taps"]=a500_json(result.taps);r["susceptances"]=a500_json(result.susceptances)
            a500_details(c,r,angles,p,costs)
            expected=objective=="loss" ? r["loss_mw"]/c.base_power : objective=="cost" ? r["economic_cost"]/1e5 : 0.
            r["objective_replay_error"]=abs(expected-r["objective"])
            r["accepted"] && @assert isapprox(expected,r["objective"];atol=1e-5,rtol=1e-6)
        end
    catch err
        err isa InterruptException && rethrow()
        r["error"]=sprint(showerror,err)
    end
    a500_save(path,r);println("END ",name," accepted=",r["accepted"]," status=",get(r,"solver_status",get(r,"error","unknown"))," seconds=",get(r,"solve_wall_seconds",0.));flush(stdout);r
end
function a500_calibrate(c,s;percent=8.)
    ds=VoltVarDroop[];as=GeneratorControlAttachment[];idx=DroopOPF._bus_indices(c.network)
    for (i,g) in enumerate(c.generators)
        g.available || continue
        @assert g.q_max>g.q_min
        m=percent/100/(g.q_max-g.q_min);ref=s.vm[idx[g.bus_id]]+m*s.qg[i]
        push!(ds,VoltVarDroop(VoltageSchedule(ref;v_db_low=ref,v_db_high=ref),m,0.,ReactiveCapability(p_min=g.p_min,p_max=g.p_max,q_min=g.q_min,q_max=g.q_max)))
        push!(as,GeneratorControlAttachment(g.id,length(ds),RegulatedLocation(:bus,g.bus_id)))
    end
    Case(c.id*"-droop$percent";base_power=c.base_power,base_frequency=c.base_frequency,network=c.network,generators=c.generators,loads=c.loads,controls=ds,attachments=as)
end
function a500_preflight()
    mkpath(A500_OUT);c,s,angles,costs,n=a500_inputs();p=a500_policy(c,"fixed")
    r=Dict{String,Any}("state"=>a500_json(s),"taps"=>Dict(),"susceptances"=>Dict(),"solver_success"=>true)
    a500_details(c,r,angles,p,costs);a500_save(joinpath(A500_OUT,"source_replay.json"),r);@assert r["point_pass"]
    sol=JSON.parsefile(joinpath(A500_DATA,"opf_ac.json"))["solution"]
    err=maximum(maximum(abs(b[key]-sol["branch"][string(b["id"])][orig]*c.base_power) for (key,orig) in (("pf_mw","pf"),("pt_mw","pt"),("qf_mvar","qf"),("qt_mvar","qt"))) for b in r["branches"])
    @assert err<1e-3
    edges=Dict(b.id=>Int[] for b in c.network.buses)
    for b in c.network.branches;b.available || continue;push!(edges[b.from_bus],b.to_bus);push!(edges[b.to_bus],b.from_bus);end
    seen=Set{Int}();components=0
    for id in keys(edges)
        id in seen && continue;components+=1;queue=[id]
        while !isempty(queue);x=pop!(queue);x in seen && continue;push!(seen,x);append!(queue,edges[x]);end
    end
    @assert components==1
    write_study(joinpath(A500_OUT,"source-study.json"),Study(c));a500_save(joinpath(A500_OUT,"angle_limits.json"),angles)
    hashes=Dict(relpath(joinpath(A500_DATA,f),A500_ROOT)=>bytes2hex(sha256(read(joinpath(A500_DATA,f)))) for f in ("network_model.json","opf_ac.json","scopf_ac.json"))
    a500_save(joinpath(A500_OUT,"preflight.json"),Dict("buses"=>length(c.network.buses),"online_generators"=>count(g->g.available,c.generators),"online_branches"=>count(b->b.available,c.network.branches),"online_transformers"=>count(b->b.available && b.kind==:transformer,c.network.branches),"online_banks"=>count(b->b.available,c.network.banks),"connected_components"=>components,"source_replay_valid"=>true,"source_flow_max_error_mva_components"=>err,"source_hashes"=>hashes,"all_online_generators_positive_Q_span"=>true))
    println("PREFLIGHT PASS flow error ",err);flush(stdout)
end
function a500_reference_stage()
    a500_preflight();c,s,angles,costs,n=a500_inputs();p=a500_policy(c,"fixed")
    rows=[]
    for objective in ("loss","cost"),f in (1.,.9,1.1,.95,1.05)
        cc=DroopOPF._feasibility_scaled_case(c,f)
        r=a500_attempt(cc,s,angles,costs,p,"source-$objective-$f-ipopt";objective,tags=Dict("stage"=>"source","factor"=>f,"objective"=>objective))
        push!(rows,r)
        r["accepted"] || continue
        if f==1.
            push!(rows,a500_attempt(cc,s,angles,costs,p,"source-$objective-$f-madnlp";solver=:madnlp,objective,tags=Dict("stage"=>"source","factor"=>f,"objective"=>objective)))
        end
    end
    p=a500_policy(c,"tap_shunt")
    for init in ("loss","cost"),solver in (:ipopt,:madnlp)
        r=only(filter(r->r["name"]=="source-$init-1.0-ipopt",rows));r["accepted"] || continue
        push!(rows,a500_attempt(c,a500_state(r["state"]),angles,costs,p,"joint-reference-$init-$solver";solver,tags=Dict("stage"=>"reference","factor"=>1.,"init"=>init)))
    end
    good=filter(r->r["tags"]["stage"]=="reference" && r["accepted"],rows)
    isempty(good) && error("joint reference unresolved: inspect retained attempts")
    chosen=first(sort(good;by=r->(r["loss_mw"],r["name"])));a500_save(joinpath(A500_OUT,"selected_reference.json"),chosen)
    calibrated=a500_calibrate(c,a500_state(chosen["state"]));pfix=a500_policy(c,"fixed";reference=chosen,frozen=true)
    check=validate_feasibility_witness(FeasibilityProblem(calibrated;pfix...,angle_limits=angles),FeasibilityWitness(a500_state(chosen["state"]);taps=a500_settings(chosen["taps"]),susceptances=a500_settings(chosen["susceptances"])))
    a500_save(joinpath(A500_OUT,"calibration_gate.json"),check);@assert check["valid"]
    write_study(joinpath(A500_OUT,"calibrated-study.json"),Study(calibrated))
    frozen=with_shunt_settings(with_tap_settings(calibrated,a500_settings(chosen["taps"])),a500_settings(chosen["susceptances"]))
    write_study(joinpath(A500_OUT,"frozen-study.json"),Study(frozen))
    println("REFERENCE COMPLETE loss=",chosen["loss_mw"]," controls=",length(calibrated.controls));flush(stdout)
end
function a500_frozen_stage()
    c,_,angles,costs,_=a500_inputs();base=read_study(joinpath(A500_OUT,"frozen-study.json")).case;ref=JSON.parsefile(joinpath(A500_OUT,"selected_reference.json"));p=a500_policy(base,"fixed")
    for f in (1.,.9,1.1,.95,1.05),init in ("joint","loss","cost"),solver in (:ipopt,:madnlp,:ccopt)
        r=init=="joint" ? ref : JSON.parsefile(joinpath(A500_OUT,"attempts","source-$init-$f-ipopt.json"));r["accepted"] || continue
        cc=DroopOPF._feasibility_scaled_case(base,f)
        a500_attempt(cc,a500_state(r["state"]),angles,costs,p,"frozen-$f-$init-$solver";solver,tags=Dict("stage"=>"frozen","factor"=>f,"init"=>init,"family"=>"fixed"))
    end
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    stage=isempty(ARGS) ? "reference" : ARGS[1]
    stage=="reference" ? a500_reference_stage() : stage=="frozen" ? a500_frozen_stage() : error("unknown stage")
end
