import pymupdf, re, json, sys
CJK=re.compile(r'[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]')
WM=re.compile(r'click to buy|docu-track|tracker-software|pdf-xchange|xchange editor',re.I)
HEAD=re.compile(r'^(\d{1,2}(?:\.\d{1,2}){1,3})\.?\s+(.*)$')
STEP=re.compile(r'^(\d{1,2})\s*[)）]\s*(.*)$')
def en(s): return CJK.sub('',s).strip(' \t:：;；')
# running page headers/footers to drop: tools/manual_parse.py manual.pdf out.json [--skip "Header text" ...]
SKIP=[]
def parse(pdf, first_page=6, last_page=127):
    d=pymupdf.open(pdf); lines=[]
    for pi in range(first_page-1,last_page):
        for l in d[pi].get_text().splitlines():
            l=l.strip()
            if not l or len(l)<=1 or WM.search(l): continue
            if any(l.startswith(p) for p in SKIP): continue
            lines.append((pi+1,l))
    secs=[]; cur=None; pending_num=None
    i=0
    while i<len(lines):
        pg,l=lines[i]
        # headings may be split: number on one line, title on next
        if re.fullmatch(r'\d{1,2}(\.\d{1,2}){1,3}\.?',l) and i+1<len(lines):
            l=l+' '+lines[i+1][1]; i+=1
        m=HEAD.match(l)
        if m and not STEP.match(l):
            title=en(m.group(2))
            # drop TOC-like lines and table rows
            if title and not re.search(r'\.{5,}',title) and len(title)<140 and not re.match(r'^[\d.\s%]+$',title):
                cur={'id':m.group(1),'title':title,'page':pg,'steps':[],'text':[]}; secs.append(cur); i+=1; continue
        s=STEP.match(l)
        if cur is not None:
            if s:
                body=s.group(2)
                if CJK.search(body) and not re.search(r'[A-Za-z]{4,}',en(body)): i+=1; continue  # Chinese-only step
                cur['steps'].append({'n':int(s.group(1)),'text':en(body)})
            elif not CJK.search(l):
                if cur['steps'] and not HEAD.match(l): cur['steps'][-1]['text']+=' '+l
                else: cur['text'].append(l)
        i+=1
    # dedupe steps (Chinese/English pairs share numbers): keep English
    for s in secs:
        seen={};out=[]
        for st in s['steps']:
            t=st['text'].strip()
            if not re.search(r'[A-Za-z]',t): continue
            out.append({'n':st['n'],'text':re.sub(r'\s+',' ',t)})
        s['steps']=out; s['text']=re.sub(r'\s+',' ',' '.join(s['text']))[:1500]
    return secs
if __name__=='__main__':
    a=sys.argv[1:]
    while '--skip' in a: i=a.index('--skip'); SKIP.append(a[i+1]); del a[i:i+2]
    secs=parse(a[0])
    json.dump(secs,open(a[1],'w'),ensure_ascii=False,indent=1)
    print(len(secs),'sections;',sum(1 for s in secs if s['steps']),'with steps')
    for s in secs:
        if s['steps']: print(s['id'],s['title'][:70],'|',len(s['steps']),'steps p',s['page'])
