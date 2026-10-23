# Numerical experiment: positive AVR projection gain changes no exact fixed point.
# Only an independently validated native result can qualify; bounds stay unchanged.
include("warm_mixed_avr_corridor.jl")
length(ARGS) in (1,2)||error("provide reserve campaign root and optional polish flag")
root=abspath(ARGS[1]);source=read(joinpath(MIX_ROOT,"src/jump.jl"),String)
firstpos=first(findfirst("function _build_acopf_model(",source))
_,lastpos=Meta.parse(source,firstpos;greedy=true)
fragment=source[firstpos:lastpos-1]
needle="gain=max(sum(g.q_max-g.q_min for g in generators),1e-6)/.02"
@assert occursin(needle,fragment)
fragment=replace(fragment,needle=>"gain=.01max(sum(g.q_max-g.q_min for g in generators),1e-6)/.02")
write(joinpath(root,"numerical-avr-projection-source.jl"),fragment)
mix_save(joinpath(root,"numerical-avr-projection-experiment.json"),(;gain_multiplier=.01,
    changed_physical_limits=false,qualification="unchanged exact AVR/AC/circle and response audit required",
    purpose="equivalent positive projection gain; no fuel costs or extra control freedom"))
include_string(DroopOPF,fragment,"numerical-avr-projection-source.jl")
if length(ARGS)==2 && ARGS[2]=="polish"
    warm_corridor(root;output_name="security-master-corridor-scaled-polish",
        source_name="security-master-corridor-scaled-avr",seconds=180.,tight=true)
else
    warm_corridor(root;output_name="security-master-corridor-scaled-avr")
end
