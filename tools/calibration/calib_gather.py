import sys, pickle, os, cv2, numpy as np
sys.path.insert(0,'app')
from extractor.reader2 import detect, pair
from extractor.reader3 import cell_image, clean
from extractor.fontlib import split_chars
from extractor.segment import norm
pdf=sys.argv[1]; name=os.path.splitext(os.path.basename(pdf))[0]
page,k,cells=detect(pdf); recs=[]
for n,(o,a,b) in enumerate(pair(cells)):
    for part,cell in (('t',a),('b',b)):
        im,mask=cell_image(page,k,cell,o); bw=clean(im,mask); chars,band=split_chars(bw)
        if not chars: continue
        Hc=band[1]-band[0]+1
        for i,(x0,x1,sub) in enumerate(chars):
            v,asp=norm(sub,Hc)
            small=cv2.resize((255-sub*255).astype(np.uint8),(max(4,int(sub.shape[1]*40/sub.shape[0])),40))
            recs.append(dict(sheet=name,cell=f'{n}{part}',i=i,v=v,asp=asp,img=small))
pickle.dump(recs,open(f'calib/{name}.pkl','wb')); print(name,len(recs))
