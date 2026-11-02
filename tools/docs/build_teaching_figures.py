"""Generate repository-native SVG teaching schematics (no plotting dependency)."""
from pathlib import Path
from html import escape
import math
OUT=Path(__file__).resolve().parents[2]/'docs/src/assets/teaching'
BLUE='#235d85';TEAL='#177b70';ORANGE='#ad571d';INK='#20354b';GRAY='#586b7e'
class SVG:
 def __init__(self,title,h=360,w=1000):
  self.w=w;self.h=h;self.s=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" role="img" aria-label="{escape(title)}"><title>{escape(title)}</title><defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="{GRAY}"/></marker></defs><rect width="100%" height="100%" fill="white"/>'];self.text(30,32,title,24,INK,anchor='start')
 def text(self,x,y,t,size=18,color=INK,anchor='middle'):
  self.s.append(f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-family="DejaVu Sans,Arial,sans-serif" font-size="{size}" fill="{color}">{escape(t)}</text>')
 def line(self,x,y,u,v,color=GRAY,arrow=False,dash=False):
  self.s.append(f'<path d="M{x} {y}L{u} {v}" fill="none" stroke="{color}" stroke-width="2.5"'+(' marker-end="url(#arrow)"' if arrow else '')+(' stroke-dasharray="7 5"' if dash else '')+'/>')
 def box(self,x,y,w,h,lines,color=BLUE):
  self.s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="#f5f9fc" stroke="{color}" stroke-width="2"/>')
  for i,t in enumerate(lines):self.text(x+w/2,y+27+25*i,t,17,color)
 def circle(self,x,y,r,label):
  self.s.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="white" stroke="{BLUE}" stroke-width="2.5"/>');self.text(x,y+6,label,20,BLUE)
 def save(self,name):
  OUT.mkdir(parents=True,exist_ok=True);(OUT/(name+'.svg')).write_text('\n'.join(self.s)+ '\n</svg>\n')

def network():
 s=SVG('A two-bus case: electrical connection and regulated voltage',350)
 s.circle(90,150,35,'G1');s.line(125,150,260,150);s.line(260,105,260,195,BLUE);s.line(260,150,700,150);s.line(700,105,700,195,BLUE);s.line(700,150,860,150,arrow=True)
 s.text(330,82,'Bus 1');s.text(700,82,'Bus 2');s.text(480,122,'Branch 11: r = 0.01, x = 0.10 pu');s.text(870,192,'Load 1');s.text(790,220,'Pᴸ = 0.50 pu; Qᴸ = 0.20 pu')
 s.text(95,220,'Generator 1');s.text(270,254,'Angle reference: δ₁ = 0 rad');s.text(270,281,'Voltage magnitude v₁ is solved')
 s.line(260,105,260,57,TEAL);s.line(260,57,90,57,TEAL);s.line(90,57,90,115,TEAL,arrow=True);s.text(545,57,'Teal path: controller measures bus 1 voltage',17,TEAL)
 s.text(500,326,'System base: 100 MVA. Positive generator power injects; positive load power consumes.',17)
 s.save('two_bus')

def pipeline():
 s=SVG('From a declared physical problem to a checked operating point',330)
 labels=[['Case','Network + devices'],['Study / controls','Allowed decisions'],['Build and solve','Approximate encoding'],['Independent replay','Exact physics + policy']]
 for i,lines in enumerate(labels):
  x=25+i*245;s.box(x,90,220,80,lines)
  if i<3:s.line(x+220,130,x+240,130,arrow=True)
 s.line(870,170,870,218,arrow=True);s.box(755,225,225,65,['Native success + replay','Accept within scope'],TEAL)
 s.text(370,226,'Solver status answers a numerical question.',18);s.text(370,256,'Replay checks the supplied physical/control equations.',18);s.text(370,286,'Failed or incomplete checks remain visible.',18)
 s.save('workflow')

def branch():
 s=SVG('One branch: from-side tap, series impedance and charging',380)
 s.line(75,95,75,215,BLUE);s.line(920,95,920,215,BLUE);s.text(75,75,'From bus f');s.text(920,75,'To bus t')
 s.line(75,150,195,150);s.box(195,120,155,60,['Tap a = τ exp(jφ)']);s.line(350,150,480,150);s.box(480,125,200,50,['Series z = r + jx']);s.line(680,150,920,150)
 s.line(420,150,420,226);s.line(398,226,442,226);s.line(398,236,442,236);s.line(420,236,420,261);s.line(405,261,435,261)
 s.line(760,150,760,226);s.line(738,226,782,226);s.line(738,236,782,236);s.line(760,236,760,261);s.line(745,261,775,261)
 s.text(420,292,'j bᶜʰ / 2');s.text(760,292,'j bᶜʰ / 2');s.text(410,103,'Internal voltage U_f = V_f / a',16)
 s.line(90,189,170,189,ORANGE,arrow=True);s.text(137,215,'I_f',18,ORANGE);s.line(900,189,820,189,ORANGE,arrow=True);s.text(861,215,'I_t',18,ORANGE)
 s.text(500,335,'Both terminal currents point into the branch; S_f + S_t is its net complex absorption.',17)
 s.text(500,360,'τ: positive tap ratio; φ: phase shift (rad); j² = −1; bᶜʰ: total charging susceptance.',16)
 s.save('branch_pi')

def scenarios():
 s=SVG('Security means one declared policy across several AC equilibria',370)
 s.box(30,125,230,85,['Shared controller θ','Supplied bounds','Equipment timing'],TEAL)
 for k,lines in enumerate([['Base state x₀','All supplied devices'],['Outage state x₁','Declared device removed'],['Outage state x₂','Another device removed']]):
  y=65+k*95;s.box(500,y,440,75,lines);s.line(260,168,485,y+38,arrow=True)
 s.text(500,350,'Each state solves its own AC balance. Base dispatch and outage response are coupled.',17)
 s.save('security_states')

def periods():
 s=SVG('Periods are chronological; outages are alternative states',400)
 for k in range(3):
  x=150+k*290;s.text(x+105,78,f'Period {k+1}')
  s.box(x,100,215,62,['Base active outputs','AC state for this demand'])
  s.box(x,200,215,62,['Outage A state','Same period controls'])
  s.box(x,295,215,62,['Outage B state','Same period controls'])
  s.line(x+108,162,x+108,195,arrow=True)
  s.line(x+108,262,x+108,290,dash=True)
  if k<2:s.line(x+215,126,x+285,126,TEAL,arrow=True);s.text(x+250,183,'ramp',14,TEAL)
 s.text(30,133,'Base',17,anchor='start');s.text(30,237,'Outage A',17,anchor='start');s.text(30,331,'Outage B',17,anchor='start')
 s.text(500,386,'Shared droop parameters θ span the grid. Horizontal ramp arrows constrain preventive active power only.',16)
 s.save('period_scenario_grid')

def controls():
 s=SVG('Reactive mode chooses the equation that accompanies AC balance',365)
 labels=[('FreeQ',['Optimizer chooses Q','within its limits']),('FixedQ',['Q = supplied schedule','while available']),('AVR',['Hold measured voltage','until Q reaches a limit']),('VoltVarDroop',['Follow supplied Q(v)','with deadband and limits'])]
 for k,(name,lines) in enumerate(labels):
  x=20+k*247;s.box(x,80,230,120,[name]+lines)
 s.text(500,242,'The bus voltage and reactive output are solved together with the network.',19)
 s.text(500,277,'An angle-reference bus does not create unlimited active or reactive capability.',18)
 s.text(500,315,'AVR: automatic voltage regulation. Q: reactive output. v: measured voltage magnitude.',17)
 s.save('reactive_modes')

def curves():
 s=SVG('Read the Volt/VAR curve: saturation, deadband and proportional regions',400)
 x=lambda v:105+(v-.9)/.2*810;y=lambda q:200-100*q
 s.line(105,320,935,320,arrow=True);s.line(105,320,105,65,arrow=True)
 s.text(510,376,'Measured voltage magnitude v (pu)',18);s.text(210,64,'Reactive output Q (pu)',18)
 for q in [-1,0,1]:
  s.line(105,y(q),920,y(q),dash=True);s.text(78,y(q)+6,str(q),16)
 pts=[(.9,1),(.94,1),(.99,0),(1.01,0),(1.06,-1),(1.1,-1)]
 s.s.append('<polyline points="'+' '.join(f'{x(v)},{y(q)}' for v,q in pts)+f'" fill="none" stroke="{BLUE}" stroke-width="4"/>')
 for v in [.9,.94,.99,1.01,1.06,1.1]:s.text(x(v),345,f'{v:g}',15)
 s.text(190,91,'Upper Q limit',16,BLUE);s.text(823,286,'Lower Q limit',16,BLUE);s.text(510,173,'Deadband',17,TEAL)
 s.text(275,195,'Slope dQ/dv = −1/m',16,BLUE);s.text(718,160,'m = 0.05 pu V / pu Q',16,BLUE)
 s.save('volt_var_curve')

def active():
 s=SVG('A saturated participant holds its bound while another keeps responding',390)
 x=lambda v:100+v*1250;y=lambda p:310-p*600
 s.line(100,310,930,310,arrow=True);s.line(100,310,100,70,arrow=True)
 s.text(500,370,'Common active-response signal λ (pu active power)',18);s.text(260,66,'Delivered change ΔP (pu)',18)
 for q in [0,.1,.2,.3]:s.text(68,y(q)+6,f'{q:g}',16);s.line(100,y(q),900,y(q),dash=True)
 for lam in [0,.2,.4,.6]:s.text(x(lam),339,f'{lam:g}',16)
 for name,color,fun,at in [('Unit A: weight 0.6, headroom 0.10',BLUE,lambda l:min(.6*l,.1),.6),('Unit B: weight 0.4, headroom 0.40',TEAL,lambda l:.4*l,.56)]:
  points=[(x(l),y(fun(l))) for l in [i*.006 for i in range(101)]];s.s.append('<polyline points="'+' '.join(f'{u},{v}' for u,v in points)+f'" fill="none" stroke="{color}" stroke-width="4"/>')
  s.text(440,105 if color==BLUE else 135,name,17,color)
 s.text(570,228,'A reaches its bound; B continues.',17,ORANGE)
 s.save('active_response')
def triangle():
 s=SVG('Three buses: connected line outage and loss of one generator',380)
 s.line(255,110,745,110);s.line(255,110,500,285);s.line(745,110,500,285)
 s.circle(100,110,30,'G7');s.line(130,110,255,110);s.circle(900,110,30,'G9');s.line(745,110,870,110)
 s.line(255,80,255,140,BLUE);s.line(745,80,745,140,BLUE);s.line(470,285,530,285,BLUE);s.line(500,285,500,330,arrow=True)
 s.text(255,65,'Bus 10: angle reference',17);s.text(745,65,'Bus 20',17);s.text(600,292,'Bus 30',17)
 s.text(500,90,'Branch 11',17);s.text(290,215,'Branch 33',17);s.text(705,215,'Branch 22',17)
 s.text(500,356,'Load: 0.60 pu active + 0.15 pu reactive power',18)
 s.text(109,168,'Generator 7',16);s.text(896,168,'Generator 9',16)
 s.save('three_bus_security')

if __name__=='__main__':
 for f in [network,pipeline,branch,scenarios,periods,controls,curves,active,triangle]:f()
 print('Generated nine teaching SVGs in',OUT)
