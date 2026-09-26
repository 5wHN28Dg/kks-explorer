"""Reusable KKS tag reader built on a learned glyph library (no OCR)."""
import numpy as np, cv2, pickle, re
from .feats import left_straight, bottom_right_tail
from .segment import norm

def _lower_right(g):
    h,w=g.shape; return g[int(h*0.55):int(h*0.85), int(w*0.7):].mean()

def clean_cell(im):
    bw=(im<150).astype(np.uint8)
    n,lab,st,_=cv2.connectedComponentsWithStats(bw,8)
    H,W=bw.shape; keep=np.zeros_like(bw)
    inner_h=H-60
    for i in range(1,n):
        x,y,w,h,a=st[i]
        comp=(lab==i).astype(np.uint8)
        if w>0.6*W or h>0.95*inner_h+20:
            continue
        edge = x<=34 or x+w>=W-34
        if edge and h>0.5*inner_h:
            # rescue full-height vertical strokes fused to the container arc
            sub=comp[y:y+h, x:x+w]; colcov=sub.sum(0)/h
            strong=np.where(colcov>0.7)[0]
            if len(strong):
                c0,c1=strong.min(),strong.max()
                pad=int(0.35*h*0.18)+3
                c0=max(0,c0-pad); c1=min(w-1,c1+pad)
                # keep only rows/cols of the stroke region, and drop arc pixels outside text band
                m=np.zeros_like(sub); m[:,c0:c1+1]=sub[:,c0:c1+1]
                keep[y:y+h, x:x+w]|=m
            continue
        keep|=comp
    return keep

def split_chars(bw):
    ys,xs=np.nonzero(bw)
    if len(xs)==0: return [],None
    y0,y1=ys.min(),ys.max(); Hc=y1-y0+1
    col=bw[y0:y1+1].sum(0); runs=[]; inrun=False
    for x,v in enumerate(list(col)+[0]):
        if v>0 and not inrun: s=x; inrun=True
        elif v==0 and inrun:
            if bw[y0:y1+1,s:x].sum()>=15: runs.append((s,x))
            inrun=False
    if not runs: return [],None
    widths=sorted(b-a for a,b in runs)
    typical=max(np.median(widths), 0.42*Hc)          # typical single-char width
    out=[]
    for a,b in runs:
        w=b-a; n=int(round(w/typical))
        if w>1.45*typical and n>=2:
            cuts=[a]
            for k in range(1,n):
                c=a+int(k*w/n); lo=max(a+2,c-int(0.25*typical)); hi=min(b-2,c+int(0.25*typical))
                seg=col[lo:hi]; cuts.append(lo+int(np.argmin(seg)) if len(seg) else c)
            cuts.append(b)
            for p,q in zip(cuts,cuts[1:]):
                if q-p>2: out.append((p,q,bw[y0:y1+1,p:q]))
        else:
            out.append((a,b,bw[y0:y1+1,a:b]))
    return out,(y0,y1)

class FontLib:
    def __init__(self, X, Y): self.X=X; self.Y=np.array(Y)
    def classify(self, sub, Hc):
        v,asp=norm(sub,Hc)
        s=self.X@v; top=np.argsort(-s)[:5]
        best=self.Y[top[0]]; sim=float(s[top[0]])
        agree=np.mean(self.Y[top]==best)
        lab=best
        g=sub.astype(bool); ys,xs=np.nonzero(g); g=g[ys.min():ys.max()+1,xs.min():xs.max()+1]
        if lab in ('C','G'): lab='G' if _lower_right(g)>0.45 else 'C'
        elif lab in ('B','8'): lab='8' if left_straight(g)<0.9 else 'B'
        elif lab in ('0','D','Q'):
            t=bottom_right_tail(g); st=left_straight(g)
            lab='Q' if t>0.12 else ('D' if (t<-0.08 and st>0.95) else '0')
        conf=min(1.0,max(0.0,(sim-0.80)/0.12))*agree
        return lab, conf
    def read(self, im):
        bw=clean_cell(im); chars,band=split_chars(bw)
        if not chars: return '',0.0,[]
        Hc=band[1]-band[0]+1
        s='';confs=[]
        for a,b,sub in chars:
            l,c=self.classify(sub,Hc)
            if l=='': continue
            s+=l; confs.append(c)
        return s,(min(confs) if confs else 0.0),confs

SYS=re.compile(r'^\d{2}[A-Z]{3}\d{2}$')
COMP=re.compile(r'^[A-Z]{2}\d{3}[A-Z]?$')
FULL=re.compile(r'^(\d{2}[A-Z]{3}\d{2}[A-Z]{2}\d{3})((?:X[A-Z]{1,2}\d{1,2})|[A-Z]{0,2})$')
ISA=re.compile(r'^[A-Z]{1,6}$')
def _fix_kks(s):
    # KKS never uses letters I or O: in digit slots they can only be 1 / 0
    t=list(s)
    for pat in ('DDLLLDDLLDDD','DDLLLDD','LLDDD'):
        if len(t)>=len(pat):
            for i,c in enumerate(pat):
                if c=='D' and t[i]=='I': t[i]='1'
                if c=='D' and t[i]=='O': t[i]='0'
            break
    return ''.join(t)
def interpret(top,bottom):
    # two thin 1s drawn close together read as one 'U' (CBD sheet: 'ULCQ75' = 11LCQ75); a system part always starts
    # with the 2-digit unit, and only 11 can merge like that (2026-09-25)
    if re.fullmatch(r'U[A-Z]{3}\d{2}',top or ''): top='11'+top[1:]
    top=top.replace('1','I') if re.fullmatch(r'[A-Z1]{1,6}',top or '') and not re.match(r'^\d\d',top or '') else top
    top=_fix_kks(top) if re.match(r'^[\dI]{2}[A-Z]{3}',top or '') else top
    bottom=_fix_kks(bottom)
    m=FULL.match(bottom)
    if m and not (top or '').strip():  # instrument bubble printed without function letters (e.g. 10LCB10GF001)
        return dict(kind='instrument',kks=m.group(1),suffix=m.group(2),isa=None)
    if m and ISA.match(top):
        kks=m.group(1)
        # C/G is this font's weakest pair, misread even at full confidence. A KKS measuring point is C + the measured
        # variable, which is also the instrument's first ISA letter (PI -> CP, FIAC -> CF, TIA -> CT, PDA -> CP), so
        # 'G' followed by that letter can only be a misread C.
        v='P' if top.startswith('PD') else top[0]
        top=top[0]+top[1:].replace('G','C')   # no later function letter G exists on these drawings: TIAG/PIAG were TIAC/PIAC
        if kks[7]=='G' and kks[8]==v: kks=kks[:7]+'C'+kks[8:]
        return dict(kind='instrument',kks=kks,suffix=m.group(2),isa=top)
    if SYS.match(top) and COMP.match(bottom): return dict(kind='equipment',kks=top+bottom,suffix='')
    if SYS.match(top) and re.match(r'^[A-Z0-9]{3,6}$',bottom):
        return dict(kind='suspect',kks=None,note=f'component code "{bottom}" does not fit KKS format (drawing error?)')
    if re.match(r'^\d?[A-Z]{3}\d{2}',bottom) or re.match(r'^\d?[A-Z]{3}\d{2}',top):
        return dict(kind='suspect',kks=None,note='partially read tag')
    return dict(kind='other',kks=None)
