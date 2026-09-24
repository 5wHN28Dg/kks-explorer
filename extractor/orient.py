import pymupdf, sys, os

from .glyphs import load_paths
from .textlines import build_lines
def rotated_copy(src,dst,extra):
    s=pymupdf.open(src); s[0].set_rotation(0); r=s[0].rect  # unrotated, 1:1
    W,H=(r.width,r.height) if extra in (0,180) else (r.height,r.width)
    d=pymupdf.open(); p=d.new_page(width=W,height=H)
    p.show_pdf_page(p.rect,s,0,rotate=extra,keep_proportion=True)
    d.save(dst)
def score(pdf):
    L=build_lines(load_paths(pdf))
    return sum(1 for l in L if l['axis']=='h' and len(l['paths'])>=6), sum(1 for l in L if l['axis']=='v' and len(l['paths'])>=6)
if __name__=='__main__':
    src=sys.argv[1]; extras=[int(x) for x in sys.argv[2].split(',')]
    name=os.path.splitext(os.path.basename(src))[0]
    for extra in extras:
        dst=f'norm/{name}.pdf' if len(extras)==1 else f'norm/{name}__r{extra}.pdf'
        rotated_copy(src,dst,extra); print(name[:25],extra,score(dst),flush=True)
