"""Reference .kkp files (vector paths only, no images) from ref/pathstore.from_pdf_page, for diff_kkp.nim. Local
only: plant data, written outside the repository.
  .venv/bin/python importer/tests/dump_kkp.py REFDIR"""
import json, os, sys
import pymupdf
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from ref import pathstore as K
d = sys.argv[1]
for m in json.load(open(os.path.join(d, 'manifest.json'))):
    page = pymupdf.open(m['src'])[0]
    w, h, styles, paths, images = K.from_pdf_page(page, m['rot'])
    open(os.path.join(d, m['id'] + '.kkp'), 'wb').write(K.encode(w, h, styles, paths, images))
    print(m['id'], len(paths), 'paths', len(styles), 'styles', flush=True)
