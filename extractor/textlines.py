from .glyphs import load_paths
from collections import defaultdict, Counter
import math

def band_ok(a,b,axis,tol):
    # a,b: rects; axis 'h' -> compare y bands; 'v' -> x bands
    if axis=='h': return abs(a[3]-b[3])<tol and abs((a[1]+a[3])/2-(b[1]+b[3])/2) < tol*1.5
    return abs(a[0]-b[0])<tol and abs((a[0]+a[2])/2-(b[0]+b[2])/2) < tol*1.5

def build_lines(paths):
    lines=[]; i=0; n=len(paths)
    while i<n:
        line=[paths[i]]; j=i+1; axis=None
        while j<n and paths[j]['seq']==line[-1]['seq']+1:
            a=line[-1]['r']; b=paths[j]['r']
            H=max(max(q['r'][3]-q['r'][1] for q in line), b[3]-b[1])
            W=max(max(q['r'][2]-q['r'][0] for q in line), b[2]-b[0])
            # horizontal candidate: b starts near/after a along x, similar vertical extent
            hc = (b[0] > a[0]-0.6*H and b[0] < a[2]+0.9*H) and (b[1] < a[3]+0.2*H and b[3] > a[1]-0.2*H)
            vc = (b[1] < a[3]+0.9*W and b[3] > a[1]-0.9*W) and (b[0] < a[2]+0.2*W and b[2] > a[0]-0.2*W)
            # vertical text in this plot reads bottom-to-top: next char has smaller y
            if axis is None:
                dx=b[0]-a[0]; dy=b[3]-a[3]
                if hc and abs(dy) < 0.35*H and dx > -0.2: axis='h'
                elif vc and abs(b[0]-a[0]) < 0.35*W and dy < 0.2: axis='v'
                elif hc: axis='h'
                else: break
            if axis=='h' and hc: line.append(paths[j]); j+=1; continue
            if axis=='v' and vc: line.append(paths[j]); j+=1; continue
            break
        lines.append({'paths':line,'axis':axis or 'h'})
        i=j
    return lines

def to_local(line):
    """rotate vertical lines into horizontal frame: for 'v' text reading bottom->top,
    local x = -y, local y = x  (rotate 90deg ccw->cw)."""
    out=[]
    for pth in line['paths']:
        if line['axis']=='h':
            segs=pth['segs']
        else:
            segs=[(-y1,x1,-y2,x2) for (x1,y1,x2,y2) in pth['segs']]
        xs=[s[0] for s in segs]+[s[2] for s in segs]; ys=[s[1] for s in segs]+[s[3] for s in segs]
        out.append({'segs':segs,'r':(min(xs),min(ys),max(xs),max(ys)),'seq':pth['seq']})
    return out

def split_chars(lp):
    chars=[]
    for pth in lp:
        x0,y0,x1,y1=pth['r']
        if chars:
            c=chars[-1]; cx0,_,cx1,_=c['r']
            ov=min(x1,cx1)-max(x0,cx0); w=max(min(x1-x0,cx1-cx0),0.05)
            contained = (x0>=cx0-0.25 and x1<=cx1+0.25) or (cx0>=x0-0.25 and cx1<=x1+0.25)
            if (ov >= 0.5*w - 0.05 and ov>0.15) or contained:
                c['segs']+=pth['segs']; c['r']=(min(x0,cx0),min(y0,c['r'][1]),max(x1,cx1),max(y1,c['r'][3])); continue
        chars.append({'segs':list(pth['segs']),'r':pth['r']})
    return chars

def signature(ch, base_y, H):
    x0=ch['r'][0]
    q=lambda v: round(v/H*20)
    ss=[]
    for (a,b,c,d) in ch['segs']:
        p1=(q(a-x0),q(b-base_y)); p2=(q(c-x0),q(d-base_y))
        if p1==p2: continue
        ss.append(tuple(sorted([p1,p2])))
    return tuple(sorted(set(ss)))

def process(pdf):
    paths=load_paths(pdf)
    lines=build_lines(paths)
    out=[]
    for L in lines:
        lp=to_local(L)
        H=max(p['r'][3]-p['r'][1] for p in lp)
        if H<2.5: continue
        base=max(p['r'][3] for p in lp)
        chars=split_chars(lp)
        sigs=[signature(c,base,H) for c in chars]
        # char positions back in page space: approximate
        out.append({'axis':L['axis'],'H':round(H,2),'chars':chars,'sigs':sigs,
                    'bbox':(min(p['r'][0] for p in L['paths']),min(p['r'][1] for p in L['paths']),
                            max(p['r'][2] for p in L['paths']),max(p['r'][3] for p in L['paths'])),
                    'seq0':L['paths'][0]['seq']})
    return out
