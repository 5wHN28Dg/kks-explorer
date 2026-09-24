"""Extract KKS-tagged equipment from one P&ID PDF page (AutoCAD plot, vector strokes).
Pipeline: container detection -> masked high-res crops -> learned-font reader -> KKS grammar -> confidence.
Second pass: long vector text lines outside containers (open-ended instrument balloons)."""
import pickle, re, os, json, cv2, numpy as np, pymupdf
from .fontlib import FontLib, interpret
from .reader3 import Reader, read_sheet, clean
from .textlines import process as vector_lines

HERE=os.path.dirname(__file__)
def load_lib():
    X,Y=pickle.load(open(os.path.join(HERE,'fontlib.pkl'),'rb')); return FontLib(X,Y)

def _crop(page,r,orient,dpi=600):
    pix=page.get_pixmap(clip=pymupdf.Rect(*r),dpi=dpi,colorspace=pymupdf.csGRAY)
    im=np.frombuffer(pix.samples,np.uint8).reshape(pix.height,pix.width).copy()
    if orient=='v': im=cv2.rotate(im,cv2.ROTATE_90_CLOCKWISE)
    im=cv2.copyMakeBorder(im,30,30,30,30,cv2.BORDER_CONSTANT,value=255)
    return im,np.full_like(im,255)

def _near(b,e,pad=12):
    cx,cy=(b[0]+b[2])/2,(b[1]+b[3])/2; return e[0]-pad<cx<e[2]+pad and e[1]-pad<cy<e[3]+pad

def extract(pdf, page_no=0, log=print):
    lib=load_lib()
    log('detecting tag containers + reading...')
    tags,size=read_sheet(pdf,lib)
    log(f'  {len(tags)} containers')
    log('second pass: open-ended balloons...')
    page=pymupdf.open(pdf)[page_no]; rd=Reader(lib)
    lines=vector_lines(pdf)
    extra=[]
    for li,L in enumerate(lines):
        if len(L['chars'])<11 or len(L['chars'])>18 or not (4<L['H']<9): continue
        b=L['bbox']
        if any(_near(b,t['bbox']) for t in tags) or any(_near(b,e['bbox'],4) for e in extra): continue
        o=L['axis']
        u,cu=rd.read(*_crop(page,(b[0]-2,b[1]-2,b[2]+2,b[3]+2),o))
        if not re.match(r'^\d{2}[A-Z]{3}\d{2}',u) and cu<0.3 and not re.search(r'[A-Z]{3}\d{2}[A-Z]{2}\d',u): continue
        best=None
        for M in lines:
            if M is L or M['axis']!=o: continue
            m=M['bbox']
            if o=='v' and 3<b[0]-m[2]<14 and abs((m[1]+m[3])/2-(b[1]+b[3])/2)<12: best=m
            if o=='h' and 3<b[1]-m[3]<14 and abs((m[0]+m[2])/2-(b[0]+b[2])/2)<12: best=m
        tt,ct='',1.0
        if best: tt,ct=rd.read(*_crop(page,(best[0]-2,best[1]-2,best[2]+2,best[3]+2),o))
        bb=[b[0],b[1],b[2],b[3]]
        if best: bb=[min(b[0],best[0]),min(b[1],best[1]),max(b[2],best[2]),max(b[3],best[3])]
        rec=dict(id=f'ob{li}',orient=o,bbox=[round(v,1) for v in bb],top=tt,bottom=u,conf=round(min(cu,ct),2),source='open-balloon')
        rec.update(interpret(tt,u)); extra.append(rec)
    log(f'  {len(extra)} open-balloon candidates')
    allt=tags+extra
    for t in allt:
        if t['kind']=='other' and re.match(r'^\d{2}[A-Z]{3}\d{2}[A-Z]{2}\d{3}[A-Z0-9]*$',t['bottom']):
            t.update(kind='instrument',kks=t['bottom'][:12],suffix=t['bottom'][12:],isa=None); t['conf']=min(t['conf'],0.25)
        if t['kind']=='instrument' and t.get('isa') and not re.fullmatch(r'[A-Z]{1,6}',t['isa']): t['isa']=None; t['conf']=min(t['conf'],0.25)
        t['status']='auto' if (t['kind'] in('equipment','instrument') and t['conf']>=0.3) else ('review' if (t['kind']!='other' or t['top'] or t['bottom']) else 'ignore')
    # duplicate KKS on the same sheet -> flag
    from collections import Counter
    c=Counter((t.get('kks') or '')+(t.get('suffix') or '') for t in allt if t['status']=='auto')
    for t in allt:
        k=(t.get('kks') or '')+(t.get('suffix') or '')
        if t['status']=='auto' and c[k]>1: t['flag']='duplicate KKS on this sheet'
    return allt,size

def render_image(pdf,out_png,zoom=2.0,page_no=0):
    p=pymupdf.open(pdf)[page_no]; pix=p.get_pixmap(matrix=pymupdf.Matrix(zoom,zoom),colorspace=pymupdf.csGRAY)
    pix.save(out_png); return pix.width,pix.height
