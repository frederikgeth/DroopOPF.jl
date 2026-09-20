using DroopOPF
if !isdefined(@__MODULE__,:m6_shunt_case)
    include("m6_shunt_case.jl")
end
function m72_case(;capacitor=true,available=true)
    c=m6_shunt_case(include_bank=false)
    banks=[ShuntBank(201,30;step_susceptances=(capacitor ? .02 : -.02,),
        step_conductances=(.001,),legal_states=((0,),(1,),(2,),(3,)),state=(1,),available),
        ShuntBank(202,20;step_susceptances=(-.01,),step_conductances=(.0005,),
        legal_states=((0,),(1,),(2,)),state=(1,))]
    Case("m72-simple-banks";base_power=c.base_power,base_frequency=c.base_frequency,
        network=ACNetwork(c.network.buses,c.network.branches;shunts=c.network.shunts,banks),
        generators=c.generators,loads=c.loads,controls=c.controls,attachments=c.attachments)
end
