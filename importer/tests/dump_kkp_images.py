"""Reference images of ref/pathstore.from_pdf_page (pixels before JXL), for diff_kkp.nim. Local only (plant data).
<sid>.images.json: [{after, rect, w, h, mode}], <sid>.images.bin: RGBA bytes of each, in order.
  .venv/bin/python importer/tests/dump_kkp_images.py REFDIR"""
import json, os, sys
import numpy as np, pymupdf
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from ref import pathstore as K
d = sys.argv[1]
for m in json.load(open(os.path.join(d, 'manifest.json'))):
    page = pymupdf.open(m['src'])[0]
    got = []
    w, h, styles, paths, images = K.from_pdf_page(page, m['rot'], jxl_encode=lambda im: got.append(im) or b'')
    meta, blob = [], bytearray()
    for im, pim in zip(images, got):
        meta.append({'after': im['after'], 'rect': list(im['rect']), 'w': pim.width, 'h': pim.height, 'mode': pim.mode})
        blob += np.asarray(pim.convert('RGBA'), np.uint8).tobytes()
    json.dump(meta, open(os.path.join(d, m['id'] + '.images.json'), 'w'))
    open(os.path.join(d, m['id'] + '.images.bin'), 'wb').write(bytes(blob))
    print(m['id'], [(x['mode'], x['w'], x['h'], x['after']) for x in meta], flush=True)
