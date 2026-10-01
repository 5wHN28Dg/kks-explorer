"""The grid-indexed path store (.kkp), version 1: encoder, decoder, and a converter from PDF drawings.
Spec: docs/PATHSTORE.md. Test-only reference (the importer in Nim writes the product files).

Model (all coordinates integers in 1/64 point):
  style = (kind, cap, join, width, stroke_rgb, fill_rgb)
  path  = {'style': int, 'bbox': (x0, y0, x1, y1), 'cmds': [('M', x, y) | ('L', x, y) | ('C', x1, y1, x2, y2, x, y) | ('Z',)]}
  image = {'after': int, 'rect': (x0, y0, x1, y1), 'data': bytes}"""
import math, struct, zlib

Q = 64
MAGIC = b'KKP1'
STROKE, FILL, EVENODD, HAIRLINE = 1, 2, 4, 8
OPS = {'M': 0, 'L': 1, 'C': 2, 'Z': 3}
NPTS = {'M': 1, 'L': 1, 'C': 3, 'Z': 0}
MAX_BYTES = 256 * 2 ** 20


class FormatError(ValueError):
    pass


# ---------- varints ----------
def _uv(n, out):
    if not 0 <= n < 2 ** 32:
        raise FormatError(f'varint out of range: {n}')
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return


def _sv(n, out):
    if not -2 ** 31 <= n < 2 ** 31:
        raise FormatError(f'svarint out of range: {n}')
    _uv(((n << 1) ^ (n >> 31)) & 0xFFFFFFFF, out)


class _R:
    def __init__(self, b):
        self.b, self.p = b, 0

    def take(self, n):
        if self.p + n > len(self.b):
            raise FormatError('truncated')
        v = self.b[self.p:self.p + n]
        self.p += n
        return v

    def u8(self):
        return self.take(1)[0]

    def u16(self):
        return struct.unpack('<H', self.take(2))[0]

    def u32(self):
        return struct.unpack('<I', self.take(4))[0]

    def uv(self):
        n = shift = 0
        for i in range(5):
            b = self.u8()
            n |= (b & 0x7F) << shift
            if not b & 0x80:
                if n >= 2 ** 32:
                    raise FormatError('varint too large')
                return n
            shift += 7
        raise FormatError('varint longer than 5 bytes')

    def sv(self):
        z = self.uv()
        return (z >> 1) ^ -(z & 1)


# ---------- grid ----------
def cell_range(v0, v1, size, n):
    """Cells (0..n-1) an interval [v0, v1] touches, with cell i = [i*size//n, (i+1)*size//n)."""
    def cell(v):
        v = min(max(v, 0), size - 1) if size > 0 else 0
        lo, hi = 0, n - 1
        while lo < hi:   # the last i with i*size//n <= v
            mid = (lo + hi + 1) // 2
            if mid * size // n <= v:
                lo = mid
            else:
                hi = mid - 1
        return lo
    return range(cell(v0), cell(v1) + 1)


def build_grid(width, height, paths, gx, gy):
    cells = [[] for _ in range(gx * gy)]
    for i, p in enumerate(paths):
        x0, y0, x1, y1 = p['bbox']
        for cy in cell_range(y0, y1, height, gy):
            for cx in cell_range(x0, x1, width, gx):
                cells[cy * gx + cx].append(i)
    return cells


def choose_grid(width, height, cell_pt=100):
    """docs/PATHSTORE.md: cells of about 100 pt, 8..64 on the longer side."""
    long = max(width, height)
    g = max(8, min(64, math.ceil(long / (cell_pt * Q))))
    return max(1, round(g * width / long)), max(1, round(g * height / long))


# ---------- encode / decode ----------
def encode(width, height, styles, paths, images=(), grid=None, compress=True):
    gx, gy = grid or choose_grid(width, height)
    out = bytearray(struct.pack('<IIHH', width, height, gx, gy))
    for n in (len(styles), len(paths), len(images)):
        _uv(n, out)
    for kind, cap, join, w, stroke, fill in styles:
        if kind & ~15 or not kind & (STROKE | FILL) or cap > 2 or join > 2:
            raise FormatError('bad style')
        out += bytes([kind, cap, join])
        _uv(w, out)
        out += bytes(stroke) + bytes(fill)
    for p in paths:
        _uv(p['style'], out)
        for v in p['bbox']:
            _uv(v, out)
        cmds = p['cmds']
        if not cmds or cmds[0][0] != 'M':
            raise FormatError('a path starts with a move')
        _uv(len(cmds), out)
        packed = bytearray((len(cmds) + 3) // 4)
        for i, c in enumerate(cmds):
            packed[i // 4] |= OPS[c[0]] << (2 * (i % 4))
        out += packed
        px, py = p['bbox'][0], p['bbox'][1]
        for c in cmds:
            pts = c[1:]
            if len(pts) != 2 * NPTS[c[0]]:
                raise FormatError(f'wrong point count for {c[0]}')
            for j in range(0, len(pts), 2):
                _sv(pts[j] - px, out)
                _sv(pts[j + 1] - py, out)
                px, py = pts[j], pts[j + 1]
    for cell in build_grid(width, height, paths, gx, gy):
        _uv(len(cell), out)
        prev = None
        for i in cell:
            _uv(i if prev is None else i - prev, out)
            prev = i
    for im in images:
        _uv(im['after'], out)
        for v in im['rect']:
            _uv(v, out)
        _uv(len(im['data']), out)
        out += im['data']
    head = MAGIC + struct.pack('<HH', 1, 1 if compress else 0)
    return head + (zlib.compress(bytes(out), 9) if compress else bytes(out))


def decode(b):
    """-> dict(width, height, grid=(gx, gy), styles, paths, cells, images). Raises FormatError on any violation."""
    if len(b) > MAX_BYTES:
        raise FormatError('file too large')
    if len(b) < 8 or b[:4] != MAGIC:
        raise FormatError('not a KKP1 file')
    version, flags = struct.unpack('<HH', b[4:8])
    if version != 1 or flags & ~1:
        raise FormatError('unsupported version or flags')
    body = b[8:]
    if flags & 1:
        d = zlib.decompressobj()
        try:
            body = d.decompress(body, MAX_BYTES + 1)
        except zlib.error:
            raise FormatError('bad zlib stream')
        if len(body) > MAX_BYTES or not d.eof or d.unused_data:
            raise FormatError('zlib stream: too large, truncated or followed by other bytes')
    r = _R(body)
    width, height, gx, gy = r.u32(), r.u32(), r.u16(), r.u16()
    if not (1 <= gx <= 1024 and 1 <= gy <= 1024):
        raise FormatError('bad grid')
    ns, np_, ni = r.uv(), r.uv(), r.uv()
    styles = []
    for _ in range(ns):
        kind, cap, join = r.u8(), r.u8(), r.u8()
        if kind & ~15 or not kind & (STROKE | FILL) or cap > 2 or join > 2:
            raise FormatError('bad style')
        styles.append((kind, cap, join, r.uv(), tuple(r.take(3)), tuple(r.take(3))))
    paths = []
    names = {v: k for k, v in OPS.items()}
    for _ in range(np_):
        st = r.uv()
        if st >= ns:
            raise FormatError('style index')
        bbox = tuple(r.uv() for _ in range(4))
        if bbox[0] > bbox[2] or bbox[1] > bbox[3]:
            raise FormatError('bbox')
        n = r.uv()
        if n < 1:
            raise FormatError('empty path')
        packed = r.take((n + 3) // 4)
        ops = [names[(packed[i // 4] >> (2 * (i % 4))) & 3] for i in range(n)]
        if n % 4 and packed[-1] >> (2 * (n % 4)):
            raise FormatError('unused command bits set')
        if ops[0] != 'M':
            raise FormatError('a path starts with a move')
        px, py = bbox[0], bbox[1]
        cmds = []
        for op in ops:
            pts = []
            for _ in range(NPTS[op]):
                px += r.sv()
                py += r.sv()
                pts += [px, py]
            cmds.append((op, *pts))
        paths.append({'style': st, 'bbox': bbox, 'cmds': cmds})
    cells = []
    for _ in range(gx * gy):
        cnt = r.uv()
        cell = []
        for k in range(cnt):
            d = r.uv()
            if k and d == 0:
                raise FormatError('grid indices must ascend')
            cell.append(d if k == 0 else cell[-1] + d)
        if cell and cell[-1] >= np_:
            raise FormatError('grid index')
        cells.append(cell)
    images = []
    for _ in range(ni):
        after = r.uv()
        if after > np_:
            raise FormatError('image position')
        rect = tuple(r.uv() for _ in range(4))
        images.append({'after': after, 'rect': rect, 'data': bytes(r.take(r.uv()))})
    if r.p != len(body):
        raise FormatError('trailing bytes')
    return {'width': width, 'height': height, 'grid': (gx, gy), 'styles': styles, 'paths': paths, 'cells': cells,
            'images': images}


# ---------- from a PDF page (PyMuPDF; importer and measurements) ----------
def _q(v):
    return int(round(v * Q))


def from_pdf_page(page, extra_rotation=0, jxl_encode=None):
    """-> (width, height, styles, paths, images) for one PDF page, in display orientation. extra_rotation = degrees
    clockwise on top of the page's own rotation (the importer's choice, sheets.json `rot`)."""
    import pymupdf
    m = page.rotation_matrix * pymupdf.Matrix(extra_rotation)
    r = page.rect * pymupdf.Matrix(extra_rotation)          # page.rect is already in the page's rotated frame
    shift = pymupdf.Matrix(1, 0, 0, 1, -r.x0, -r.y0)
    m = m * shift
    width, height = _q(r.width), _q(r.height)
    style_ids, styles, paths = {}, [], []
    for d in sorted(page.get_drawings(), key=lambda d: d['seqno']):
        t = d['type']
        kind = (STROKE if 's' in t else 0) | (FILL if 'f' in t else 0)
        if 'f' in t and d.get('even_odd'):
            kind |= EVENODD
        w = d.get('width') or 0
        if 's' in t and w == 0:
            kind |= HAIRLINE
        if d.get('dashes') not in (None, '[] 0', '[] 0.0', '[] 0.00'):
            raise FormatError(f'dash pattern not supported: {d["dashes"]}')
        cap = (d.get('lineCap') or (0,))[0] if 's' in t else 0
        join = int(d.get('lineJoin') or 0) if 's' in t else 0
        rgb = lambda c: tuple(int(round(max(0, min(1, x)) * 255)) for x in (c or (0, 0, 0))[:3])
        scale = math.sqrt(abs(m.a * m.d - m.b * m.c))
        wq = _q(w * scale) if 's' in t and w else 0
        st = (kind, int(cap), join, wq, rgb(d.get('color')) if 's' in t else (0, 0, 0),
              rgb(d.get('fill')) if 'f' in t else (0, 0, 0))
        if st not in style_ids:
            style_ids[st] = len(styles)
            styles.append(st)
        cmds, cur, start = [], None, None

        def pt(p):
            q = p * m
            return _q(q.x), _q(q.y)
        for it in d['items']:
            op = it[0]
            if op in ('l', 'c'):
                a = pt(it[1])
                if a != cur:
                    cmds.append(('M', *a))
                    start = a
                if op == 'l':
                    cur = pt(it[2])
                    cmds.append(('L', *cur))
                else:
                    c1, c2, cur = pt(it[2]), pt(it[3]), pt(it[4])
                    cmds.append(('C', *c1, *c2, *cur))
            elif op in ('re', 'qu'):
                if op == 're':
                    rc = it[1]
                    corners = [rc.tl, rc.tr, rc.br, rc.bl]
                else:
                    qd = it[1]
                    corners = [qd.ul, qd.ur, qd.lr, qd.ll]
                ps = [pt(c) for c in corners]
                cmds.append(('M', *ps[0]))
                cmds += [('L', *p) for p in ps[1:]]
                cmds.append(('Z',))
                cur = start = ps[0]
            else:
                raise FormatError(f'unknown drawing item {op}')
        if d.get('closePath'):
            cmds.append(('Z',))
        if not cmds:
            continue
        xs = [c[i] for c in cmds for i in range(1, len(c), 2)]
        ys = [c[i] for c in cmds for i in range(2, len(c), 2)]
        pad = (wq + 1) // 2 + (Q if kind & HAIRLINE else 0)
        bbox = (max(0, min(xs) - pad), max(0, min(ys) - pad), max(xs) + pad, max(ys) + pad)
        paths.append({'style': style_ids[st], 'bbox': bbox, 'cmds': cmds, 'seqno': d['seqno']})
    images = []
    if jxl_encode is not None:
        images = _images(page, m, paths, jxl_encode)
    for p in paths:
        p.pop('seqno', None)
    return width, height, styles, paths, images


def _images(page, m, paths, jxl_encode):
    """Images in paint order: pixels from the page's image blocks, positions from the bbox log."""
    import io
    from PIL import Image
    log = page.get_bboxlog()
    seqnos = sorted(p['seqno'] for p in paths)
    blocks = [b for b in page.get_text('dict')['blocks'] if b.get('type') == 1]
    out, used = [], set()
    import bisect
    for i, (kind, bbox) in enumerate(log):
        if 'image' not in kind:
            continue
        # match the logged image to an image block by its box
        best = min((j for j in range(len(blocks)) if j not in used),
                   key=lambda j: sum(abs(a - b) for a, b in zip(blocks[j]['bbox'], bbox)), default=None)
        if best is None:
            continue
        used.add(best)
        blk = blocks[best]
        # the block transform maps the unit square to the image in unrotated page space, (0,0) = top-left pixel,
        # (1,0) along the columns, (0,1) along the rows. Compose with the display matrix and bake any quarter turn or
        # flip into the pixels, so the stored image is upright (docs/PATHSTORE.md: images are axis-aligned).
        import pymupdf
        T = pymupdf.Matrix(blk['transform']) * m
        eps = 1e-6 * max(abs(T.a), abs(T.b), abs(T.c), abs(T.d), 1)
        im = Image.open(io.BytesIO(blk['image']))
        if blk.get('mask'):   # a soft mask arrives as its own encoded image: it becomes the alpha channel
            a = Image.open(io.BytesIO(blk['mask'])).convert('L')
            im = im.convert('RGBA')
            im.putalpha(a.resize(im.size) if a.size != im.size else a)
        else:
            im = im.convert('RGBA' if im.mode in ('RGBA', 'LA', 'P') and 'transparency' in im.info or im.mode == 'RGBA' else 'RGB')
        if abs(T.b) <= eps and abs(T.c) <= eps:          # columns along x, rows along y
            if T.a < 0:
                im = im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if T.d < 0:
                im = im.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        elif abs(T.a) <= eps and abs(T.d) <= eps:        # columns along y, rows along x: swap axes first
            im = im.transpose(Image.Transpose.TRANSPOSE)
            if T.c < 0:
                im = im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if T.b < 0:
                im = im.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        else:
            raise FormatError('image drawn at an angle other than a quarter turn: not supported')
        corners = [pymupdf.Point(x, y) * T for x, y in ((0, 0), (1, 0), (0, 1), (1, 1))]
        rect = (_q(min(c.x for c in corners)), _q(min(c.y for c in corners)),
                _q(max(c.x for c in corners)), _q(max(c.y for c in corners)))
        out.append({'after': bisect.bisect_left(seqnos, i), 'rect': rect, 'data': jxl_encode(im)})
    return out
