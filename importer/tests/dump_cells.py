"""Reference trace of the Python importer for the Nim port's gate (decision 0026). Local only: plant data, written to
a folder outside the repository. Per sheet <sid>.trace.jsonl, one line per event, in call order:
  {"e":"score","rot":R,"h":H,"v":V}                           orient.score on each rotated copy
  {"e":"read","im":HASH,"mask":HASH,"s":TEXT,"c":CONF}        every Reader.read (image + mask hashed with shape)
  {"e":"glyph","l":LABEL,"c":CONF,"top":[...],"sim":[...]}    every FontLib.classify inside it (before the read line)
  {"e":"tags","tags":[...]}                                   extract()'s result
  .venv/bin/python importer/tests/dump_cells.py OUTDIR [SHEET...]"""
import hashlib, json, os, sys, tempfile
from multiprocessing import Pool
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from extractor import orient, reader3, fontlib, extract_sheet


def h(a):
    a = np.ascontiguousarray(a)
    return hashlib.sha256(repr(a.shape).encode() + a.astype(np.uint8).tobytes()).hexdigest()[:16]

def run(args):
    out, sid, src, rot = args
    ev = []
    real_classify = fontlib.FontLib.classify
    def classify(self, sub, Hc):
        lab, conf = real_classify(self, sub, Hc)
        from extractor.segment import norm
        v, _ = norm(sub, Hc); s = self.X @ v; top = np.argsort(-s)[:5]
        ev.append({'e': 'glyph', 'l': str(lab), 'c': float(conf), 'top': [int(t) for t in top],
                   'sim': [float(s[t]) for t in top], 'sub': h(sub), 'hc': int(Hc)})
        return lab, conf
    fontlib.FontLib.classify = classify
    real_read = reader3.Reader.read
    def read(self, im, mask):
        s, c = real_read(self, im, mask)
        ev.append({'e': 'read', 'im': h(im), 'mask': h(mask), 's': s, 'c': float(c)})
        return s, c
    reader3.Reader.read = read
    tmp = tempfile.mkdtemp()
    for r in (0, 90, 180, 270):
        p = os.path.join(tmp, f'r{r}.pdf'); orient.rotated_copy(src, p, r)
        H, V = orient.score(p); ev.append({'e': 'score', 'rot': r, 'h': H, 'v': V})
    T, size = extract_sheet.extract(os.path.join(tmp, f'r{rot}.pdf'), log=lambda m: None)
    ev.append({'e': 'tags', 'size': list(size), 'tags': T})
    with open(os.path.join(out, f'{sid}.trace.jsonl'), 'w') as f:
        for e in ev: f.write(json.dumps(e, default=float) + '\n')
    return sid, len(T), sum(1 for e in ev if e['e'] == 'read')

if __name__ == '__main__':
    out = sys.argv[1]; only = sys.argv[2:]
    man = json.load(open(os.path.join(out, 'manifest.json')))
    jobs = [(out, m['id'], m['src'], m['rot']) for m in man if not only or m['id'] in only]
    with Pool(min(len(jobs), 11)) as p:
        for sid, n, reads in p.imap_unordered(run, jobs): print(sid, n, 'tags', reads, 'reads', flush=True)
