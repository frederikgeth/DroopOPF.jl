# Compact hard-physics models between small demand steps; no artificial
# restoration variables survive into physical feasibility/penalty stages.
include("s2_arpae500_loadability.jl")

function el_stage_regression()
    rows=Any[]
    for fresh in (false,true)
        m=Model(MadNLP.Optimizer);set_silent(m)
        @variable(m,0<=d<=1,start=.1);@variable(m,0<=s<=10,start=.4)
        @variable(m,ap>=0,start=0);@variable(m,an>=0,start=0)
        @variable(m,v>=.5,start=1.)
        @NLconstraint(m,d+s+ap-an==.5);@NLconstraint(m,v^2==1.)
        @objective(m,Min,ap+an);el_fresh_optimizer!(m,:madnlp,10.);optimize!(m)
        starts=[(a,value(a)) for a in all_variables(m)]
        for(a,b) in starts;set_start_value(a,b);end
        fix(ap,0.;force=true);fix(an,0.;force=true)
        @objective(m,Min,s)
        fresh && el_fresh_optimizer!(m,:madnlp,10.)
        optimize!(m)
        record=(;fresh,status=string(termination_status(m)),dr=value(d),shedding=value(s),
            balance_error=abs(value(d)+value(s)-.5),correct_minimum=value(s)<1e-6 && abs(value(d)-.5)<1e-6)
        push!(rows,record)
        fresh && !record.correct_minimum && error("Fresh-backend staged objective regression failed")
    end
    fd_save(joinpath(EL_OUT,"staged_objective_regression.json"),(;rows))
end

function el_compact_continuation()
    el_stage_regression()
    x=el_context();events=filter(e->e.id in (:branch_219,:generator_14,:generator_60),eligible_contingencies(contingency_catalog(x.study.case)))
    initial=joinpath(EL_OUT,"emergency/zero-shedding-1.1")
    seed=el_read_point(initial;stage="dr");controller=seed.study;combined=copy(seed.states)
    rows=Any[(;factor=1.1,path=relpath(initial,EL_OUT),stage="dr",accepted=true)]
    for f in (1.075,1.05,1.025,1.,.975,.95,.925,.9)
        # An earlier accepted point can warm the physical model even if its
        # resource allocation was not minimal. The controller must match exactly.
        for suffix in ("-retry","")
            old=joinpath(EL_OUT,"decomposition/demand-$f"*suffix)
            if isfile(joinpath(old,"selected_feasible_stage.json"))
                stage=JSON.parsefile(joinpath(old,"selected_feasible_stage.json"))["stage"]
                p=el_read_point(old;stage)
                if DroopOPF._json_data(p.study.case.controls)==DroopOPF._json_data(controller.case.controls)
                    merge!(combined,p.states);break
                end
            end
        end
        seed=(;study=controller,states=combined)
        lane=el_solve(x,"compact/demand-$f/zero-relief",(f,),events;seed,fixed_controller=true,
            emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_dr=true,zero_shedding=true,
            feasibility_only=true,solver=:ipopt,seconds=60.)
        selected=el_select_accepted(lane.folder)
        if !isnothing(selected)
            lane=el_solve(x,"compact/demand-$f/emergency-penalty",(f,),events;seed=selected.point,fixed_controller=true,
                emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_dr=true,zero_shedding=true,
                separator=true,solver=:madnlp,seconds=60.)
            penalty=el_select_accepted(lane.folder)
            if !isnothing(penalty);selected=penalty;else;lane=(;folder=joinpath(EL_OUT,"compact/demand-$f/zero-relief"));end
        else
            lane=el_solve(x,"compact/demand-$f/dr-recovery",(f,),events;seed=lane.point,fixed_controller=true,
                emergency=true,relief=true,thermal_multiplier=1.1,restore=false,zero_shedding=true,
                separator=true,solver=:madnlp,seconds=90.)
            selected=el_select_accepted(lane.folder)
        end
        if isnothing(selected)
            lane=el_solve(x,"compact/demand-$f/last-resort",(f,),events;seed=lane.point,fixed_controller=true,
                emergency=true,relief=true,thermal_multiplier=1.1,restore=false,
                separator=true,solver=:ipopt,seconds=90.)
            selected=el_select_accepted(lane.folder)
        end
        push!(rows,(;factor=f,path=relpath(lane.folder,EL_OUT),stage=isnothing(selected) ? nothing : selected.stage,
            accepted=!isnothing(selected)))
        required=Set((.9,.95,1.,1.05,1.1))
        training=filter(r->r.factor in required,rows)
        accepted=length(training)==5 && all(r.accepted for r in training)
        fd_save(joinpath(EL_OUT,"decomposition/summary.json"),(;rows,accepted,
            controller_fixed_across_demands=true,nominal_controller_reused=false,
            shared_controller_training_objective="110%-designed controller verified by demand decomposition; no joint multi-demand optimum claim",
            critical_outages=[e.id for e in events],exhaustive_connected_qualified=false,full_n1_accepted=false))
        isnothing(selected) && break
        merge!(combined,selected.point.states)
    end
    write_study(joinpath(EL_OUT,"decomposition/shared-controller.json"),controller)
    fd_save(joinpath(EL_OUT,"decomposition/shared-states.json"),
        [(;factor=f,id,state=s.state,taps=s.taps,banks=s.banks,dr=s.dr,shed=s.shed) for ((f,id),s) in combined])
    training=filter(r->r.factor in Set((.9,.95,1.,1.05,1.1)),rows)
    if length(training)==5 && all(r.accepted for r in training)
        el_emergency_scan((;study=controller,states=combined),(1.1,1.05,1.,.95,.9);label="compact-five-demand")
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && el_compact_continuation()
