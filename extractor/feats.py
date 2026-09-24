import numpy as np, cv2
def glyph_bw(recs,i):
    name,idx,v,asp,(a,b,y0,y1)=recs[i]
    g=(cv2.imread(f'work_lp/cells/{name}.png',0)[y0:y1+1,a:b]<150)
    ys,xs=np.nonzero(g); return g[ys.min():ys.max()+1, xs.min():xs.max()+1]
def left_straight(g):
    h,w=g.shape; rows=range(int(h*0.12),int(h*0.88))
    L=[np.argmax(g[r]) for r in rows if g[r].any()]
    return np.mean(np.array(L)<=max(1,w*0.08))
def right_mid(g):
    h,w=g.shape; band=g[int(h*0.45):int(h*0.8), int(w*0.6):]
    return band.mean()
def bottom_right_tail(g):
    h,w=g.shape
    # Q: extra ink beyond symmetric: compare bottom-right quadrant ink vs bottom-left
    br=g[int(h*0.75):, w//2:].sum(); bl=g[int(h*0.75):, :w//2].sum()
    return (br-bl)/(br+bl+1e-6)
