# Fixed synthetic controller settings. All paired cases retain identical physical limits.
limiter_test(;kwargs...)=ThresholdVirtualImpedance(;merge((;onset_fraction=.5,
    impedance_gain=.005+.02im,max_multiplier=4.),(;kwargs...))...)

@testset "Threshold impedance contract and phasor verification" begin
    for kw in ((;onset_fraction=0.),(;onset_fraction=1.),(;onset_fraction=NaN),
        (;impedance_gain=0.),(;impedance_gain=-.1im),(;impedance_gain=Inf),
        (;max_multiplier=0.),(;max_multiplier=Inf))
        @test_throws ArgumentError limiter_test(;kw...)
    end
    p=vsplant(i_max=.8);l=limiter_test()
    for i in (.2-.1im,.4+0im,.6-.1im,1.5-.2im)
        # Construct a known current and source phasor from the explicit controller law.
        expected=min(l.max_multiplier,max(0.,abs2(i)/(l.onset_fraction*p.i_max)^2-1))
        v=1.0+0im
        e=v+(p.z_physical+p.z_virtual+l.impedance_gain*expected)*i
        a=voltage_source_response(p,v,e;limiter=l)
        @test a.current≈i atol=1e-12
        @test a.limiter_multiplier≈expected atol=1e-12
        @test a.converter_voltage≈v+p.z_physical*i atol=1e-12
        @test real(a.converter_power)≈a.p+a.physical_loss atol=1e-12
        @test a.physical_loss≈real(p.z_physical)*abs2(i) atol=1e-12
        # Same E and V: added passive impedance must not increase current magnitude.
        @test abs(a.current)<=abs(voltage_source_response(p,v,e).current)+1e-12
    end
    # Continuity through onset; hard ceiling remains separate from finite-gain control.
    onset=l.onset_fraction*p.i_max
    for factor in (1-1e-7,1.,1+1e-7)
        ii=onset*factor
        lam=min(l.max_multiplier,max(0.,factor^2-1))
        e=1+(p.z_physical+p.z_virtual+lam*l.impedance_gain)*ii
        a=voltage_source_response(p,1.,e;limiter=l)
        @test abs(a.current-ii)<1e-12
        @test abs(a.limiter_multiplier-lam)<1e-12
    end
    a=voltage_source_response(p,1.,3.;limiter=l)
    @test !a.current_within_limit
    @test a.limiter_multiplier≈l.max_multiplier
end

@testset "Limiter native equilibria and unchanged envelopes" begin
    c=vscase();p=[vsplant(i_max=.8),vsplant(generator_id=2,terminal_bus=2,i_max=.8)]
    snapshot=model_data(c)
    base=solve_voltage_source_opf(c,p;frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(c,base).valid
    for (settings,mode) in ((limiter_test(),:active),
        (limiter_test(onset_fraction=.95),:inactive),
        (limiter_test(max_multiplier=.1),:ceiling))
        ls=Dict(x.generator_id=>settings for x in p)
        r=solve_voltage_source_opf(c,p;limiters=ls,frequency_bounds=(48.,52.))
        report=validate_voltage_source_opf(c,r)
        @test report.valid
        @test all(x->x.limiter_mode==mode,report.plants)
        @test all(x->x.current<=.8+1e-6,report.plants)
        @test r.plants==base.plants # No rating, reference, droop or impedance mutation.
        @test model_data(c)==snapshot

        if mode==:inactive
            @test r.opf.state.vm≈base.opf.state.vm atol=1e-6
            @test r.opf.state.pg≈base.opf.state.pg atol=1e-6
            @test r.frequency_hz≈base.frequency_hz atol=1e-6
        end
        if mode==:active
            @test maximum(r.limiter_multiplier)>0
            bad=VoltageSourceResult(r.opf,r.plants,r.inverters,r.responses,r.internal_voltage,
                r.frequency_hz,r.frequency_bounds,r.solved_frequency,r.limiters,r.limiter_multiplier.+.1)
            @test !validate_voltage_source_opf(c,bad).valid
            # Removing or changing the controller contract cannot validate the old solution.
            bad=VoltageSourceResult(r.opf,r.plants,r.inverters,r.responses,r.internal_voltage,
                r.frequency_hz,r.frequency_bounds,r.solved_frequency)
            @test !validate_voltage_source_opf(c,bad).valid
            for (base_mva,reference) in ((200.,1),(100.,2))
                cc=vscase(base=base_mva,reference=reference)
                rr=solve_voltage_source_opf(cc,p;limiters=ls,frequency_bounds=(48.,52.))
                @test validate_voltage_source_opf(cc,rr).valid
                @test rr.opf.state.pg*base_mva≈r.opf.state.pg*100 atol=1e-4
                @test rr.limiter_multiplier≈r.limiter_multiplier atol=1e-5
                @test rr.frequency_hz≈r.frequency_hz atol=1e-6
            end
        end
    end
    @test_throws ArgumentError solve_voltage_source_opf(c,p;limiters=Dict(99=>limiter_test()))
    # Native voltage and load bounds imply P <= Vmax Imax for each unit.
    # Demand 1.2 exceeds combined 2*1.1*.3=.66, irrespective of controller setting.
    small=[vsplant(i_max=.3),vsplant(generator_id=2,terminal_bus=2,i_max=.3)]
    ls=Dict(x.generator_id=>limiter_test() for x in small)
    bad=solve_voltage_source_opf(c,small;limiters=ls,frequency_bounds=(48.,52.),
        optimizer_attributes=Dict("max_iter"=>150))
    @test !validate_voltage_source_opf(c,bad).valid
    # Offline sources have zero multiplier, not a fictitious energized impedance.
    co=vscase(online=false,load=.8)
    po=[vsplant(),vsplant(generator_id=2,terminal_bus=2)]
    ro=solve_voltage_source_opf(co,po;limiters=Dict(2=>limiter_test()),frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(co,ro).valid
    @test ro.limiter_multiplier[2]==0
end

@testset "Limiter prescribed frequency, mixed fleet and metadata rejection" begin
    c=vscase();p=vsplant(i_max=.8);ls=Dict(1=>limiter_test())
    r=solve_voltage_source_opf(c,[p];limiters=ls,frequency_hz=50.)
    @test validate_voltage_source_opf(c,r).valid
    @test r.opf.state.pg[1]≈.5 atol=1e-6
    @test validate_voltage_source_opf(c,r).plants[1].limiter_mode==:active
    law=GeneratorFrequencyResponse(generator_id=2,p_ref=.5,gain_pu_per_hz=.5,f_ref_hz=50.)
    mixed=solve_voltage_source_opf(c,[p];limiters=ls,responses=[law],frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(c,mixed).valid
    gfl=StaticInverter(generator_id=2,terminal_bus=2,mode=:gfl,priority=:reactive,q_control=:fixed_q,
        base_mva=100.,terminal_base_kv=20.,i_max=2.,s_max=2.,p_available=2.,p_ref=.5,q_ref=.05,
        v_ref=1.,q_droop=.05,f_ref_hz=50.,p_droop_hz=2.,reactive_available=true)
    mixed=solve_voltage_source_opf(c,[p];limiters=ls,inverters=[gfl],frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(c,mixed).valid
    warm=solve_voltage_source_opf(c,[p];limiters=ls,inverters=[gfl],frequency_bounds=(48.,52.),initial_state=mixed.opf.state)
    @test validate_voltage_source_opf(c,warm).valid
    @test warm.limiter_multiplier≈mixed.limiter_multiplier atol=1e-5
    for multipliers in (Float64[],[NaN],[-.1],[100.])
        bad=VoltageSourceResult(r.opf,r.plants,r.inverters,r.responses,r.internal_voltage,r.frequency_hz,
            r.frequency_bounds,r.solved_frequency,r.limiters,multipliers)
        @test !validate_voltage_source_opf(c,bad).valid
    end
    altered=Dict(1=>limiter_test(impedance_gain=.01+.04im))
    bad=VoltageSourceResult(r.opf,r.plants,r.inverters,r.responses,r.internal_voltage,r.frequency_hz,
        r.frequency_bounds,r.solved_frequency,altered,r.limiter_multiplier)
    @test !validate_voltage_source_opf(c,bad).valid
end
@testset "Voltage-source campaign branch angle contract" begin
 c=vscase();p=[vsplant(),vsplant(generator_id=2,terminal_bus=2)]
 angles=Dict(1=>(-.2,.2))
 r=solve_voltage_source_opf(c,p;frequency_bounds=(48.,52.),branch_angle_bounds=angles)
 @test validate_voltage_source_opf(c,r).valid
 @test r.branch_angle_bounds==angles
 bad=VoltageSourceResult(r.opf,r.plants,r.inverters,r.responses,r.internal_voltage,r.frequency_hz,
  r.frequency_bounds,r.solved_frequency,r.limiters,r.limiter_multiplier,Dict(1=>(.1,.2)))
 @test !validate_voltage_source_opf(c,bad).valid
 for a in (Dict(99=>(-.2,.2)),Dict(1=>(.2,-.2)),Dict(1=>(NaN,.2)))
  @test_throws ArgumentError solve_voltage_source_opf(c,p;branch_angle_bounds=a)
 end
end
