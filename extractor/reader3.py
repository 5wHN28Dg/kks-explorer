import pymupdf, cv2, numpy as np, pickle, sys
from .fontlib import FontLib, interpret, split_chars
from .reader2 import detect, pair, DPI_READ
SHRINK=2
def cell_image(page,k,cell,orient,ccw=False):
    (x,y,w,h),poly=cell
    r=pymupdf.Rect((x+SHRINK)/k,(y+SHRINK)/k,(x+w-SHRINK)/k,(y+h-SHRINK)/k)
    pix=page.get_pixmap(clip=r,dpi=DPI_READ,colorspace=pymupdf.csGRAY)
    im=np.frombuffer(pix.samples,np.uint8).reshape(pix.height,pix.width).copy()
    s=DPI_READ/72
    pts=((poly-np.array([r.x0,r.y0]))*s).astype(np.int32)
    # Convex hull, not the traced contour: a character touching the border (suffix R against a bubble arc, a leading
    # 1 against a box edge) is part of the outline blob, so the traced hole goes around it and would cut it out.
    # Cells are convex (boxes, bubble halves), so the hull restores those notches and still excludes the outline.
    mask=np.zeros_like(im); cv2.fillPoly(mask,[cv2.convexHull(pts)],255)
    mask=cv2.erode(mask,np.ones((3,3),np.uint8),iterations=3)
    if orient=='v':
        r=cv2.ROTATE_90_COUNTERCLOCKWISE if ccw else cv2.ROTATE_90_CLOCKWISE
        im=cv2.rotate(im,r); mask=cv2.rotate(mask,r)
    P=30
    im=cv2.copyMakeBorder(im,P,P,P,P,cv2.BORDER_CONSTANT,value=255)
    mask=cv2.copyMakeBorder(mask,P,P,P,P,cv2.BORDER_CONSTANT,value=0)
    return im,mask
def clean(im,mask):
    bw=(im<190).astype(np.uint8)
    n,lab,st,_=cv2.connectedComponentsWithStats(bw,8)
    H,W=bw.shape; inner=H-60; keep=np.zeros_like(bw)
    for i in range(1,n):
        x,y,w,h,a=st[i]; comp=(lab==i).astype(np.uint8)
        if w>0.6*W or h>0.95*inner+20: continue
        edge = x<=34 or x+w>=W-34
        if edge and h>0.5*inner:
            trimmed=comp&(mask>0)
            # keep trimmed part only if it is a substantial glyph-like remnant
            ys,xs=np.nonzero(trimmed)
            if len(xs)>40 and (ys.max()-ys.min())>0.6*inner:
                # remove leftover arc crumbs: keep largest component of trimmed
                m,l2,s2,_=cv2.connectedComponentsWithStats(trimmed,8)
                if m>1:
                    j=1+int(np.argmax(s2[1:,4])); keep|=(l2==j).astype(np.uint8)
            continue
        keep|=comp
    # drop specks far smaller than the text (corner crumbs, arc tips) so the text band is measured correctly
    n2,l2,s2,_=cv2.connectedComponentsWithStats(keep,8)
    if n2>1:
        maxh=s2[1:,3].max()
        for j in range(1,n2):
            if s2[j,3]<0.3*maxh and s2[j,2]<0.3*maxh: keep[l2==j]=0
    return keep
class Reader:
    def __init__(self,lib): self.lib=lib
    def read(self,im,mask):
        bw=clean(im,mask); chars,band=split_chars(bw)
        if not chars: return '',0.0
        Hc=band[1]-band[0]+1; s='';cs=[]
        for a,b,sub in chars:
            l,c=self.lib.classify(sub,Hc)
            if l: s+=l; cs.append(c)
        return s,(min(cs) if cs else 0.0)
def read_single(R,page,k,cell):
    """A bubble drawn without the dividing line between function letters and KKS is one closed cell, which pair()
    can't use. Split it at the widest empty row band between its two text rows and read both parts."""
    (x,y,w,h),poly=cell; W,H=w/k,h/k
    if min(W,H)<10: return None                      # too thin for two rows of text
    o='h' if W>=H else 'v'
    if o=='v':  # vertical text runs either way on these drawings: keep the reading that makes a tag
        rs=[r for r in (_read_single(R,page,k,cell,o,False),_read_single(R,page,k,cell,o,True)) if r]
        return max(rs,key=lambda r:(interpret(r[1],r[2])['kind'] in ('equipment','instrument'),r[3])) if rs else None
    return _read_single(R,page,k,cell,o,False)
def _read_single(R,page,k,cell,o,ccw):
    im,mask=cell_image(page,k,cell,o,ccw)
    im=im.copy(); im[mask==0]=255                    # a whole bubble's rounded ends lie inside the crop
    rows=clean(im,mask).sum(1); ys=np.nonzero(rows)[0]
    if not len(ys): return None
    best=(0,None); run=0
    for i,e in enumerate(rows[ys[0]:ys[-1]]==0):
        run=run+1 if e else 0
        if run>best[0]: best=(run,ys[0]+i-run//2)
    if best[1] is None or best[0]<4:  # one row of text only: a code printed without function letters
        u,cu=R.read(im,mask)
        return o,'',u,cu
    c=best[1]; pad=lambda a,v: cv2.copyMakeBorder(a,30,30,0,0,cv2.BORDER_CONSTANT,value=v)
    t,ct=R.read(pad(im[:c+1],255),pad(mask[:c+1],0)); u,cu=R.read(pad(im[c:],255),pad(mask[c:],0))
    return o,t,u,min(ct,cu)
def read_sheet(pdf,lib):
    page,k,cells=detect(pdf); R=Reader(lib); out=[]
    pairs=pair(cells); used={id(c[1]) for _,a,b in pairs for c in (a,b)}
    for n,(o,a,b) in enumerate(pairs):
        t,ct=R.read(*cell_image(page,k,a,o)); u,cu=R.read(*cell_image(page,k,b,o))
        if o=='v' and interpret(t,u)['kind'] not in ('equipment','instrument'):
            # vertical text reading top-to-bottom: function letters are in the right-hand cell, turn the other way
            t2,ct2=R.read(*cell_image(page,k,b,o,True)); u2,cu2=R.read(*cell_image(page,k,a,o,True))
            if interpret(t2,u2)['kind'] in ('equipment','instrument'): t,ct,u,cu=t2,ct2,u2,cu2
        (ax,ay,aw,ah),_=a; (bx,by,bw_,bh),_=b
        bb=[min(ax,bx)/k,min(ay,by)/k,max(ax+aw,bx+bw_)/k,max(ay+ah,by+bh)/k]
        rec=dict(id=n,orient=o,bbox=[round(v,1) for v in bb],top=t,bottom=u,conf=round(min(ct,cu),2))
        rec.update(interpret(t,u)); out.append(rec)
    for n,cell in enumerate(c for c in cells if id(c[1]) not in used):  # bubbles without a divider
        r=read_single(R,page,k,cell)
        if not r: continue
        o,t,u,conf=r; (x,y,w,h),_=cell
        rec=dict(id=f's{n}',orient=o,bbox=[round(v,1) for v in (x/k,y/k,(x+w)/k,(y+h)/k)],top=t,bottom=u,conf=round(conf,2))
        rec.update(interpret(t,u))
        if rec['kind'] in ('equipment','instrument'): out.append(rec)   # other single cells are table/legend boxes
    return out,(page.rect.width,page.rect.height)
if __name__=='__main__':
    X,Y=pickle.load(open('fontlib_hrsg.pkl','rb'))
    tags,size=read_sheet(sys.argv[1],FontLib(X,Y))
    pickle.dump((tags,size),open(sys.argv[2],'wb'))
    from collections import Counter; print(Counter(t['kind'] for t in tags))
