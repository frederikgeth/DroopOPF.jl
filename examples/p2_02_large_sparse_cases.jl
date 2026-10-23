using DroopOPF
# Six fresh cases; all constants and anchor-to-droop rules frozen before any solve.
function p2_large_sparse_inputs()
 inputs=[]
 for n in (48,96),cohort in (:normal,:tight_reactive,:saturation)
  p=(cohort==:normal ? .015 : .04)*n
  q=(cohort==:normal ? .008 : cohort==:tight_reactive ? .09 : .03)*n
  qmax=cohort==:tight_reactive ? .45 : .75
  pairs=vcat([(i,mod1(i+1,n)) for i in 1:n],[(1,div(n,2)+1),(2,n-1)])
  gbuses=collect(1:4:n);loads=[i for i in 1:n if !(i in gbuses)];ng=length(gbuses)
  branches=[Branch(i,f,t;resistance=.018,reactance=.157,thermal_limit=1.4,
   kind=i==length(pairs) ? :transformer : :line,tap_ratio=i==length(pairs) ? 1.005 : 1.) for (i,(f,t)) in enumerate(pairs)]
  case=Case("p2-large-sparse-$n-$cohort";base_power=100.,base_frequency=50.,
   network=ACNetwork([Bus(i;reference=i==1) for i in 1:n],branches;
    shunts=[FixedShunt(100,n;conductance=.0003,susceptance=.004)]),
   generators=[Generator(i,b;p_min=0.,p_max=.95,q_min=-.7,q_max=qmax,initial_p=p/ng,initial_q=q/ng) for (i,b) in enumerate(gbuses)],
   loads=[Load(i,b;p=p/length(loads),q=q/length(loads)) for (i,b) in enumerate(loads)],
   controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
  push!(inputs,(;case,cohort))
 end
 inputs
end
function p2_large_sparse_overlay(case,base;cohort)
 validate_equilibrium(case,base).valid || error("Invalid AVR anchor")
 idx=Dict(b.id=>i for (i,b) in enumerate(case.network.buses));controls=VoltVarDroop[];attachments=GeneratorControlAttachment[]
 for (i,g) in enumerate(case.generators)
  v=base.vm[idx[g.bus_id]];q=base.qg[i];width=.003;slope=.04
  # In the saturation cohort, every fourth generator has a frozen controller
  # upper limit equal to its anchor Q. Other controllers remain proportional.
  saturated=cohort==:saturation && mod(i-1,4)==0
  upper=saturated ? q : g.q_max
  q0=saturated ? q-.1 : q-width/slope
  center=saturated ? v+width+.1slope+.005 : v+2width
  g.q_min<=q0<=upper || error("Predeclared overlay outside Q range")
  push!(controls,VoltVarDroop(VoltageSchedule(center;v_db_low=center-width,v_db_high=center+width),slope,q0,
   ReactiveCapability(p_min=g.p_min,p_max=g.p_max,q_min=g.q_min,q_max=upper)))
  push!(attachments,GeneratorControlAttachment(g.id,length(controls),RegulatedLocation(:bus,g.bus_id)))
 end
 result=Case(case.id*"-droop";base_power=case.base_power,base_frequency=case.base_frequency,network=case.network,
  generators=case.generators,loads=case.loads,controls,attachments)
 validate_equilibrium(result,base).valid || error("Frozen overlay does not reproduce anchor")
 result
end
