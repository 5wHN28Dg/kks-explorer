import pickle, glob, numpy as np, cv2
from collections import Counter
recs=[]
for f in sorted(glob.glob('calib/*.pkl')): recs+=pickle.load(open(f,'rb'))
V=np.stack([r['v'] for r in recs]); A=np.array([r['asp'] for r in recs])
X,Y=pickle.load(open('fontlib_hrsg.pkl','rb')); Y=np.array(Y)
# library prediction per glyph
S=V@X.T; top=np.argsort(-S,axis=1)[:,:5]; best=S[np.arange(len(V)),top[:,0]]
pred=[Counter(Y[t]).most_common(1)[0][0] for t in top]
# cluster
centers=[];mem=[]
for i in range(len(V)):
    if centers:
        C=np.stack(centers); C=C/np.linalg.norm(C,axis=1,keepdims=True); s=C@V[i]; j=int(np.argmax(s))
        if s[j]>=0.92 and abs(A[mem[j][0]]-A[i])<0.2: mem[j].append(i); centers[j]=centers[j]+V[i]; continue
    centers.append(V[i].copy()); mem.append([i])
order=sorted(range(len(mem)),key=lambda j:-len(mem[j]))
info=[]
for j in order:
    m=mem[j]; c=Counter(pred[i] for i in m); lab,n=c.most_common(1)[0]
    info.append(dict(members=m,pred=lab,purity=n/len(m),sim=float(np.mean(best[m]))))
pickle.dump((recs,info),open('calib_clusters.pkl','wb'))
print('glyphs',len(recs),'clusters',len(info),'singletons',sum(len(x['members'])==1 for x in info))
confident=[x for x in info if x['sim']>0.93 and x['purity']>0.9]
print('confident clusters',len(confident),'covering',sum(len(x['members']) for x in confident))
def sheet(items,fn,start):
    rows=[]
    for k,x in enumerate(items):
        m=x['members']; samp=[m[t] for t in np.linspace(0,len(m)-1,min(7,len(m))).astype(int)]
        row=np.full((48,560),255,np.uint8)
        cv2.putText(row,f"{start+k}:{len(m)} [{x['pred']}] {x['sim']:.2f}",(2,30),cv2.FONT_HERSHEY_SIMPLEX,0.5,0,1)
        xx=190
        for s in samp:
            g=recs[s]['img']; w=g.shape[1]
            if xx+w>555: break
            row[4:44,xx:xx+w]=g; xx+=w+14
        rows.append(row)
    cv2.imwrite(fn,np.vstack(rows))
unc=[x for x in info if not (x['sim']>0.93 and x['purity']>0.9) and len(x['members'])>=2]
pickle.dump(unc,open('calib_unc.pkl','wb'))
print('uncertain clusters',len(unc),'covering',sum(len(x['members']) for x in unc))
for p in range(0,len(unc),45): sheet(unc[p:p+45],f'cal_{p//45}.png',p)
print('sheets',(len(unc)+39)//40)
