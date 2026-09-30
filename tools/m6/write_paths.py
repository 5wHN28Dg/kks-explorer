"""Pickled paths (grid_bench.py extraction pass) -> compact little-endian binary for the Android benchmark.
Format: b'KKG1', f32 w, f32 h, i32 n; per path: f32 x0 y0 x1 y1, f32 line width, i32 stroke rgb, i32 fill rgb or -1,
i32 segments; per segment: u8 type (0 line: 4 f32, 1 cubic: 8 f32, 2 rect x y w h: 4 f32, 3 quad: 8 f32)."""
import pickle, struct, sys

def rgb(c):
    return (int(c[0] * 255) << 16) | (int(c[1] * 255) << 8) | int(c[2] * 255)

for s in sys.argv[1:]:
    w, h, paths, _ = pickle.load(open(f'{s}.paths.pkl', 'rb'))
    out = bytearray(b'KKG1' + struct.pack('<ffi', w, h, len(paths)))
    for bbox, lw, col, fill, segs in paths:
        out += struct.pack('<5fiii', *bbox, lw, rgb(col), rgb(fill) if fill else -1, len(segs))
        for sg in segs:
            t = {'l': 0, 'c': 1, 're': 2, 'qu': 3}[sg[0]]
            out += struct.pack('<B', t) + struct.pack(f'<{len(sg) - 1}f', *sg[1:])
    open(f'{s}.kkg', 'wb').write(out)
    print(s, len(paths), 'paths', len(out) // 1024, 'KB')
