#!/usr/bin/env python3
"""Add a P&ID to the explorer.
Usage:  python3 import_sheet.py path/to/drawing.pdf "Display name" [sheet_id]
Needs:  pip install pymupdf opencv-python-headless numpy
Works on vector AutoCAD-plotted P&IDs (not scans). Takes 1-5 minutes per sheet."""
import sys, os, json, re, tempfile
from extractor.orient import rotated_copy, score
from extractor.extract_sheet import extract, render_image
import pymupdf
HERE=os.path.dirname(os.path.abspath(__file__))
def main():
    if len(sys.argv)<3: print(__doc__); sys.exit(1)
    src,name=sys.argv[1],sys.argv[2]
    sid=sys.argv[3] if len(sys.argv)>3 else re.sub(r'[^a-z0-9]+','-',name.lower()).strip('-')[:24]
    sheets=json.load(open(os.path.join(HERE,'data/sheets.json'))); tags=json.load(open(os.path.join(HERE,'data/tags.json')))
    if any(s['id']==sid for s in sheets): print(f'Sheet id "{sid}" exists; pass a different id as 3rd argument.'); sys.exit(1)
    tmp=tempfile.mkdtemp(); best=None
    print('Finding orientation...')
    for extra in (0,90,180,270):
        dst=os.path.join(tmp,f'r{extra}.pdf'); rotated_copy(src,dst,extra); h=score(dst)[0]; print(f'  {extra:>3}°: {h} text lines')
        if best is None or h>best[0]: best=(h,dst)
    pdf=best[1]
    print('Extracting tags (this is the slow part)...'); T,size=extract(pdf,log=lambda m:print(' ',m))
    p=pymupdf.open(pdf)[0]; Z=min(2.0,6400/max(p.rect.width,p.rect.height))
    os.makedirs(os.path.join(HERE,'data/sheets'),exist_ok=True)
    w,h=render_image(pdf,os.path.join(HERE,f'data/sheets/{sid}.png'),zoom=Z)
    notes=[]
    for a in pymupdf.open(src)[0].annots():
        t=(a.info.get('content') or '').strip()
        if t: notes.append(t)
    sheets.append(dict(id=sid,name=name,file=f'data/sheets/{sid}.png',w=w,h=h,notes=notes))
    n={'auto':0,'review':0}
    for t in T:
        if t['status']=='ignore': continue
        n[t['status']]+=1
        tags.append(dict(id=f"{sid}:{t['id']}",sheet=sid,kks=t.get('kks'),suffix=t.get('suffix') or '',isa=t.get('isa'),kind=t['kind'],status=t['status'],
            conf=float(t['conf']),bbox=[round(v*Z,1) for v in t['bbox']],orient=t['orient'],read=[t['top'],t['bottom']],note=t.get('note',''),flag=t.get('flag',''),suggestion=None))
    json.dump(sheets,open(os.path.join(HERE,'data/sheets.json'),'w'),indent=1); json.dump(tags,open(os.path.join(HERE,'data/tags.json'),'w'))
    print(f'Done: "{name}" added — {n["auto"]} tags auto-read, {n["review"]} in the review queue. Reload the page.')
if __name__=='__main__': main()
