isdefined(@__MODULE__, :scopf_parallel_case) || include(joinpath(@__DIR__,"..","examples","scopf_validation_cases.jl"))
@testset "Bounded threaded contingency assessment" begin
    case=scopf_parallel_case();base=scopf_validation_base(case).state
    @test_throws ArgumentError assess_contingency_pipeline(case,base;workers=0)
    @test_throws ArgumentError assess_contingency_pipeline(case,base;workers=Threads.nthreads()+1)
    if Threads.nthreads() >= 2
        serial=assess_contingency_pipeline(case,base;screening_enabled=false,sparse_balance=true)
        callbacks=Symbol[];owner=current_task()
        threaded=assess_contingency_pipeline(case,base;workers=2,screening_enabled=false,sparse_balance=true,
            _assessment_callback=a->begin
                @test current_task()===owner
                push!(callbacks,a.entry.contingency.id)
            end)
        @test callbacks==[a.entry.contingency.id for a in serial.assessments]
        @test threaded.checks==serial.checks
        @test [a.rank.classification for a in threaded.assessments]==[a.rank.classification for a in serial.assessments]
        for (a,b) in zip(serial.assessments,threaded.assessments)
            @test b.exact_assessment.report.valid
            for id in keys(a.exact_assessment.result.states),field in (:vm,:va,:pg,:qg)
                @test getproperty(a.exact_assessment.result.states[id],field) ≈ getproperty(b.exact_assessment.result.states[id],field) atol=1e-8
            end
        end
        active=Threads.Atomic{Int}(0);peak=Threads.Atomic{Int}(0)
        hook=model->begin
            n=Threads.atomic_add!(active,1)+1;Threads.atomic_max!(peak,n)
            try
                sleep(.03)
                error("intentional worker failure")
            finally
                Threads.atomic_sub!(active,1)
            end
        end
        failed=assess_contingency_pipeline(case,base;workers=2,screening_enabled=false,_model_hook=hook)
        @test failed.checks.error_count==length(failed.assessments)
        @test peak[]==2 && active[]==0
        @test_throws ErrorException assess_contingency_pipeline(case,base;workers=2,screening_enabled=false,continue_on_error=false,_model_hook=hook)
        @test active[]==0
        mktempdir() do dir
            @test_throws InterruptException run_contingency_campaign(dir,case,base;workers=2,
                screening_enabled=false,sparse_balance=true,on_checkpoint=a->throw(InterruptException()))
            @test !ispath(joinpath(dir,".campaign-lock"))
            resumed=run_contingency_campaign(dir,case,base;workers=2,screening_enabled=false,sparse_balance=true)
            @test resumed.resumed_count==1
            @test resumed.evaluated_count==3
            @test resumed.result.checks==serial.checks
            @test_throws ArgumentError run_contingency_campaign(dir,case,base;workers=1,screening_enabled=false,sparse_balance=true)
            @test run_contingency_campaign(dir,case,base;workers=2,screening_enabled=false,sparse_balance=true).evaluated_count==0
        end
    end
end
