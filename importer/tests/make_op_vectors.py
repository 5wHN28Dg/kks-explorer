"""Synthetic cases for src/kksi/imgops.nim, computed by cv2 (OpenCV 5.0.0 here). No plant data.
  .venv/bin/python importer/tests/make_op_vectors.py importer/tests/vectors/cv2-ops.json.gz
(test_imgops.nim reads it; the committed file was made with OpenCV 5.0.0 on x86-64 with AVX2.)"""
import base64, gzip, json, sys
import numpy as np, cv2
rng = np.random.default_rng(7)
b64 = lambda a: base64.b64encode(np.ascontiguousarray(a).tobytes()).decode()
cases = []
for i in range(150):   # hull + fill, points partly outside the image like cell_image's
    W, H = int(rng.integers(20, 90)), int(rng.integers(20, 60))
    n = int(rng.integers(1, 60))
    if i % 3 == 0:   # a box-like contour
        x0, y0 = rng.integers(-20, 10, 2); x1, y1 = W + rng.integers(-10, 20), H + rng.integers(-10, 20)
        pts = np.array([[x, y0] for x in range(x0, x1)] + [[x1, y] for y in range(y0, y1)] +
                       [[x, y1] for x in range(x1, x0, -1)] + [[x0, y] for y in range(y1, y0, -1)], np.int32)
        pts += rng.integers(-2, 3, pts.shape).astype(np.int32)
    else:
        pts = np.stack([rng.integers(-30, W + 30, n), rng.integers(-30, H + 30, n)], 1).astype(np.int32)
    hull = cv2.convexHull(pts)
    m = np.zeros((H, W), np.uint8); cv2.fillPoly(m, [hull], 255)
    cases.append({'op': 'hullfill', 'w': W, 'h': H, 'pts': pts.tolist(), 'hull': hull.reshape(-1, 2).tolist(),
                  'area': float(cv2.contourArea(hull)), 'mask': b64(m)})
for i in range(40):
    W, H = int(rng.integers(5, 60)), int(rng.integers(5, 40))
    m = (rng.random((H, W)) < rng.uniform(0.3, 0.98)).astype(np.uint8) * 255
    cases.append({'op': 'erode', 'w': W, 'h': H, 'src': b64(m), 'out': b64(cv2.erode(m, np.ones((3, 3), np.uint8), iterations=3))})
for i in range(40):
    W, H = int(rng.integers(5, 80)), int(rng.integers(5, 40))
    bw = (rng.random((H, W)) < rng.uniform(0.1, 0.6)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(bw, 8)
    cases.append({'op': 'cc', 'w': W, 'h': H, 'src': b64(bw), 'n': int(n), 'labels': b64(lab.astype(np.int32)),
                  'stats': st[1:].tolist()})
for i in range(120):
    H = int(rng.integers(8, 80)); W = int(rng.integers(1, 60))
    sub = (rng.random((H, W)) < 0.4).astype(np.float32)
    s = 32 / H; dw = max(1, int(round(W * s)))
    out = cv2.resize(sub, (dw, 32), interpolation=cv2.INTER_AREA)
    cases.append({'op': 'resize', 'w': W, 'h': H, 'src': b64(sub), 'dw': dw, 'out': b64(out.astype('<f4'))})
for i in range(30):
    c = np.zeros((32, 20), np.float32); c[:, 2:18] = rng.random((32, 16)).astype(np.float32) * (rng.random((32, 16)) < 0.5)
    cases.append({'op': 'gauss', 'src': b64(c), 'out': b64(cv2.GaussianBlur(c, (3, 3), 0.8))})
# --- the reader's own steps (extractor/), on synthetic input
import os, pickle
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from extractor.fontlib import FontLib, interpret, split_chars
from extractor.reader3 import clean
for i in range(60):   # holes: boxes and rings on a blank page
    W, H = int(rng.integers(30, 120)), int(rng.integers(30, 90))
    bw = np.zeros((H, W), np.uint8)
    for k in range(int(rng.integers(1, 8))):
        x0, y0 = int(rng.integers(0, W - 6)), int(rng.integers(0, H - 6))
        x1, y1 = int(rng.integers(x0 + 4, min(W, x0 + 40))), int(rng.integers(y0 + 4, min(H, y0 + 30)))
        cv2.rectangle(bw, (x0, y0), (x1, y1), 255, int(rng.integers(1, 3)))
    bw |= ((rng.random((H, W)) < 0.03) * 255).astype(np.uint8)
    cnts, hier = cv2.findContours(bw, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    holes = []
    for j, c in enumerate(cnts):
        if hier[0][j][3] == -1: continue
        pts = np.unique(c.reshape(-1, 2), axis=0)
        holes.append({'rect': list(cv2.boundingRect(c)), 'pts': pts[np.lexsort((pts[:, 0], pts[:, 1]))].tolist()})
    cases.append({'op': 'holes', 'w': W, 'h': H, 'src': b64(bw // 255), 'holes': holes})
for i in range(60):   # clean + split_chars on a fake cell: blobs, a border arc, a mask
    W, H = int(rng.integers(120, 260)), int(rng.integers(80, 110))
    im = np.full((H, W), 255, np.uint8)
    for k in range(int(rng.integers(3, 10))):
        x, y = int(rng.integers(30, W - 40)), int(rng.integers(32, H - 45))
        cv2.rectangle(im, (x, y), (x + int(rng.integers(3, 14)), y + int(rng.integers(5, 16))), 0, -1)
    cv2.ellipse(im, (W // 2, H // 2), (W // 2 - 25, H // 2 - 26), 0, 0, 360, 0, 2)
    mask = np.zeros((H, W), np.uint8); cv2.rectangle(mask, (34, 32), (W - 35, H - 33), 255, -1)
    k_ = clean(im, mask)
    chars, band = split_chars(k_)
    cases.append({'op': 'clean', 'w': W, 'h': H, 'im': b64(im), 'mask': b64(mask), 'keep': b64(k_),
                  'chars': [[a, b] for a, b, _ in chars], 'band': list(map(int, band)) if band else None})
alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
samples = ['11LAB70', 'AA101', 'PI', '11HAD70CL503XQ01', 'TIAG', '11LAB90GP102', 'ULCQ75', '10LCB10GF001', 'LCC70',
           '', 'PDI', '1I', 'IO', '11LAB70CP101R', '11LBA70CT101K', 'O1LAB7OAA1O1']
for i in range(400):
    def rnd():
        r = rng.random()
        if r < 0.3: return samples[int(rng.integers(0, len(samples)))]
        if r < 0.5: return ''.join(alpha[int(j)] for j in rng.integers(0, 36, int(rng.integers(0, 8))))
        s = list(samples[int(rng.integers(0, len(samples)))])
        if s: s[int(rng.integers(0, len(s)))] = alpha[int(rng.integers(0, 36))]
        return ''.join(s)
    t, u = rnd(), rnd()
    cases.append({'op': 'interpret', 'top': t, 'bottom': u, 'out': interpret(t, u)})
X, Y = pickle.load(open(os.path.join(os.path.dirname(__file__), '..', '..', 'extractor', 'fontlib.pkl'), 'rb'))
lib = FontLib(X, Y)
for i in range(60):   # classify: blob glyphs (needs OPENBLAS_NUM_THREADS=1 for exact similarities)
    hc = int(rng.integers(20, 70)); w = int(rng.integers(4, 60))
    sub = (rng.random((hc, w)) < 0.3).astype(np.uint8)
    sub[:, 0] = 1; sub[0, :] = 1
    lab, conf = lib.classify(sub, hc)
    from extractor.segment import norm
    v, _ = norm(sub, hc); sc = X @ v; top = np.argsort(-sc)[:5]
    cases.append({'op': 'classify', 'w': w, 'h': hc, 'src': b64(sub), 'label': lab, 'conf': conf,
                  'sims': [float(sc[t]) for t in top]})
with gzip.GzipFile(sys.argv[1], 'wb', mtime=0) as f:
    f.write(json.dumps(cases).encode())
print(len(cases), 'cases')
