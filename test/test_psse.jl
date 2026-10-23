using LinearAlgebra, SHA, JSON
const PSSE_TEST_DATA=joinpath(@__DIR__,"data","psse")
psse_fixture(v)=read(joinpath(PSSE_TEST_DATA,"synthetic_v$v.raw"),String)
psse_parse(text)=parse_psse_raw(IOBuffer(text);source="test.raw")
@testset "PSS/E RAW versioned parsing and strict AC import" begin
    cases=Case[]
    for v in (33,34,36)
        text=psse_fixture(v);d=psse_parse(text);r=import_psse_case(d);c=r.case
        push!(cases,c)
        @test d.revision==v
        @test d.base_power==100.
        @test d.base_frequency==50.
        @test d.text==text
        @test length(d.sections[:bus])==2
        @test d.sections[:bus][1].fields[:NAME]=="SLACK / O'Brien"
        @test d.sections[:bus][2].fields[:NAME]=="LOAD, EAST"
        @test d.sections[:generator][1].fields[:STAT]==1
        @test d.sections[:generator][1].fields[:PT]==150
        @test d.sections[:generator][1].fields[:MBASE]==100
        @test length(d.sections[:transformer][1].rows)==4
        @test length(d.sections[:transformer][1].lines)==4
        @test c.base_frequency==50.
        @test c.generators[1].p_max==1.5
        @test c.loads[1].p==.6
        @test c.loads[1].q==.2
        @test c.network.shunts[1].conductance==.01
        @test c.network.shunts[1].susceptance==.02
        @test c.network.shunts[2].susceptance==.1
        @test r.source_ids[:generator][1]==(1,"G1")
        @test r.source_ids[:branch][2]==(:transformer,1,2,"T1")
        @test r.initial_state.pg==[.62]
        @test r.initial_state.va[1]==0.
        @test r.initial_state.va[2]≈deg2rad(-3.)
        t=c.network.branches[2]
        @test t.tap_ratio≈1.05/.98
        @test t.resistance≈.01*.98^2
        @test t.reactance≈.2*.98^2
        @test t.phase_shift≈deg2rad(5.)
        @test !isempty(r.diagnostics)
        @test load_psse_case(joinpath(PSSE_TEST_DATA,"synthetic_v$v.raw")).loads[1].p==.6
        if v==36
            @test d.sections[:generator][1].fields[:NREG]==9
            @test d.sections[:generator][1].fields[:DROOPNAME]=="DROOP / A"
            @test d.sections[:load][1].fields[:LOADTYPE]=="INDUSTRIAL"
            @test d.sections[:fixed_shunt][1].fields[:NAME]=="SHUNT / EAST"
            @test d.sections[:branch][1].fields[:BP]==0
            @test d.sections[:branch][1].fields[:MET]==1
            @test d.sections[:switched_shunt][1].fields[:NREG]==8
            @test d.sections[:switched_shunt][1].fields[:NAME]=="CAP / 1"
        elseif v==34
            @test d.sections[:generator][1].fields[:NREG]==7
        end
    end
    # All three schemas describe exactly the same electrical circuit.
    @test DroopOPF._json_data(cases[1])==DroopOPF._json_data(cases[2])==DroopOPF._json_data(cases[3])
    text=psse_fixture(33)
    @test psse_parse(replace(text,".01,.1,.02"=>"1D-2,1d-1,2E-2")).sections[:branch][1].fields[:R]==.01
    @test psse_parse("\ufeff"*replace(text,"\n"=>"\r\n")).revision==33
    @test DroopOPF._psse_tokens("1 'two words / A' 3 / comment")==["1","two words / A","3"]
    @test DroopOPF._psse_tokens("1,,3, / comment")==["1","","3",""]
    @test DroopOPF._psse_tokens("1,\"A, B / C\",2")==["1","A, B / C","2"]
    @test_throws ArgumentError DroopOPF._psse_tokens("1,'bad")
    @test_throws ArgumentError psse_parse(replace(text,"0,100,33"=>"1,100,33"))
    @test_throws ArgumentError psse_parse(replace(text,"0,100,33"=>"0,100,35"))
    @test_throws ArgumentError psse_parse(replace(text,"0,100,33"=>"0,-100,33"))
    @test_throws ArgumentError psse_parse(replace(text,"0,100,33"=>"0,100,33.5"))
    @test_throws ArgumentError psse_parse(replace(text,".01,.1,.02"=>"NaN,.1,.02"))
    @test_throws ArgumentError psse_parse(replace(text,".01,.1,.02"=>"BAD,.1,.02"))
    @test_throws ArgumentError psse_parse(first(split(text,"0 / END OF BRANCH")))
    @test_throws ArgumentError psse_parse(replace(text,".98,110\n"=>""))
    @test_throws ArgumentError psse_parse(text*"1,2,3\n")
    @test_throws ArgumentError parse_psse_raw(IOBuffer(text);encoding=:bad)
    latin=replace(text,"SLACK / O''Brien"=>"CAFÉ");bytes=UInt8[Int(c) for c in latin]
    @test parse_psse_raw(IOBuffer(bytes);encoding=:latin1).sections[:bus][1].fields[:NAME]=="CAFÉ"
    @test_throws ArgumentError parse_psse_raw(IOBuffer(bytes))
    # Empty optional fields retain their position and use explicit RAW defaults.
    @test psse_parse(replace(text,"62,21,80"=>"62,,80")).sections[:generator][1].fields[:QT]==80
    @test !haskey(psse_parse(replace(text,"62,21,80"=>"62,,80")).sections[:generator][1].fields,:QG)
    # Unsupported electrical records and unknown sections cannot vanish in import.
    unknown=psse_parse(replace(text,"Q\n"=>"0 / END OF INDUCTION MACHINE DATA, BEGIN MYSTERY DATA\n'X / A',2,3\nQ\n"))
    @test haskey(unknown.sections,:mystery)
    @test unknown.sections[:mystery][1].rows[1][1]=="X / A"
    @test_throws ArgumentError import_psse_case(unknown)
    dc=psse_parse(replace(text,"Q\n"=>"0 / END OF INDUCTION MACHINE DATA, BEGIN VSC DC LINE DATA\n'LINK',1,2\nQ\n"))
    @test_throws ArgumentError import_psse_case(dc)
    duplicate=replace(text,"0 / END OF BUS"=>"1,'DUP',220,1\n0 / END OF BUS")
    @test_throws ArgumentError import_psse_case(psse_parse(duplicate))
    @test_throws ArgumentError import_psse_case(psse_parse(replace(text,"1,2,'A'"=>"1,999,'A'")))
    @test_throws ArgumentError import_psse_case(psse_parse(replace(text,"0,100,33,0,0"=>"0,100,33,1,0")))
    unrated=psse_parse(replace(text,"100,110,120,0,0,0,0,1"=>"0,110,120,0,0,0,0,1"))
    @test_throws ArgumentError import_psse_case(unrated)
    @test import_psse_case(unrated;unrated_limit=7.).case.network.branches[1].thermal_limit==7.
    @test_throws ArgumentError import_psse_case(unrated;unrated_limit=Inf)
    @test_throws ArgumentError import_psse_case(psse_parse(replace(text,"60,20,0,0,0,0"=>"60,20,2,0,0,0")))
    impedance=import_psse_case(psse_parse(replace(text,"60,20,0,0,0,0"=>"60,20,0,0,2,3")))
    @test impedance.case.network.shunts[1].conductance==.02
    @test impedance.case.network.shunts[1].susceptance==-.03
    @test_throws ArgumentError import_psse_case(psse_parse(replace(text,"0,0,0,0,1,1,0,1,1"=>".01,0,0,0,1,1,0,1,1")))
    named=psse_parse(replace(text,"1,2,'A'"=>"'SLACK 220',2,'A'"))
    @test named.sections[:branch][1].fields[:I]=="SLACK 220"
    @test_throws ArgumentError import_psse_case(named)
    modern=psse_parse(psse_fixture(36));modern.sections[:branch][1].fields[:BP]=1
    @test_throws ArgumentError import_psse_case(modern)
    @test_throws ArgumentError import_psse_case(psse_parse(replace(text,"'L1',1,1,1"=>"'L1',3,1,1")))
    mag=psse_parse(text);mag.sections[:transformer][1].fields[:MAG1]=.01
    @test_throws ArgumentError import_psse_case(mag)
    rawextra=psse_parse(replace(text,"SLACK / O''Brien',220,3,1,1,1,1.02,5,1.1,.9,1.1,.9"=>"SLACK / O''Brien',220,3,1,1,1,1.02,5,1.1,.9,1.1,.9,'EXTRA / INFO'"))
    @test rawextra.sections[:bus][1].fields[:extra_fields]==["EXTRA / INFO"]
    three=replace(text,"1,2,0,'T1'"=>"1,2,3,'T1'", ".01,.2,50\n"=>".01,.2,50,.02,.3,50,.04,.5,50,1.,0.\n", ".98,110\n"=>".98,110,0,100,110,120\n1.,110,0,100,110,120\n")
    t3=psse_parse(three)
    @test length(t3.sections[:transformer][1].rows)==5
    @test t3.sections[:transformer][1].fields[:K]==3
    @test_throws ArgumentError import_psse_case(t3)
    # Native equal-Q limits are preserved without widening them.
    fixedq=import_psse_case(psse_parse(replace(text,"62,21,80,-50"=>"62,0,0,0")))
    @test fixedq.case.generators[1].q_min==fixedq.case.generators[1].q_max==0.
    @test fixedq.initial_state.qg==[0.]
    fixed_case=Case("fixed-Q import support";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=true),Bus(2)],
            [Branch(1,1,2;resistance=.01,reactance=.1,thermal_limit=2.)]),
        generators=[Generator(1,1;p_min=0.,p_max=1.,q_min=0.,q_max=0.,initial_p=.3),
            Generator(2,2;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,initial_q=.1)],
        loads=[Load(1,2;p=.3,q=.1)],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    fixed_solution=solve_opf(fixed_case;smooth_epsilon=1e-6)
    @test fixed_solution.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
    @test validate_equilibrium(fixed_case,fixed_solution).valid
    @test fixed_solution.state.qg[1]==0.
    # Cross-base impedance and both winding ratios, checked against a direct
    # two-port current primitive (independent of the importer's Branch builder).
    for cw in 1:3,cz in 1:3
        raw=psse_parse(text);f=raw.sections[:transformer][1].fields
        f[:CW]=cw;f[:CZ]=cz;f[:NOMV_1]=230.;f[:NOMV_2]=115.
        f[:WINDV_1]=cw==2 ? 231. : 1.05;f[:WINDV_2]=cw==2 ? 107.8 : .98
        f[:R12]=cz==3 ? 50000. : .01
        znom=cz==3 ? complex(.001,sqrt(.2^2-.001^2)) : complex(.01,.2)
        znom*=cz==1 ? 1. : (100/50)*(230/220)^2
        a=cw==1 ? 1.05 : cw==2 ? 231/220 : 1.05*230/220
        b=cw==1 ? .98 : cw==2 ? 107.8/110 : .98*115/110
        phi=deg2rad(5.);tap=complex(cos(phi),sin(phi))*a
        expected=ComplexF64[1/(znom*abs2(tap)) -1/(znom*conj(tap)*b);-1/(znom*tap*b) 1/(znom*b^2)]
        tr=import_psse_case(raw).case.network.branches[2]
        z=complex(tr.resistance,tr.reactance);t=tr.tap_ratio*cis(tr.phase_shift)
        actual=ComplexF64[1/(z*abs2(t)) -1/(z*conj(t));-1/(z*t) 1/z]
        @test actual≈expected atol=1e-12
    end
    # Public native exports exercise actual v33 and v34 section ordering.
    source=joinpath(@__DIR__,"data/arpae/c1_network01/scenario_01/case.raw")
    native=parse_psse_raw(source);imported=import_psse_case(native)
    @test native.revision==33
    @test length(native.sections[:bus])==15
    @test length(imported.case.network.buses)==14
    @test length(native.sections[:transformer])==4
    public=joinpath(PSSE_TEST_DATA,"public_v34_ieee14.raw")
    provenance=JSON.parsefile(joinpath(PSSE_TEST_DATA,"PROVENANCE.json"))
    @test bytes2hex(sha256(read(public)))==provenance["sha256"]
    raw=parse_psse_raw(public);c=import_psse_case(raw;unrated_limit=1e6).case
    @test raw.revision==34
    @test length(c.network.buses)==14
    @test length(c.generators)==5
    @test length(c.network.branches)==20
    @test raw.sections[:branch][1].fields[:ST]==1
    @test c.network.branches[end].tap_ratio≈.87976
    @test c.network.branches[end].phase_shift≈deg2rad(2.541)
end
