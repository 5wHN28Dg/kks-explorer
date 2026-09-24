import cv2, numpy as np
def clean_cell(im):
    """im: grayscale, text dark. Remove container border remnants: keep components not touching image edge after padding removal."""
    bw=(im<150).astype(np.uint8)
    n,lab,st,cen=cv2.connectedComponentsWithStats(bw,8)
    H,W=bw.shape; keep=np.zeros_like(bw)
    for i in range(1,n):
        x,y,w,h,a=st[i]
        # drop things that are very long/thin borders or hug the left/right/top/bottom padding zone
        if h>0.85*(H-60) or w>0.6*W: continue
        if x<=32 or x+w>=W-32:
            if h>0.5*(H-60) and w<0.12*W and (x<=32 or x+w>=W-32): continue
        keep[lab==i]=1
    return keep
def split_chars(bw):
    ys,xs=np.nonzero(bw)
    if len(xs)==0: return []
    y0,y1=ys.min(),ys.max()
    col=bw[y0:y1+1].sum(0)
    chars=[];inrun=False
    for x,v in enumerate(col):
        if v>0 and not inrun: s=x;inrun=True
        elif v==0 and inrun: chars.append((s,x));inrun=False
    if inrun: chars.append((s,len(col)))
    out=[]
    for a,b in chars:
        sub=bw[y0:y1+1,a:b]
        if sub.sum()<15: continue
        out.append((a,b,sub))
    return out,(y0,y1)
def norm(sub,Hcap,GW=20,GH=32):
    h,w=sub.shape
    s=GH/max(Hcap,1)
    im=cv2.resize(sub.astype(np.float32),(max(1,int(round(w*s))),GH),interpolation=cv2.INTER_AREA)
    canvas=np.zeros((GH,GW),np.float32)
    ww=min(GW,im.shape[1]); off=(GW-ww)//2
    canvas[:,off:off+ww]=im[:,:ww]
    canvas=cv2.GaussianBlur(canvas,(3,3),0.8)
    v=canvas.ravel(); n=np.linalg.norm(v)
    return v/n if n else v, w/max(Hcap,1)
