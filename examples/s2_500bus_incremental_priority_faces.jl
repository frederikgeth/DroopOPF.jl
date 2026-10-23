# Hard zero-violation faces and feasibility-first DR-target recovery.
include("s2_500bus_incremental_shared.jl")
const RF_SOURCE=read(@__FILE__,String)
function rf_normal_seed()
    folder=joinpath(RX_OUT,"joint-ipopt-3d-cap-priorities-emergency-p1")
    audit=JSON.parsefile(joinpath(folder,"audit-emergency.json"));@assert audit["accepted"]
    @assert all(s["max_normal_loading_ratio"]<=1. && isempty(s["normal_voltage_departures"]) for s in audit["states"])
    seed=el_read_point(folder;stage="emergency")
    for(key,s) in seed.states
        seed.states[key]=(;s...,dr=Dict(k=>0. for k in keys(s.dr)),shed=Dict(k=>0. for k in keys(s.shed)))
    end
    seed
end
function rf_chain(label,factors,seed,events;solver,emergency=false,zero_shedding=true,zero_dr=true,
    objectives=(:feasibility,:loss),initial_budgets=Dict{Symbol,Float64}())
    rows=Any[];budgets=copy(initial_budgets);selected=nothing;complete=true
    for stage in objectives
        good=nothing;anchor=seed
        for profile in 1:2
            run=fm_attempt("$label-$stage-p$profile",stage,factors,seed,events;solver,zero_shedding,zero_dr,emergency,
                budgets,retry=true,seconds=length(factors)>1 ? 240. : 180.,optimizer_options=rx_options(solver,profile),
                output_root=RX_OUT,direct_relief=true,implied_q_bounds=true,objective_scale=stage in (:dr,:shedding,:loss) ? 100. : 1.,
                check_start=profile==1,native_call_limit=64)
            write(joinpath(run.folder,"executed_priority_face_driver.jl"),RF_SOURCE);push!(rows,run.summary)
            if run.accepted;good=run;break;end
            audit=JSON.parsefile(joinpath(run.folder,"audit-$stage.json"))
            seed=audit["physical_valid"] && !isnothing(run.point) ? run.point : anchor
        end
        if isnothing(good);complete=false;seed=anchor;break;end
        seed=good.point;selected=(;path=relpath(good.folder,S2500_OUT),stage)
        fd_save(joinpath(RX_OUT,"progress-$label.json"),(;rows,selected))
    end
    result=(;label,factors,solver,emergency,zero_shedding,zero_dr,rows,selected,complete,
        loss_objective_completed=complete && :loss in objectives,full_n1_accepted=false)
    fd_save(joinpath(RX_OUT,"summary-$label.json"),result)
    (;point=seed,result)
end
function rf_scan(point,selected,factors,label)
    events=eligible_contingencies(contingency_catalog(el_context().study.case))
    ordered=sort(events;by=e->isempty(e.generator_ids) ? (1,Int(e.branch_ids[1])) :
        (0,-only(filter(g->g.id==e.generator_ids[1],point.study.case.generators)).p_max))
    rows=Any[];failed=Symbol[];root=joinpath(EL_OUT,"coverage",label)
    master=joinpath(S2500_OUT,selected.path);stage=string(selected.stage)
    for f in factors
        entries=Any[]
        for event in ordered
            if haskey(point.states,(f,event.id))
                push!(entries,(;event=event.id,accepted=true,path=relpath(master,EL_OUT),stage,reused_master_state=true))
            else
                name="coverage/$label/demand-$f/$(event.id)";chosen=nothing;last_run=nothing
                for profile in 1:2
                    solver=profile==1 ? :madnlp : :ipopt
                    lane=el_solve(el_context(),name*(profile==1 ? "" : "-retry"),(f,),[event];seed=point,solver,
                        emergency=false,relief=false,thermal_multiplier=1.,zero_shedding=true,zero_dr=true,
                        fixed_controller=true,fixed_base=true,restore=false,separator=true,feasibility_only=true,
                        penalty_proxies=false,ac_builder=fm_smooth_cap_ac,model_label="Normal zero-relief original-rating reduced feasibility",
                        seconds=profile==1 ? 15. : 45.,optimizer_options=rx_options(solver,2))
                    last_run=lane;el_audit(lane.folder);chosen=el_select_accepted(lane.folder)
                    !isnothing(chosen) && break
                end
                accepted=!isnothing(chosen)
                push!(entries,(;event=event.id,accepted,path=relpath(last_run.folder,EL_OUT),
                    stage=accepted ? chosen.stage : string(last_run.summary.final_stage)))
                accepted || push!(failed,event.id)
            end
            fd_save(joinpath(root,"progress-$f.json"),(;factor=f,rows=entries,failed,exhaustive=length(entries)==389))
            length(entries)%25==0 && (println("NORMAL SCAN ",f," ",length(entries),"/389 failed=",length(failed));flush(stdout))
            length(failed)>=4 && break
        end
        push!(rows,(;factor=f,rows=entries,exhaustive=length(entries)==389));length(failed)>=4 && break
    end
    accepted=length(rows)==length(factors) && isempty(failed) && all(r.exhaustive for r in rows)
    fd_save(joinpath(root,"summary.json"),(;accepted,rows,failed,full_n1_accepted=false,scope="Normal limits; zero DR/shedding; same controller and per-demand preventive base"))
    python=get(ENV,"NR_PYTHON","/tmp/s214-plot-env/bin/python");script=joinpath(FD_ROOT,"examples/audit_s2_500bus_finish_coverage.py")
    fs=join(string.(factors),",")
    println(read(`$python $script $label $(selected.path) $stage $fs zero $RX_OUT`,String));flush(stdout)
    (;accepted,failed)
end
function rf_normal(solver)
    events=rx_events(FM_EVENTS);seed=rf_normal_seed();rounds=Any[]
    for round in 1:2
        run=rf_chain("normal-zero-$solver-3d-r$round",(.9,.95,1.),seed,events;solver)
        scan=run.result.loss_objective_completed ? rf_scan(run.point,run.result.selected,(.9,.95,1.),"incremental-normal-$solver-r$round") : nothing
        push!(rounds,(;round,master=run.result,coverage=scan))
        fd_save(joinpath(RX_OUT,"summary-normal-zero-$solver.json"),(;rounds,full_n1_accepted=false))
        (isnothing(scan) || scan.accepted || round==2) && break
        ids=unique([getproperty.(events,:id);scan.failed]);events=rx_events(ids);seed=run.point
    end
end
function rf_105_target()
    seed=el_read_point(joinpath(RX_OUT,"expanded-105-r1-dr-p1");stage="dr")
    events=rx_events([FM_EVENTS...;RX_EXTRA...])
    run=rf_chain("expanded-105-dr-target",(1.05,),seed,events;solver=:ipopt,emergency=true,zero_dr=false,
        objectives=(:feasibility,),initial_budgets=Dict{Symbol,Float64}(:dr=>.065))
    if run.result.complete
        # Release the numerical target for the original DR optimization objective.
        tail=rx_pipeline("expanded-105-feasibility-first",(1.05,),run.point,events;
            zero_shedding=true,stages=(:dr,:emergency,:loss),implied_q_bounds=true)
        tail.result.loss_objective_completed && rx_scan(tail.point,tail.result.selected,(1.05,),"incremental-105-feasibility-first";zero_shedding=true)
    end
end
function rf_run(mode)
    rx_protocol()
    mode=="105" ? rf_105_target() : rf_normal(Symbol(mode))
end
abspath(PROGRAM_FILE)==(@__FILE__) && rf_run(only(ARGS))
