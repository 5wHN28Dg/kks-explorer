"""cv2.findContours holes on the detection images (dump_ref.py output), as the reader2.detect uses them.
Binary per sheet: count, then per hole (in cv2's order among holes): n, x0 y0 w h, then n unique sorted (y, x) int32."""
import json, os, struct, sys
import numpy as np, cv2
d = sys.argv[1]
man = json.load(open(os.path.join(d, 'manifest.json')))
for s in man:
    W, H = s['det']
    img = np.frombuffer(open(os.path.join(d, s['id'] + '.det.gray'), 'rb').read(), np.uint8).reshape(H, W)
    bw = (img < 215).astype(np.uint8) * 255
    cnts, hier = cv2.findContours(bw, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    holes = [(i, c) for i, c in enumerate(cnts) if hier[0][i][3] != -1]
    with open(os.path.join(d, s['id'] + '.holes.bin'), 'wb') as f:
        f.write(struct.pack('<i', len(holes)))
        for i, c in holes:
            pts = np.unique(c.reshape(-1, 2)[:, ::-1], axis=0)   # (y, x) sorted
            x, y, w, h = cv2.boundingRect(c)
            f.write(struct.pack('<5i', len(pts), x, y, w, h))
            f.write(pts.astype('<i4').tobytes())
    print(s['id'], len(cnts), 'contours,', len(holes), 'holes', flush=True)
