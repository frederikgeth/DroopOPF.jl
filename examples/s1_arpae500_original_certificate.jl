isdefined(@__MODULE__, :a500_inputs) || include("s1_arpae500_campaign.jl")
push!(LOAD_PATH,get(ENV,"A500_GLOBAL_ENV",joinpath(A500_OUT,"global_environment")))
import HiGHS
# This is an OUTER problem: study droops and necessary voltage envelopes
# implied by the original Q operating bounds. An infeasibility certificate transfers to
# the fixed-curve original-Q problem (and its tighter original-PQ subset).
function a500_original_certificate()
    _,_,angles,_,_=a500_inputs();base=read_study(joinpath(A500_OUT,"frozen-study.json")).case
    orig=JSON.parsefile(joinpath(A500_ROOT,"test/data/arpae/c1_network01/results/network_model.json"))
    fq=DroopOPF._fq;intervals=Dict(b.id=>(fq(b.v_min),fq(b.v_max)) for b in base.network.buses);derivation=[]
    tol=fq(1e-6)+fq(1e-5) # original operating-bound tolerance + exact-droop tolerance
    for a in base.attachments
        d=base.controls[a.control_id];@assert d.schedule.v_db_low==d.schedule.v_ref==d.schedule.v_db_high
        g=orig["gen"][string(a.generator_id)];lo,hi=intervals[a.location.bus_id]
        qlo=fq(g["qmin"])-tol;qhi=fq(g["qmax"])+tol
        curve=droop_curve(d);xs=fq.(curve.breakpoints);ys=fq.(curve.values)
        function inverse_curve(q)
            i=only([i for i in 1:length(xs)-1 if ys[i]>ys[i+1] && ys[i]>=q>=ys[i+1]])
            xs[i]+(q-ys[i])*(xs[i+1]-xs[i])/(ys[i+1]-ys[i])
        end
        lower=qhi<fq(d.capability.q_max) ? inverse_curve(qhi) : lo
        upper=qlo>fq(d.capability.q_min) ? inverse_curve(qlo) : hi
        intervals[a.location.bus_id]=(max(lo,lower),min(hi,upper))
        push!(derivation,Dict("generator"=>a.generator_id,"bus"=>a.location.bus_id,"necessary_v_lower_exact"=>string(lower),"necessary_v_upper_exact"=>string(upper),"q_tolerance_exact"=>string(tol)))
    end
    buses=[Bus(b.id;v_min=prevfloat(Float64(intervals[b.id][1])),v_max=nextfloat(Float64(intervals[b.id][2])),reference=b.reference) for b in base.network.buses]
    for b in buses;@assert fq(b.v_min)<=intervals[b.id][1] && fq(b.v_max)>=intervals[b.id][2];end
    net=ACNetwork(buses,base.network.branches;shunts=base.network.shunts,banks=base.network.banks)
    outer=Case(base.id*"-originalQ-necessary-outer";base_power=base.base_power,base_frequency=base.base_frequency,network=net,generators=base.generators,loads=base.loads,controls=base.controls,attachments=base.attachments)
    a500_save(joinpath(A500_OUT,"original_q_voltage_derivation.json"),Dict("scope"=>"necessary outer conditions; exact rational inverse of serialized curve knots and outward-rounded voltage bounds; original study droop graphs retained, original Q implied through voltage bounds","bounds"=>derivation))
    results=[]
    for f in (1.,.9,1.1,.95,1.05)
        p=FeasibilityProblem(DroopOPF._feasibility_scaled_case(outer,f);angle_limits=angles)
        println("START original-Q outer certificate ",f);flush(stdout)
        r=check_feasibility(p;solve_missing=false,lp_options=(optimizer_factory=HiGHS.Optimizer,time_limit=30.,max_rounds=15,psd_clique_limit=0))
        @assert verify_feasibility_result(p,r)
        write_feasibility_result(joinpath(A500_OUT,"original-q-outer-$f.json"),p,r)
        push!(results,Dict("factor"=>f,"status"=>string(r.status),"explanation"=>r.reason))
        a500_save(joinpath(A500_OUT,"original_q_certificates.json"),results)
        println("END original-Q outer certificate ",f," ",r.status);flush(stdout)
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && a500_original_certificate()
