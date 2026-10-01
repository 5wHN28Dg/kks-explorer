"""Reference data from the Python importer stages, for the Nim port's differential tests. Local only: plant data,
written to a folder outside the repository.
  .venv/bin/python importer/tests/dump_ref.py OUTDIR"""
import json, os, sys, tempfile
import numpy as np, pymupdf
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from extractor.orient import rotated_copy
from extractor.glyphs import load_paths
SRC = {'lp': 'HRSG LOW PRESSURE SYSTEM P&ID.pdf', 'ip': 'IP Circuit.pdf', 'hp': 'HP system final revision.pdf',
       'fw': 'FW system.pdf', 'rh': 'Reheat system.pdf', 'cbd': 'Intermittent & CBD and cooling pool pump.pdf',
       'flue': 'KEPPT-RUPP-0-SDEP-HNA-DI-0001_HRSG FLUE GAS SYSTEM PID_REV B unprow.pdf',
       'b1hp': 'Block1 HP MS piping.pdf', 'b1ip': 'Block1 IP Cylinder.pdf', 'b1lp': 'Block1 LP MS line.pdf',
       'b1cond': 'KEPPT-RUPP-1-SDEP-MA-DM-0012 P&ID FOR BLOCK 1 CONDENSATE SYSTEM AND MAKE-UP WATER SYSTEM DIAGRAM REV.B IFC unprow..pdf'}
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
only = sys.argv[2:]
sheets = {s['id']: s for s in json.load(open('plant-data/sheets.json'))}
man = []
for sid, src in SRC.items():
    if only and sid not in only: continue
    rot = sheets[sid]['rot']
    tmp = tempfile.mkdtemp(); pdf = os.path.join(tmp, 'r.pdf'); rotated_copy(os.path.join('source', src), pdf, rot)
    page = pymupdf.open(pdf)[0]
    pymupdf.TOOLS.set_graphics_min_line_width(0.5)
    pix = page.get_pixmap(dpi=200, colorspace=pymupdf.csGRAY)
    pymupdf.TOOLS.set_graphics_min_line_width(0)
    open(os.path.join(out, f'{sid}.det.gray'), 'wb').write(pix.samples)
    clips = []
    W, H = page.rect.width, page.rect.height
    rng = np.random.default_rng(len(sid))
    for k in range(4):
        x, y = float(rng.uniform(0, W - 40)), float(rng.uniform(0, H - 20))
        r = pymupdf.Rect(x, y, x + float(rng.uniform(15, 40)), y + float(rng.uniform(5, 20)))
        cp = page.get_pixmap(clip=r, dpi=600, colorspace=pymupdf.csGRAY)
        open(os.path.join(out, f'{sid}.clip{k}.gray'), 'wb').write(cp.samples)
        clips.append({'rect': [r.x0, r.y0, r.x1, r.y1], 'w': cp.width, 'h': cp.height, 'x': cp.x, 'y': cp.y})
    paths = load_paths(pdf)
    json.dump([[p['seq'], p['r'], p['segs']] for p in paths], open(os.path.join(out, f'{sid}.paths.json'), 'w'))
    man.append({'id': sid, 'src': os.path.abspath(os.path.join('source', src)), 'rot': rot, 'page': [W, H],
                'det': [pix.width, pix.height], 'clips': clips, 'paths': len(paths)})
    print(sid, rot, pix.width, pix.height, len(paths), flush=True)
json.dump(man, open(os.path.join(out, 'manifest.json'), 'w'), indent=1)
