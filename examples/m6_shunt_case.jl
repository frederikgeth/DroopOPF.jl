using DroopOPF
if !isdefined(@__MODULE__,:m5_transformer_case)
    include("m5_transformer_case.jl")
end

function m6_bank(;state=(1,0),available=true)
    ShuntBank(201,30;step_conductances=(.001,.0005),step_susceptances=(.02,-.01),
        legal_states=((0,0),(1,0),(2,0),(0,1),(1,1)),state=state,
        nominal_state=(1,0),available=available)
end

function m6_shunt_case(;state=(1,0),available=true,include_fixed=true,include_bank=true)
    c=m5_transformer_case()
    net=ACNetwork(c.network.buses,c.network.branches;
        shunts=include_fixed ? [FixedShunt(101,30;conductance=.002,susceptance=.01)] : FixedShunt[],
        banks=include_bank ? [m6_bank(;state,available)] : ShuntBank[])
    Case("m6-fixed-bank-study";base_power=c.base_power,base_frequency=c.base_frequency,
        network=net,loads=c.loads,generators=c.generators,controls=c.controls,attachments=c.attachments)
end

function m6_shunt_study(;mode=:preventive,kwargs...)
    c=m6_shunt_case(;kwargs...)
    cs=[Contingency(:transformer_out;branch_ids=[11]),Contingency(:line_out;branch_ids=[22]),
        Contingency(:generator_out;generator_ids=[9])]
    mode==:preventive ? Study(c;contingencies=cs,participation=Dict(7=>1.,9=>1.)) :
        Study(c;contingencies=cs,mode=:corrective,redispatch_limits=Dict(7=>1.,9=>1.))
end
