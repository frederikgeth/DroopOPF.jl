@testset "Local RAW time series" begin
    mktempdir() do dir
        text=read(joinpath(@__DIR__,"data","psse","synthetic_v33.raw"),String)
        write(joinpath(dir,"01.raw"),text)
        write(joinpath(dir,"02.RAW"),replace(text,"62,21,80"=>"63,22,80","60,20"=>"65,23"))
        s=load_psse_series(dir;duration_hours=[.5,1.5])
        @test length(s.study.cases)==2
        @test s.study.duration_hours==[.5,1.5]
        @test s.imports[2].initial_state.pg==[.63]
        @test s.study.cases[2].generators[1].initial_p==.63
        @test s.study.cases[2].loads[1].p==.65
        reverse_order=load_psse_series(dir;files=["02.RAW","01.raw"])
        @test reverse_order.imports[1].initial_state.pg==[.63]
        @test s.study.cases[1].network.branches==s.study.cases[2].network.branches
        d=psse_series_diagnostic(s)
        @test Set(keys(d))==Set(["schema","import_status","saved_replay","security_status"])
        @test !occursin(dir,JSON.json(d))
        @test !occursin("SLACK",JSON.json(d))
        @test_throws ArgumentError load_psse_series(dir;files=["../01.raw"])
        @test_throws ArgumentError load_psse_series(dir;files=["01.raw","01.raw"])
        @test_throws ArgumentError load_psse_series(dir;duration_hours=[1.])
        @test_throws ArgumentError load_psse_series(dir;require_valid=true)
        write(joinpath(dir,"02.RAW"),replace(text,"150,0,1"=>"160,0,1"))
        @test_throws ArgumentError load_psse_series(dir)
        write(joinpath(dir,"02.RAW"),replace(text,".01,.1,.02"=>".02,.1,.02"))
        @test_throws ArgumentError load_psse_series(dir)
        rm(joinpath(dir,"02.RAW"));symlink(joinpath(dir,"01.raw"),joinpath(dir,"02.raw"))
        @test_throws ArgumentError load_psse_series(dir)
    end
end

@testset "RAW change inspection and supplied commitment" begin
    mktempdir() do dir
        text=read(joinpath(@__DIR__,"data","psse","synthetic_v33.raw"),String)
        off=replace(text,"0,.1,0,0,1,1,100,150"=>"0,.1,0,0,1,0,100,150")
        @test off!=text
        write(joinpath(dir,"01.raw"),text);write(joinpath(dir,"02.raw"),off)
        s=load_psse_series(dir)
        @test s.study.cases[1].generators[1].available
        @test !s.study.cases[2].generators[1].available
        report=inspect_psse_series(s)
        @test s.changes==report.changes
        @test any(c->c.section==:generator && c.field==:STAT && c.before==1 && c.after==0 && c.category==:major,report.changes)
        @test inspect_psse_series(dir).changes==report.changes
        write(joinpath(dir,"02.raw"),replace(text,"62,21,80"=>"63,22,80","60,20"=>"65,23"))
        op=inspect_psse_series(dir)
        @test all(c.category==:operating_point for c in op.changes)
        @test length(op.changes)==4
        # Inspection remains available when strict optimization import is rejected.
        write(joinpath(dir,"02.raw"),replace(text,".01,.1,.02"=>".02,.1,.02","SLACK / O''Brien"=>"<script>alert(1)</script>"))
        changed=inspect_psse_series(dir)
        @test any(c->c.section==:branch && c.field==:R && c.category==:major,changed.changes)
        @test_throws ArgumentError load_psse_series(dir)
        io=IOBuffer();write_psse_series_inspection(io,changed);html=String(take!(io))
        @test occursin("&lt;script&gt;alert(1)&lt;/script&gt;",html)
        @test !occursin("<script>alert(1)</script>",html)
        @test occursin("default-src 'none'",html)
        @test occursin("Include load, dispatch",html)
        @test !occursin("https://",html)
        @test all(c.category==:major for c in changed.changes)
        write(joinpath(dir,"02.raw"),replace(text,"1,'G1'"=>"1,'G2'"))
        @test count(c->c.section==:generator && c.field==:record,inspect_psse_series(dir).changes)==2
    end
end

@testset "Per-period generator commitment is enforced in native models" begin
    function commitment_case(online)
        Case("commitment";base_power=100.,base_frequency=50.,network=ACNetwork([Bus(1;reference=true)],Branch[]),
            loads=[Load(1,1;p=.5,q=.1)],controls=VoltVarDroop[],
            attachments=GeneratorControlAttachment[],
            generators=[Generator(1,1;p_min=0.,p_max=2.,q_min=-1.,q_max=1.),
                Generator(2,1;available=online,p_min=0.,p_max=1.,q_min=-1.,q_max=1.)])
    end
    cs=[commitment_case(true),commitment_case(false),commitment_case(true)]
    study=MultiPeriodStudy(cs)
    result=optimize_multi_period(study;optimizer_attributes=Dict("tol"=>1e-9,"max_cpu_time"=>20.))
    @test validate_multi_period(study,result).valid
    @test abs(result.periods[2].state.pg[2])<1e-8
    @test abs(result.periods[2].state.qg[2])<1e-8
end

@testset "RAW zone extraction, boundary conservation and reference report" begin
    mktempdir() do dir
        text=read(joinpath(@__DIR__,"data","psse","synthetic_v33.raw"),String)
        # BUS 1 is zone 4, with original system reference outside zone 4.
        text=replace(text,"220,3,1,1,1"=>"220,2,1,4,1","110,1,1,1,1"=>"110,3,1,1,1")
        genline=only(filter(l->startswith(l,"1,'G1'"),split(text,'\n')))
        g2=replace(genline,"'G1'"=>"'G2'","150,0,1"=>"200,0,1")
        g3=replace(genline,"1,'G1'"=>"2,'EXTERNAL'","150,0,1"=>"300,0,1")
        text=replace(text,genline=>join([genline,g2,g3],"\n"))
        write(joinpath(dir,"01.raw"),text)
        write(joinpath(dir,"02.raw"),replace(text,"1.02,5,1.1"=>"1.03,6,1.1"))
        series=load_psse_series(dir;zone=4)
        @test length(series.study.cases[1].network.buses)==1
        @test isempty(series.study.cases[1].network.branches)
        @test length(series.study.cases[1].generators)==2
        report=series.build_reports[1]
        @test report["zone"]==4
        @test report["reference_generator_id"]==2
        @test report["reference_bus"]==1
        @test report["reference_pmax_mw"]==200.
        @test report["nodal_balance_preservation_error_pu"]<1e-12
        @test length(report["boundary_exchanges"])==2
        @test series.initial_states[1].va==[0.]
        @test length(series.initial_states[1].pg)==2
        @test length(series.imports[1].initial_state.pg)==3
        full=series.imports[1];flows=branch_flows(full.case.network,full.initial_state)
        @test series.study.cases[1].loads[1].p≈real(flows.from[1])
        @test series.study.cases[1].loads[1].q≈imag(flows.from[1])
        @test series.study.cases[1].loads[1].p!=series.study.cases[2].loads[1].p
        other=extract_psse_zone(full;zone=1)
        equiv=filter(l->l.id>maximum(x.id for x in full.case.loads),other.case.loads)
        @test equiv[1].p≈real(flows.to[1])
        @test equiv[1].q≈imag(flows.to[1])
        @test other.report["reference_generator_id"]==3
        @test_throws ArgumentError extract_psse_zone(full;zone=999)
        io=IOBuffer();write_psse_series_build_report(io,series)
        @test occursin("reference_generator_id",String(take!(io)))
        write_psse_series_inspection(io,series)
        @test occursin("Network build report",String(take!(io)))
        @test !occursin("reference_generator_id",JSON.json(psse_series_diagnostic(series)))
        studies=[Study(c;contingencies=[Contingency(:g1;generator_ids=[1])]) for c in series.study.cases]
        secured=optimize_psse_series_security(series,studies;
            optimizer_attributes=Dict("tol"=>1e-9,"max_cpu_time"=>20.))
        @test validate_multi_period_security(studies,secured).valid
        @test !secured.emergency
        @test all(isempty,secured.relief)
        @test_throws ArgumentError optimize_psse_series_security(series,studies;s2_emergency=true)
        @test_throws ArgumentError optimize_psse_series_security(series,[Study(full.case),Study(full.case)])
        # Offline largest unit retains the common angle gauge, not dispatch freedom.
        write(joinpath(dir,"02.raw"),replace(text,g2=>replace(g2,"0,.1,0,0,1,1,100"=>"0,.1,0,0,1,0,100")))
        off=load_psse_series(dir;zone=4)
        @test off.build_reports[2]["reference_generator_id"]==2
        @test !off.build_reports[2]["reference_generator_online"]
        # Changing zone membership is a model change, never silently merged.
        write(joinpath(dir,"02.raw"),replace(text,"110,3,1,1,1"=>"110,3,1,4,1"))
        @test_throws ArgumentError load_psse_series(dir;zone=4)
    end
end

@testset "Generator technology CSV and exploratory IBR Volt-VAR estimation" begin
    mktempdir() do dir
        raw=read(joinpath(@__DIR__,"data","psse","synthetic_v33.raw"),String)
        raw=replace(raw,"220,3,1,1,1"=>"220,3,1,4,1")
        csv=joinpath(dir,"technology.csv")
        write(csv,"\ufeffbus_number,bus_name,technology\r\n1,\"SLACK / O'Brien\",ibr_unidentified\r\n")
        @test read_psse_generator_csv(csv)[1].technology=="ibr_unidentified"
        for (i,v) in enumerate([.98,.99,.995,1.,1.005,1.01,1.02])
            q=(.1-(v-1.)/.05)*100
            text=replace(raw,"1.02,5,1.1"=>"$v,5,1.1","62,21,80"=>"62,$q,80")
            write(joinpath(dir,"$i.raw"),text)
        end
        s=load_psse_series(dir;zone=4,generator_csv=csv)
        @test length(s.ibr_fits)==1
        fit=only(s.ibr_fits)
        @test fit["status"]=="candidate_partial_range"
        @test !fit["full_curve_identified"]
        @test fit["rmse_mvar"]<1e-8
        @test fit["candidate_curve"]["slope_v_per_q_pu"]≈.05 atol=1e-10
        @test length(fit["observations"])==7
        @test all(isempty(c.controls) for c in s.study.cases)
        @test s.generator_technologies[1][1]["technology"]=="ibr_unidentified"
        @test haskey(s.build_reports[1],"ibr_fit_details")
        @test !haskey(s.build_reports[2],"ibr_fit_details")
        @test !occursin("ibr",JSON.json(psse_series_diagnostic(s)))
        io=IOBuffer();write_psse_series_inspection(io,s);html=String(take!(io))
        @test occursin("<svg",html)
        @test occursin("slope_v_per_q_pu",html)
        @test !occursin("https://",html)
        @test load_psse_series(dir;generator_csv=csv,files=["1.raw"]).ibr_fits[1]["status"]=="insufficient_data"
        for tech in ("synchronous_generator","synchronous_condenser")
            write(csv,"bus_number,bus_name,technology\n1,\"SLACK / O'Brien\",$tech\n")
            @test isempty(load_psse_series(dir;generator_csv=csv).ibr_fits)
        end
        write(csv,"bus_number,bus_name,technology\n1,wrong,ibr_unidentified\n")
        @test_throws ArgumentError load_psse_series(dir;generator_csv=csv)
        write(csv,"bus_number,bus_name,technology\n1,name,unknown\n")
        @test_throws ArgumentError read_psse_generator_csv(csv)
        write(csv,"bus_number,bus_name,technology\n1,\"name, with \"\"quotes\"\"\",synchronous_generator\n")
        @test read_psse_generator_csv(csv)[1].bus_name=="name, with \"quotes\""
        write(csv,"bus_number,bus_name,technology\n1,\"line\nname\",synchronous_generator\n")
        @test read_psse_generator_csv(csv)[1].bus_name=="line\nname"
        write(csv,"bus_number,bus_name,technology\n1,\"unterminated,synchronous_generator")
        @test_throws ArgumentError read_psse_generator_csv(csv)
        @test_throws ArgumentError load_psse_series(dir;ibr_fit_options=(minimum_points=2,))
        # One row per RAW generator ID is required at a multi-unit bus.
        genline=only(filter(l->startswith(l,"1,'G1'"),split(raw,'\n')))
        write(joinpath(dir,"1.raw"),replace(raw,genline=>genline*"\n"*replace(genline,"'G1'"=>"'G2'")))
        write(csv,"bus_number,bus_name,technology\n1,\"SLACK / O'Brien\",ibr_unidentified\n")
        @test_throws ArgumentError load_psse_series(dir;files=["1.raw"],generator_csv=csv)
        write(csv,"bus_number,bus_name,technology,generator_id\n1,\"SLACK / O'Brien\",ibr_unidentified,G1\n1,\"SLACK / O'Brien\",synchronous_generator,G2\n")
        multiple=load_psse_series(dir;files=["1.raw"],generator_csv=csv)
        @test length(multiple.generator_technologies[1])==2
        @test length(multiple.ibr_fits)==1
    end
end

@testset "IBR identification coverage and inconclusive diagnostics" begin
    v=[.93,.94,.95,.96,.97,.98,.99,1.,1.01,1.02,1.03,1.04,1.05,1.06,1.07]
    q=[clamp(10*(max(.99-x,0.)-max(x-1.01,0.)),-.5,.5) for x in v]
    full=DroopOPF._psse_fit_voltvar(v,q,-.5,.5)
    @test full["status"]=="candidate_full_regime_coverage"
    @test full["candidate_curve"]["slope_v_per_q_pu"]≈.1 atol=1e-10
    @test full["rmse_q_pu"]<1e-10
    @test !full["full_curve_identified"]
    @test DroopOPF._psse_fit_voltvar(fill(1.,6),zeros(6),-.5,.5)["status"]=="insufficient_data"
    @test DroopOPF._psse_fit_voltvar(v,-q,-.5,.5)["candidate_curve"]===nothing
    @test DroopOPF._psse_fit_voltvar(v,fill(.5,length(v)),-.5,.5)["status"]=="insufficient_unsaturated_data"
    @test_throws ArgumentError DroopOPF._psse_fit_voltvar(v,q,-.5,.5;minimum_voltage_span=0.)
    @test_throws ArgumentError DroopOPF._psse_fit_voltvar(v,q,-.5,.5;maximum_grid_points=100)
    mktempdir() do dir
        raw=read(joinpath(@__DIR__,"data","psse","synthetic_v33.raw"),String)
        csv=joinpath(dir,"technology.csv")
        write(csv,"bus_number,bus_name,technology\n1,\"SLACK / O'Brien\",ibr_unidentified\n999,Absent,synchronous_generator\n")
        for (i,x) in enumerate([.98,.99,.995,1.,1.005,1.01,1.02])
            reactive=(.1-(x-1.)/.05)*100
            text=replace(raw,"1.02,5,1.1"=>"$x,5,1.1","62,21,80"=>"62,$reactive,80")
            write(joinpath(dir,"$i.raw"),text)
        end
        s=load_psse_series(dir;generator_csv=csv)
        @test length(s.build_reports[1]["unmatched_csv_rows"])==1
        p=joinpath(dir,"1.raw");text=read(p,String)
        write(p,replace(text,"0,.1,0,0,1,1,100"=>"0,.1,0,0,1,0,100"))
        offline=load_psse_series(dir;generator_csv=csv)
        @test offline.ibr_fits[1]["observations"][1]["reason"]=="offline"
        @test offline.ibr_fits[1]["online_usable_points"]==6
        write(p,replace(text,"1.02,0,100"=>"1.03,0,100"))
        changed=load_psse_series(dir;generator_csv=csv)
        @test changed.ibr_fits[1]["status"]=="control_settings_or_limits_changed"
        @test changed.ibr_fits[1]["candidate_curve"]===nothing
        # RAW IREG selects the recorded remote bus rather than terminal voltage.
        for file in filter(f->endswith(f,".raw"),readdir(dir;join=true))
            write(file,replace(read(file,String),"1.02,0,100"=>"1.02,2,100","1.03,0,100"=>"1.02,2,100"))
        end
        remote=load_psse_series(dir;generator_csv=csv)
        @test remote.ibr_fits[1]["status"]=="insufficient_data"
        @test all(o["voltage_bus"]==2 for o in remote.ibr_fits[1]["observations"])
    end
end

@testset "Classified series diagnostic exposes statuses only" begin
    mktempdir() do dir
        raw=read(joinpath(@__DIR__,"data","psse","synthetic_v33.raw"),String)
        write(joinpath(dir,"1.raw"),replace(raw,"220,3,1,1,1"=>"220,3,1,4,1"))
        csv=joinpath(dir,"generator-technology.csv")
        write(csv,"bus_number,bus_name,technology\n1,\"SLACK / O'Brien\",ibr_unidentified\n")
        series=load_psse_series(dir;zone=4,generator_csv=csv)
        status=psse_series_diagnostic(series)
        @test Set(keys(status))==Set(["schema","import_status","saved_replay","security_status"])
        @test status["import_status"]=="compatible"
        @test status["security_status"]=="not_run"
        text=JSON.json(status)
        for private_value in (dir,"SLACK","ibr_unidentified","generator_id","candidate_curve")
            @test !occursin(private_value,text)
        end
        # Only the typed series API can construct the minimal status object;
        # callers cannot pass a detailed report and claim it has been redacted.
        @test_throws MethodError psse_series_diagnostic(series.build_reports[1])
    end
end

@testset "CSV synchronous generators and condensers use source AVR" begin
    mktempdir() do dir
        raw=read(joinpath(@__DIR__,"data","psse","synthetic_v33.raw"),String)
        raw=replace(raw,"220,3,1,1,1"=>"220,3,1,4,1")
        generator=only(filter(l->startswith(l,"1,'G1'"),split(raw,'\n')))
        condenser=replace(generator,"'G1'"=>"'SC'","62,21,80"=>"0,0,80","150,0,1"=>"0,0,1")
        raw=replace(raw,generator=>generator*"\n"*condenser)
        csv=joinpath(dir,"technology.csv")
        write(csv,"bus_number,bus_name,technology,generator_id\n1,\"SLACK / O'Brien\",synchronous_generator,G1\n1,\"SLACK / O'Brien\",synchronous_condenser,SC\n")
        write(joinpath(dir,"1.raw"),raw)
        shifted=replace(raw,"1.02,0,100"=>"1.03,0,100")
        shifted=replace(shifted,replace(condenser,"1.02,0,100"=>"1.03,0,100")=>
            replace(condenser,"1.02,0,100"=>"1.04,0,100","0,.1,0,0,1,1,100"=>"0,.1,0,0,1,0,100"))
        write(joinpath(dir,"2.raw"),shifted)
        series=load_psse_series(dir;zone=4,generator_csv=csv)
        @test all(r["avr_policy"]["qualified"] for r in series.build_reports)
        @test all(length(a)==2 for a in series.reactive_assignments)
        @test all(a.mode isa AVR for a in series.reactive_assignments[1])
        @test series.reactive_assignments[1][1].mode.voltage_setpoint==1.02
        @test series.reactive_assignments[2][1].mode.voltage_setpoint==1.03
        @test series.reactive_assignments[2][2].mode.voltage_setpoint==1.04
        @test series.study.cases[1].generators[2].p_max==0.
        @test !series.study.cases[2].generators[2].available
        studies=psse_series_studies(series)
        @test studies[1].participation[2]==0.
        @test studies[1].participation[1]==studies[2].participation[1]
        @test !haskey(studies[2].participation,2)
        @test_throws ArgumentError optimize_psse_series_security(series,[Study(c) for c in series.study.cases])
        @test_throws ArgumentError psse_series_studies(series;participation=Dict(1=>1.,2=>1.))
        @test_throws ArgumentError optimize_multi_period_security(studies)
        result=optimize_psse_series_security(series;optimizer_attributes=Dict("tol"=>1e-9,"max_cpu_time"=>20.))
        @test validate_multi_period_security(studies,result).valid
        @test result.periods[1].states[:base].vm[1]≈1.02 atol=1e-6
        @test result.periods[2].states[:base].vm[1]≈1.03 atol=1e-6
        @test abs(result.periods[1].states[:base].pg[2])<1e-8
        @test abs(result.periods[2].states[:base].qg[2])<1e-8
        @test series.initial_states[2].vm[1]==1.02
        # A physical condenser label cannot silently leave dispatchable positive P.
        for file in ("1.raw","2.raw")
            text=read(joinpath(dir,file),String)
            sc=only(filter(l->startswith(l,"1,'SC'"),split(text,'\n')))
            write(joinpath(dir,file),replace(text,sc=>replace(sc,"100,0,0,1"=>"100,10,0,1")))
        end
        unqualified=load_psse_series(dir;zone=4,generator_csv=csv)
        @test !unqualified.build_reports[1]["avr_policy"]["qualified"]
        @test psse_series_diagnostic(unqualified)["import_status"]=="control_policy_unqualified"
        @test_throws ArgumentError psse_series_studies(unqualified)
        # A remote voltage measurement outside the zone is not replaced by terminal VM.
        for file in ("1.raw","2.raw")
            write(joinpath(dir,file),replace(raw,"1.02,0,100"=>"1.02,2,100"))
        end
        remote=load_psse_series(dir;zone=4,generator_csv=csv)
        @test all(x["status"]=="regulated_bus_outside_model" for x in remote.build_reports[1]["avr_policy"]["assignments"])
        @test_throws ArgumentError psse_series_studies(remote)
        full=load_psse_series(dir;generator_csv=csv)
        @test all(a.location.bus_id==2 for a in full.reactive_assignments[1])
        @test full.build_reports[1]["avr_policy"]["qualified"]
    end
end
