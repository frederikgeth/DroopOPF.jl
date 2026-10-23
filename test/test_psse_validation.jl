using JSON
@testset "PSS/E saved power-flow check on load" begin
    mktempdir() do dir
        for v in (33,34,36)
            text=read(joinpath(@__DIR__,"data/psse/synthetic_v$v.raw"),String)
            imported=import_psse_case(parse_psse_raw(IOBuffer(text)))
            b=power_balance(imported.case,imported.initial_state)
            # Construct a saved equilibrium analytically from terminal currents;
            # no optimizer or hidden dispatch recovery is used by this test.
            p=62-100b.active[1];q=21-100b.reactive[1]
            pl=60+100b.active[2];ql=20+100b.reactive[2]
            balanced=replace(text,"62,21,80,-50"=>"$p,$q,80,-50","60,20,0,0"=>"$pl,$ql,0,0")
            path=joinpath(dir,"balanced-$v.raw");write(path,balanced)
            report=check_psse_file(path;verbose=false)
            @test report["valid"]
            @test report["status"]=="passed"
            @test report["power_flow_consistent"]
            @test report["thermal_coverage_complete"]
            @test report["max_p_mismatch_mw"]<1e-10
            @test report["max_q_mismatch_mvar"]<1e-10
            @test length(report["branch_flows"])==2
            @test report["optimization_performed"]===false
            @test report["branch_flows"][2]["source_id"]==["transformer",1,2,"T1"]
            output=joinpath(dir,"report-$v.json")
            c=load_psse_case(path;require_valid=true,report_path=output)
            @test length(c.network.buses)==2
            @test_throws ArgumentError check_psse_file(path;report_path=path,verbose=false)
            @test_throws ArgumentError load_psse_case(path;report_path=path)
            @test read(path,String)==balanced
            @test JSON.parsefile(output)["valid"]
            @test JSON.parsefile(output)["source_file_sha256"]==report["source_file_sha256"]
            @test_throws ArgumentError check_psse_file(path;verbose=false,power_tolerance_mw=-1.)
            @test_throws ArgumentError check_psse_file(path;verbose=false,top_buses=0)
            @test_throws ArgumentError check_psse_file(path;verbose=false,unknown_option=1)
            @test_throws ArgumentError load_psse_case(path;check_saved_solution=false,require_valid=true)
            @test length(load_psse_case(path;check_saved_solution=false).generators)==1
            bad=joinpath(dir,"bad-$v.raw")
            write(bad,replace(balanced,"$p,$q,80,-50"=>"$(p+1),$q,80,-50"))
            failed=check_psse_file(bad;verbose=false)
            @test !failed["valid"]
            @test failed["status"]=="power_flow_mismatch"
            @test failed["max_p_mismatch_mw"]≈1. atol=1e-10
            @test failed["worst_buses"][1]["bus_id"]==1
            @test_throws ArgumentError load_psse_case(bad;require_valid=true)
            # The checker reports Q limits separately from correct saved AC balance.
            write(bad,replace(balanced,",80,-50,"=>",0,0,"))
            limited=check_psse_file(bad;verbose=false)
            @test limited["power_flow_consistent"]
            @test !limited["known_limits_valid"]
            @test limited["status"]=="limits_violated"
            # Unknown ratings never gain meaning from the internal replay marker.
            write(bad,replace(balanced,"100,110,120"=>"0,110,120"))
            unrated=check_psse_file(bad;verbose=false)
            @test unrated["power_flow_consistent"]
            @test !unrated["thermal_coverage_complete"]
            @test unrated["status"]=="limits_unassessed"
            @test all(r["normal_rating_mva"]===nothing for r in unrated["branch_flows"])
            @test_throws ArgumentError load_psse_case(bad)
            # Dropping saved Vm/Va cannot validate substituted defaults as a solution.
            write(bad,replace(balanced,"1.02,5,1.1,.9,1.1,.9"=>",,1.1,.9,1.1,.9"))
            missing=check_psse_file(bad;verbose=false)
            @test missing["status"]=="missing_saved_solution"
            @test !missing["saved_state_complete"]
            @test !isempty(missing["missing_saved_fields"])
            # Original topology/tap and shunt mistakes must be detected.
            write(bad,replace(balanced,"1.05,220,5"=>".95,220,5"))
            @test !check_psse_file(bad;verbose=false)["power_flow_consistent"]
            write(bad,replace(balanced,"'F1',1,1,2"=>"'F1',1,1,-2"))
            @test !check_psse_file(bad;verbose=false)["power_flow_consistent"]
            write(bad,replace(balanced,"$pl,$ql,0,0"=>"$(pl+1),$ql,0,0"))
            @test !check_psse_file(bad;verbose=false)["power_flow_consistent"]
        end
        malformed=joinpath(dir,"malformed.raw");write(malformed,"not a RAW file")
        output=joinpath(dir,"invalid.json")
        @test check_psse_file(malformed;verbose=false,report_path=output)["status"]=="invalid_file"
        @test JSON.parsefile(output)["valid"]===false
        unknown=replace(read(joinpath(@__DIR__,"data/psse/synthetic_v33.raw"),String),
            "Q\n"=>"0 / END OF INDUCTION MACHINE DATA, BEGIN VSC DC LINE DATA\n'LINK',1,2\nQ\n")
        write(malformed,unknown)
        @test check_psse_file(malformed;verbose=false)["status"]=="unsupported"
        @test check_psse_file(malformed;verbose=false)["power_flow_consistent"]===nothing
        @test check_psse_file(joinpath(dir,"absent.raw");verbose=false)["status"]=="invalid_file"
    end
end
