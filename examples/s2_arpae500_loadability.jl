# Explicit, bounded Phase-I/continuation study. Imports never start a solve.
# Emergency limits and load relief are study policies, not equipment remedies.
include("s2_arpae500_multidemand.jl")
const EL_OUT=joinpath(S2500_OUT,"emergency_loadability")
const EL_SOURCE=joinpath(FD_ROOT,"test/data/arpae/c1_network01/results/scenario_02_pmin0_qsym/network_model.json")
const EL_EXECUTED_SOURCE=read(@__FILE__,String)
const EL_EXECUTED_SHA=bytes2hex(sha256(EL_EXECUTED_SOURCE))

function el_case(c;emergency=false,thermal_multiplier=1.0)
    n=c.network
    buses=[Bus(b.id;v_min=b.v_min-(emergency ? .05 : 0.),v_max=b.v_max+(emergency ? .05 : 0.),reference=b.reference) for b in n.buses]
    branches=[Branch(b.id,b.from_bus,b.to_bus;resistance=b.resistance,reactance=b.reactance,
        charging=b.charging,thermal_limit=b.thermal_limit*(emergency ? thermal_multiplier : 1.),
        available=b.available,tap_ratio=b.tap_ratio,phase_shift=b.phase_shift,kind=b.kind) for b in n.branches]
    net=ACNetwork(buses,branches;shunts=n.shunts,banks=n.banks)
    Case(c.id;base_power=c.base_power,base_frequency=c.base_frequency,network=net,loads=c.loads,
        generators=c.generators,controls=c.controls,attachments=c.attachments)
end

function el_fresh_optimizer!(m,solver,seconds)
    set_optimizer(m,solver==:ccopt ? CCOpt.Optimizer : solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer)
    solver==:ccopt && DroopOPF.MathOptComplements.Bridges.add_all_bridges(m)
    set_silent(m);set_optimizer_attribute(m,"tol",1e-8)
    set_optimizer_attribute(m,"bound_relax_factor",0.);set_optimizer_attribute(m,"max_iter",6000)
    if solver==:ipopt
        set_optimizer_attribute(m,"print_level",0);set_optimizer_attribute(m,"max_cpu_time",seconds)
        set_optimizer_attribute(m,"mu_strategy","adaptive")
    else
        set_optimizer_attribute(m,"max_wall_time",seconds);set_optimizer_attribute(m,"linear_solver",MadNLP.UmfpackSolver)
    end
end

function el_context()
    nominal=JSON.parsefile(joinpath(S2500_QUAL,"summary-expanded-madnlp-reserve.json"))
    folder=joinpath(S2500_OUT,nominal["selected"])
    study=read_study(joinpath(folder,"optimized-1.0.json"))
    result=read_scopf_result(joinpath(folder,"result-1.0.json"))
    (;study,result,controls=s214_multi_controls(fd_inputs(500).base),angles=fd_inputs(500).angles)
end

function el_protocol(confirmation)
    isempty(strip(confirmation)) && error("Explicit campaign confirmation required")
    x=el_context();mkpath(EL_OUT)
    source=JSON.parsefile(EL_SOURCE)
    @assert all(b["rate_a"]==b["rate_c"] for b in values(source["branch"]) if b["br_status"]==1)
    paths=["examples/s2_arpae500_loadability.jl","examples/s2_arpae500_multidemand.jl",
        "examples/s2_arpae500_linear_recovery.jl","src/jump.jl","src/tap_optimization.jl",
        "src/scopf.jl","Project.toml","Manifest.toml",relpath(EL_SOURCE,FD_ROOT)]
    fd_save(joinpath(EL_OUT,"protocol.json"),(;confirmation,tap_controls=x.study.tap_controls,
        shunt_controls=x.study.shunt_controls,control_policy=x.study.control_policy,
        shared_droop_parameters=102,dr_fraction_per_positive_load=.01,
        shedding_mw_per_contingency=10.,combined_fraction_per_load=.1,proportional_q_relief=true,
        basecase_emergency_or_relief=false,voltage_extension_pu=.05,confirmed_thermal_multiplier=1.1,
        source_rate_c_equals_rate_a_all_593=true,
        priorities=["Phase I artificial residuals (must vanish)","involuntary shedding","demand response","normalized emergency departures","base losses"],
        strict_demand_steps=(1.025,1.05,1.075,1.09,1.1),boundary_refinement_factor_tolerance=.0025,
        boundary_caveat="Local failures are unresolved, not proofs of infeasibility; individual AC points do not establish a shared-controller interval",
        limits=(master_states=48,master_native_seconds_per_stage=180.,master_iterations=6000,
            separator_native_seconds=15.,separator_retry_seconds=45.,maximum_contingency_addition_rounds=4),
        run_source_hashes=Dict(p=>bytes2hex(sha256(read(joinpath(FD_ROOT,p)))) for p in paths)))
end

function el_response!(m,study,c,base,v,prefix,cap,prior,scale)
    cap>=0 || error("Response relaxation cap must be nonnegative")
    if cap==0
        delta=DroopOPF._add_response_constraints!(m,study,c,base,v,prefix)
        if !isnothing(delta) && !isnothing(prior) && hasproperty(prior,:delta) && !isnothing(prior.delta)
            set_start_value(delta,prior.delta*scale)
        end
        return delta,VariableRef[]
    end
    study.mode==:preventive || error("Response diagnostic requires preventive mode")
    alpha=DroopOPF._participation(study,c)
    initial=!isnothing(prior) && hasproperty(prior,:delta) && !isnothing(prior.delta) ? prior.delta*scale : 0.
    delta=@variable(m,base_name=prefix*"balancing_power",start=initial)
    errors=VariableRef[]
    for (i,g) in enumerate(c.generators)
        g.available || continue
        bound=cap*max(g.p_max,1e-6)
        e=@variable(m,lower_bound=-bound,upper_bound=bound,base_name=prefix*"response_error_$(g.id)")
        set_start_value(e,clamp(start_value(v.pg[i])-start_value(base.pg[i])-alpha[i]*initial,-bound,bound))
        @constraint(m,v.pg[i]==base.pg[i]+alpha[i]*delta+e)
        push!(errors,e)
        if haskey(study.redispatch_limits,g.id)
            limit=study.redispatch_limits[g.id]
            @constraint(m,-limit<=v.pg[i]-base.pg[i]<=limit)
        end
    end
    delta,errors
end

function el_relief_variables!(m,c,post,relief,zero_dr,zero_shedding,prefix,prior,dr_all,shed_all)
    dr=Dict{Int,VariableRef}();shed=Dict{Int,VariableRef}()
    for l in c.loads
        eligible=post && relief && l.p>0
        d=@variable(m,lower_bound=0.,upper_bound=eligible && !zero_dr ? .01*l.p : 0.,base_name=prefix*"dr_$(l.id)")
        s=@variable(m,lower_bound=0.,upper_bound=eligible && !zero_shedding ? .1*l.p : 0.,base_name=prefix*"shed_$(l.id)")
        if eligible && !zero_shedding
            @constraint(m,d+s<=.1*l.p)
        end
        dr[l.id]=d;shed[l.id]=s;append!(dr_all,[d]);append!(shed_all,[s])
        if !isnothing(prior) && hasproperty(prior,:dr)
            set_start_value(d,min(upper_bound(d),get(prior.dr,l.id,0.)))
            set_start_value(s,min(upper_bound(s),get(prior.shed,l.id,0.)))
        else
            set_start_value(d,0.);set_start_value(s,0.)
        end
    end
    zero_shedding || @constraint(m,sum(values(shed))<=10/c.base_power)
    dr,shed
end

function el_build(x,factors,events;emergency=false,relief=false,thermal_multiplier=1.,seed=nothing,
    solver=:madnlp,fixed_controller=false,fixed_base=false,normalization=false,reserve_start=false,
    restore=true,zero_shedding=false,zero_dr=false,ac_builder=DroopOPF._build_acopf_model,penalty_proxies=true,
    response_relaxation_cap=0.,droop_normalization=normalization,direct_relief=false)
    direct_relief && restore && error("Direct relief requires an exact physical model without restoration slacks")
    m=Model(solver==:ccopt ? CCOpt.Optimizer : solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer);set_silent(m)
    solver==:ccopt && DroopOPF.MathOptComplements.Bridges.add_all_bridges(m)
    parameters=Dict{Int,NamedTuple}()
    controller=isnothing(seed) ? x.study : seed.study
    if !fixed_controller
        for control in x.controls
            p=DroopOPF._joint_droop_policy(x.study.case,control);names=keys(p.ranges)
            initial=DroopSettings(controller.case.controls[control.control_id])
            parameters[control.control_id]=NamedTuple{names}(Tuple(DroopOPF._droop_design_variable(m,
                "shared_$(control.control_id)_$k",getfield(p.ranges,k),getfield(initial,k);normalize=droop_normalization) for k in names))
        end
    end
    blocks=Any[];artificial=VariableRef[];shed_all=VariableRef[];dr_all=VariableRef[];departure=Any[];response_errors=VariableRef[]
    allstates=isnothing(seed) ? Dict() : seed.states
    fixed_base && any(!haskey(allstates,(f,:base)) for f in factors) && error("A fixed base must match the exact demand factor")
    for (j,f) in enumerate(factors)
        study=DroopOPF._copy_study(controller;case=DroopOPF._feasibility_scaled_case(controller.case,f),contingencies=events)
        vars=Any[];ids=[:base;[c.id for c in events]];deltas=Dict{Symbol,VariableRef}();base_equipment=nothing
        for (k,(id,normal)) in enumerate(zip(ids,[study.case;[scenario_case(study.case,e) for e in events]]))
            prefix="f$(j)_s$(k)_";post=k>1
            c=el_case(normal;emergency=post && emergency,thermal_multiplier)
            prior=get(allstates,(f,id),nothing);prior_factor=f
            if isnothing(prior) && !isempty(allstates)
                keys_same=filter(key->key[2]==id,collect(keys(allstates)))
                if !isempty(keys_same)
                    key=keys_same[argmin([abs(key[1]-f) for key in keys_same])]
                    prior=allstates[key];prior_factor=key[1]
                end
            end
            if isnothing(prior) && !isempty(allstates)
                keys_base=filter(key->key[2]==:base,collect(keys(allstates)))
                if !isempty(keys_base)
                    key=keys_base[argmin([abs(key[1]-f) for key in keys_base])]
                    prior=allstates[key];prior_factor=key[1]
                    pg=copy(prior.state.pg);qg=copy(prior.state.qg)
                    lost=sum(pg[i] for (i,g) in enumerate(c.generators) if !g.available;init=0.)
                    alpha=DroopOPF._participation(study,c)
                    for (i,g) in enumerate(c.generators)
                        pg[i]=g.available ? clamp(pg[i]+alpha[i]*lost,g.p_min,g.p_max) : 0.
                        g.available || (qg[i]=0.)
                    end
                    prior=(;prior...,state=ACState(copy(prior.state.vm),copy(prior.state.va),pg,qg))
                end
            end
            priorstate=isnothing(prior) ? get(x.result.states,id,x.result.states[:base]) : prior.state
            if prior_factor!=f && !reserve_start && !(fixed_base && k==1)
                pg=[g.available ? clamp(priorstate.pg[i]*f/prior_factor,g.p_min,g.p_max) : 0. for (i,g) in enumerate(c.generators)]
                qg=[g.available ? priorstate.qg[i] : 0. for (i,g) in enumerate(c.generators)]
                priorstate=ACState(copy(priorstate.vm),copy(priorstate.va),pg,qg)
            end
            if reserve_start && !(fixed_base && k==1)
                cap=sum(g.p_max for g in c.generators if g.available)
                target=min(sum(l.p for l in c.loads)+.4,.999*cap)
                pg=[g.available ? target*g.p_max/cap : 0. for g in c.generators]
                qg=[g.available ? clamp(priorstate.qg[i],g.q_min,g.q_max) : 0. for (i,g) in enumerate(c.generators)]
                priorstate=ACState(copy(priorstate.vm),copy(priorstate.va),pg,qg)
            end
            oldt=isnothing(prior) ? get(x.result.tap_settings,id,x.result.tap_settings[:base]) : prior.taps
            oldb=isnothing(prior) ? get(x.result.shunt_settings,id,x.result.shunt_settings[:base]) : prior.banks
            if fixed_base && k==1
                # Base physics is independently replayed as data, avoiding
                # constant nonlinear equalities and a rank-deficient Jacobian.
                v=(;vm=priorstate.vm,va=priorstate.va,pg=priorstate.pg,qg=priorstate.qg,taps=oldt,shunts=oldb)
                base_equipment=v;push!(vars,priorstate)
                zeros=Dict(l.id=>0. for l in c.loads)
                push!(blocks,(;factor=f,id,study,normal,case=c,v,dr=zeros,shed=copy(zeros),artificial=VariableRef[],delta=nothing))
                continue
            end
            balance_kwargs=NamedTuple()
            if direct_relief
                dr,shed=el_relief_variables!(m,c,post,relief,zero_dr,zero_shedding,prefix,prior,dr_all,shed_all)
                rp=[sum((dr[l.id]+shed[l.id] for l in c.loads if l.bus_id==bus.id);init=0.) for bus in c.network.buses]
                rq=[sum((l.q/l.p*(dr[l.id]+shed[l.id]) for l in c.loads if l.bus_id==bus.id && l.p>0);init=0.) for bus in c.network.buses]
                balance_kwargs=(;load_relief=(;p=rp,q=rq))
            end
            tc=[TapControl(t.branch_id;lower=t.lower,upper=t.upper,nominal=t.nominal,
                initial=clamp(oldt[t.branch_id],t.lower,t.upper)) for t in DroopOPF._scenario_tap_controls(study,c)]
            sc=[ShuntControl(t.bank_id;lower=t.lower,upper=t.upper,nominal=t.nominal,
                initial=clamp(oldb[t.bank_id],t.lower,t.upper)) for t in study.shunt_controls]
            need_balance_slacks=restore || (post && !(zero_dr && zero_shedding) && !direct_relief)
            _,v=ac_builder(c;voltage_epsilon=1e-6,reactive_relative_epsilon=1e-6,
                reactive_epsilon=1e-6,silent=true,shared_model=m,scenario_prefix=prefix,set_objective=false,
                initial_state=priorstate,reactive_assignments=study.reactive_assignments,
                tap_controls=tc,shunt_controls=sc,normalize_controls=normalization,
                droop_parameter_variables=parameters,power_balance_slacks=need_balance_slacks,balance_kwargs...)
            push!(vars,v)
            if post
                delta,re=el_response!(m,study,c,vars[1],v,prefix,response_relaxation_cap,prior,f/prior_factor)
                append!(response_errors,re)
                isnothing(delta) || (deltas[id]=delta)
                DroopOPF._couple_equipment!(m,study.control_policy,base_equipment.taps,base_equipment.shunts,v)
            else
                base_equipment=v
            end
            if !direct_relief
                dr,shed=el_relief_variables!(m,c,post,relief,zero_dr,zero_shedding,prefix,prior,dr_all,shed_all)
            end
            idx=DroopOPF._bus_indices(c.network)
            state_art=VariableRef[]
            for (i,bus) in enumerate(c.network.buses)
                if need_balance_slacks && !(hasproperty(v,:eliminated_indices) && i in v.eliminated_indices)
                    if restore
                        ap=@variable(m,lower_bound=0.,base_name=prefix*"art_p_pos_$i")
                        an=@variable(m,lower_bound=0.,base_name=prefix*"art_p_neg_$i")
                        aq=@variable(m,lower_bound=0.,base_name=prefix*"art_q_pos_$i")
                        ar=@variable(m,lower_bound=0.,base_name=prefix*"art_q_neg_$i")
                        append!(artificial,[ap,an,aq,ar]);append!(state_art,[ap,an,aq,ar])
                        for a in (ap,an,aq,ar);set_start_value(a,0.);end
                    else
                        ap=an=aq=ar=0.
                    end
                    loads=filter(l->l.bus_id==bus.id,c.loads)
                    rp=sum((dr[l.id]+shed[l.id] for l in loads);init=0.)
                    rqpos=sum((max(l.q/l.p,0.)*(dr[l.id]+shed[l.id]) for l in loads if l.p>0);init=0.)
                    rqneg=sum((max(-l.q/l.p,0.)*(dr[l.id]+shed[l.id]) for l in loads if l.p>0);init=0.)
                    for (suffix,expression) in (("p_balance_pos",rp+ap),("p_balance_neg",an),("q_balance_pos",rqpos+aq),("q_balance_neg",rqneg+ar))
                        variable=variable_by_name(m,prefix*suffix*"[$i]")
                        # Empty/zero-coefficient relief expressions can be
                        # affine zero, especially the unused Q sign. Fix their
                        # nonnegative auxiliaries directly rather than imposing
                        # a zero equality at an active lower bound.
                        identically_zero=(expression isa Real || expression isa JuMP.GenericAffExpr) && iszero(expression)
                        if !restore && identically_zero
                            fix(variable,0.;force=true);set_start_value(variable,0.)
                        else
                            @constraint(m,variable==expression)
                            set_start_value(variable,JuMP.value(a->something(start_value(a),0.),expression))
                        end
                    end
                end
                post && emergency && penalty_proxies || continue
                normalbus=normal.network.buses[i]
                # Physical Vm bounds remain at +/-0.05 in el_case. Penalty
                # proxies have a looser finite ceiling to avoid three redundant
                # active bounds on (Vm, proxy) at the physical emergency cap.
                vl=@variable(m,lower_bound=0.,upper_bound=.1,base_name=prefix*"vlo_$i")
                vh=@variable(m,lower_bound=0.,upper_bound=.1,base_name=prefix*"vhi_$i")
                if v.vm[i] isa VariableRef
                    @constraint(m,v.vm[i]+vl>=normalbus.v_min);@constraint(m,v.vm[i]-vh<=normalbus.v_max)
                else
                    @NLconstraint(m,v.vm[i]+vl>=normalbus.v_min);@NLconstraint(m,v.vm[i]-vh<=normalbus.v_max)
                end
                push!(departure,vl/.05);push!(departure,vh/.05)
                set_start_value(vl,max(0.,normalbus.v_min-priorstate.vm[i]));set_start_value(vh,max(0.,priorstate.vm[i]-normalbus.v_max))
            end
            for b in normal.network.branches
                b.available || continue;lo,hi=x.angles[b.id];ii,jj=idx[b.from_bus],idx[b.to_bus]
                if v.va[ii] isa VariableRef && v.va[jj] isa VariableRef
                    @constraint(m,lo<=v.va[ii]-v.va[jj]<=hi)
                else
                    @NLconstraint(m,lo<=v.va[ii]-v.va[jj]<=hi)
                end
                post && emergency && penalty_proxies || continue
                tau=get(v.taps,b.id,b.tap_ratio);yff,yft,ytf,ytt=DroopOPF._branch_admittances(b)
                for (i,j,self,mutual,from) in ((ii,jj,yff*b.tap_ratio^2,yft*b.tap_ratio,true),(jj,ii,ytt,ytf*b.tap_ratio,false))
                    gs,bs,gm,bm=real(self),imag(self),real(mutual),imag(mutual)
                    if hasproperty(v,:terminal_powers)
                        p,q=v.terminal_powers[(b.id,from)]
                    else
                        scale=from ? @NLexpression(m,1/tau^2) : 1.
                        p=@NLexpression(m,v.vm[i]^2*gs*scale+v.vm[i]*v.vm[j]/tau*(gm*cos(v.va[i]-v.va[j])+bm*sin(v.va[i]-v.va[j])))
                        q=@NLexpression(m,-v.vm[i]^2*bs*scale+v.vm[i]*v.vm[j]/tau*(gm*sin(v.va[i]-v.va[j])-bm*cos(v.va[i]-v.va[j])))
                    end
                    allowance=post && emergency ? b.thermal_limit*(thermal_multiplier-1.) : 0.
                    s=@variable(m,lower_bound=0.,upper_bound=max(0.,2*allowance))
                    @NLconstraint(m,p^2+q^2<=(b.thermal_limit+s)^2)
                    push!(departure,s/b.thermal_limit);set_start_value(s,0.)
                end
            end
            push!(blocks,(;factor=f,id,study,normal,case=c,v,dr,shed,artificial=state_art,
                delta=post ? get(deltas,id,nothing) : nothing))
        end
    end
    set_optimizer_attribute(m,"tol",1e-8);set_optimizer_attribute(m,"bound_relax_factor",0.)
    set_optimizer_attribute(m,"max_iter",6000)
    if solver==:ipopt
        set_optimizer_attribute(m,"print_level",0);set_optimizer_attribute(m,"max_cpu_time",180.);set_optimizer_attribute(m,"mu_strategy","adaptive")
    else
        set_optimizer_attribute(m,"max_wall_time",180.);set_optimizer_attribute(m,"linear_solver",MadNLP.UmfpackSolver)
    end
    (;m,blocks,artificial,shed_all,dr_all,departure,response_errors,parameters,controller,factors,events,solver)
end

function el_extract(built)
    m=built.m;study=built.controller
    for (id,p) in built.parameters
        settings=DroopSettings((DroopOPF._droop_design_value(getfield(p,k)) for k in keys(p))...)
        study=with_droop_settings(study,id,settings)
    end
    states=Dict()
    for b in built.blocks
        state=ACState((Float64.(value.(getproperty(b.v,key))) for key in (:vm,:va,:pg,:qg))...)
        states[(b.factor,b.id)]=(;state,taps=Dict(i=>Float64(value(a)) for (i,a) in b.v.taps),
            banks=Dict(i=>Float64(value(a)) for (i,a) in b.v.shunts),
            dr=Dict(i=>Float64(value(a)) for (i,a) in b.dr),shed=Dict(i=>Float64(value(a)) for (i,a) in b.shed),
            delta=isnothing(b.delta) ? nothing : Float64(value(b.delta)))
    end
    (;study,states)
end

function el_save_point(folder,built,stage,record)
    has_values(built.m) || return nothing
    point=el_extract(built);write_study(joinpath(folder,"controller-$stage.json"),point.study)
    rows=Any[]
    for b in built.blocks
        s=point.states[(b.factor,b.id)]
        push!(rows,(;factor=b.factor,id=b.id,state=s.state,taps=s.taps,banks=s.banks,dr=s.dr,shed=s.shed,
            artificial_max_pu=maximum(value.(b.artificial);init=0.),delta=isnothing(b.delta) ? nothing : value(b.delta)))
    end
    fd_save(joinpath(folder,"point-$stage.json"),(;record,states=rows))
    point
end

function el_read_point(folder;stage=nothing)
    stages=JSON.parsefile(joinpath(folder,"stages.json"));isnothing(stage) && (stage=last(stages)["stage"])
    study=read_study(joinpath(folder,"controller-$stage.json"));raw=JSON.parsefile(joinpath(folder,"point-$stage.json"))
    states=Dict()
    for r in raw["states"]
        states[(Float64(r["factor"]),Symbol(r["id"]))]=(;state=a500_state(r["state"]),taps=a500_settings(r["taps"]),
            banks=a500_settings(r["banks"]),dr=a500_settings(r["dr"]),shed=a500_settings(r["shed"]),delta=get(r,"delta",nothing))
    end
    (;study,states)
end

function el_audit(folder)
    audit_script=joinpath(FD_ROOT,"examples/audit_s2_500bus_loadability.py")
    output=read(`python3 $audit_script $folder`,String)
    println("LOADABILITY AUDIT ",folder," ",output);flush(stdout)
    stage=last(JSON.parsefile(joinpath(folder,"stages.json")))["stage"]
    JSON.parsefile(joinpath(folder,"audit-$stage.json"))
end

function el_select_accepted(folder)
    stages=JSON.parsefile(joinpath(folder,"stages.json"))
    for row in reverse(stages)
        row["stage"]=="phase1" && continue
        row["native_success"] || continue
        stage=row["stage"];script=joinpath(FD_ROOT,"examples/audit_s2_500bus_loadability.py")
        read(`python3 $script $folder $stage`,String)
        ck=JSON.parsefile(joinpath(folder,"audit-$stage.json"))
        if ck["accepted"]
            fd_save(joinpath(folder,"selected_feasible_stage.json"),(;stage,
                note="Accepted physical point at the last converged stage; later-stage failure does not imply physical infeasibility"))
            return (;point=el_read_point(folder;stage),stage,audit=ck)
        end
    end
    nothing
end

function el_strict_continuation(;steps=(1.05,1.075,1.09,1.095,1.0975),seconds=180.)
    x=el_context();events=filter(e->e.id in (:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    initial=joinpath(EL_OUT,"strict/pilot-1.025")
    first=el_audit(initial);first["accepted"] || error("Strict pilot did not pass")
    seed=el_read_point(initial);rows=Any[(;factor=1.025,accepted=true,path=relpath(initial,EL_OUT))]
    for f in steps
        name="strict/continuation-$f"
        lane=el_solve(x,name,(f,),events;seed,seconds)
        audit=el_audit(lane.folder)
        if !audit["accepted"]
            warm=el_read_point(lane.folder)
            lane=el_solve(x,name*"-retry",(f,),events;seed=warm,solver=:ipopt,seconds)
            audit=el_audit(lane.folder)
        end
        push!(rows,(;factor=f,accepted=audit["accepted"],path=relpath(lane.folder,EL_OUT)))
        fd_save(joinpath(EL_OUT,"strict/continuation-summary.json"),(;rows,
            scope="Three critical connected outages only; not exhaustive security or a multi-demand design",full_n1_accepted=false))
        if audit["accepted"];seed=lane.point;else;break;end
    end
end

function el_solve(x,name,factors,events;emergency=false,relief=false,thermal_multiplier=1.,seed=nothing,
    solver=:madnlp,fixed_controller=false,fixed_base=false,normalization=false,seconds=180.,phase_only=false,
    separator=false,restore=true,reserve_start=false,feasibility_only=false,zero_shedding=false,zero_dr=false,
    ac_builder=DroopOPF._build_acopf_model,model_label="full-network",penalty_proxies=true,
    response_relaxation_cap=0.,response_objective=false,droop_normalization=normalization,
    optimizer_options=Dict{String,Any}())
    penalty_proxies || feasibility_only || error("Departure proxies may be omitted only for feasibility-only solves")
    response_relaxation_cap>0 && fixed_base && error("Response diagnostic currently requires a free preventive base")
    folder=joinpath(EL_OUT,name);mkpath(folder)
    write(joinpath(folder,"executed_adapter.jl"),EL_EXECUTED_SOURCE)
    initial_controller=isnothing(seed) ? x.study.case.controls : seed.study.case.controls
    fixed_base_reference=fixed_base ? [(;factor=f,state=seed.states[(f,:base)].state,
        taps=seed.states[(f,:base)].taps,banks=seed.states[(f,:base)].banks) for f in factors] : nothing
    fd_save(joinpath(folder,"contract.json"),(;name,factors,outages=[e.id for e in events],emergency,relief,
        thermal_multiplier,solver,fixed_controller,fixed_base,normalization,seconds,phase_only,separator,restore,reserve_start,feasibility_only,zero_shedding,zero_dr,
        initial_controller,fixed_base_reference,optimizer_options,
        run_source_sha256=EL_EXECUTED_SHA,model_label,penalty_proxies,response_relaxation_cap,response_objective,droop_normalization))
    built=el_build(x,factors,events;emergency,relief,thermal_multiplier,seed,solver,fixed_controller,fixed_base,normalization,reserve_start,restore,zero_shedding,zero_dr,ac_builder,penalty_proxies,response_relaxation_cap,droop_normalization)
    maps=[(;factor=b.factor,id=b.id,reduction=b.v.reduction) for b in built.blocks if hasproperty(b.v,:reduction)]
    isempty(maps) || fd_save(joinpath(folder,"network_reduction_maps.json"),maps)
    m=built.m;set_optimizer_attribute(m,solver==:ipopt ? "max_cpu_time" : "max_wall_time",seconds)
    if zero_shedding
        for v in built.shed_all;fix(v,0.;force=true);set_start_value(v,0.);end
    end
    if zero_dr
        for v in built.dr_all;fix(v,0.;force=true);set_start_value(v,0.);end
    end
    stages=Any[];point=seed;physical=!restore
    if !restore
        for v in built.artificial;fix(v,0.;force=true);set_start_value(v,0.);end
    end
    objectives=phase_only ? [:phase1] : feasibility_only ? [(restore ? [:phase1] : Symbol[]);:feasibility] : [(restore ? [:phase1] : Symbol[]);
        (relief && !zero_shedding ? [:shedding] : Symbol[]);(relief && !zero_dr ? [:dr] : Symbol[]);(emergency ? [:emergency] : Symbol[]);
        (separator ? Symbol[] : [:loss])]
    for stage in objectives
        objective=stage==:feasibility ? (response_objective ? sum(e^2 for e in built.response_errors) : 0.) : stage==:phase1 ? sum(built.artificial) : stage==:shedding ? sum(built.shed_all) :
            stage==:dr ? sum(built.dr_all) : stage==:emergency ? sum(built.departure) :
            sum(sum(b.v.pg)-sum(l.p for l in b.normal.loads) for b in built.blocks if b.id==:base)
        @objective(m,Min,objective)
        # Recopy the complete staged model, including changed bounds and the
        # current objective, into a fresh backend. Warm starts remain explicit.
        el_fresh_optimizer!(m,solver,seconds)
        for (key,val) in optimizer_options;set_optimizer_attribute(m,key,val);end
        println("LOADABILITY START ",name," ",stage);flush(stdout)
        timed=@timed optimize!(m)
        native_details=try
            raw=JuMP.unsafe_backend(m)
            if solver==:madnlp && hasproperty(raw,:solver) && !isnothing(raw.solver)
                s=raw.solver
                (;iterations=s.cnt.k,primal=s.inf_pr,dual=s.inf_du,complementarity=s.inf_compl,
                    barrier=s.mu,linear_solver_seconds=s.cnt.linear_solver_time)
            else
                nothing
            end
        catch
            nothing
        end
        success=termination_status(m) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.ALMOST_LOCALLY_SOLVED,JuMP.MOI.OPTIMAL)
        netmax=has_values(m) ? maximum((max(abs(value(a[i])-value(a[i+1])),abs(value(a[i+2])-value(a[i+3])))
            for b in built.blocks for a in (b.artificial,) for i in 1:4:length(a));init=0.) : nothing
        record=(;stage,status=string(termination_status(m)),native_success=success,elapsed_seconds=timed.time,
            objective=has_values(m) ? objective_value(m) : nothing,
            artificial_max_pu=has_values(m) ? maximum(value.(built.artificial);init=0.) : nothing,
            artificial_net_max_pu=netmax,
            num_variables=num_variables(m),num_constraints=num_constraints(m;count_variable_in_set_constraints=true),native_details)
        push!(stages,record);fd_save(joinpath(folder,"stages.json"),stages)
        println("LOADABILITY END ",name," ",stage," ",record);flush(stdout)
        if has_values(m)
            point=el_save_point(folder,built,stage,record)
            # Cache before changing the model: JuMP invalidates its result cache.
            starts=[(v,value(v)) for v in all_variables(m)]
            obj=objective_value(m);amax=maximum(value.(built.artificial);init=0.)
            if separator && success && (stage==:dr || (stage==:shedding && zero_dr))
                script=joinpath(FD_ROOT,"examples/audit_s2_500bus_loadability.py")
                read(`python3 $script $folder $(string(stage))`,String)
                ck=JSON.parsefile(joinpath(folder,"audit-$stage.json"))
                if ck["accepted"] && all(isempty(s["normal_voltage_departures"]) && isempty(s["normal_thermal_departures"]) for s in ck["states"])
                    # The true nonnegative emergency penalty already attains
                    # zero. Do not optimize barrier proxy floors further.
                    break
                end
            end
            for (v,val) in starts;isfinite(val) && set_start_value(v,val);end
            if stage==:phase1
                # Interior-point centrality can leave cancelling positive and
                # negative slacks. Only permit transition when their net
                # injection vanishes; all slacks are fixed exactly to zero next.
                min(amax,netmax)<=1e-6 || break
                for v in built.artificial;fix(v,0.;force=true);set_start_value(v,0.);end
                physical=true
                phase_only && break
            elseif !success
                break
            elseif !(stage in (:loss,:feasibility))
                if stage==:shedding && obj<1e-7
                    for v in built.shed_all;fix(v,0.;force=true);set_start_value(v,0.);end
                elseif stage==:dr && obj<1e-7
                    for v in built.dr_all;fix(v,0.;force=true);set_start_value(v,0.);end
                else
                    @constraint(m,objective<=max(0.,obj)+1e-7)
                end
            end
        else
            break
        end
    end
    final=last(stages)
    summary=(;name,factors,outages=[e.id for e in events],emergency,relief,thermal_multiplier,solver,
        phase1_zero=physical,final_stage=final.stage,native_success=final.native_success,
        independent_accepted=false,stages)
    fd_save(joinpath(folder,"summary.json"),summary)
    (;point,summary,folder)
end

function el_seed_result(x,point,f,events)
    study=DroopOPF._copy_study(point.study;case=DroopOPF._feasibility_scaled_case(point.study.case,f),contingencies=events)
    pairs=filter(p->p[1][1]==f,collect(point.states))
    states=Dict{Symbol,Union{Nothing,ACState{Float64}}}(key[2]=>s.state for (key,s) in pairs)
    taps=Dict(key[2]=>s.taps for (key,s) in pairs);banks=Dict(key[2]=>s.banks for (key,s) in pairs)
    result=SCOPFResult(states,Dict{Symbol,Float64}(),sum(states[:base].pg)-sum(l.p for l in study.case.loads),
        :LOCALLY_SOLVED,:FEASIBLE_POINT,study.mode,:smooth,1e-6,1e-6,1e-6,"loadability independently replayed seed",
        study.reactive_assignments,taps,banks,study.tap_controls,study.shunt_controls,study.control_policy)
    (;study,result)
end

function el_strict_scan(folder;max_rounds=4)
    x=el_context();point=el_read_point(folder);contract=JSON.parsefile(joinpath(folder,"contract.json"))
    f=only(contract["factors"]);audit=el_audit(folder);audit["accepted"] || error("Unaccepted master")
    events=eligible_contingencies(contingency_catalog(x.study.case));working=Set(Symbol.(contract["outages"]))
    rounds=Any[];selected_master=folder
    for round in 1:max_rounds
        pair=el_seed_result(x,point,f,events)
        scan=s2500_scan("emergency_loadability/strict/full-$f/round-$round",pair.study,pair.result,x.angles;solver=:madnlp)
        push!(rounds,(;round,accepted=scan.accepted,exhaustive=scan.exhaustive,evaluated=length(scan.rows),failed=scan.failed))
        fd_save(joinpath(EL_OUT,"strict/full-$f/summary.json"),(;factor=f,rounds,accepted=scan.accepted,
            selected_master=relpath(selected_master,EL_OUT),
            full_n1_accepted=false,scope="All 389 connected outages, one demand factor"))
        scan.accepted && return (;accepted=true,point,rounds)
        union!(working,scan.failed)
        chosen=filter(e->e.id in working,events)
        lane=el_solve(x,"strict/full-$f/round-$round/redesign",(f,),chosen;seed=point,feasibility_only=true,reserve_start=true)
        ck=el_audit(lane.folder)
        ck["accepted"] || return (;accepted=false,point=lane.point,rounds)
        point=lane.point;selected_master=lane.folder
    end
    (;accepted=false,point,rounds)
end

function el_multidemand(;thermal_multiplier=1.1,seconds=180.,solver=:ipopt,seed_directory=nothing)
    x=el_context();events=filter(e->e.id in (:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    primary=isnothing(seed_directory) ? joinpath(EL_OUT,"emergency/continuation-1.1") : seed_directory
    if isnothing(seed_directory) && (!isfile(joinpath(primary,"stages.json")) || !el_audit(primary)["accepted"])
        primary=joinpath(EL_OUT,"emergency/continuation-1.1-retry")
    end
    seed=el_read_point(primary);rows=Any[]
    for factors in ((1.,1.1),(.95,1.,1.1),(.9,.95,1.,1.05,1.1))
        name="multidemand/$(length(factors))-demand"
        lane=el_solve(x,name,factors,events;seed,seconds,emergency=true,relief=true,thermal_multiplier,solver)
        ck=el_audit(lane.folder)
        if !ck["accepted"]
            lane=el_solve(x,name*"-retry",factors,events;seed=lane.point,seconds,emergency=true,
                relief=true,thermal_multiplier,solver=solver==:ipopt ? :madnlp : :ipopt)
            ck=el_audit(lane.folder)
        end
        push!(rows,(;factors,accepted=ck["accepted"],path=relpath(lane.folder,EL_OUT)))
        fd_save(joinpath(EL_OUT,"multidemand/summary.json"),(;rows,
            shared_droop_parameters=102,connected_outages_checked_in_master=3,full_n1_accepted=false,
            exhaustive_connected_qualified=false))
        ck["accepted"] || break
        seed=lane.point
    end
end

function el_emergency_scan(point,factors;label="five-demand",max_failures=4,seconds=15.,reuse_master=true,
    master_witness=nothing,zero_shedding_only=false)
    x=el_context();events=eligible_contingencies(contingency_catalog(x.study.case))
    rows=Any[];failed=Symbol[]
    # Fixed-base certificates order generator capacity stress first; every event
    # still needs its own AC solve. No screening score is an acceptance test.
    ordered=sort(events;by=e->isempty(e.generator_ids) ? (1,Int(e.branch_ids[1])) :
        (0,-only(filter(g->g.id==e.generator_ids[1],x.study.case.generators)).p_max))
    for f in factors
        factor_rows=Any[]
        master_entry=nothing;master_audit=nothing
        if reuse_master
            shared=JSON.parsefile(joinpath(EL_OUT,"decomposition/summary.json"))
            candidates=filter(r->r["factor"]==f && r["accepted"],shared["rows"])
            if !isempty(candidates)
                master_entry=only(candidates);folder=joinpath(EL_OUT,master_entry["path"]);stage=master_entry["stage"]
                script=joinpath(FD_ROOT,"examples/audit_s2_500bus_loadability.py")
                read(`python3 $script $folder $stage`,String)
                master_audit=JSON.parsefile(joinpath(folder,"audit-$stage.json"))
                @assert master_audit["accepted"]
                source=read_study(joinpath(folder,"controller-$stage.json"))
                @assert DroopOPF._json_data(source.case.controls)==DroopOPF._json_data(point.study.case.controls)
            end
        end
        if !isnothing(master_witness)
            folder=master_witness.folder;stage=master_witness.stage
            master_entry=Dict("path"=>relpath(folder,EL_OUT),"stage"=>stage)
            script=joinpath(FD_ROOT,"examples/audit_s2_500bus_loadability.py")
            read(`python3 $script $folder $stage`,String)
            master_audit=JSON.parsefile(joinpath(folder,"audit-$stage.json"))
            @assert master_audit["accepted"]
            source=read_study(joinpath(folder,"controller-$stage.json"))
            @assert DroopOPF._json_data(source.case.controls)==DroopOPF._json_data(point.study.case.controls)
        end
        for event in ordered
            known=isnothing(master_audit) ? Any[] : filter(s->s["id"]==string(event.id),master_audit["states"])
            if !isempty(known) && haskey(point.states,(f,event.id))
                folder=joinpath(EL_OUT,master_entry["path"]);stage=master_entry["stage"]
                raw=JSON.parsefile(joinpath(folder,"point-$stage.json"))["states"]
                for sid in (:base,event.id)
                    s=point.states[(f,sid)];r=only(filter(r->r["factor"]==f && r["id"]==string(sid),raw))
                    @assert DroopOPF._json_data(s.state)==r["state"]
                    for (key,values) in (("taps",s.taps),("banks",s.banks),("dr",s.dr),("shed",s.shed))
                        @assert Dict(string(i)=>v for (i,v) in values)==r[key]
                    end
                end
                push!(factor_rows,(;event=event.id,accepted=true,path=master_entry["path"],reused_master_state=true,stage))
                fd_save(joinpath(EL_OUT,"coverage/$label/progress-$f.json"),(;factor=f,rows=factor_rows,failed,
                    exhaustive=length(factor_rows)==length(events)))
                continue
            end
            name="coverage/$label/demand-$f/$(event.id)"
            cached=nothing
            for suffix in ("","-retry")
                prior=joinpath(EL_OUT,name*suffix)
                isfile(joinpath(prior,"stages.json")) || continue
                selected=el_select_accepted(prior)
                isnothing(selected) && continue
                same=DroopOPF._json_data(selected.point.study.case.controls)==DroopOPF._json_data(point.study.case.controls)
                a=selected.point.states[(f,:base)];b=point.states[(f,:base)]
                same &= DroopOPF._json_data(a.state)==DroopOPF._json_data(b.state) && a.taps==b.taps && a.banks==b.banks
                if same
                    cached=(;event=event.id,accepted=true,path=relpath(prior,EL_OUT),stage=selected.stage,reused_checkpoint=true)
                    break
                end
            end
            if !isnothing(cached)
                push!(factor_rows,cached)
                fd_save(joinpath(EL_OUT,"coverage/$label/progress-$f.json"),(;factor=f,rows=factor_rows,failed,
                    exhaustive=length(factor_rows)==length(events)))
                continue
            end
            lane=el_solve(x,name,(f,),[event];seed=point,emergency=true,relief=true,thermal_multiplier=1.1,
                fixed_controller=true,fixed_base=true,restore=false,separator=true,zero_shedding=true,seconds)
            ck=el_audit(lane.folder)
            selected=el_select_accepted(lane.folder)
            if !isnothing(selected)
                ck=selected.audit
            end
            if !ck["accepted"]
                lane=el_solve(x,name*"-retry",(f,),[event];seed=lane.point,emergency=true,relief=true,
                    thermal_multiplier=1.1,fixed_controller=true,fixed_base=true,separator=true,seconds=45.,
                    zero_shedding=zero_shedding_only)
                ck=el_audit(lane.folder)
                selected=el_select_accepted(lane.folder)
                isnothing(selected) || (ck=selected.audit)
            end
            push!(factor_rows,(;event=event.id,accepted=ck["accepted"],path=relpath(lane.folder,EL_OUT),
                stage=isnothing(selected) ? string(lane.summary.final_stage) : selected.stage))
            ck["accepted"] || push!(failed,event.id)
            length(factor_rows)%25==0 && (println("EMERGENCY SCAN ",f," ",length(factor_rows),"/389 failed=",length(failed));flush(stdout))
            fd_save(joinpath(EL_OUT,"coverage/$label/progress-$f.json"),(;factor=f,rows=factor_rows,failed,
                exhaustive=length(factor_rows)==length(events)))
            length(failed)>=max_failures && break
        end
        push!(rows,(;factor=f,rows=factor_rows,exhaustive=length(factor_rows)==length(events)))
        length(failed)>=max_failures && break
    end
    accepted=length(rows)==length(factors) && isempty(failed) && all(r.exhaustive for r in rows)
    fd_save(joinpath(EL_OUT,"coverage/$label/summary.json"),(;accepted,rows,failed,
        controller_sha256=DroopOPF._feasibility_case_hash(point.study.case),
        full_n1_accepted=false,scope="389 connected outages per demand; shared fixed controller and fixed base per demand"))
    (;accepted,rows,failed)
end

function el_emergency_continuation(;steps=(1.1,1.105,1.11,1.115,1.12),seconds=180.)
    x=el_context();events=filter(e->e.id in (:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    previous=JSON.parsefile(joinpath(EL_OUT,"strict/continuation-summary.json"))["rows"]
    good=filter(r->r["accepted"],previous);seed=el_read_point(joinpath(EL_OUT,last(good)["path"]))
    rows=Any[]
    for f in steps
        name="emergency/continuation-$f"
        lane=el_solve(x,name,(f,),events;seed,seconds,emergency=true,relief=true,thermal_multiplier=1.1,reserve_start=true)
        audit=el_audit(lane.folder)
        if !audit["accepted"]
            warm=el_read_point(lane.folder)
            lane=el_solve(x,name*"-retry",(f,),events;seed=warm,solver=:ipopt,seconds,
                emergency=true,relief=true,thermal_multiplier=1.1)
            audit=el_audit(lane.folder)
        end
        push!(rows,(;factor=f,accepted=audit["accepted"],path=relpath(lane.folder,EL_OUT)))
        fd_save(joinpath(EL_OUT,"emergency/continuation-summary.json"),(;rows,
            scope="Three critical connected outages only; not exhaustive security or a multi-demand design",full_n1_accepted=false))
        if audit["accepted"];seed=lane.point;else;break;end
    end
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)>=1 || error("Specify protocol or strict-pilot")
    if ARGS[1]=="protocol"
        el_protocol(ARGS[2])
    elseif ARGS[1]=="strict-pilot"
        x=el_context();events=filter(e->e.id in (:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
        el_solve(x,"strict/pilot-1.025",(1.025,),events)
    elseif ARGS[1]=="strict-continuation"
        el_strict_continuation()
    elseif ARGS[1]=="emergency-continuation"
        el_emergency_continuation()
    else
        error("Unknown action")
    end
end
