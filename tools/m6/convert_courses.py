"""Converts the three HTML courses (data/courses/*.html) to the JSON content model (docs/COURSES.md), decision 0025.

  /path/to/venv-with-playwright/bin/python tools/m6/convert_courses.py dump RAWDIR
      evaluates each course's script in headless Chromium and writes RAWDIR/<course>.json: the modules with their
      bodies as HTML, the questions, glossary, tests, drills and the static pages as HTML
  /path/to/venv-with-pillow/bin/python tools/m6/convert_courses.py build RAWDIR OUTDIR
      converts the HTML to blocks and runs, the static SVG diagrams to static figures, attaches the 16 animated
      figures (tools/m6/course_figures.py), writes OUTDIR/courses/<file>.json and the images as .jxl (cjxl), and
      validates every course with ref/courses.py

The dump holds the courses' text only; they are public (data/courses is in the repo)."""
import base64, html, io, json, math, os, re, subprocess, sys, tempfile
from html.parser import HTMLParser

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, REPO)
sys.path.insert(0, os.path.join(REPO, 'tools', 'm6'))

COURSES = [  # (file, id, order)
    ('1-power-plant-technology.html', 'ppt', 1),
    ('2-plant-foundations.html', 'fnd', 2),
    ('3-hrsg-course.html', 'hrsg', 3),
]

# ---------------------------------------------------------------- stage 1: dump

DUMP_JS = r"""() => {
  const q = x => x && ({type: x.type, id: x.id, q: x.q, o: x.o, steps: x.steps, panel: x.panel, src: x.src});
  const out = {modules: M.map(m => ({id: m.id, n: m.n, title: m.title, short: m.short, goal: m.goal, body: m.body(),
      warm: q(m.warm), worked: m.worked || null, practice: (m.practice || []).map(q), bridge: (m.bridge || []).map(q)})),
    extra: EXTRA, title: document.title,
    short: document.querySelector('.brand small').textContent};
  if (typeof PLACE !== 'undefined') out.place = PLACE.map(([m, x]) => ({m, q: q(x)}));
  if (typeof FINAL !== 'undefined') out.final = FINAL.map(it => ({m: it.m, q: q(it.q)}));
  if (typeof GLOSS !== 'undefined') out.gloss = GLOSS;
  if (typeof DRILL !== 'undefined') out.drill = DRILL.map(d => ({cat: d.cat, p: d.p, u: d.u, ctx: d.ctx, vals: d.vals,
      note: d.note, j: d.j.toString(), judged: d.vals.map(d.j)}));
  if (typeof AUDIT !== 'undefined') out.audit = AUDIT;
  out.pages = {};
  for (const e of EXTRA) { go(e.id); VIS.stop(); out.pages[e.id] = document.getElementById('main').innerHTML; }
  return out;
}"""


def dump(rawdir):
    from playwright.sync_api import sync_playwright
    os.makedirs(rawdir, exist_ok=True)
    with sync_playwright() as p:
        b = p.chromium.launch()
        for file, cid, _ in COURSES:
            page = b.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto('file://' + os.path.join(REPO, 'data', 'courses', file))
            page.wait_for_function('() => typeof M !== "undefined" && M.length > 0')
            d = page.evaluate(DUMP_JS)
            d['errors'] = errors
            with open(os.path.join(rawdir, cid + '.json'), 'w') as f:
                json.dump(d, f, ensure_ascii=False, indent=0)
            print(cid, len(d['modules']), 'modules', 'errors:', errors)
            page.close()
        b.close()


# ---------------------------------------------------------------- a small DOM

class El:
    def __init__(self, tag, attrs):
        self.tag, self.attrs, self.kids = tag, attrs, []

    @property
    def cls(self): return self.attrs.get('class', '').split()

    def has(self, c): return c in self.cls

    def __repr__(self): return '<%s %s>' % (self.tag, self.attrs.get('class', ''))


VOID = {'br', 'img', 'input', 'hr', 'meta', 'source', 'wbr'}


class Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = El('#root', {})
        self.st = [self.root]

    def handle_starttag(self, tag, attrs):
        e = El(tag, {k: (v if v is not None else '') for k, v in attrs})
        self.st[-1].kids.append(e)
        if tag not in VOID:
            self.st.append(e)

    def handle_startendtag(self, tag, attrs):
        self.st[-1].kids.append(El(tag, {k: (v if v is not None else '') for k, v in attrs}))

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        for i in range(len(self.st) - 1, 0, -1):
            if self.st[i].tag == tag:
                del self.st[i:]
                return
        raise ValueError('stray </%s>' % tag)

    def handle_data(self, d):
        self.st[-1].kids.append(d)


def parse_html(s):
    t = Tree()
    t.feed(s)
    t.close()
    return t.root


def text_of(e):
    if isinstance(e, str):
        return e
    return ''.join(text_of(k) for k in e.kids)


class Bad(Exception):
    pass


# ---------------------------------------------------------------- runs

def course_link(href):
    for file, cid, _ in COURSES:
        if href == file:
            return {'course': cid}
    if href.startswith('http://creativecommons.org/'):
        href = 'https://' + href[len('http://'):]
    if href.startswith('https://'):
        return {'url': href}
    raise Bad('link ' + href)


def run_items(nodes, ctx):
    out = []
    for n in nodes:
        if isinstance(n, str):
            out.append(n)
            continue
        t, c = n.tag, n.cls
        if t in ('b', 'strong'):
            out.append({'b': run_items(n.kids, ctx)})
        elif t in ('i', 'em'):
            out.append({'i': run_items(n.kids, ctx)})
        elif t == 'small':
            out.append({'small': run_items(n.kids, ctx)})
        elif t == 'span' and 'num' in c:
            out.append({'num': norm_space(text_of(n)).strip()})
        elif t == 'span' and 'credit' in c:
            out.extend(run_items(n.kids, ctx))
        elif t == 'span' and 'pill' in c:
            out.append({'b': [text_of(n)]})
        elif t == 'span' and not c:
            out.extend(run_items(n.kids, ctx))
        elif t == 'a':
            out.append({'link': run_items(n.kids, ctx), 'to': course_link(n.attrs['href'])})
        elif t == 'button' and 'gochip' in c:
            out.append({'link': run_items(n.kids, ctx), 'to': {'page': n.attrs['data-go']}})
        elif t == 'br':
            out.append('\n')
        else:
            raise Bad('%s: inline %r' % (ctx, n))
    return out


def norm_space(s):
    return re.sub(r'[ \t\r\n\f]+', ' ', s)


def tidy(items):
    """collapse HTML whitespace, merge strings, trim the ends, drop empty items"""
    def walk(it):
        res = []
        for x in it:
            if isinstance(x, str):
                x = norm_space(x)
                if res and isinstance(res[-1], str):
                    res[-1] += x
                elif x:
                    res.append(x)
            else:
                x = dict(x)
                for k in ('b', 'i', 'small', 'link', 'term'):
                    if k in x:
                        x[k] = walk(x[k])
                        if not x[k]:
                            x = None
                        break
                if x is not None:
                    res.append(x)
        return res
    r = walk(items)

    def trim(r, left):
        if not r:
            return r
        i = 0 if left else -1
        x = r[i]
        if isinstance(x, str):
            x = x.lstrip(' ') if left else x.rstrip(' ')
            if x:
                r[i] = x
            else:
                r.pop(i)
                return trim(r, left)
        else:
            for k in ('b', 'i', 'small', 'link'):
                if k in x:
                    x[k] = trim(x[k], left)
                    if not x[k]:
                        r.pop(i)
                        return trim(r, left)
        return r
    return trim(trim(r, True), False)


def run(nodes_or_html, ctx, allow_empty=False):
    nodes = parse_html(nodes_or_html).kids if isinstance(nodes_or_html, str) else nodes_or_html
    r = tidy(run_items(nodes, ctx))
    if not r and not allow_empty:
        raise Bad(ctx + ': empty run')
    return r


def plain(html_s):
    return norm_space(text_of(parse_html(html_s))).strip()


# ---------------------------------------------------------------- static SVG diagrams → static figures (§9)

TOKENS = {'ink': 'ink', 'muted': 'muted', 'rule': 'rule', 'accent': 'accent', 'act': 'act', 'ok': 'ok', 'alarm': 'alarm',
          'alarm-fill': 'alarm_fill', 'surface': 'surface', 'sunk': 'sunk', 'ground': 'ground',
          # not theme tokens in the model: nearest token (zone-ok #CFD8DC / #26323A vs rule #C6CFD4 / #2B363D), or
          # the token at a reduced opacity (accent-soft = accent over the surface)
          'zone-ok': 'rule', 'accent-soft': ('accent', 0.18)}

# the static diagrams, by the start of their aria-label: (figure id, title)
STATIC = [
    ('Valve flow characteristics', 'valve_char', 'Valve flow characteristics'),
    ('Pump curve and two system curves', 'pump_curve', 'Pump curve and system curves'),
    ('Diverter damper, bypass stack', 'damper_layout', 'Diverter damper and bypass stack'),
    ('Combined cycle:', 'cycle', 'The combined cycle'),
    ('Water saturation temperature', 'saturation', 'Boiling temperature against pressure'),
    ('Drum level protection ladder', 'level_ladder', 'Drum level protection ladder'),
    ('HP system (MPa) pressure settings', 'press_hp', 'HP system pressure settings (MPa)'),
    ('IP system (MPa) pressure settings', 'press_ip', 'IP system pressure settings (MPa)'),
    ('Reheat (MPa) pressure settings', 'press_rh', 'Reheat pressure settings (MPa)'),
    ('LP system (MPa) pressure settings', 'press_lp', 'LP system pressure settings (MPa)'),
]


def number(s):
    v = float(s)
    return int(v) if v == int(v) and abs(v) < 1e9 else round(v, 3)


def paint(v, ctx):
    """→ (paint, opacity factor)"""
    v = v.strip()
    if v in ('none', 'transparent'):
        return 'none', 1
    m = re.fullmatch(r'var\(--([a-z-]+)\)', v)
    if m:
        t = TOKENS.get(m[1])
        if t is None:
            raise Bad('%s: colour %s' % (ctx, v))
        return (t, 1) if isinstance(t, str) else t
    if re.fullmatch(r'#[0-9a-fA-F]{6}', v):
        return v.upper(), 1
    if re.fullmatch(r'#[0-9a-fA-F]{3}', v):
        return '#' + ''.join(c * 2 for c in v[1:]).upper(), 1
    raise Bad('%s: colour %s' % (ctx, v))


def style_of(e):
    st = {k: v for k, v in e.attrs.items()}
    for decl in e.attrs.get('style', '').split(';'):
        if ':' in decl:
            k, v = decl.split(':', 1)
            st[k.strip()] = v.strip()
    return st


def font_role(fam):
    f = fam.lower()
    if 'mono' in f:
        return 'mono'
    if 'barlow' in f or 'display' in f:
        return 'display'
    return 'body'


def svg_figure(svg, caption, ctx):
    label = svg.attrs.get('aria-label', '')
    hit = [s for s in STATIC if label.startswith(s[0])]
    if len(hit) != 1:
        raise Bad('%s: unknown static diagram %r' % (ctx, label))
    _, fid, title = hit[0]
    vb = [float(x) for x in svg.attrs['viewbox'].split()]
    if vb[0] or vb[1]:
        raise Bad(ctx + ': viewBox origin')
    markers = {}
    scene = []

    def common(el, st, ctx2):
        op = 1.0
        if 'fill' in st:
            el['fill'], f = paint(st['fill'], ctx2)
            op *= f
        if 'stroke' in st:
            el['stroke'], f = paint(st['stroke'], ctx2)
        if 'stroke-width' in st:
            el['stroke_width'] = number(st['stroke-width'].replace('px', ''))
        if 'opacity' in st:
            op *= float(st['opacity'])
        if op != 1:
            el['opacity'] = round(op, 4)
        if 'stroke-dasharray' in st and st['stroke-dasharray'] not in ('none', '0'):
            el['dash'] = [number(x) for x in re.split(r'[ ,]+', st['stroke-dasharray'].strip())]
        if st.get('stroke-linecap') in ('round', 'square'):
            el['cap'] = st['stroke-linecap']
        if st.get('stroke-linejoin') in ('round', 'bevel'):
            el['join'] = st['stroke-linejoin']
        if 'transform' in st:
            tf = []
            for name, args in re.findall(r'(\w+)\(([^)]*)\)', st['transform']):
                a = [number(x) for x in re.split(r'[ ,]+', args.strip())]
                if name == 'rotate':
                    tf.append({'rotate': (a + [0, 0])[:3]})
                elif name == 'translate':
                    tf.append({'translate': (a + [0])[:2]})
                elif name == 'scale':
                    tf.append({'scale': a if len(a) == 2 else [a[0], a[0]]})
                else:
                    raise Bad(ctx2 + ': transform ' + name)
            el['transform'] = tf
        return el

    def walk(e, out):
        for k in e.kids:
            if isinstance(k, str):
                if k.strip():
                    raise Bad(ctx + ': text outside <text>')
                continue
            st = style_of(k)
            t = k.tag
            if t == 'defs':
                for m in k.kids:
                    if isinstance(m, El) and m.tag == 'marker':
                        markers[m.attrs['id']] = True
                continue
            g = lambda n: number(st[n])
            if t == 'rect':
                el = {'rect': [g('x'), g('y'), g('width'), g('height')]}
                if 'rx' in st:
                    el['rx'] = g('rx')
            elif t == 'circle':
                el = {'circle': [g('cx'), g('cy'), g('r')]}
            elif t == 'ellipse':
                el = {'ellipse': [g('cx'), g('cy'), g('rx'), g('ry')]}
            elif t == 'line':
                el = {'line': [g('x1'), g('y1'), g('x2'), g('y2')]}
            elif t == 'path':
                from course_figures import parse_d
                el = {'path': parse_d(st['d'])}
            elif t == 'text':
                txt = norm_space(text_of(k)).strip().replace('{', '{{').replace('}', '}}')
                el = {'text': txt, 'at': [g('x'), g('y')]}
                if st.get('text-anchor', 'start') != 'start':
                    el['anchor'] = st['text-anchor']
                if 'font-size' in st:
                    sz = number(st['font-size'].replace('px', ''))
                    if sz != 12:
                        el['size'] = sz
                role = font_role(st.get('font-family', 'body'))
                if role != 'body':
                    el['font'] = role
                w = st.get('font-weight', '400')
                w = {'bold': '700', 'normal': '400'}.get(w, w)
                if w != '400':
                    el['weight'] = int(w)
            elif t == 'g':
                el = {'group': []}
                walk(k, el['group'])
            else:
                raise Bad('%s: svg <%s>' % (ctx, t))
            common(el, st, ctx)
            # SVG defaults: shapes fill black unless told otherwise; text fills black
            if t in ('rect', 'circle', 'ellipse', 'path') and 'fill' not in st:
                el['fill'] = 'ink'
            if t == 'text' and 'fill' not in st:
                el['fill'] = 'ink'
            if t == 'text' and el.get('fill') == 'ink':
                del el['fill']
            if el.get('fill') == 'none' and t != 'text':
                del el['fill']
            if 'marker-end' in st:
                if t == 'line':
                    el['arrow'] = True
                elif t == 'path':
                    # the model's arrowhead is on lines only: add a line along the path's last segment
                    a, b = el['path'][-2], el['path'][-1]
                    x1, y1, x2, y2 = a[-2], a[-1], b[-2], b[-1]
                    ln = math.hypot(x2 - x1, y2 - y1)
                    out.append(el)
                    el = {'line': [round(x2 - (x2 - x1) / ln, 3), round(y2 - (y2 - y1) / ln, 3), x2, y2], 'arrow': True,
                          'stroke': el.get('stroke', 'ink'), 'stroke_width': el.get('stroke_width', 1)}
            out.append(el)
    walk(svg, scene)
    return fid, {'title': title, 'caption': caption, 'alt': label, 'w': math.ceil(vb[2]), 'h': math.ceil(vb[3]),
                 'scene': scene}


# ---------------------------------------------------------------- blocks

SHARED_IMAGES = {}   # source bytes → file name, across the courses


class Conv:
    """one course's conversion state: figures and images found while converting blocks"""

    def __init__(self, cid):
        self.cid = cid
        self.figures = {}       # id → figure
        self.images = []        # (file, bytes of the source image)
        self.anim = None

    def elems(self, node):
        return [k for k in node.kids if isinstance(k, El) or k.strip()]

    def blocks(self, nodes, ctx):
        out = []
        for n in nodes:
            if isinstance(n, str):
                if n.strip():
                    raise Bad('%s: loose text %r' % (ctx, n[:60]))
                continue
            out.extend(self.block(n, ctx))
        return out

    def block(self, n, ctx):
        t, c = n.tag, n.cls
        if t in ('h2', 'h3'):
            return [{'h': run(n.kids, ctx), 'level': 2 if t == 'h2' else 3}]
        if t == 'p':
            r = run(n.kids, ctx, allow_empty=True)
            if not r:
                return []
            return [{'p': [{'small': r}] if 'src' in c else r}]
        if t in ('ul', 'ol') and 'issues' in c:
            return [{'issues': [self.issue(li, ctx) for li in self.elems(n)]}]
        if t in ('ul', 'ol'):
            items = []
            for li in self.elems(n):
                if li.tag != 'li':
                    raise Bad(ctx + ': list item ' + li.tag)
                items.append(run(li.kids, ctx))
            return [{t: items}]
        if t == 'div' and 'tablewrap' in c:
            return [self.table(self.elems(n)[0], ctx)]
        if t == 'table':
            return [self.table(n, ctx)]
        if t == 'div' and ('why' in c or 'flag' in c):
            return [self.callout(n, ctx)]
        if t == 'div' and 'intro-grid' in c:
            cards = []
            for d in self.elems(n):
                head = d.kids[0]
                if not (isinstance(head, El) and head.tag == 'b'):
                    raise Bad(ctx + ': card without a title')
                cards.append([run(head.kids, ctx), run(d.kids[1:], ctx)])
            return [{'cards': cards}]
        if t == 'div' and 'chain' in c:
            return [{'chain': [run(s.kids, ctx) for s in self.elems(n) if 'link' in s.cls]}]
        if t == 'div' and 'kks' in c:
            # the coloured KKS segments: code over its meaning, as cards
            return [{'cards': [[run(s.kids[0].kids, ctx), run(s.kids[1].kids, ctx)] for s in self.elems(n)]}]
        if t == 'div' and 'photo-row' in c:
            return [b for f in self.elems(n) for b in self.block(f, ctx)]
        if t == 'figure' and 'photo' in c:
            return [self.image(n, ctx)]
        if t == 'figure' and 'vis' in c:
            fid = n.attrs['data-vis']
            if fid not in self.anim:
                raise Bad(ctx + ': no converted figure ' + fid)
            f = dict(self.anim[fid])
            f['title'] = norm_space(text_of([k for k in self.elems(n) if 'vis-head' in k.cls][0].kids[0])).strip()
            f['caption'] = run([k for k in self.elems(n) if k.tag == 'figcaption'][0].kids, ctx)
            self.add_figure(fid, f, ctx)
            return [{'figure': fid}]
        if t == 'div' and 'figure' in c:
            svg = [k for k in self.elems(n) if k.tag == 'svg'][0]
            cap = [k for k in self.elems(n) if 'figcap' in k.cls]
            fid, f = svg_figure(svg, run(cap[0].kids, ctx) if cap else [], ctx)
            self.add_figure(fid, f, ctx)
            return [{'figure': fid}]
        raise Bad('%s: block %r' % (ctx, n))

    def add_figure(self, fid, f, ctx):
        if fid in self.figures and self.figures[fid] != f:
            raise Bad('%s: figure %s used twice with different content' % (ctx, fid))
        self.figures[fid] = f

    def issue(self, li, ctx):
        k = [x for x in li.kids if isinstance(x, El) or x.strip()]
        pill, title, rest = k[0], k[1], li.kids[li.kids.index(k[1]) + 1:]
        if 'pill' not in pill.cls or title.tag != 'b':
            raise Bad(ctx + ': issue shape')
        sev = text_of(pill).strip().lower()
        t = norm_space(text_of(title)).strip().rstrip('.')
        return [sev, [t], run(rest, ctx)]

    def table(self, tb, ctx):
        head, rows, num = [], [], set()
        for sect in self.elems(tb):
            for tr in self.elems(sect):
                cells = self.elems(tr)
                if sect.tag == 'thead':
                    head = [run(th.kids, ctx, allow_empty=True) for th in cells]
                else:
                    rows.append([run(td.kids, ctx, allow_empty=True) for td in cells])
                    num |= {i for i, td in enumerate(cells) if 'v' in td.cls}
        for r in rows:
            if len(r) != len(head):
                raise Bad(ctx + ': table row length')
        return {'table': {'head': head, 'rows': rows, 'num': sorted(num)}}

    def callout(self, n, ctx):
        kids = [k for k in n.kids if isinstance(k, El) or k.strip()]
        first = kids[0]
        if 'why' in n.cls:
            if not (isinstance(first, El) and 'tag' in first.cls):
                raise Bad(ctx + ': why without a tag')
            label = norm_space(text_of(first)).strip()
            kind = ('why_general' if 'general' in label else 'at_plant' if label.startswith('At ') else 'why')
        else:
            kind = 'flag'
            if not (isinstance(first, El) and first.tag == 'b'):
                raise Bad(ctx + ': flag without a title')
            label = norm_space(text_of(first)).strip()
        rest = n.kids[n.kids.index(first) + 1:]
        if any(isinstance(k, El) and k.tag in ('p', 'ul', 'ol', 'div', 'table') for k in rest):
            body = self.blocks(rest, ctx)
        else:
            body = [{'p': run(rest, ctx)}]
        return {'callout': kind, 'label': [label], 'body': body}

    def image(self, fig, ctx):
        img = [k for k in self.elems(fig) if k.tag == 'img'][0]
        cap = [k for k in self.elems(fig) if k.tag == 'figcaption']
        capk = cap[0].kids if cap else []
        credit = [k for k in capk if isinstance(k, El) and 'credit' in k.cls]
        caption = run([k for k in capk if not (isinstance(k, El) and 'credit' in k.cls)], ctx, allow_empty=True)
        m = re.fullmatch(r'data:image/(webp|png|jpeg);base64,(.*)', img.attrs['src'], re.S)
        if not m:
            raise Bad(ctx + ': image source')
        data = base64.b64decode(m[2])
        name = SHARED_IMAGES.get(data)
        if name is None:   # the same photo in several courses is one file
            name = SHARED_IMAGES[data] = '%s-%02d.jxl' % (self.cid, len(self.images) + 1)
        self.images.append((name, data))
        return {'image': {'file': name, 'w': int(img.attrs['width']), 'h': int(img.attrs['height']),
                          'alt': img.attrs['alt'].strip(), 'caption': caption,
                          'credit': run(credit[0].kids, ctx, allow_empty=True) if credit else []}}


# ---------------------------------------------------------------- questions and pages

def question(q, ctx):
    ctx = '%s %s' % (ctx, q['id'])
    src = run(q['src'] or '', ctx, allow_empty=True)
    opts = lambda: [{'text': run(o[0], ctx), 'right': bool(o[1]), 'why': run(o[2] or '', ctx, allow_empty=True)}
                    for o in q['o']]
    if q['type'] == 'mcq':
        return {'type': 'choice', 'id': q['id'], 'q': run(q['q'], ctx), 'options': opts(), 'src': src}
    if q['type'] == 'order':
        return {'type': 'order', 'id': q['id'], 'q': run(q['q'], ctx), 'steps': [run(s, ctx) for s in q['steps']],
                'src': src}
    if q['type'] == 'scn':
        panel = [{'name': run(r[0], ctx), 'value': run(r[1], ctx), 'state': r[2] or ''} for r in q['panel']]
        return {'type': 'scenario', 'id': q['id'], 'panel': panel, 'q': run(q['q'], ctx), 'options': opts(), 'src': src}
    raise Bad(ctx + ': question type ' + q['type'])


def drill_rules(src, ctx):
    """a judging function of the reading drill (`v=>v>=550||v<=-550?'act':v>=400?'alarm':'ok'`) → rules"""
    body = re.sub(r'\s+', '', src)
    m = re.fullmatch(r'v=>(.*)', body)
    if not m:
        raise Bad(ctx + ': drill rule ' + src)
    rest, rules = m[1], []
    while True:
        m = re.fullmatch(r"((?:v(?:>=|<=|>|<)-?[\d.]+)(?:\|\|v(?:>=|<=|>|<)-?[\d.]+)*)\?'(alarm|act)':(.*)", rest)
        if not m:
            break
        for op, lim in re.findall(r'v(>=|<=|>|<)(-?[\d.]+)', m[1]):
            rules.append([op, number(lim), m[2]])
        rest = m[3]
    if rest != "'ok'":
        raise Bad(ctx + ': drill rule ' + src)
    return rules


def page_parts(html_s, ctx):
    """a rendered page → (eyebrow, title, intro paragraphs, the rest as nodes); interactive parts are dropped"""
    root = parse_html(html_s)
    eyebrow, title, intro, rest = '', None, [], []
    for n in root.kids:
        if isinstance(n, str):
            continue
        if 'eyebrow' in n.cls:
            eyebrow = norm_space(text_of(n)).strip()
        elif n.tag == 'h1':
            title = run(n.kids, ctx)
        elif n.tag == 'p' and not rest and 'src' not in n.cls:
            intro.append(n)
        elif n.tag == 'div' and ('act' in n.cls or 'chips' in n.cls or n.attrs.get('id') == 'fq'):
            continue
        else:
            rest.append(n)
    return eyebrow, title, intro, rest


TESTS = {   # the result texts, from each course's renderFinal (pass mark, on_pass, on_fail)
    'ppt': (lambda n: math.ceil(n * 0.85),
            '<p><b>Done.</b> Go on to <a href="2-plant-foundations.html">Rumaila Plant Foundations</a>.</p>',
            '<p><b>Not yet.</b> Revisit the modules below, then try again.</p>'),
    'fnd': (lambda n: 17,
            '<p><b>Ready.</b> Go on to the <a href="3-hrsg-course.html">HRSG course</a>.</p>',
            '<p><b>Not yet.</b> Revisit the modules below, then try again.</p>'),
    'hrsg': (lambda n: n,
             '<p>Nothing to revisit. Keep the Reading drill going to hold on to it.</p>',
             ''),
}


def convert(raw, cid, order, short):
    cv = Conv(cid)
    from course_figures import build as build_figures
    cv.anim = build_figures()
    pages, qids = [], set()
    mods = {m['id']: m for m in raw['modules']}
    for m in raw['modules']:
        ctx = '%s/%s' % (cid, m['id'])
        p = {'kind': 'module', 'id': m['id'], 'n': m['n'], 'title': run(m['title'], ctx), 'short': plain(m['short']),
             'goals': [run(g, ctx) for g in m['goal']], 'warm': question(m['warm'], ctx),
             'body': cv.blocks(parse_html(m['body']).kids, ctx),
             'worked': None if not m['worked'] else {'case': run(m['worked']['case'], ctx),
                                                     'steps': [[run(a, ctx), run(b, ctx)] for a, b in m['worked']['steps']]},
             'practice': [question(q, ctx) for q in m['practice']]}
        if m['bridge']:
            p['bridge'] = {'title': ['Bridge to the HRSG course'],
                           'intro': ['These come straight from the HRSG course and manual. If you can answer them, you '
                                     'are ready for the parts of that course that rely on this module.'],
                           'questions': [question(q, ctx) for q in m['bridge']]}
        pages.append(p)
    for e in raw['extra']:
        pid, html_s = e['id'], raw['pages'][e['id']]
        ctx = '%s/%s' % (cid, pid)
        eyebrow, title, intro_nodes, rest = page_parts(html_s, ctx)
        intro = cv.blocks(intro_nodes, ctx)
        base = {'id': pid, 'title': title, 'intro': intro}
        if pid == 'place':
            pages.append(dict(base, kind='placement',
                              items=[{'module': it['m'], 'q': question(it['q'], ctx)} for it in raw['place']]))
        elif pid == 'final':
            pass_of, on_pass, on_fail = TESTS[cid]
            if 'final' in raw:
                items = [{'module': it['m'], 'q': question(it['q'], ctx)} for it in raw['final']]
            else:   # the bridge questions of every module, by reference
                items = [{'module': m['id'], 'ref': q['id']} for m in raw['modules'] for q in m['bridge']]
            pages.append(dict(base, kind='test', items=items, draw=None, **{'pass': pass_of(len(items))},
                              on_pass=cv.blocks(parse_html(on_pass).kids, ctx),
                              on_fail=cv.blocks(parse_html(on_fail).kids, ctx)))
        elif pid == 'drill' and 'drill' in raw:
            items = []
            for d in raw['drill']:
                rules = drill_rules(d['j'], ctx)
                it = {'cat': d['cat'], 'name': run(d['p'], ctx), 'unit': d['u'], 'context': run(d['ctx'], ctx, True),
                      'values': d['vals'], 'rules': rules, 'note': run(d['note'], ctx, True)}
                from ref.courses import judge
                got = [judge(it, v) for v in d['vals']]
                if got != d['judged']:
                    raise Bad('%s: drill rules differ from the original for %s: %s vs %s' % (ctx, d['p'], got, d['judged']))
                items.append(it)
            pages.append(dict(base, kind='reading_drill', items=items))
        elif pid == 'drill':
            pages.append(dict(base, kind='vocab_drill'))
        elif pid == 'ref' and 'gloss' in raw:
            pages.append(dict(base, kind='glossary'))
        elif pid == 'kks':
            pages.append(dict(base, kind='page', eyebrow=eyebrow, body=[{'tool': 'kks_decoder'}]))
        else:
            pages.append(dict(base, kind='page', eyebrow=eyebrow, body=cv.blocks(rest, ctx)))
    gloss = [{'term': plain(t), 'meaning': run(mn, cid + '/gloss'), 'module': mod} for t, mn, mod in raw.get('gloss', [])]
    doc = {'format': 'kks-course', 'version': 1, 'id': cid, 'title': raw['title'], 'short': short, 'order': order,
           'figures': cv.figures, 'glossary': gloss, 'pages': pages}
    return doc, cv.images


# ---------------------------------------------------------------- images and main

def to_jxl(src):
    """the course's WebP → JPEG XL at distance 1.9, the photos' setting (0018), → (bytes, w, h)"""
    from PIL import Image
    im = Image.open(io.BytesIO(src))
    im.load()
    with tempfile.TemporaryDirectory() as d:
        png, out = os.path.join(d, 'a.png'), os.path.join(d, 'a.jxl')
        im.save(png)
        subprocess.run(['cjxl', png, out, '-d', '1.9', '-e', '9', '--quiet'], check=True)
        with open(out, 'rb') as f:
            return f.read(), im.width, im.height


def build(rawdir, outdir):
    from ref import courses as K
    os.makedirs(outdir, exist_ok=True)
    total, done = 0, {}
    for file, cid, order in COURSES:
        with open(os.path.join(rawdir, cid + '.json')) as f:
            raw = json.load(f)
        doc, images = convert(raw, cid, order, raw['short'])
        sizes = {}
        for name, src in images:
            if name in done:
                sizes[name] = done[name]
                continue
            data, w, h = to_jxl(src)
            done[name] = (w, h)
            sizes[name] = (w, h)
            with open(os.path.join(outdir, name), 'wb') as f:
                f.write(data)
            total += len(data)

        def fix(x):   # image blocks carry the picture's pixel size
            if isinstance(x, dict):
                if 'image' in x and isinstance(x['image'], dict) and x['image'].get('file') in sizes:
                    x['image']['w'], x['image']['h'] = sizes[x['image']['file']]
                for v in x.values():
                    fix(v)
            elif isinstance(x, list):
                for v in x:
                    fix(v)
        fix(doc)
        data = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode()
        with open(os.path.join(outdir, cid + '.json'), 'wb') as f:
            f.write(data)
        counts = K.check_course(doc, image_files=set(sizes), size=len(data))
        print('%s: %d KB JSON, %d images, %s' % (cid, len(data) // 1024, len(set(sizes)), counts))
    print('images: %d KB' % (total // 1024))


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'dump':
        dump(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == 'build':
        build(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
