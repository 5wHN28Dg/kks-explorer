import json, cv2, numpy as np, pymupdf, pickle
tags=json.load(open('app/data/tags.json')); sheets={s['id']:s for s in json.load(open('app/data/sheets.json'))}
FN={'lp':'HRSG_LOW_PRESSURE_SYSTEM_P_ID','ip':'IP_Circuit','hp':'HP_system_final_revision','fw':'FW_system','rh':'Reheat_system','cbd':'Intermittent___CBD_and_cooling_pool_pump','flue':'DOCUMENT','b1hp':'Block1_HP_MS_piping','b1ip':'Block1_IP_Cylinder','b1lp':'Block1_LP_MS_line'}
rev=[t for t in tags if t['status']=='review']
order=[]; pages={}
for sid in FN:
    items=[t for t in rev if t['sheet']==sid]
    if not items: continue
    page=pymupdf.open(f'norm/{FN[sid]}.pdf')[0]; Z=sheets[sid]['w']/page.rect.width
    for t in items:
        b=[v/Z for v in t['bbox']]; pad=3
        pix=page.get_pixmap(clip=pymupdf.Rect(b[0]-pad,b[1]-pad,b[2]+pad,b[3]+pad),dpi=260,colorspace=pymupdf.csGRAY)
        im=np.frombuffer(pix.samples,np.uint8).reshape(pix.height,pix.width).copy()
        if t['orient']=='v': im=cv2.rotate(im,cv2.ROTATE_90_CLOCKWISE)
        s=min(66/im.shape[0],230/im.shape[1]); im=cv2.resize(im,(max(1,int(im.shape[1]*s)),max(1,int(im.shape[0]*s))),interpolation=cv2.INTER_AREA)
        c=np.full((96,300),255,np.uint8); c[2:2+im.shape[0],4:4+im.shape[1]]=im
        k=len(order); guess=((t['kks'] or '')+(t['suffix'] or '')) or (t['read'][0]+'/'+t['read'][1])
        cv2.putText(c,f"{k}: {(t['isa']+' ') if t['isa'] else ''}{guess}"[:40],(4,88),cv2.FONT_HERSHEY_SIMPLEX,0.42,0,1)
        cv2.rectangle(c,(0,0),(299,95),200,1)
        order.append(t['id']); pages.setdefault(k//48,[]).append(c)
for p,cells in pages.items():
    while len(cells)%4: cells.append(np.full((96,300),255,np.uint8))
    cv2.imwrite(f'rv_{p:02d}.png',np.vstack([np.hstack(cells[i:i+4]) for i in range(0,len(cells),4)]))
json.dump(order,open('rv_order.json','w'))
from collections import Counter
print(len(order),'items',len(pages),'sheets', Counter(t.split(':')[0] for t in order))
