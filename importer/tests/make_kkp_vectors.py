"""A synthetic drawing for the .kkp writer (tests/test_kkp.nim), and what ref/pathstore.from_pdf_page makes of it.
No plant data. Writes tests/vectors/kkp-sample.pdf and kkp-sample.json:
  {"rot": R, "kkp": <base64 of the vector-only .kkp>, "images": [{"after", "rect", "w", "h", "rgba": <base64>}]}
  .venv/bin/python importer/tests/make_kkp_vectors.py"""
import base64, io, json, os, sys
import numpy as np, pymupdf
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from ref import pathstore as K
out = os.path.join(os.path.dirname(__file__), 'vectors')
doc = pymupdf.open()
page = doc.new_page(width=842, height=595)
page.set_cropbox(pymupdf.Rect(10, 12, 830, 590))
for i in range(30):                                        # strokes of several widths, hairlines, colours
    page.draw_line((40 + 20 * i, 60), (60 + 20 * i, 200 + 3 * i), color=(i % 3 == 0, 0, i % 3 == 2), width=(i % 4) * 0.35)
page.draw_bezier((100, 300), (150, 250), (250, 350), (300, 300), color=(0, 0, 0), width=1.2)
page.draw_rect(pymupdf.Rect(400, 80, 520, 160), color=(0, 0, 0), fill=(1, 1, 0), width=0.8)    # fill + stroke
page.draw_quad(pymupdf.Quad((550, 90), (650, 70), (560, 170), (670, 160)), color=(0, 0, 1), width=0.5)
page.draw_polyline([(100, 400), (160, 380), (220, 430), (100, 400)], color=(0, 0, 0), fill=(0.5, 0.5, 0.5), closePath=True)
sh = page.new_shape()                                       # even-odd fill
sh.draw_rect(pymupdf.Rect(300, 400, 420, 500)); sh.draw_rect(pymupdf.Rect(330, 430, 390, 470))
sh.finish(color=None, fill=(0.2, 0.6, 0.2), even_odd=True); sh.commit()
page.draw_circle((700, 450), 40, color=(1, 0, 0), width=2, lineCap=1, lineJoin=1)
rgba = np.zeros((24, 40, 4), np.uint8)                      # an RGBA image (soft mask), drawn upright
rgba[..., 0] = np.arange(40)[None, :] * 6; rgba[..., 1] = np.arange(24)[:, None] * 10; rgba[..., 2] = 90
rgba[..., 3] = np.where((np.arange(40)[None, :] + np.arange(24)[:, None]) % 7 == 0, 0, 255)
b = io.BytesIO(); Image.fromarray(rgba, 'RGBA').save(b, 'PNG')
page.insert_image(pymupdf.Rect(600, 250, 700, 310), stream=b.getvalue())
gray = (np.arange(16 * 16).reshape(16, 16) % 256).astype(np.uint8)
b = io.BytesIO(); Image.fromarray(gray, 'L').save(b, 'PNG')
page.insert_image(pymupdf.Rect(500, 380, 560, 440), stream=b.getvalue(), rotate=90)
page.set_rotation(90)
data = doc.tobytes(garbage=3, deflate=True)
open(os.path.join(out, 'kkp-sample.pdf'), 'wb').write(data)
page = pymupdf.open(stream=data)[0]
got = []
rot = 270
w, h, styles, paths, images = K.from_pdf_page(page, rot, jxl_encode=lambda im: got.append(im) or b'')
ims = [{'after': i['after'], 'rect': list(i['rect']), 'w': g.width, 'h': g.height,
        'rgba': base64.b64encode(np.asarray(g.convert('RGBA'), np.uint8).tobytes()).decode()} for i, g in zip(images, got)]
json.dump({'rot': rot, 'kkp': base64.b64encode(K.encode(w, h, styles, paths)).decode(), 'images': ims},
          open(os.path.join(out, 'kkp-sample.json'), 'w'))
print(len(paths), 'paths', len(styles), 'styles', len(ims), 'images', len(data), 'bytes of PDF')
