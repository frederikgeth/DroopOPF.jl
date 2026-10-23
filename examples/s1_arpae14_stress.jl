# S1 base-case stress matrix. No SCOPF runs are performed here.
include("s1_ccopt_matrix.jl")
const A14_ROOT=joinpath(@__DIR__,"..","test","data","arpae","c1_network01")
ordered(d)=sort(collect(d);by=x->parse(Int,first(x)))
function a14_case()
    n=JSON.parsefile(joinpath(A14_ROOT,"results","scenario_01_pmin0_qsym","network_model.json"))
    sol=JSON.parsefile(joinpath(A14_ROOT,"results","scenario_01_pmin0_qsym","opf_ac.json"))["solution"]
    buses=[Bus(parse(Int,k);v_min=b["vmin"],v_max=b["vmax"],reference=b["bus_type"]==3) for (k,b) in ordered(n["bus"]) if b["bus_type"]!=4]
    ids=Set(b.id for b in buses)
    branches=Branch[]
    for (k,b) in ordered(n["branch"])
        b["f_bus"] in ids && b["t_bus"] in ids || continue
        abs(b["g_fr"])+abs(b["g_to"])+abs(b["b_fr"]-b["b_to"])<1e-12 || error("unsupported asymmetric branch admittance")
        push!(branches,Branch(parse(Int,k),b["f_bus"],b["t_bus"];resistance=b["br_r"],reactance=b["br_x"],charging=b["b_fr"]+b["b_to"],thermal_limit=b["rate_a"],available=b["br_status"]==1,tap_ratio=b["tap"],phase_shift=b["shift"],kind=b["transformer"] ? :transformer : :line))
    end
    gens=[Generator(parse(Int,k),g["gen_bus"];available=g["gen_status"]==1,p_min=g["pmin"],p_max=g["pmax"],q_min=g["qmin"],q_max=g["qmax"],initial_p=clamp(g["pg"],g["pmin"],g["pmax"]),initial_q=clamp(g["qg"],g["qmin"],g["qmax"])) for (k,g) in ordered(n["gen"]) if g["gen_bus"] in ids]
    loads=[Load(parse(Int,k),l["load_bus"];p=l["pd"],q=l["qd"]) for (k,l) in ordered(n["load"]) if l["status"]==1 && l["load_bus"] in ids]
    shunts=FixedShunt[];banks=ShuntBank[]
    for (k,s) in ordered(n["shunt"])
        if get(s,"dispatchable",false)
            s["bs"]==0. && s["bmin"]==0. || error("expected initially disconnected positive source bank")
            push!(banks,ShuntBank(parse(Int,k),s["shunt_bus"];step_susceptances=(s["bmax"],),legal_states=((0,),(1,)),state=(0,),available=s["status"]==1))
        else
            push!(shunts,FixedShunt(parse(Int,k),s["shunt_bus"];conductance=s["gs"],susceptance=s["bs"],available=s["status"]==1))
        end
    end
    c=Case("arpae14-s1-pmin0-qsym";base_power=n["baseMVA"],base_frequency=60.,network=ACNetwork(buses,branches;shunts,banks),generators=gens,loads,controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    state=ACState([sol["bus"][string(b.id)]["vm"] for b in buses],[sol["bus"][string(b.id)]["va"] for b in buses],[get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"] for g in gens],[get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"] for g in gens])
    validate_equilibrium(c,state).valid || error("source OPF replay failed: $(validate_equilibrium(c,state))")
    return c,state,n
end
function a14_overlay(c,anchor)
    idx=Dict(b.id=>i for (i,b) in enumerate(c.network.buses));controls=VoltVarDroop[];attachments=GeneratorControlAttachment[]
    for (i,g) in enumerate(c.generators)
        g.available || continue
        q=anchor.qg[i]; min(q-g.q_min,g.q_max-q)>1e-3 || continue
        v=anchor.vm[idx[g.bus_id]]
        push!(controls,VoltVarDroop(VoltageSchedule(v;v_db_low=v-.005,v_db_high=v+.005),.04/(g.q_max-g.q_min),q,ReactiveCapability(p_min=g.p_min,p_max=g.p_max,q_min=g.q_min,q_max=g.q_max)))
        push!(attachments,GeneratorControlAttachment(g.id,length(controls),RegulatedLocation(:bus,g.bus_id)))
    end
    cc=Case(c.id*"-droop";base_power=c.base_power,base_frequency=c.base_frequency,network=c.network,loads=c.loads,generators=c.generators,controls,attachments)
    p=(tap_controls=[TapControl(b.id;lower=.95*b.tap_ratio,upper=1.05*b.tap_ratio,nominal=b.tap_ratio) for b in c.network.branches if b.available && b.kind==:transformer],shunt_controls=[ShuntControl(b.id) for b in c.network.banks if b.available],droop_controls=[DroopControl(i;slope_bounds=(.5*x.slope,2*x.slope)) for (i,x) in enumerate(controls)])
    validate_equilibrium(cc,anchor).valid || error("nominal droop anchor failed")
    return cc,p
end
function a14_start(c,anchor,mode)
    mode==:anchor && return anchor
    v=mode==:flat_low ? .95 : 1.05
    ACState(fill(v,length(c.network.buses)),zeros(length(c.network.buses)),[g.available ? g.initial_p : 0. for g in c.generators],[g.available ? g.initial_q : 0. for g in c.generators])
end
function a14_run(out)
    mkpath(out); c,source,n=a14_case()
    rows=isfile(joinpath(out,"summary.json")) ? JSON.parsefile(joinpath(out,"summary.json")) : Any[]
    done=Set(r["name"] for r in rows)
    function attempt(name,case,state,solver,p;tags,epsilon=1e-6,normalization=:none,qform=:explicit)
        name in done && return nothing
        row,result=solver==:ccopt ? s1_ccopt_attempt(out,name,case,state;policies=p,tags,option_overrides=merge(s1_ccopt_profile(:tight),Dict{String,Any}("max_iter"=>600,"max_wall_time"=>20.))) : s1_attempt(out,name,case,state;policies=p,solver,tags,epsilon,control_normalization=normalization,droop_q_formulation=qform,options=solver==:ipopt ? Dict{String,Any}("max_iter"=>600,"max_cpu_time"=>20.) : Dict{String,Any}("max_iter"=>600,"max_wall_time"=>20.))
        row["solver"]=string(solver)
        row["actual_budget"]=Dict("iterations"=>600,"native_seconds"=>20.)
        row["budget"]=copy(row["actual_budget"])
        row["free_counts"]=Dict("tap"=>length(p.tap_controls),"shunt"=>length(p.shunt_controls),"droop"=>length(p.droop_controls))
        if result!==nothing && result.opf.state!==nothing
            row["exact_droop_audit"]=exact_droop_audit(case,result)
            phys=with_joint_settings(case,result);st=result.opf.state;idx=Dict(b.id=>i for (i,b) in enumerate(phys.network.buses))
            row["source_angle_violation_rad"]=maximum(max(n["branch"][string(b.id)]["angmin"]-(st.va[idx[b.from_bus]]-st.va[idx[b.to_bus]]),(st.va[idx[b.from_bus]]-st.va[idx[b.to_bus]])-n["branch"][string(b.id)]["angmax"],0.) for b in phys.network.branches if b.available)
            row["valid"]=get(row,"valid",false) && row["source_angle_violation_rad"]<=1e-5
            row["metrics"]=DroopOPF._json_data(joint_design_metrics(case,result))
        end
        write(joinpath(out,name*"-diagnostics.json"),JSON.json(row;pretty=true))
        push!(rows,row);push!(done,name);s1_summary(out,rows)
        return result
    end
    empty=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
    # Common native-objective anchor is created once, with all source equipment fixed.
    anchor_path=joinpath(out,"native-anchor.json")
    anchor=if isfile(anchor_path)
        read_joint_design(anchor_path)
    else
        x=optimize_joint_design(c;initial_state=source,optimizer_attributes=Dict("tol"=>1e-9,"max_iter"=>1000,"max_cpu_time"=>30.))
        validate_joint_design(c,x).valid || error("native anchor failed")
        write_joint_design(anchor_path,x);x
    end
    cc,p=a14_overlay(c,source)
    control_anchor=source
    write_study(joinpath(out,"source-study.json"),Study(c));write_study(joinpath(out,"droop-study.json"),Study(cc))
    write(joinpath(out,"protocol.json"),JSON.json(Dict("scope"=>"S1 base-case; no contingencies","solvers"=>["ipopt","madnlp","ccopt"],"primary_cells"=>72,"baseline_cells"=>3,"extra_cells"=>20,"controls"=>Dict("droops"=>length(cc.controls),"taps"=>length(p.tap_controls),"banks"=>length(p.shunt_controls)),"starts"=>["anchor"],"load_factors"=>[.9,1.,1.1],"objective"=>"native squared P dispatch deviation + 1e-3 squared Q deviation; not upstream fuel cost","tap_bounds"=>"synthetic +/-5% around source ratios","bank_bounds"=>"source bank at bus 11: continuous B 0 to 0.4 pu; not discrete switching","droop"=>"anchor-derived VoltVar: +/-0.005 pu deadband; nominal slope .04/Q width; free slope 0.5 to 2 times nominal","budget"=>"600 iterations/20 native solver seconds per cell; CCOpt tight relaxation profile","source_sha256"=>bytes2hex(sha256(read(joinpath(A14_ROOT,"scenario_01_pmin0_qsym","case.raw")))),"source_replay_valid"=>true);pretty=true))
    for solver in (:ipopt,:madnlp,:ccopt),mode in (:anchor,)
        attempt("baseline-$solver-$mode",c,a14_start(c,source,mode),solver,empty;tags=Dict("block"=>"baseline","family"=>"uncontrolled","start"=>string(mode),"load_factor"=>1.))
    end
    for factor in (1.,.9,1.1),family in S1_CCOPT_FAMILIES,mode in (:anchor,),solver in (:ipopt,:madnlp,:ccopt)
        pp=s1_ccopt_family(p,family;count=100)
        mode==:anchor || (pp=s1_reseed(cc,pp;fraction=mode==:flat_low ? .2 : .8))
        attempt("matrix-$factor-$family-$mode-$solver",s1_load(cc,factor),a14_start(cc,control_anchor,mode),solver,pp;tags=Dict("block"=>"matrix","family"=>string(family),"start"=>string(mode),"load_factor"=>factor))
    end
    for solver in (:ipopt,:madnlp),eps in (1e-4,1e-8),mode in (:anchor,)
        attempt("epsilon-$solver-$eps-$mode",cc,a14_start(cc,control_anchor,mode),solver,p;epsilon=eps,tags=Dict("block"=>"epsilon","family"=>"joint","start"=>string(mode),"load_factor"=>1.))
    end
    for solver in (:ipopt,:madnlp),config in (:unit_box,:reduced),mode in (:anchor,)
        attempt("formulation-$solver-$config-$mode",cc,a14_start(cc,control_anchor,mode),solver,p;normalization=config==:unit_box ? :bounds : :none,qform=config==:reduced ? :reduced : :explicit,tags=Dict("block"=>"formulation","family"=>string(config),"start"=>string(mode),"load_factor"=>1.))
    end
    for solver in (:ipopt,:madnlp,:ccopt),count in (1,3),factor in (1.,1.1)
        pp=s1_ccopt_family(p,:joint;count=count)
        attempt("count-$solver-$count-$factor",s1_load(cc,factor),control_anchor,solver,pp;tags=Dict("block"=>"control_count","family"=>"joint$count","start"=>"anchor","load_factor"=>factor))
    end
    println("S1 COMPLETE ",length(rows)," cells; accepted ",Base.count(r->get(r,"valid",false),rows));flush(stdout)
end
abspath(PROGRAM_FILE)==(@__FILE__) && a14_run(abspath(isempty(ARGS) ? joinpath(@__DIR__,"..","artifacts","s1_arpae14_stress") : ARGS[1]))
