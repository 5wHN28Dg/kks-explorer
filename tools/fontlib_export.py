#!/usr/bin/env python3
"""Write the glyph library (extractor/fontlib.pkl, a Python pickle) in the documented binary format the Nim importer
reads (decision 0026; format in docs/GLYPHLIB.md):
  .venv/bin/python tools/fontlib_export.py [extractor/fontlib.pkl] [extractor/fontlib.kgl]"""
import gzip, os, pickle, struct, sys
import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'extractor', 'fontlib.pkl')
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'extractor', 'fontlib.kgl')
X, Y = pickle.load(open(src, 'rb'))
X = np.ascontiguousarray(X, dtype='<f4')
n, dim = X.shape
assert dim == 20 * 32 and len(Y) == n
body = bytearray(b'KKSGLYPH' + struct.pack('<IIHH', 1, n, 20, 32))
body += X.tobytes()
for y in Y:
    b = y.encode('utf-8'); assert len(b) < 256
    body += struct.pack('<B', len(b)) + b
with gzip.GzipFile(dst, 'wb', compresslevel=9, mtime=0) as f:
    f.write(bytes(body))
print(f'{n} glyphs, {len(set(Y))} labels → {dst} ({os.path.getsize(dst) / 1e6:.1f} MB)')
