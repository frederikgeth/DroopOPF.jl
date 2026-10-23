# Campaign orchestration; loaded by p2_mixed_avr_500.jl after its helpers.
function mixed_protocol(folder)
    mix_save(joinpath(folder,"protocol.json"),(;scope="P2 exact-S2 500-bus data with mixed AVR/droop and apparent circles",
        selection="nearest 30% of online positive-Pmax generator count, half upward; descending Pmax then ascending ID",
        ratings="explicit exploratory S=Pmax/0.95 for online units; not verified nameplate",
        avr="fixed nominal S2 generator-bus targets; separate preventive scheduled sensitivity +/-0.02 pu within normal bounds, <=0.01 pu/hour",
        droop="36 shared curves, original calibrated 2-8% full-Q-span slopes and reference +/-0.02 pu; zero deadband",
        equipment="131 corrective taps and 11 continuous banks with S2 absolute bounds; no extra movement cap; settled response, no validated delays or discrete switching",
        profile=[.9,1.,1.05,1.,.9],duration_hours=ones(5),ramps="25% active capability range/hour, preventive dispatch only; no initial/terminal boundary",
        response="exact S2 stored Pmax-proportional equality, not inverter frequency dynamics",
        emergency="S2 outage V +/-0.05 pu and RateA*1.1; DR <=1%/positive load; shed <=10 MW/outage; combined <=10%/load, proportional Q relief; base full load/normal bounds",
        resource_objective="joint masters: local lexicographic shed, DR, loss; frozen-base scans: feasibility only",
        coverage="389 eligible connected outages; structural exclusions reported separately; rational active-only necessary exclusions never predict safety",
        computational_budget="five optimized outage states per frozen-base batch; two-outage joint pilot, at most 15 states; no monolithic 1950-state campaign",
        original_s2="paused and unchanged",p2="not closed by this campaign",inverter_models="GFL/GFM deferred to P3"))
end
function mixed_equipment_starts(periods)
    [(;taps=p.tap_settings[:base],shunts=p.shunt_settings[:base]) for p in periods]
end
function mixed_fixed_reference(x,folder,names)
    factors=[.9,1.,1.05,1.,.9]
    parents=[read_multi_period_security(joinpath(folder,name,"result.json")) for name in names]
    periods=[p.periods[1] for p in parents]
    ramps=Dict(g.id=>(.25*(g.p_max-g.p_min),.25*(g.p_max-g.p_min)) for g in x.setup.case.generators if g.available)
    energy=sum(p.objective_mwh for p in parents)
    solution=MultiPeriodSecurityResult(periods,Dict{Int,DroopSettings{Float64}}(),DroopControl[],
        [Dict{Symbol,NamedTuple}() for _ in 1:5],energy,:COMPOSED_REFERENCE,:FEASIBLE_POINT,ones(5),ramps,x.angles,
        :s2_proportional,true,[Dict{Int,Float64}() for _ in 1:5],Dict{Int,Tuple{Float64,Float64}}(),.01,
        NamedTuple[(;name=:composition,status=:NOT_JOINTLY_OPTIMIZED,objective=energy)])
    dir=joinpath(folder,"fixed-reference");mkpath(dir);write_multi_period_security(joinpath(dir,"result.json"),solution)
    rows=Any[];ramp=0.
    for (t,name) in enumerate(names)
        source=joinpath(folder,name)
        mix_save(joinpath(dir,"period-$t.json"),JSON.parsefile(joinpath(source,"period-1.json")))
        audit=JSON.parsefile(joinpath(source,"audit.json"));python=JSON.parsefile(joinpath(source,"python-audit.json"))
        push!(rows,(;period=t,factor=factors[t],source=name,native_status=parents[t].termination_status,
            valid=audit["valid"]&&python["valid"],source_sha256=bytes2hex(sha256(read(joinpath(source,"result.json"))))))
        t==1&&continue
        for (i,g) in enumerate(x.setup.case.generators)
            g.available||continue
            d=periods[t].states[:base].pg[i]-periods[t-1].states[:base].pg[i];up,down=ramps[g.id]
            ramp=max(ramp,d-up,-d-down)
        end
    end
    assessment=(;valid=all(r.valid for r in rows)&&ramp<=1e-6,joint_optimizer_converged=false,
        kind="assembled independently optimized fixed-curve periods with verified temporal ramps",rows,
        ramp_violation=ramp,objective_mwh=energy)
    mix_save(joinpath(dir,"assessment.json"),assessment)
    (;solution,assessment)
end
function mixed_catalogue_scan(x,folder,solution,candidate;seconds=5.,scan_name="scan-$candidate")
    factors=[.9,1.,1.05,1.,.9];c=x.setup.case
    for (id,s) in solution.droops;c=with_droop_settings(Study(c),id,s).case;end
    a=DroopOPF._settings_assignments(c,x.setup.assignments,solution.droops)
    run(`python3 -B $(joinpath(@__DIR__,"mixed_avr_capacity_screen.py")) $folder $candidate`)
    screen=JSON.parsefile(joinpath(folder,candidate*"-capacity-screen.json"))
    proofs=Set(Symbol(r["event"]) for r in screen["rows"] if r["certified_infeasible"])
    opts=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8)
    eq=mixed_equipment_starts(solution.periods);rows=Any[]
    for (k,e) in enumerate(x.events)
        id=e.contingency.id;nproof=count(r->Symbol(r["event"])==id&&r["certified_infeasible"],screen["rows"])
        if nproof==5
            push!(rows,(;event=id,accepted=false,route="rational necessary active-only exclusion of fixed dispatch",path=nothing,
                certified_periods=5,numerical_failure=false))
        else
            studies=mix_studies(x,factors,[e];case=c,assignments=a)
            starts=mix_response_starts(x,solution,c,[e],factors);path=joinpath(folder,scan_name,string(id))
            attempt=mix_attempt(x,path,factors,[e];studies,starts,fixed_bases=solution.periods,
                initial_equipment=eq,solver_options=opts,seconds)
            push!(rows,(;event=id,accepted=attempt.summary.accepted,route="native exact AC solve plus Julia/Python replay",path,
                certified_periods=nproof,numerical_failure=!attempt.summary.accepted))
        end
        mix_save(joinpath(folder,scan_name,"summary.json"),(;candidate,rows,complete=k==length(x.events),
            accepted=k==length(x.events)&&all(r.accepted for r in rows),native_passed=count(r->r.accepted,rows),
            certified_excluded=count(r->r.certified_periods>0,rows),numerically_unresolved=count(r->r.numerical_failure,rows)))
        k%10==0&&(println(scan_name," ",k,"/",length(x.events));flush(stdout))
        GC.gc(false)
    end
end
function mixed_campaign(folder)
    ispath(folder)&&error("fresh output directory required");mkpath(folder);x=mix_inputs(folder);mixed_protocol(folder)
    fixed=mix_attempt(x,joinpath(folder,"nominal-fixed"),[1.],[];seconds=120.)
    fixed.summary.accepted || return (;status=:nominal_unresolved)
    p=fixed.result.periods[1];eq=mixed_equipment_starts([p])
    mix_attempt(x,joinpath(folder,"nominal-design"),[1.],[];controls=x.controls,
        starts=[Dict(:base=>p.states[:base])],initial_equipment=eq,
        objective_upper_bound=fixed.result.objective_mwh+1e-6,seconds=180.)
    for (f,name) in ((.9,"low-fixed"),(1.05,"peak-fixed"))
        attempt=mix_attempt(x,joinpath(folder,name),[f],[];starts=[Dict(:base=>p.states[:base])],initial_equipment=eq,seconds=120.)
        attempt.summary.accepted || return (;status=:period_reference_unresolved)
    end
    reference=mixed_fixed_reference(x,folder,["low-fixed","nominal-fixed","peak-fixed","nominal-fixed","low-fixed"])
    reference.assessment.valid || return (;status=:reference_ramp_unresolved)
    factors=[.9,1.,1.05,1.,.9];sol=reference.solution
    starts=[Dict(:base=>p.states[:base]) for p in sol.periods];eq=mixed_equipment_starts(sol.periods)
    # Preserve the coupled fixed-lane attempt as distinct from the composed reference.
    mix_attempt(x,joinpath(folder,"multi-fixed"),factors,[];starts,initial_equipment=eq,seconds=120.)
    design=mix_attempt(x,joinpath(folder,"multi-design"),factors,[];controls=x.controls,starts,initial_equipment=eq,
        objective_upper_bound=sol.objective_mwh+1e-6,seconds=180.)
    design.summary.accepted || return (;status=:shared_design_unresolved)
    starts=[Dict(:base=>p.states[:base]) for p in design.result.periods];eq=mixed_equipment_starts(design.result.periods)
    mix_attempt(x,joinpath(folder,"multi-scheduled-avr"),factors,[];controls=x.controls,starts,initial_equipment=eq,
        objective_upper_bound=design.result.objective_mwh+1e-6,schedule=true,seconds=180.)
    mixed_catalogue_scan(x,folder,sol,"fixed-reference";scan_name="scan-fixed")
    mixed_catalogue_scan(x,folder,design.result,"multi-design";scan_name="scan-designed")
    (;status=:assessment_complete,security_requires_scan_acceptance=true)
end
