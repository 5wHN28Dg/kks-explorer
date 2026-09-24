import pymupdf, json
from collections import defaultdict, Counter

def load_paths(pdf):
    d=pymupdf.open(pdf); p=d[0]
    out=[]
    for x in p.get_drawings():
        r=x['rect']
        if x['fill'] is not None: continue
        if max(r.width,r.height) > 14: continue
        segs=[]
        ok=True
        for it in x['items']:
            if it[0]=='l': segs.append((it[1].x,it[1].y,it[2].x,it[2].y))
            else: ok=False
        if not ok or not segs: continue
        out.append({'seq':x['seqno'],'segs':segs,'r':(r.x0,r.y0,r.x1,r.y1)})
    out.sort(key=lambda a:a['seq'])
    return out

def group_chars(paths):
    """consecutive paths whose bbox overlap strongly along the text direction -> same char.
    We don't know orientation yet, so merge consecutive paths if bboxes intersect/touch."""
    chars=[]; cur=None
    for pth in paths:
        x0,y0,x1,y1=pth['r']
        if cur and pth['seq']==cur['last']+1:
            cx0,cy0,cx1,cy1=cur['r']
            tol=0.3
            # merge if bbox overlaps (not just adjacent)
            if x0 < cx1-tol and x1 > cx0+tol and y0 < cy1+tol and y1 > cy0-tol and (min(x1,cx1)-max(x0,cx0))>0.5 or \
               (x0 < cx1-tol and x1 > cx0+tol and y0 < cy1-tol and y1 > cy0+tol and (min(y1,cy1)-max(y0,cy0))>0.5 and False):
                cur['segs']+=pth['segs']; cur['r']=(min(x0,cx0),min(y0,cy0),max(x1,cx1),max(y1,cy1)); cur['last']=pth['seq']; continue
        cur={'segs':list(pth['segs']),'r':pth['r'],'first':pth['seq'],'last':pth['seq']}
        chars.append(cur)
    return chars
