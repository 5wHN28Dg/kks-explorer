"""Vector version of a sheet for the viewer's sharp zoom layer.

PyMuPDF's SVG of an AutoCAD plot has one <path> per stroke (40k-140k per sheet), which browsers draw slowly.
optimize() bakes each path's transform into its coordinates and merges all black paths of the same style into one
(paint order doesn't matter when everything is black), leaving coloured paths, images, masks and text glyph <use>s
in place and in order. Result: 13-134 paths per sheet; pixel-identical in Chromium at 1x-125x (<0.07% of pixels
differ, anti-aliasing only). Standard library only; sheet_svg() needs pymupdf (importer venv)."""
import gzip, math, os, re, xml.etree.ElementTree as ET
NS = 'http://www.w3.org/2000/svg'; S = '{%s}' % NS
NUM = re.compile(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
BLACK = {None, '#000000', '#000', 'black'}


def mat(t):
    m = re.fullmatch(r'\s*matrix\(([^)]*)\)\s*', t or '')
    if not m: return None if t else (1, 0, 0, 1, 0, 0)
    return tuple(float(x) for x in re.split(r'[ ,]+', m[1].strip()))


def bake(d, M):
    """Absolute M/L/C/Z path in page units. None if the path uses commands we don't handle."""
    a, b, c, dd, e, f = M
    tr = lambda x, y: (a * x + c * y + e, b * x + dd * y + f)
    fmt = lambda p: f'{p[0]:.2f} {p[1]:.2f}'.replace('.00', '')
    tok = NUM.findall(d); i = 0; x = y = sx = sy = 0.0; out = []; cmd = None
    def nums(n):
        nonlocal i
        v = [float(t) for t in tok[i:i + n]]; i += n; return v
    while i < len(tok):
        if tok[i].isalpha(): cmd = tok[i]; i += 1
        if cmd in 'Zz': out.append('Z'); x, y = sx, sy; continue
        rel = cmd.islower(); C = cmd.upper()
        if C == 'M': px, py = nums(2); x, y = (x + px, y + py) if rel else (px, py); sx, sy = x, y; out.append('M' + fmt(tr(x, y))); cmd = 'l' if rel else 'L'
        elif C == 'L': px, py = nums(2); x, y = (x + px, y + py) if rel else (px, py); out.append('L' + fmt(tr(x, y)))
        elif C == 'H': px, = nums(1); x = x + px if rel else px; out.append('L' + fmt(tr(x, y)))
        elif C == 'V': py, = nums(1); y = y + py if rel else py; out.append('L' + fmt(tr(x, y)))
        elif C == 'C':
            v = nums(6)
            pts = [(x + v[k], y + v[k + 1]) if rel else (v[k], v[k + 1]) for k in (0, 2, 4)]
            x, y = pts[2]; out.append('C' + ' '.join(fmt(tr(*p)) for p in pts))
        else:
            return None
    return ''.join(out)


def optimize(svg_text):
    ET.register_namespace('', NS); ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
    root = ET.fromstring(svg_text)
    buckets = {}  # style -> [d]
    def walk(el, inherited_ok):
        for ch in list(el):
            if ch.tag in (S + 'defs', S + 'clipPath', S + 'mask', S + 'symbol'):
                continue
            if ch.tag == S + 'path' and inherited_ok and 'id' not in ch.attrib:
                A = ch.attrib; M = mat(A.get('transform'))
                fill, stroke = A.get('fill'), A.get('stroke')
                black = (fill in BLACK or fill == 'none') and (stroke in BLACK or stroke is None or stroke == 'none')
                if M and black and not any(k in A for k in ('opacity', 'fill-opacity', 'stroke-opacity', 'clip-path', 'mask')):
                    d = bake(A['d'], M)
                    if d is not None:
                        sc = math.sqrt(abs(M[0] * M[3] - M[1] * M[2]))
                        if stroke and stroke != 'none':
                            w = float(A.get('stroke-width', 1)) * sc
                            dash = A.get('stroke-dasharray')
                            dash = ','.join(f'{float(v) * sc:.2f}' for v in re.split(r'[ ,]+', dash.strip())) if dash and dash != 'none' else None
                            key = ('s', round(w, 3), A.get('stroke-linecap', 'butt'), A.get('stroke-linejoin', 'miter'), dash)
                        else:
                            key = ('f', A.get('fill-rule', 'nonzero'))
                        buckets.setdefault(key, []).append(d); el.remove(ch); continue
            walk(ch, inherited_ok and 'transform' not in ch.attrib)
    walk(root, True)
    for key, ds in buckets.items():
        p = ET.SubElement(root, S + 'path', d=''.join(ds))
        if key[0] == 's':
            _, w, cap, join, dash = key
            p.attrib.update({'fill': 'none', 'stroke': '#000', 'stroke-width': f'{w:g}', 'stroke-linecap': cap, 'stroke-linejoin': join})
            if dash: p.attrib['stroke-dasharray'] = dash
        else:
            p.attrib['fill-rule'] = key[1]
    return ET.tostring(root, encoding='unicode')



def sheet_svg(pdf_path, out_gz):
    """Write the optimized, gzipped SVG of page 1 of pdf_path (already rotated like the sheet image)."""
    import pymupdf
    svg = pymupdf.open(pdf_path)[0].get_svg_image(text_as_path=True)
    data = optimize(svg).encode()
    with gzip.open(out_gz + '.tmp', 'wb', compresslevel=9) as f:
        f.write(data)
    os.replace(out_gz + '.tmp', out_gz)
    return len(data)
