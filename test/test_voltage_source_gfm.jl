# Synthetic assumptions only: no manufacturer capability is inferred.
function vsplant(;kwargs...)
    defaults=(;generator_id=1,terminal_bus=1,base_mva=100.,z_physical=.01+.1im,
        z_virtual=.02+.05im,p_ref=.5,q_ref=0.,f_ref_hz=50.,p_droop_hz=2.,
        e_ref=1.,q_droop=.05,e_bounds=(.8,1.2),u_bounds=(.8,1.2),i_max=2.,s_max=2.,p_available=2.)
    VoltageSourceGFM(;merge(defaults,(;kwargs...))...)
end
function vscase(;base=100.,load=1.2,qload=.1,reference=1,online=true)
    a=100/base
    Case("synthetic-voltage-source";base_power=base,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=reference==1,v_min=.9,v_max=1.1),
            Bus(2;reference=reference==2,v_min=.9,v_max=1.1)],
            [Branch(1,1,2;resistance=.01/a,reactance=.05/a,thermal_limit=3a)]),
        loads=[Load(1,2;p=load*a,q=qload*a)],
        generators=[Generator(1,1;p_min=0.,p_max=2a,q_min=-a,q_max=a,initial_p=.6a),
            Generator(2,2;available=online,p_min=0.,p_max=2a,q_min=-a,q_max=a,initial_p=.6a)],
        controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
end
@testset "Voltage-source contract and independent phasors" begin
    for kw in ((;base_mva=0.),(;z_physical=-.1im),(;z_virtual=NaN),
        (;z_physical=0.,z_virtual=0.),(;p_droop_hz=0.),(;q_droop=-1.),
        (;e_bounds=(1.1,1.2)),(;u_bounds=(0.,1.2)),(;i_max=Inf),(;p_ref=NaN))
        @test_throws ArgumentError vsplant(;kw...)
    end
    p=vsplant();v=1.0+0im;i=.6-.2im;e=v+(p.z_physical+p.z_virtual)*i
    r=voltage_source_response(p,v,e)
    @test r.current≈i
    @test r.p≈.6
    @test r.q≈.2
    @test r.physical_loss≈.004
    @test real(r.converter_power)≈r.p+r.physical_loss
    @test imag(r.converter_power)≈r.q+imag(p.z_physical)*abs2(i)
    @test real(e*conj(i))-real(r.converter_power)≈real(p.z_virtual)*abs2(i)
end
@testset "Voltage-source analytical equilibrium and sharing" begin
    c=Case("one-bus";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=true,v_min=.9,v_max=1.1)],Branch{Float64}[]),
        loads=[Load(1,1;p=1.2,q=0.)],
        generators=[Generator(i,1;p_min=0.,p_max=2.,q_min=-1.,q_max=1.,initial_p=.6) for i in 1:2],
        controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    # Active slopes imply 2:1 incremental sharing; Q is determined by voltage/network equations.
    p1=vsplant(p_droop_hz=1.,z_physical=.1im,z_virtual=.05im)
    p2=vsplant(generator_id=2,p_droop_hz=2.,z_physical=.1im,z_virtual=.05im)
    r=solve_voltage_source_opf(c,[p1,p2];frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(c,r).valid
    @test r.frequency_hz≈50-.2/1.5 atol=1e-6
    @test r.opf.state.pg≈[.5+.2/1.5,.5+.1/1.5] atol=1e-6
    # Single source analytical voltage: E² = V² + (X P/V)² at Q=0.
    single=Case("single";base_power=100.,base_frequency=50.,network=c.network,
        loads=[Load(1,1;p=.6,q=0.)],generators=c.generators[1:1],controls=c.controls,attachments=c.attachments)
    r=solve_voltage_source_opf(single,[p1];frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(single,r).valid
    expected=sqrt((1+sqrt(1-4*(.15*.6)^2))/2)
    @test r.opf.state.vm[1]≈expected atol=1e-6
    @test abs(r.internal_voltage[1])≈1. atol=1e-6
    @test r.frequency_hz≈49.9 atol=1e-6
    # A current bound is an envelope, never a silent clipping/limiter law.
    bad=solve_voltage_source_opf(single,[vsplant(i_max=.2)];frequency_bounds=(48.,52.),
        optimizer_attributes=Dict("max_iter"=>100))
    @test !validate_voltage_source_opf(single,bad).valid
end
@testset "Voltage-source network replay, bases, gauge and corruption" begin
    plants=[vsplant(),vsplant(generator_id=2,terminal_bus=2)]
    c=vscase();r=solve_voltage_source_opf(c,plants;frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(c,r).valid
    @test sum(r.opf.state.pg)>1.2 # Physical network branch losses.
    for (base,reference) in ((200.,1),(100.,2))
        cc=vscase(;base,reference)
        rr=solve_voltage_source_opf(cc,plants;frequency_bounds=(48.,52.))
        @test validate_voltage_source_opf(cc,rr).valid
        @test rr.opf.state.pg*base≈r.opf.state.pg*100 atol=1e-4
        @test rr.opf.state.vm≈r.opf.state.vm atol=1e-6
        @test rr.frequency_hz≈r.frequency_hz atol=1e-6
    end
    fixed=solve_voltage_source_opf(c,[plants[1]];frequency_hz=50.)
    @test validate_voltage_source_opf(c,fixed).valid
    @test fixed.opf.state.pg[1]≈.5 atol=1e-6
    for (ev,ff) in ((r.internal_voltage.*1.01,r.frequency_hz),(r.internal_voltage,r.frequency_hz+.1),
        ([complex(NaN,0.),r.internal_voltage[2]],r.frequency_hz))
        corrupt=VoltageSourceResult(r.opf,r.plants,r.inverters,r.responses,ev,ff,r.frequency_bounds,true)
        @test !validate_voltage_source_opf(c,corrupt).valid
    end
    for pp in ([plants[1],plants[1]],[vsplant(generator_id=99)], [vsplant(terminal_bus=2)])
        @test_throws ArgumentError solve_voltage_source_opf(c,pp)
    end
    @test_throws ArgumentError solve_voltage_source_opf(c,[plants[1]];frequency_bounds=(48.,52.))
    @test_throws ArgumentError solve_voltage_source_opf(c,plants;frequency_bounds=(52.,48.))
    offline=vscase(online=false,load=.8)
    ro=solve_voltage_source_opf(offline,plants;frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(offline,ro).valid
    @test ro.internal_voltage[2]==0
    @test abs(ro.opf.state.pg[2])<1e-8
    law=GeneratorFrequencyResponse(generator_id=2,p_ref=.5,gain_pu_per_hz=.5,f_ref_hz=50.)
    mixed=solve_voltage_source_opf(c,[plants[1]];responses=[law],frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(c,mixed).valid
end
@testset "Voltage-source envelopes and mixed static fleet" begin
    c=vscase();plants=[vsplant(),vsplant(generator_id=2,terminal_bus=2)]
    r=solve_voltage_source_opf(c,plants;frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(c,r).valid
    for kw in ((;i_max=.1),(;s_max=.1),(;p_available=.1),(;u_bounds=(1.1,1.2)),(;e_bounds=(1.,1.2)))
        changed=[vsplant(;kw...),plants[2]]
        corrupt=VoltageSourceResult(r.opf,changed,r.inverters,r.responses,r.internal_voltage,r.frequency_hz,r.frequency_bounds,true)
        @test !validate_voltage_source_opf(c,corrupt).valid
    end
    warm=solve_voltage_source_opf(c,plants;frequency_bounds=(48.,52.),initial_state=r.opf.state)
    @test validate_voltage_source_opf(c,warm).valid
    @test warm.frequency_hz≈r.frequency_hz atol=1e-6
    gfl=StaticInverter(generator_id=2,terminal_bus=2,mode=:gfl,priority=:active,q_control=:fixed_q,
        base_mva=100.,terminal_base_kv=20.,i_max=2.,s_max=2.,p_available=2.,p_ref=.5,q_ref=.05,
        v_ref=1.,q_droop=.05,f_ref_hz=50.,p_droop_hz=2.,reactive_available=true)
    mixed=solve_voltage_source_opf(c,[plants[1]];inverters=[gfl],frequency_bounds=(48.,52.))
    @test validate_voltage_source_opf(c,mixed).valid
    @test mixed.opf.state.pg[2]≈.5 atol=1e-6
    stressed=vscase(online=false)
    rejected=solve_voltage_source_opf(stressed,plants;frequency_bounds=(48.,52.),optimizer_attributes=Dict("max_iter"=>100))
    @test !validate_voltage_source_opf(stressed,rejected).valid
end
