include("s1_arpae14_slope_sensitivity.jl")
const SLOPE_MATRIX_OUT=joinpath(GATED_OUT,"slope_matrix_none")
const SLOPE_MATRIX_RATIOS=(0.5,0.75,1.0,1.25,1.5,2.0)
const SLOPE_MATRIX_SOLVERS=(:ipopt,:madnlp,:ccopt)
const SLOPE_MATRIX_STARTS=(:anchor,)
const SLOPE_MATRIX_FACTORS=(0.9,1.0,1.1)
const SLOPE_MATRIX_EMPTY=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])

function slope_matrix_case(base,anchor,ratios)
    idx=DroopOPF._bus_indices(base.network);controls=copy(base.controls)
    for (ci,d) in enumerate(base.controls)
        ratio=get(ratios,ci,1.0);slope=d.slope*ratio
        a=only(filter(x->x.control_id==ci,base.attachments))
        gi=findfirst(g->g.id==a.generator_id,base.generators);q=anchor.qg[gi]
        vm=anchor.vm[idx[a.location.bus_id]]
        lo=d.schedule.v_ref-d.schedule.v_db_low;hi=d.schedule.v_db_high-d.schedule.v_ref
        offset=q>1e-9 ? lo : q < -1e-9 ? -hi : 0.0
        vref=vm+slope*q+offset
        sched=VoltageSchedule(vref;v_db_low=vref-lo,v_db_high=vref+hi,unit=d.schedule.unit)
        controls[ci]=VoltVarDroop(sched,slope,d.q_at_deadband,d.capability)
    end
    Case(base.id*"-sensitivity";base_power=base.base_power,base_frequency=base.base_frequency,
        network=base.network,generators=base.generators,loads=base.loads,controls,attachments=base.attachments)
end

function slope_profiles(base)
    profiles=Tuple{String,Dict{Int,Float64}}[]
    for ratio in SLOPE_MATRIX_RATIOS
        push!(profiles,("all_$(ratio)",Dict(i=>ratio for i in eachindex(base.controls))))
    end
    for ci in eachindex(base.controls),ratio in SLOPE_MATRIX_RATIOS
        ratio==1.0 && continue
        gid=only(filter(a->a.control_id==ci,base.attachments)).generator_id
        push!(profiles,("g$(gid)_$(ratio)",Dict(ci=>ratio)))
    end
    profiles
end

function run_slope_matrix(out=SLOPE_MATRIX_OUT)
    mkpath(out);source,anchor,angles,candidates=gated_inputs();rows=Any[]
    for variant in ("no_deadband","with_deadband")
        base=candidates[variant]
        for (profile,ratios) in slope_profiles(base)
            c=slope_matrix_case(base,anchor,ratios)
            anchor_check=check_feasibility(FeasibilityProblem(c;angle_limits=angles);witnesses=[FeasibilityWitness(anchor)],solve_missing=false)
            anchor_check.status==:feasible || error("$variant/$profile source anchor failed: $(anchor_check.status)")
            slope_tag=Dict(string(a.generator_id)=>4*get(ratios,a.control_id,1.) for a in base.attachments)
            write(joinpath(out,"$variant-$profile-anchor.json"),JSON.json(Dict("status"=>string(anchor_check.status),"slopes_percent_full_q_span"=>slope_tag);pretty=true))
            for factor in SLOPE_MATRIX_FACTORS,mode in SLOPE_MATRIX_STARTS,solver in SLOPE_MATRIX_SOLVERS
                name="$(variant)-$(profile)-$(factor)-$(mode)-$(solver)"
                diag=joinpath(out,name*"-diagnostics.json")
                if isfile(diag)
                    push!(rows,JSON.parsefile(diag));continue
                end
                scaled=DroopOPF._feasibility_scaled_case(c,factor)
                start=a14_start(scaled,anchor,mode)
                row=gated_cell(out,name,scaled,start,solver,SLOPE_MATRIX_EMPTY,angles,anchor,c;
                    tags=Dict("variant"=>variant,"factor"=>factor,"family"=>"fixed","start"=>string(mode),
                        "solver"=>string(solver),"slope_profile"=>profile,"slopes_percent_full_q_span"=>slope_tag))
                push!(rows,row)
                if length(rows)%30==0
                    write(joinpath(out,"progress_summary.json"),JSON.json(rows;pretty=true))
                end
            end
        end
    end
    write(joinpath(out,"summary.json"),JSON.json(rows;pretty=true))
    println("SLOPE MATRIX COMPLETE ",length(rows));flush(stdout)
end

function choose_and_run_mixed(out=SLOPE_MATRIX_OUT)
    source,anchor,angles,candidates=gated_inputs();rows=JSON.parsefile(joinpath(out,"summary.json"));selected=Dict{String,Dict{Int,Float64}}()
    for variant in ("no_deadband","with_deadband")
        base=candidates[variant];mixed=Dict{Int,Float64}()
        for ci in eachindex(base.controls)
            gid=only(filter(a->a.control_id==ci,base.attachments)).generator_id
            choices=[]
            for ratio in SLOPE_MATRIX_RATIOS
                ratio==1.0 && continue
                profile="g$(gid)_$(ratio)"
                cell=[r for r in rows if get(r,"tags",Dict())["variant"]==variant &&
                    get(r,"tags",Dict())["slope_profile"]==profile]
                verified=count(r->get(r,"point_pass",false),cell)
                objs=[r["objective"] for r in cell if get(r,"point_pass",false) && get(r,"objective",nothing)!==nothing]
                meanobj=isempty(objs) ? Inf : sum(objs)/length(objs)
                push!(choices,(ratio,verified,meanobj))
            end
            best=sort(choices;by=x->(-x[2],x[3],abs(x[1]-1.0)))[1]
            mixed[ci]=best[1]
            println("SELECT ",variant," G",gid," ratio=",best[1]," verified=",best[2]," mean_obj=",best[3]);flush(stdout)
        end
        selected[variant]=mixed
    end
    write(joinpath(out,"selected_mixed_slopes.json"),JSON.json(Dict(v=>Dict(string(k)=>r for (k,r) in x) for (v,x) in selected);pretty=true))
    mixedrows=Any[]
    for variant in ("no_deadband","with_deadband")
        base=candidates[variant];ratios=selected[variant];c=slope_matrix_case(base,anchor,ratios)
        check=check_feasibility(FeasibilityProblem(c;angle_limits=angles);witnesses=[FeasibilityWitness(anchor)],solve_missing=false)
        check.status==:feasible || error("mixed $variant source anchor failed")
        slope_tag=Dict(string(a.generator_id)=>4*ratios[a.control_id] for a in base.attachments)
        for factor in SLOPE_MATRIX_FACTORS,mode in SLOPE_MATRIX_STARTS,solver in SLOPE_MATRIX_SOLVERS
            name="$(variant)-mixed-$(factor)-$(mode)-$(solver)";diag=joinpath(out,name*"-diagnostics.json")
            if isfile(diag);push!(mixedrows,JSON.parsefile(diag));continue;end
            scaled=DroopOPF._feasibility_scaled_case(c,factor);start=a14_start(scaled,anchor,mode)
            row=gated_cell(out,name,scaled,start,solver,SLOPE_MATRIX_EMPTY,angles,anchor,c;
                tags=Dict("variant"=>variant,"factor"=>factor,"family"=>"fixed","start"=>string(mode),
                    "solver"=>string(solver),"slope_profile"=>"mixed-selected","slopes_percent_full_q_span"=>slope_tag))
            push!(mixedrows,row)
        end
    end
    write(joinpath(out,"mixed_summary.json"),JSON.json(mixedrows;pretty=true))
end

if abspath(PROGRAM_FILE)==@__FILE__
    run_slope_matrix()
    choose_and_run_mixed()
end
