"""Small fixed-Q infeasibility certificate using a PSD outer relaxation.

Discovery uses NumPy/SciPy. Verification uses only Python's standard library.
All final algebra is rational. Trig coefficients are enclosed by Taylor bounds.
The certificate excludes AC states even allowing the declared validation tolerances.
"""
from fractions import Fraction as F
import hashlib
import json
from pathlib import Path
import sys

TOL=F('0.000001000000001') # Conservatively exceeds the numerical 1e-6 tolerance.
def rational(x): return F(x) if isinstance(x,(int,float)) else F(x)
def pairtext(x): return str(x)
def digest(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def trig(theta):
    assert abs(theta)<=1
    co=sum((-1)**k*theta**(2*k)/F(__import__('math').factorial(2*k)) for k in range(9))
    si=sum((-1)**k*theta**(2*k+1)/F(__import__('math').factorial(2*k+1)) for k in range(9))
    return co,si,abs(theta)**18/F(__import__('math').factorial(18)),abs(theta)**19/F(__import__('math').factorial(19))

def build(casepath,cuts):
    study=json.loads(Path(casepath).read_text())['data'];c=study['case'];net=c['network'];bus=net['buses'];gens=c['generators'];n=len(bus)
    assert n==3 and not study['contingencies'] and all(a['mode']['type']=='FixedQ' for a in study['reactive_assignments'])
    assert all(b['available'] for b in net['branches']) and all(g['available'] for g in gens)
    idx={b['id']:i for i,b in enumerate(bus)};pairs=[(0,1),(0,2),(1,2)]
    # Each Y entry contains exact rational center real/imag and error radii.
    Y=[[[F(0),F(0),F(0),F(0)] for _ in bus] for _ in bus]
    def add(i,j,g,b,eg=F(0),eb=F(0)):
        for k,v in enumerate((g,b,eg,eb)):Y[i][j][k]+=v
    for br in net['branches']:
        i,j=idx[br['from_bus']],idx[br['to_bus']];r,x=map(rational,(br['resistance'],br['reactance']));t=rational(br['tap_ratio']);bc=rational(br['charging'])/2
        assert t>0;r2=r*r+x*x;g,b=r/r2,-x/r2;co,si,ec,es=trig(rational(br['phase_shift']))
        add(i,i,g/t**2,(b+bc)/t**2);add(j,j,g,b+bc)
        add(i,j,-(g*co-b*si)/t,-(g*si+b*co)/t,(abs(g)*ec+abs(b)*es)/t,(abs(g)*es+abs(b)*ec)/t)
        add(j,i,-(g*co+b*si)/t,-(-g*si+b*co)/t,(abs(g)*ec+abs(b)*es)/t,(abs(g)*es+abs(b)*ec)/t)
    for s in net['shunts']:
        if s['available']:add(idx[s['bus_id']],idx[s['bus_id']],rational(s['conductance']),rational(s['susceptance']))
    for s in net['banks']:
        if s['available']:
            add(idx[s['bus_id']],idx[s['bus_id']],sum(rational(k)*rational(g) for k,g in zip(s['state'],s['step_conductances'])),sum(rational(k)*rational(b) for k,b in zip(s['state'],s['step_susceptances'])))
    lower=[(rational(b['v_min'])-TOL)**2 for b in bus];upper=[(rational(b['v_max'])+TOL)**2 for b in bus]
    assert all(rational(b['v_min'])>TOL for b in bus)
    cross=max(upper);bounds=list(zip(lower,upper))+[(-cross,cross)]*6
    P=[];Q=[];EP=[];EQ=[]
    for i in range(n):
        pr=[F(0)]*9;qi=pr.copy();ep=pr.copy();eq=pr.copy()
        for j in range(n):
            g,b,eg,eb=Y[i][j]
            if i==j:pr[i]+=g;qi[i]-=b;ep[i]+=eg;eq[i]+=eb
            else:
                pair=(min(i,j),max(i,j));k=3+2*pairs.index(pair);sign=1 if i<j else -1
                pr[k]+=g;pr[k+1]+=sign*b;qi[k]-=b;qi[k+1]+=sign*g
                ep[k]+=eg;ep[k+1]+=eb;eq[k]+=eb;eq[k+1]+=eg
        P.append(pr);Q.append(qi);EP.append(ep);EQ.append(eq)
    loadsP=[F(0)]*n;loadsQ=loadsP.copy();fixedQ=loadsP.copy();ng=[0]*n;pmn=loadsP.copy();pmx=loadsP.copy()
    for l in c['loads']:loadsP[idx[l['bus_id']]]+=rational(l['p']);loadsQ[idx[l['bus_id']]]+=rational(l['q'])
    assignments={a['generator_id']:a for a in study['reactive_assignments']}
    for g in gens:
        i=idx[g['bus_id']];fixedQ[i]+=rational(assignments[g['id']]['mode']['q_schedule']);ng[i]+=1
        pmn[i]+=rational(g['p_min']);pmx[i]+=rational(g['p_max'])
    A=[];rhs=[];labels=[]
    def row(a,b,label):A.append(a);rhs.append(b);labels.append(label)
    for i in range(n):
        qtarget=fixedQ[i]-loadsQ[i];qerr=TOL*(ng[i]+1)
        eqerr=sum(e*max(abs(lo),abs(hi)) for e,(lo,hi) in zip(EQ[i],bounds))
        eperr=sum(e*max(abs(lo),abs(hi)) for e,(lo,hi) in zip(EP[i],bounds))
        for sign in (-1,1):row([sign*x for x in Q[i]],sign*qtarget+qerr+eqerr,f'bus {i} Q {sign}')
        row(P[i],pmx[i]-loadsP[i]+TOL*(ng[i]+1)+eperr,f'bus {i} P upper')
        row([-x for x in P[i]],-pmn[i]+loadsP[i]+TOL*(ng[i]+1)+eperr,f'bus {i} P lower')
    for direction in cuts:
        v=[(F(a),F(b)) for a,b in direction];a=[-(x*x+y*y) for x,y in v]
        for i,j in pairs:
            ar,ai=v[i];br,bi=v[j];a.extend([-2*(ar*br+ai*bi),2*(ar*bi-ai*br)])
        row(a,F(0),'PSD direction')
    # Explicit bound rows aid floating discovery of a Farkas multiplier.
    for j,(lo,hi) in enumerate(bounds):
        a=[F(0)]*9;a[j]=1;row(a,hi,f'box {j} upper')
        a=[F(0)]*9;a[j]=-1;row(a,-lo,f'box {j} lower')
    return A,rhs,bounds,labels

def proof_gap(A,b,bounds,weights):
    assert len(weights)==len(A) and all(x>=0 for x in weights)
    c=[sum(w*row[j] for w,row in zip(weights,A)) for j in range(9)]
    return sum(min(x*lo,x*hi) for x,(lo,hi) in zip(c,bounds))-sum(w*y for w,y in zip(weights,b))

def verify(casepath,certpath):
    cert=json.loads(Path(certpath).read_text());assert cert['case_sha256']==digest(casepath)
    A,b,bounds,labels=build(casepath,cert['psd_directions'])
    gap=proof_gap(A,b,bounds,[F(x) for x in cert['nonnegative_multipliers']])
    assert gap==F(cert['exact_gap']) and gap>0
    return dict(status='VERIFIED_INFEASIBLE',positive_gap=float(gap),rows=len(A),psd_cuts=len(cert['psd_directions']),
        meaning='Normalized algebraic contradiction; not a MW or MVAr shortage',
        scope='Fixed nominal Q at 105% demand, frozen tag111 equipment, source voltage bounds plus validation tolerances',
        solver_needed_for_verification=False)

def discover(casepath,out):
    import numpy as np
    from scipy.optimize import linprog
    out.mkdir(parents=True,exist_ok=True)
    assert not (out/'protocol.json').exists(),'Use a fresh certificate output directory'
    (out/'protocol.json').write_text(json.dumps(dict(case_sha256=digest(casepath),script_sha256=digest(__file__),
        purpose='Resolve the retained fixed-Q 105% exception using an outer relaxation; no original acceptance rule changes',
        tolerance=str(TOL),method='Hermitian voltage-product PSD cuts; exact rational multiplier verification with rigorous trig enclosures'),indent=2)+'\n')
    pairs=[(0,1),(0,2),(1,2)];basis=[]
    for i in range(3):
        B=np.zeros((3,3),complex);B[i,i]=1;basis.append(B)
    for i,j in pairs:
        B=np.zeros((3,3),complex);B[i,j]=B[j,i]=1;basis.append(B)
        B=np.zeros((3,3),complex);B[i,j]=1j;B[j,i]=-1j;basis.append(B)
    cuts=[];history=[]
    for it in range(60):
        A,b,bounds,labels=build(casepath,cuts);af=np.array(A,float);bf=np.array(b,float)
        r=linprog(np.zeros(9),A_ub=af,b_ub=bf,bounds=[(None,None)]*9,method='highs',options={'primal_feasibility_tolerance':1e-9,'dual_feasibility_tolerance':1e-9})
        history.append(dict(iteration=it,solver_status=int(r.status),message=r.message,rows=len(A)))
        if r.status==2:
            dual=linprog(bf,A_eq=np.vstack([af.T,np.ones(len(A))]),b_eq=np.r_[np.zeros(9),1.],bounds=(0,None),method='highs')
            assert dual.success,dual.message
            for denom in (10**8,10**12,10**16):
                weights=[F(float(max(0,x))).limit_denominator(denom) for x in dual.x]
                gap=proof_gap(A,b,bounds,weights)
                if gap>0:break
            assert gap>0,'Floating infeasibility did not yield an exact positive certificate'
            cert=dict(case_sha256=digest(casepath),psd_directions=cuts,nonnegative_multipliers=[str(x) for x in weights],exact_gap=str(gap),
                derivation='Every physical AC voltage vector yields PSD W=V*V^H. v^H W v >=0 for each stored rational direction. All physical constraints are contained in the rational interval-relaxed rows. A nonnegative weighted sum is <=0 for any feasible W; its exact minimum over the voltage-product box is strictly positive. Contradiction.')
            certpath=out/'certificate.json';certpath.write_text(json.dumps(cert,indent=2)+'\n')
            result=verify(casepath,certpath)
            (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
            (out/'discovery.json').write_text(json.dumps(history,indent=2)+'\n')
            print(json.dumps(result));return
        assert r.success,r.message
        W=sum(x*B for x,B in zip(r.x,basis));ev,V=np.linalg.eigh(W)
        assert ev.min()<-1e-9,'Outer relaxation is feasible; no certificate discovered'
        for k,e in enumerate(ev):
            if e<-1e-9:
                cuts.append([[str(F(float(z.real)).limit_denominator(10**8)),str(F(float(z.imag)).limit_denominator(10**8))] for z in V[:,k]])
    raise RuntimeError('No certificate within bounded discovery budget')

if __name__=='__main__':
    mode,casepath,dest=sys.argv[1:]
    if mode=='discover':discover(Path(casepath),Path(dest))
    elif mode=='verify':print(json.dumps(verify(casepath,dest)))
    else:raise SystemExit('Expected discover or verify')
