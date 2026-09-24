import pickle, numpy as np
recs,info=pickle.load(open('calib_clusters.pkl','rb'))
unc=[x for x in info if not (x['sim']>0.93 and x['purity']>0.9) and len(x['members'])>=2]
SKIP=None
lab={0:'8',1:'9',2:'8',3:'0',4:'8',5:'E',6:'C',7:'D',8:'Y',9:'9',10:'N',11:'R',12:'',13:'90',14:'',15:'V',16:'11',17:'L',18:'E',19:'1L',20:'E',21:'N',22:'',23:'',24:'',
26:'TI',27:'5',28:'',29:'',30:'',31:'',32:'',33:'C',34:'',36:'',37:'',38:'',40:'5',41:'',42:'P',44:'1',
45:'J',46:'S',47:'',48:'K',49:'B',50:'',51:'',52:'',53:'',54:'D',55:'6',56:'',57:'',58:'K',59:'W',61:'',62:'U',64:'',65:'M',66:'7',67:'',68:'S',69:'',70:'T1',71:'S',72:'9',73:'E',74:'F',75:'Q',76:'',77:'',79:'V',80:'',82:'G',83:'',84:'E',85:'S',86:'G',87:'',88:'',89:'',
90:'Q',91:'S',92:'B',93:'9',94:'M',95:'',96:'',98:'',99:'J',100:'91',101:'AD9',102:'',103:'A',106:'FI',107:'G',108:'',109:'',110:'',113:'C',114:'',115:'G',116:'',118:'',119:'G',120:'D',121:'3',122:'',123:'8',124:'',125:'C',126:'',127:'',128:'R',129:'',131:'',132:'AD90',133:'L1',134:'AC',
135:'W',136:'V',137:'V',138:'',139:'',140:'',141:'',142:'',143:'',144:'',145:'',146:'',147:'',148:'M',149:'N',150:'W',151:'D',152:'',153:'',154:'AT',155:'A',156:'T',157:''}
X=[];Y=[]
for k,x in enumerate(unc):
    if k in lab:
        for i in x['members']: X.append(recs[i]['v']); Y.append(lab[k])
conf=[x for x in info if x['sim']>0.93 and x['purity']>0.9]
for x in conf:
    for i in x['members']:
        if recs[i]['asp']>0.95 and len(x['pred'])==1: continue
        X.append(recs[i]['v']); Y.append(x['pred'])
X0,Y0=pickle.load(open('fontlib_hrsg.pkl','rb'))
X=np.vstack([X0,np.stack(X)]); Y=list(Y0)+Y
pickle.dump((X,Y),open('app/extractor/fontlib.pkl','wb'))
from collections import Counter
print('library',len(Y),'classes',len(set(Y)), sorted(set(Y)))
