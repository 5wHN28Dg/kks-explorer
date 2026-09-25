import pymupdf, cv2, numpy as np, pickle, sys
from .fontlib import FontLib, interpret, split_chars
DPI_DET=200; DPI_READ=600
def detect(pdf):
    page=pymupdf.open(pdf)[0]
    pix=page.get_pixmap(dpi=DPI_DET,colorspace=pymupdf.csGRAY)
    img=np.frombuffer(pix.samples,np.uint8).reshape(pix.height,pix.width)
    k=DPI_DET/72
    bw=(img<215).astype(np.uint8)*255
    cnts,hier=cv2.findContours(bw,cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
    cells=[]
    for i,c in enumerate(cnts):
        if hier[0][i][3]==-1: continue
        x,y,w,h=cv2.boundingRect(c); W,H=w/k,h/k
        if not ((4<H<24 and 15<W<110) or (4<W<24 and 15<H<110)): continue
        # hull, not the traced contour: a letter touching the border (suffix K/R against a bubble arc) carves a notch
        # into the traced hole and made real tag halves fail this test (2026-09-25)
        if cv2.contourArea(cv2.convexHull(c))<0.75*w*h: continue
        cells.append(((x,y,w,h), c.reshape(-1,2).astype(np.float32)/k))  # contour in PDF points
    return page,k,cells
def _fits(p,pw,q,qw):
    ov=min(p+pw,q+qw)-max(p,q)
    return ov>=0.85*min(pw,qw) and min(pw,qw)>=0.7*max(pw,qw)
def pair(cells):
    cells=sorted(cells,key=lambda c:(c[0][0],c[0][1])); pairs=[];used=set()
    for i,(a,ca) in enumerate(cells):
        if i in used: continue
        for j,(b,cb) in enumerate(cells):
            if i==j or j in used: continue
            # halves stacked edge to edge; one may be narrower (text touching both ends of a bubble half cuts into its
            # traced hole), so require overlap rather than equal width (2026-09-25)
            if 0<=b[1]-(a[1]+a[3])<8 and _fits(a[0],a[2],b[0],b[2]): pairs.append(('h',(a,ca),(b,cb))); used|={i,j}; break
            if 0<=b[0]-(a[0]+a[2])<8 and _fits(a[1],a[3],b[1],b[3]): pairs.append(('v',(a,ca),(b,cb))); used|={i,j}; break
    return pairs
def cell_image(page,k,cell,orient):
    (x,y,w,h),poly=cell
    r=pymupdf.Rect(x/k-1,y/k-1,(x+w)/k+1,(y+h)/k+1)
    pix=page.get_pixmap(clip=r,dpi=DPI_READ,colorspace=pymupdf.csGRAY)
    im=np.frombuffer(pix.samples,np.uint8).reshape(pix.height,pix.width).copy()
    s=DPI_READ/72
    pts=((poly-np.array([r.x0,r.y0]))*s).astype(np.int32)
    mask=np.zeros_like(im); cv2.fillPoly(mask,[pts],255)
    mask=cv2.erode(mask,np.ones((3,3),np.uint8),iterations=2)
    im[mask==0]=255
    if orient=='v': im=cv2.rotate(im,cv2.ROTATE_90_CLOCKWISE)
    return cv2.copyMakeBorder(im,30,30,30,30,cv2.BORDER_CONSTANT,value=255)
def simple_clean(im):
    bw=(im<150).astype(np.uint8)
    n,lab,st,_=cv2.connectedComponentsWithStats(bw,8)
    keep=np.zeros_like(bw); H=bw.shape[0]-60
    hs=[st[i][3] for i in range(1,n)]
    cap=np.percentile(hs,75) if hs else 0
    for i in range(1,n):
        x,y,w,h,a=st[i]
        if a<12: continue
        if w>0.45*bw.shape[1] or (h<0.25*cap and w>1.5*cap): continue   # border slivers
        if h<0.3*cap and w<0.3*cap: continue   # specks / arc crumbs
        keep[lab==i]=1
    return keep
class Reader:
    def __init__(self,lib): self.lib=lib
    def read(self,im):
        bw=simple_clean(im); chars,band=split_chars(bw)
        if not chars: return '',0.0
        Hc=band[1]-band[0]+1; s='';cs=[]
        for a,b,sub in chars:
            l,c=self.lib.classify(sub,Hc)
            if l: s+=l; cs.append(c)
        return s,(min(cs) if cs else 0.0)
def read_sheet(pdf,lib):
    page,k,cells=detect(pdf); R=Reader(lib); out=[]
    for n,(o,a,b) in enumerate(pair(cells)):
        t,ct=R.read(cell_image(page,k,a,o)); u,cu=R.read(cell_image(page,k,b,o))
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
