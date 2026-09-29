# One process-isolated cell of the expanded S2 public qualification matrix.
# Usage: julia --project=. examples/s2_expanded_cell.jl 118 ipopt avr tap preventive OUT
include("s2_scopf_qualification.jl")

function s2_bank_overlay(case; source_shunt_id=34, bank_id=900034)
    source=only(filter(s->s.id==source_shunt_id,case.network.shunts))
    abs(source.susceptance)>0 || error("overlay source must have nonzero susceptance")
    bank=ShuntBank(bank_id,source.bus_id;
        step_conductances=[source.conductance],
        step_susceptances=[source.susceptance],legal_states=[(0,),(1,),(2,)],
        state=(1,),nominal_state=(1,))
    shunts=filter(s->s.id!=source.id,case.network.shunts)
    network=ACNetwork(case.network.buses,case.network.branches;
        shunts,banks=[case.network.banks;bank])
    overlaid=Case(case.id;base_power=case.base_power,
        base_frequency=case.base_frequency,network,loads=case.loads,
        generators=case.generators,controls=case.controls,
        attachments=case.attachments)
    overlaid,bank
end

function s2_mixed_assignments(setup,case)
    assignments=ReactiveControlAssignment[setup.assignments...]
    avr=pop!(assignments)
    generator=only(filter(g->g.id==avr.generator_id,case.generators))
    i=findfirst(g->g.id==generator.id,case.generators)
    target=avr.mode.voltage_setpoint
    control=VoltVarDroop(VoltageSchedule(target;
        v_db_low=target-0.005,v_db_high=target+0.005),0.05,setup.free.state.qg[i],
        ReactiveCapability(p_min=generator.p_min,p_max=generator.p_max,
            q_min=generator.q_min,q_max=generator.q_max))
    push!(assignments,ReactiveControlAssignment(generator.id,control,avr.location))
    assignments
end

function s2_scaled_case(case,factor)
    loads=[Load(l.id,l.bus_id;p=factor*l.p,q=factor*l.q) for l in case.loads]
    Case(case.id;base_power=case.base_power,base_frequency=case.base_frequency,
        network=case.network,loads,generators=case.generators,
        controls=case.controls,attachments=case.attachments)
end

function run_expanded_cell(network_size,solver,reactive,equipment,timing,out;
    profile=:nominal)
    network_size==118 || error("initial expanded matrix is pinned to IEEE-118")
    reactive in (:avr,:mixed) || error("reactive must be avr or mixed")
    equipment in (:tap,:shunt,:joint,:multi) || error("unknown equipment profile")
    profile in (:nominal,:holdout,:stress) || error("unknown qualification profile")
    timing in (:preventive,:corrective) || error("timing must be preventive or corrective")
    setup=s2_setup(network_size)
    case,bank=s2_bank_overlay(setup.case)
    profile==:stress && (case=s2_scaled_case(case,1.03))
    assignments=reactive==:avr ? ReactiveControlAssignment[setup.assignments...] :
        s2_mixed_assignments(setup,case)
    tap_controls=equipment in (:tap,:joint,:multi) ? copy(setup.equipment_study.tap_controls) : TapControl[]
    if equipment==:multi
        branch=only(filter(b->b.id==32,case.network.branches))
        push!(tap_controls,TapControl(branch.id;lower=.99*branch.tap_ratio,
            upper=1.01*branch.tap_ratio,initial=branch.tap_ratio,
            nominal=branch.tap_ratio))
    end
    b0=only(bank.step_susceptances)
    shunt_controls=equipment in (:shunt,:joint,:multi) ?
        [ShuntControl(bank.id;lower=0.9*b0,upper=1.1*b0,
            initial=b0,nominal=b0)] : ShuntControl[]
    policy=timing==:preventive ? SCOPFControlPolicy() : SCOPFControlPolicy(
        taps=isempty(tap_controls) ? :preventive : :corrective,
        shunts=isempty(shunt_controls) ? :preventive : :corrective,
        tap_movement_limits=isempty(tap_controls) ? nothing :
            Dict(c.branch_id=>0.005 for c in tap_controls),
        shunt_movement_limits=isempty(shunt_controls) ? nothing :
            Dict(only(shunt_controls).bank_id=>0.1*abs(b0)))
    contingencies=profile==:holdout ?
        [Contingency(:holdout_line_2;branch_ids=[2]),
         Contingency(:holdout_generator_40;generator_ids=[40])] : setup.contingencies
    study=Study(case;contingencies,
        participation=setup.participation,reactive_assignments=assignments,
        tap_controls,shunt_controls,control_policy=policy)
    result=s2_solve(study,solver)
    row,report=s2_row(study,result)
    mkpath(out)
    write_study(joinpath(out,"study.json"),study)
    write_scopf_result(joinpath(out,"result.json"),result)
    write_scopf_report(joinpath(out,"report.json"),report)
    payload=Dict("network"=>network_size,"solver"=>string(solver),
        "reactive"=>string(reactive),"equipment"=>string(equipment),
        "timing"=>string(timing),"source_fixed_shunt_id"=>34,
        "profile"=>string(profile),"load_factor"=>profile==:stress ? 1.03 : 1.0,
        "contingencies"=>string.([c.id for c in contingencies]),
        "overlay_bank_id"=>bank.id,"overlay_supplied_b"=>b0,
        "continuous_relaxation"=>true,"result"=>row,
        "s1_scorecard_unchanged"=>true)
    write(joinpath(out,"summary.json"),JSON.json(payload;pretty=true)*"\n")
    println(JSON.json(payload;pretty=true))
end

network=parse(Int,ARGS[1]);solver=Symbol(ARGS[2]);reactive=Symbol(ARGS[3])
equipment=Symbol(ARGS[4]);timing=Symbol(ARGS[5]);out=abspath(ARGS[6])
profile=length(ARGS)>=7 ? Symbol(ARGS[7]) : :nominal
run_expanded_cell(network,solver,reactive,equipment,timing,out;profile)
