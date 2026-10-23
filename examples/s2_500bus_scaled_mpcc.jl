# Exact zero-deadband projection in dimensionless Q-span coordinates.
# Network physics uses exact reduction and every original terminal rating.
include("s2_500bus_solver_demand_qualification.jl")
function sdq_scaled_mpcc(c;silent,shared_model,scenario_prefix,set_objective,initial_state,
    reactive_assignments,tap_controls,shunt_controls,normalize_controls,droop_parameter_variables,
    power_balance_slacks=false,load_relief=nothing)
    @assert isnothing(reactive_assignments) && !set_objective && !normalize_controls
    m=shared_model;prefix=scenario_prefix
    _,v=nr_build_ac(c;silent,shared_model=m,scenario_prefix,set_objective,initial_state,
        reactive_assignments,tap_controls,shunt_controls,normalize_controls,droop_parameter_variables,
        power_balance_slacks,load_relief,include_droop_equations=false,
        voltage_epsilon=1e-6,reactive_relative_epsilon=1e-6,reactive_epsilon=1e-6)
    gi=Dict(g.id=>i for (i,g) in enumerate(c.generators));bi=DroopOPF._bus_indices(c.network)
    active=[a for a in c.attachments if c.generators[gi[a.generator_id]].available]
    n=length(active)
    q_lower_slack=@variable(m,[1:n],lower_bound=0.,base_name=prefix*"normalized_q_lower_slack")
    q_upper_slack=@variable(m,[1:n],lower_bound=0.,base_name=prefix*"normalized_q_upper_slack")
    q_lower_multiplier=@variable(m,[1:n],lower_bound=0.,base_name=prefix*"normalized_q_lower_multiplier")
    q_upper_multiplier=@variable(m,[1:n],lower_bound=0.,base_name=prefix*"normalized_q_upper_multiplier")
    raw_q=Any[];metadata=Any[]
    for (k,a) in enumerate(active)
        i=gi[a.generator_id];j=bi[a.location.bus_id];d=c.controls[a.control_id]
        p=droop_parameter_variables[a.control_id]
        @assert DroopOPF._fixed_zero_deadband(p.deadband_low,p.deadband_high)
        qmin=d.capability.q_min;qmax=d.capability.q_max;span=qmax-qmin
        @assert span>0
        slope=p.slope;vref=p.v_ref;q=v.qg[i];voltage=v.vm[j]
        @assert voltage isa VariableRef
        lo=q_lower_multiplier[k];hi=q_upper_multiplier[k]
        raw=@expression(m,q-span*lo+span*hi);push!(raw_q,raw)
        # Positive slope makes this equation equivalent to raw=(Vref-V)/slope.
        # Q normal-cone multipliers and slacks are scaled by the same span.
        @constraint(m,q_lower_slack[k]==(q-qmin)/span)
        @constraint(m,q_upper_slack[k]==(qmax-q)/span)
        @constraint(m,(vref-voltage-slope*(raw-d.q_at_deadband))/.05==0.)
        @constraint(m,[q_lower_slack[k],lo] in JuMP.MOI.Complements(2))
        @constraint(m,[q_upper_slack[k],hi] in JuMP.MOI.Complements(2))
        initial_slope=DroopOPF._droop_parameter_start(slope,d.slope)
        initial_ref=DroopOPF._droop_parameter_start(vref,d.schedule.v_ref)
        raw0=d.q_at_deadband+(initial_ref-initial_state.vm[j])/initial_slope
        q0=clamp(raw0,qmin,qmax)
        set_start_value(q,q0)
        set_start_value(q_lower_slack[k],(q0-qmin)/span)
        set_start_value(q_upper_slack[k],(qmax-q0)/span)
        set_start_value(lo,max(q0-raw0,0.)/span)
        set_start_value(hi,max(raw0-q0,0.)/span)
        push!(metadata,(;generator_id=a.generator_id,control_id=a.control_id,bus_id=a.location.bus_id,
            generator_index=i,bus_index=j,q_min=qmin,q_max=qmax,q_at_deadband=d.q_at_deadband,
            slope,v_ref=vref,deadband_low=0.,deadband_high=0.))
    end
    vars=(;v...,raw_q,q_lower_slack,q_upper_slack,q_lower_multiplier,q_upper_multiplier,
        voltage_lower=Dict{Int,VariableRef}(),voltage_upper=Dict{Int,VariableRef}(),
        voltage_lower_complement=Dict{Int,VariableRef}(),voltage_upper_complement=Dict{Int,VariableRef}(),
        avr_pairs=Tuple{VariableRef,VariableRef}[])
    m.ext[:ccopt_complementarity_variables]=vars
    m.ext[:ccopt_complementarity_droop_metadata]=metadata
    m,vars
end

function sdq_scaled_recovery()
    @assert !isempty(strip(get(ENV,"SDQ_CONTROL_CONFIRMATION","")))
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    label="ccopt-10000-scaled-mpcc"
    target=joinpath(SDQ_OUT,"summary-$label.json");isfile(target) && error("Preserve completed recovery")
    phase=JSON.parsefile(joinpath(SDQ_OUT,"summary-ipopt-10000.json"));@assert phase["accepted"]
    source=joinpath(S2500_OUT,phase["selected"])
    seedstudy=read_study(joinpath(source,"optimized-1.0.json"));seed=read_scopf_result(joinpath(source,"result-1.0.json"))
    controls=s214_multi_controls(fd_inputs(500).base);angles=fd_inputs(500).angles
    fd_save(joinpath(SDQ_OUT,"protocol-$label.json"),(;confirmation=ENV["SDQ_CONTROL_CONFIRMATION"],
        solver=:ccopt,factor=1.,separator_solver=:ipopt,shared_free_variables=102,
        formulation="Exact reduced AC, original ratings; zero-deadband Q projection with normalized slacks/multipliers and multiplied positive-slope equation",
        source_sha256=bytes2hex(sha256(read(@__FILE__))),maximum_native_master_attempts=2,seconds_per_master=300.))
    attempts=Any[];accepted=false;selected=nothing;scan=nothing
    for (i,mu) in enumerate((1e-6,1e-8))
        prefix="solver_demand_qualification/$label/round-1/attempt-$i";folder=joinpath(S2500_OUT,prefix)
        ispath(folder) && error("Preserve existing attempt")
        mkpath(folder)
        for file in ("s2_500bus_scaled_mpcc.jl","s2_500bus_network_reduction.jl","s2_arpae500_recovery.jl","audit_s2_500bus_solver_demand.py")
            cp(joinpath(@__DIR__,file),joinpath(folder,"executed_"*file))
        end
        fd_save(joinpath(folder,"free-controls.json"),controls)
        lane=s2500_targeted_attempt(prefix,seedstudy,controls,seedstudy,Dict(1.0=>seed),angles;
            solver=:ccopt,retry=true,droop_normalization=true,normalization=false,mu,scheduled=i==1,
            cc_builder=sdq_scaled_mpcc,mpcc_implied_q_bounds=true,linear_solver=MadNLP.UmfpackSolver,seconds_budget=300.)
        python=get(ENV,"SDQ_PYTHON","/tmp/s214-plot-env/bin/python");script=joinpath(@__DIR__,"audit_s2_500bus_solver_demand.py")
        read(`$python $script $folder`,String)
        good=lane.record["accepted"] && JSON.parsefile(joinpath(folder,"independent-audit.json"))["accepted"]
        push!(attempts,(;name=prefix,accepted=good,record=lane.record))
        if good
            selected=prefix
            events=eligible_contingencies(contingency_catalog(lane.study.case))
            full=DroopOPF._copy_study(lane.study;contingencies=events)
            scan=s2500_scan("solver_demand_qualification/$label/round-1/demand-1.0",full,lane.results[1.],angles;solver=:ipopt)
            accepted=scan.accepted
        end
        fd_save(target,(;solver=:ccopt,factor=1.,accepted,selected,full_n1_accepted=false,
            rounds=[(;round=1,attempts,selected,working_outages=[c.id for c in seedstudy.contingencies],
                scan=isnothing(scan) ? nothing : (;accepted=scan.accepted,exhaustive=scan.exhaustive,evaluated=length(scan.rows),failed=scan.failed))]))
        good && break
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && sdq_scaled_recovery()
