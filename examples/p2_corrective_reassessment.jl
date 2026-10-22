# Bounded corrective sensitivity campaign; importing this file does not solve.
include("p2_preventive_controls.jl")
const PC_FACTORS=sort([PR_TRAIN;PR_HOLD])
const PC_OPTIONS=Dict("tol"=>1e-8,"max_iter"=>1500,"max_cpu_time"=>30.,"bound_relax_factor"=>0.)
pcnative(r)=r.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
function pcsave(dir,study,result)
    mkpath(dir);write_study(joinpath(dir,"study.json"),study)
    write_scopf_result(joinpath(dir,"result.json"),result)
    report=equilibrium_report(study,result);prsave(joinpath(dir,"validation.json"),report)
    (;accepted=pcnative(result)&&report.valid,status=result.termination_status,physical_valid=report.valid)
end
function pcstudy(case,events,policy;bank=nothing)
    sh=isnothing(bank) ? ShuntControl(201) : ShuntControl(201;lower=bank,upper=bank,initial=bank)
    Study(case;contingencies=events,tap_controls=[TapControl(11;lower=.95,upper=1.05,initial=1.)],
        shunt_controls=[sh],control_policy=policy)
end
function pcmain(out)
    ispath(out)&&error("Preserve previous campaign");mkpath(out)
    previous=joinpath(PR_ROOT,"artifacts/p2_preventive_controls_20261021/bank_fixture/preventive/primary")
    selected=read_study(joinpath(previous,"study-1.0.json"))
    anchor=read_scopf_result(joinpath(previous,"result-1.0.json"))
    # Freeze previously independently accepted robust curves, preserving bank metadata.
    original=pr_fixture();configured=Study(original)
    for (i,d) in enumerate(selected.case.controls);configured=with_droop_settings(configured,i,DroopSettings(d));end
    case=configured.case
    events=selected.contingencies;rows=Any[]
    preventive=SCOPFControlPolicy(taps=:preventive,shunts=:preventive)
    prsave(joinpath(out,"protocol.json"),(;training=PR_TRAIN,held_out=PR_HOLD,
        droop="previously accepted shared curves frozen across every demand and outage",
        preventive="equipment may be scheduled separately for each known demand; rounded legal bank then reoptimized tap and dispatch",
        stages=[(;name="immediate",seconds=0,tap_budget=0.,bank_sections=0),
            (;name="settled60",seconds=60,tap_budget=.0125,bank_sections=1),
            (;name="settled120",seconds=120,tap_budget=.025,bank_sections=2)],
        tap_absolute=[.95,1.05],bank_legal=[0.,.02,.04,.06],bank_id=201,tap_id=11,
        timing="assumed availability deadlines, independent equilibria from same base, not sequential trajectories or transient validation",
        tap_capability="continuous sensitivity envelope; no manufacturer step or timing data",
        public_scope="original 90–110% scope retained; exact capacity certificates rechecked separately",
        options=PC_OPTIONS,physical_tolerances="unchanged",screening=false))
    for factor in PC_FACTORS
        c=DroopOPF._feasibility_scaled_case(case,factor);parent=joinpath(out,"bank_fixture",string(factor))
        relaxed=pcstudy(c,events,preventive)
        r=solve_scopf(relaxed;smooth_epsilon=PR_EPS,sparse_balance=true,initial_states=anchor.states,optimizer_attributes=PC_OPTIONS)
        a=pcsave(joinpath(parent,"preventive_relaxed"),relaxed,r)
        a.accepted||error("Preventive relaxed failure at $factor: $a")
        bank=.02*clamp(round(Int,r.shunt_settings[:base][201]/.02),0,3)
        immediate_study=pcstudy(c,events,preventive;bank)
        base=solve_scopf(immediate_study;smooth_epsilon=PR_EPS,sparse_balance=true,initial_states=r.states,optimizer_attributes=PC_OPTIONS)
        for settings in values(base.shunt_settings);settings[201]=bank;end
        a=pcsave(joinpath(parent,"preventive_legal"),immediate_study,base)
        a.accepted||error("Preventive recovery failure at $factor: $a")
        # Same base, controls, curves and response weights at every subsequent stage.
        for (name,tap_budget,sections) in (("immediate",0.,0),("settled60",.0125,1),("settled120",.025,2))
            policy=sections==0 ? preventive : SCOPFControlPolicy(taps=:corrective,shunts=:corrective,
                tap_movement_limits=Dict(11=>tap_budget),shunt_movement_limits=Dict(201=>.02sections))
            study=pcstudy(c,events,policy)
            result=solve_scopf(study;fixed_base_state=base.states[:base],
                fixed_base_tap_settings=base.tap_settings[:base],fixed_base_shunt_settings=base.shunt_settings[:base],
                smooth_epsilon=PR_EPS,sparse_balance=true,initial_states=base.states,optimizer_attributes=PC_OPTIONS)
            continuous=pcsave(joinpath(parent,name,"continuous"),study,result)
            # Recover legal integer bank sections within the declared movement budget.
            bank0=round(Int,bank/.02)
            chosen=Dict(id=>.02*clamp(round(Int,v[201]/.02),max(0,bank0-sections),min(3,bank0+sections))
                for (id,v) in result.shunt_settings if id!=:base)
            function legal_bank_hook(model)
                vs=[x for x in all_variables(model) if JuMP.name(x)=="shunt_B_201"]
                length(vs)==length(events)||error("Unexpected bank variable inventory")
                for (v,e) in zip(vs,events);fix(v,chosen[e.id];force=true);end
            end
            recovered=solve_scopf(study;fixed_base_state=base.states[:base],
                fixed_base_tap_settings=base.tap_settings[:base],fixed_base_shunt_settings=base.shunt_settings[:base],
                smooth_epsilon=PR_EPS,sparse_balance=true,initial_states=result.states,
                optimizer_attributes=PC_OPTIONS,_model_hook=legal_bank_hook)
            legal=pcsave(joinpath(parent,name,"legal"),study,recovered)
            movements=Dict(string(id)=>(;tap=get(t,11,base.tap_settings[:base][11])-base.tap_settings[:base][11],
                bank_sections=round(Int,(recovered.shunt_settings[id][201]-bank)/.02))
                for (id,t) in recovered.tap_settings if id!=:base)
            row=(;factor,stage=name,continuous,legal,base_tap=base.tap_settings[:base][11],base_bank_sections=bank0,movements)
            push!(rows,row);prsave(joinpath(out,"summary.json"),rows)
            println("CORRECTIVE ",factor," ",name," continuous=",continuous.accepted," legal=",legal.accepted);flush(stdout)
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__)&&pcmain(abspath(ARGS[1]))
