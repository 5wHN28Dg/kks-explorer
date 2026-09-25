import pymupdf, cv2, numpy as np, pickle, sys
from .fontlib import FontLib, interpret, split_chars
from .reader2 import detect, pair, DPI_READ
SHRINK=2
def cell_image(page,k,cell,orient):
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
    if orient=='v': im=cv2.rotate(im,cv2.ROTATE_90_CLOCKWISE); mask=cv2.rotate(mask,cv2.ROTATE_90_CLOCKWISE)
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
def read_sheet(pdf,lib):
    page,k,cells=detect(pdf); R=Reader(lib); out=[]
    for n,(o,a,b) in enumerate(pair(cells)):
        t,ct=R.read(*cell_image(page,k,a,o)); u,cu=R.read(*cell_image(page,k,b,o))
        (ax,ay,aw,ah),_=a; (bx,by,bw_,bh),_=b
        bb=[min(ax,bx)/k,min(ay,by)/k,max(ax+aw,bx+bw_)/k,max(ay+ah,by+bh)/k]
        rec=dict(id=n,orient=o,bbox=[round(v,1) for v in bb],top=t,bottom=u,conf=round(min(ct,cu),2))
        rec.update(interpret(t,u)); out.append(rec)
    return out,(page.rect.width,page.rect.height)
if __name__=='__main__':
    X,Y=pickle.load(open('fontlib_hrsg.pkl','rb'))
    tags,size=read_sheet(sys.argv[1],FontLib(X,Y))
    pickle.dump((tags,size),open(sys.argv[2],'wb'))
    from collections import Counter; print(Counter(t['kind'] for t in tags))
