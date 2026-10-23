isdefined(@__MODULE__, :a500_read_policy) || include("audit_s1_arpae500.jl")
function a500_ccopt_fix()
    _,_,angles,costs,_=a500_inputs();rows=[JSON.parsefile(p) for p in readdir(joinpath(A500_OUT,"attempts");join=true)]
    for f in (.9,.95)
        original=filter(r->r["tags"]["stage"]=="frozen" && r["tags"]["factor"]==f,rows)
        good=filter(r->r["point_pass"],original);best=first(sort(good;by=r->r["loss_mw"]))
        c=read_study(joinpath(A500_ROOT,best["model_path"])).case;p=a500_read_policy(best["policy"])
        exact=filter(r->r["tags"]["stage"]=="recovery" && r["tags"]["factor"]==f && r["solver"]=="ccopt" && r["point_pass"],rows)
        starts=isempty(exact) ? [("smooth",best)] : [("exact",first(sort(exact;by=r->r["loss_mw"]))),("smooth",best)]
        recovered=false
        for (init,r) in starts
            for mu in (1e-6,1e-8)
                opts=Dict{String,Any}("bound_push"=>1e-8,"bound_fac"=>1e-8)
                result=a500_attempt(c,a500_state(r["state"]),angles,costs,p,"ccopt-fix-$f-$init-$mu";solver=:ccopt,extra=opts,ccopt_mu_init=mu,iterations=3000,seconds=120.,tags=Dict("stage"=>"ccopt_fix","factor"=>f,"family"=>"fixed","seed"=>r["name"],"method"=>"smaller initial barrier and bound push; unchanged tolerances and model"))
                if result["accepted"];recovered=true;break;end
            end
            recovered && break
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && a500_ccopt_fix()
