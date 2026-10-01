#!/usr/bin/env python3
"""Generate ref/vectors/pathstore-v1.json: synthetic test vectors for the .kkp path store (docs/PATHSTORE.md).
Synthetic on purpose: plant drawings never go into the public repository.

Each valid case gives the model, the exact uncompressed file (the encoding is canonical: one model, one byte string),
a compressed file (zlib level 0 = stored blocks, identical under any zlib version) and the decoded result.
Each reject case gives bytes that every reader must refuse. FROZEN once the Nim core uses it.
  .venv/bin/python ref/make_pathstore_vectors.py [--write]"""
import json, os, struct, sys, zlib
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ref import pathstore as K

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vectors', 'pathstore-v1.json')
Q = K.Q


def stored(raw):
    """KKP1 with flags bit 0 and the body as a level-0 zlib stream."""
    return raw[:4] + struct.pack('<HH', 1, 1) + zlib.compress(raw[8:], 0)


def model_json(width, height, styles, paths, images, grid):
    return {'width': width, 'height': height, 'grid': list(grid),
            'styles': [{'kind': k, 'cap': c, 'join': j, 'width': w, 'stroke': list(s), 'fill': list(f)}
                       for k, c, j, w, s, f in styles],
            'paths': [{'style': p['style'], 'bbox': list(p['bbox']), 'cmds': [list(c) for c in p['cmds']]} for p in paths],
            'images': [{'after': i['after'], 'rect': list(i['rect']), 'data_hex': i['data'].hex()} for i in images]}


def case(why, width, height, styles, paths, images, grid):
    raw = K.encode(width, height, styles, paths, images, grid=grid, compress=False)
    doc = K.decode(raw)
    assert K.decode(stored(raw)) == doc
    return {'why': why, 'model': model_json(width, height, styles, paths, images, grid),
            'file_hex': raw.hex(), 'file_deflated_hex': stored(raw).hex(),
            'cells': doc['cells']}


def build():
    V = {'format': 'KKP1', 'note': 'Path store test vectors (docs/PATHSTORE.md). Encoders must produce file_hex exactly '
         'from the model; readers must decode both files to the model and the cells, and refuse every reject case.'}
    styles = [
        (K.STROKE, 1, 1, 46, (0, 0, 0), (0, 0, 0)),                        # 0.72 pt round
        (K.STROKE | K.HAIRLINE, 0, 0, 0, (0, 0, 0), (0, 0, 0)),             # hairline
        (K.FILL | K.EVENODD, 0, 0, 0, (0, 0, 0), (230, 46, 45)),            # even-odd red fill
        (K.FILL | K.STROKE, 0, 2, 8, (0, 0, 255), (255, 255, 255)),         # fill + stroke, bevel
        (K.FILL, 2, 0, 0, (0, 0, 0), (0, 0, 0)),                            # nonzero fill (cap ignored but kept)
    ]
    W, H = 400 * Q, 300 * Q

    def P(style, cmds, pad=0):
        xs = [c[i] for c in cmds for i in range(1, len(c), 2)]
        ys = [c[i] for c in cmds for i in range(2, len(c), 2)]
        return {'style': style, 'bbox': (max(0, min(xs) - pad), max(0, min(ys) - pad), max(xs) + pad, max(ys) + pad),
                'cmds': cmds}
    paths = [
        P(0, [('M', 10 * Q, 10 * Q), ('L', 390 * Q, 10 * Q)], 23),                                   # spans the width
        P(1, [('M', 50 * Q, 50 * Q), ('L', 60 * Q, 40 * Q), ('L', 70 * Q + 5, 55 * Q - 3)], 64),       # odd quanta, up and down
        P(2, [('M', 200 * Q, 200 * Q), ('L', 260 * Q, 200 * Q), ('L', 260 * Q, 260 * Q), ('L', 200 * Q, 260 * Q), ('Z',),
              ('M', 215 * Q, 215 * Q), ('L', 245 * Q, 215 * Q), ('L', 245 * Q, 245 * Q), ('L', 215 * Q, 245 * Q), ('Z',)]),
        P(3, [('M', 100 * Q, 150 * Q), ('C', 120 * Q, 120 * Q, 160 * Q, 120 * Q, 180 * Q, 150 * Q), ('Z',),
              ('L', 140 * Q, 190 * Q)], 4),                                                          # line after close
        P(4, [('M', 0, 0), ('L', 5 * Q, 0), ('L', 0, 5 * Q), ('Z',)]),                                # at the origin
        P(0, [('M', 399 * Q, 299 * Q), ('L', 300 * Q, 200 * Q), ('L', 399 * Q, 150 * Q), ('L', 350 * Q, 299 * Q),
              ('L', 330 * Q, 250 * Q)], 23),                                                          # 5 commands: 2 cmd bytes
    ]
    images = [{'after': 2, 'rect': (300 * Q, 20 * Q, 380 * Q, 60 * Q), 'data': b'\xff\x0a' + bytes(range(20))},
              {'after': 6, 'rect': (0, 280 * Q, 20 * Q, 300 * Q), 'data': b'\xff\x0a\x00'},
              {'after': 2, 'rect': (310 * Q, 30 * Q, 320 * Q, 40 * Q), 'data': b''}]
    V['valid'] = [
        case('styles, commands, grid spanning, images interleaved', W, H, styles, paths, images, (4, 3)),
        case('same drawing, 1×1 grid', W, H, styles, paths, images, (1, 1)),
        case('one path, no images, uneven grid division', 7 * Q + 3, 5 * Q + 1, styles[:1],
             [P(0, [('M', 1, 1), ('L', 7 * Q + 2, 5 * Q)])], [], (3, 2)),
        case('empty drawing', 10 * Q, 10 * Q, styles[:1], [], [], (1, 1)),
    ]
    V['choose_grid'] = [{'width': w, 'height': h, 'grid': list(K.choose_grid(w, h))}
                        for w, h in ((3280 * Q, 1684 * Q), (1684 * Q, 2976 * Q), (100 * Q, 100 * Q), (20000 * Q, 500 * Q))]
    V['cell_range'] = [{'v0': a, 'v1': b, 'size': s, 'n': n, 'cells': list(K.cell_range(a, b, s, n))}
                       for a, b, s, n in ((0, 0, 100, 3), (33, 34, 100, 3), (32, 34, 100, 3), (0, 99, 100, 3),
                                          (66, 67, 100, 3), (150, 200, 100, 3), (5, 5, 7, 7))]

    base = bytes.fromhex(V['valid'][0]['file_hex'])
    body = bytearray(base)

    def mut(fn):
        b = bytearray(base)
        fn(b)
        return bytes(b).hex()
    rej = []
    rej.append({'why': 'bad magic', 'file_hex': mut(lambda b: b.__setitem__(0, ord('X')))})
    rej.append({'why': 'version 2', 'file_hex': mut(lambda b: b.__setitem__(4, 2))})
    rej.append({'why': 'unknown flag bit', 'file_hex': mut(lambda b: b.__setitem__(6, 2))})
    rej.append({'why': 'grid 0 columns', 'file_hex': mut(lambda b: b.__setitem__(slice(16, 18), b'\x00\x00'))})
    rej.append({'why': 'truncated', 'file_hex': base[:-5].hex()})
    rej.append({'why': 'trailing byte', 'file_hex': (base + b'\x00').hex()})
    rej.append({'why': 'compressed flag but not zlib', 'file_hex': (base[:6] + b'\x01\x00' + base[8:]).hex()})
    rej.append({'why': 'compressed stream followed by extra bytes',
                'file_hex': (stored(base) + b'\x00').hex()})
    # hand-built small files for field-level errors
    def tiny(styles_b, paths_b=b'', n_paths=0, grid_b=b'\x00', images_b=b'', n_images=0, n_styles=1):
        out = bytearray(b'KKP1' + struct.pack('<HHIIHH', 1, 0, 100, 100, 1, 1))
        for n in (n_styles, n_paths, n_images):
            K._uv(n, out)
        return (bytes(out) + styles_b + paths_b + grid_b + images_b).hex()
    good_style = bytes([K.STROKE, 0, 0]) + b'\x01' + bytes(6)
    rej.append({'why': 'style with neither stroke nor fill', 'file_hex': tiny(bytes([0, 0, 0]) + b'\x00' + bytes(6))})
    rej.append({'why': 'style with an unknown kind bit', 'file_hex': tiny(bytes([K.STROKE | 16, 0, 0]) + b'\x00' + bytes(6))})
    rej.append({'why': 'cap 3', 'file_hex': tiny(bytes([K.STROKE, 3, 0]) + b'\x00' + bytes(6))})
    one_path = lambda st, bbox, cmds_b: bytes([st]) + bytes(bbox) + cmds_b
    rej.append({'why': 'style index out of range', 'file_hex': tiny(good_style, one_path(1, (0, 0, 1, 1), b'\x01\x00\x00\x00'), 1, b'\x01\x00')})
    rej.append({'why': 'bbox x0 > x1', 'file_hex': tiny(good_style, one_path(0, (5, 0, 1, 1), b'\x01\x00\x00\x00'), 1, b'\x01\x00')})
    rej.append({'why': 'path with no commands', 'file_hex': tiny(good_style, one_path(0, (0, 0, 1, 1), b'\x00'), 1, b'\x01\x00')})
    rej.append({'why': 'first command is a line', 'file_hex': tiny(good_style, one_path(0, (0, 0, 1, 1), b'\x01\x01\x00\x00'), 1, b'\x01\x00')})
    rej.append({'why': 'unused command bits set', 'file_hex': tiny(good_style, one_path(0, (0, 0, 1, 1), b'\x01\x04\x00\x00'), 1, b'\x01\x00')})
    rej.append({'why': 'grid index out of range', 'file_hex': tiny(good_style, one_path(0, (0, 0, 1, 1), b'\x01\x00\x00\x00'), 1, b'\x01\x01')})
    two = one_path(0, (0, 0, 1, 1), b'\x01\x00\x00\x00') * 2
    rej.append({'why': 'grid indices not ascending', 'file_hex': tiny(good_style, two, 2, b'\x02\x00\x00')})
    rej.append({'why': 'varint longer than 5 bytes', 'file_hex': tiny(good_style, n_paths=0, grid_b=b'\x80\x80\x80\x80\x80\x00')})
    rej.append({'why': 'image after more paths than exist', 'file_hex': tiny(good_style, n_images=1, images_b=b'\x01\x00\x00\x01\x01\x00')})
    V['reject'] = rej
    for r in rej:
        try:
            K.decode(bytes.fromhex(r['file_hex']))
            raise AssertionError('accepted: ' + r['why'])
        except K.FormatError:
            pass
    return V


def dump(V):
    return json.dumps(V, indent=1, sort_keys=True) + '\n'


if __name__ == '__main__':
    text = dump(build())
    if '--write' in sys.argv:
        with open(OUT, 'w', encoding='utf-8') as f:
            f.write(text)
    print('pathstore-v1.json', len(text) // 1024, 'KB')
