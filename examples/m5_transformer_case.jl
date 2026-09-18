using DroopOPF
import CCOpt

"""Synthetic meshed droop study with a fixed from-side transformer on branch 11."""
function m5_transformer_case(; tap=1.02, phase=0.02, rating=2.0)
    network = ACNetwork([Bus(10; reference=true),Bus(20),Bus(30)],
        [Branch(11,10,20; resistance=.01,reactance=.1,charging=.02,
                thermal_limit=rating,tap_ratio=tap,phase_shift=phase),
         Branch(22,20,30; resistance=.01,reactance=.1,thermal_limit=rating),
         Branch(33,10,30; resistance=.01,reactance=.1,thermal_limit=rating)])
    generators = [Generator(id,bus; p_min=0.,p_max=1.2,q_min=-1.,q_max=1.,
        initial_p=.3,initial_q=0.) for (id,bus) in [(7,10),(9,20)]]
    controls = [VoltVarDroop(VoltageSchedule(1.;v_db_low=.99,v_db_high=1.01),
        slope,0.,ReactiveCapability(p_min=0.,p_max=1.2,q_min=-1.,q_max=1.))
        for slope in [.05,.075]]
    return Case("m5-fixed-transformer";base_power=100.,base_frequency=50.,
        network=network,loads=[Load(1,30;p=.6,q=.15)],generators=generators,
        controls=controls,attachments=[GeneratorControlAttachment(g.id,i,RegulatedLocation(:bus,g.bus_id))
            for (i,g) in enumerate(generators)])
end

function m5_transformer_study(; mode=:preventive)
    c=m5_transformer_case()
    outages=[Contingency(:transformer_out;branch_ids=[11]),
             Contingency(:line_out;branch_ids=[22]),
             Contingency(:generator_out;generator_ids=[9])]
    return mode == :preventive ? Study(c;contingencies=outages,participation=Dict(7=>1.,9=>1.)) :
        Study(c;contingencies=outages,mode=:corrective,redispatch_limits=Dict(7=>1.,9=>1.))
end


"""Declared proportional-regime starts for this synthetic fixture, not observations.
Flat 1 pu starts sit inside every droop deadband and can stall local solvers.
"""
function m5_initial_state(case)
    pg=[g.available ? .6/count(g.available for g in case.generators) : 0. for g in case.generators]
    qg=[g.available ? droop_response(case.controls[i],.98;p=pg[i]) : 0.
        for (i,g) in enumerate(case.generators)]
    return ACState([.98,.98,.95],[0.,-.01,-.04],pg,qg)
end

function m5_initial_states(study)
    states=Dict(:base=>m5_initial_state(study.case))
    for outage in study.contingencies
        states[outage.id]=m5_initial_state(scenario_case(study.case,outage))
    end
    return states
end


# Keep solver-specific accuracy choices out of the equipment model. A 1e-8
# product-relaxation floor can leave exact droop errors above 1e-5 in this case.
m5_ccopt_options() = Dict{String,Any}(
    "relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-12),
    "tol"=>1e-9, "acceptable_tol"=>1e-9, "bound_relax_factor"=>0.)
