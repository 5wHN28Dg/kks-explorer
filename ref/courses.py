"""Course content format, version 1 (docs/COURSES.md): validator and figure evaluator. Test-only reference: the
product renderers are the Nim core and the web UI; they must agree with this on ref/vectors/courses-v1.json."""
import math, re
from decimal import Decimal, ROUND_HALF_UP

PHI = 0.6180339887498949
ID = re.compile(r'[a-z_][a-z0-9_]{0,31}')
TOKENS = ('ink', 'muted', 'rule', 'accent', 'act', 'ok', 'alarm', 'alarm_fill', 'surface', 'sunk', 'ground')
HEX = re.compile(r'#[0-9a-f]{6}')
MAX = {'bytes': 8 << 20, 'pages': 400, 'figures': 64, 'values': 256, 'elements': 2000, 'table': 1024,
       'particles': 1000}


class FormatError(Exception):
    def __init__(self, code, where=''):
        super().__init__(f'{code}: {where}')
        self.code = code


# ---------------------------------------------------------------- validation helpers

def need(cond, code, where=''):
    if not cond:
        raise FormatError(code, where)


def keys(o, required, optional=(), where=''):
    need(isinstance(o, dict), 'bad_type', where)
    for k in required:
        need(k in o, 'missing_key', f'{where}.{k}')
    for k in o:
        need(k in required or k in optional, 'unknown_key', f'{where}.{k}')


def one_kind(o, kinds, where):
    """Blocks, nodes, elements, inline objects: exactly one of `kinds` is present."""
    need(isinstance(o, dict), 'bad_type', where)
    found = [k for k in kinds if k in o]
    need(len(found) == 1, 'bad_kind', where)
    return found[0]


def is_num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) and abs(x) < 1e9


def num(x, where, lo=None, hi=None, integer=False):
    need(is_num(x), 'bad_number', where)
    if integer:
        need(isinstance(x, int) or float(x).is_integer(), 'bad_number', where)
    if lo is not None:
        need(x >= lo, 'bad_number', where)
    if hi is not None:
        need(x <= hi, 'bad_number', where)
    return x


def ident(x, where):
    need(isinstance(x, str) and ID.fullmatch(x) is not None, 'bad_id', where)
    return x


def text(x, where):
    need(isinstance(x, str), 'bad_type', where)
    return x


def lst(x, where, lo=0, hi=None):
    need(isinstance(x, list), 'bad_type', where)
    need(len(x) >= lo and (hi is None or len(x) <= hi), 'bad_length', where)
    return x


# ---------------------------------------------------------------- course

class Course:
    """Checks a whole course document. Collects references and resolves them at the end."""

    def __init__(self, doc, image_files=None):
        self.doc = doc
        self.images = image_files          # None = don't check that image files exist
        self.page_ids, self.module_ids, self.question_ids = set(), set(), set()
        self.glossary = set()
        self.links = []                    # (target, where)
        self.gloss_refs, self.figure_refs, self.module_refs = [], [], []
        self.question_refs = []            # (module, question id, where): test items by reference
        self.module_questions = {}         # module id → its question ids (warm, practice, bridge)
        self.counts = {'pages': 0, 'modules': 0, 'questions': 0, 'figures': 0, 'blocks': 0}

    def check(self):
        d = self.doc
        keys(d, ('format', 'version', 'id', 'title', 'short', 'order', 'figures', 'glossary', 'pages'), where='course')
        need(d['format'] == 'kks-course', 'bad_format', 'format')
        need(d['version'] == 1 and not isinstance(d['version'], bool), 'bad_version', 'version')
        ident(d['id'], 'id')
        text(d['title'], 'title')
        text(d['short'], 'short')
        num(d['order'], 'order', 0, integer=True)
        need(isinstance(d['figures'], dict), 'bad_type', 'figures')
        need(len(d['figures']) <= MAX['figures'], 'limit', 'figures')
        lst(d['pages'], 'pages', 1, MAX['pages'])
        for p in d['pages']:      # first pass: ids (links may point forward)
            need(isinstance(p, dict) and 'id' in p, 'missing_key', 'page.id')
            pid = ident(p['id'], 'page.id')
            need(pid not in self.page_ids, 'dup_id', pid)
            self.page_ids.add(pid)
            if p.get('kind') == 'module':
                self.module_ids.add(pid)
        for i, g in enumerate(lst(d['glossary'], 'glossary')):
            keys(g, ('term', 'meaning', 'module'), where=f'glossary[{i}]')
            need(isinstance(g['term'], str) and g['term'], 'bad_type', 'term')
            need(g['term'] not in self.glossary, 'dup_id', g['term'])
            self.glossary.add(g['term'])
            self.run(g['meaning'], 'glossary.meaning')
            self.module_refs.append((g['module'], 'glossary.module'))
        for p in d['pages']:
            self.page(p)
        for fid, f in d['figures'].items():
            ident(fid, 'figure id')
            check_figure(f, f'figure {fid}', self)
            self.counts['figures'] += 1
        # references
        for fid, where in self.figure_refs:
            need(fid in d['figures'], 'bad_ref', where)
        need(set(d['figures']) <= {f for f, _ in self.figure_refs}, 'unused_figure', 'figures')
        for term, where in self.gloss_refs:
            need(term in self.glossary, 'bad_ref', where)
        for m, where in self.module_refs:
            need(m in self.module_ids, 'bad_ref', where)
        for m, qid, where in self.question_refs:
            need(qid in self.module_questions.get(m, ()), 'bad_ref', where)
        for t, where in self.links:
            if 'page' in t and 'course' not in t:
                need(t['page'] in self.page_ids, 'bad_ref', where)
        return self.counts

    # --- inline
    def run(self, r, where, allow_empty=False):
        lst(r, where, 0 if allow_empty else 1)
        for item in r:
            if isinstance(item, str):
                continue
            k = one_kind(item, ('b', 'i', 'small', 'num', 'term', 'link'), where)
            if k in ('b', 'i', 'small'):
                keys(item, (k,), where=where)
                self.run(item[k], where)
            elif k == 'num':
                keys(item, ('num',), where=where)
                need(isinstance(item['num'], str) and item['num'], 'bad_type', where)
            elif k == 'term':
                keys(item, ('term', 'gloss'), where=where)
                self.run(item['term'], where)
                self.gloss_refs.append((text(item['gloss'], where), where))
            else:
                keys(item, ('link', 'to'), where=where)
                self.run(item['link'], where)
                self.target(item['to'], where)

    def target(self, t, where):
        need(isinstance(t, dict) and t, 'bad_link', where)
        ks = set(t)
        if ks <= {'course', 'page'}:
            for k in ks:
                ident(t[k], where)
        elif ks == {'kks'}:
            need(isinstance(t['kks'], str) and re.fullmatch(r'[0-9A-Z]{4,24}', t['kks']), 'bad_link', where)
        elif ks == {'url'}:
            need(isinstance(t['url'], str) and re.fullmatch(r'https://[^\s]+', t['url']), 'bad_link', where)
        else:
            raise FormatError('bad_link', where)
        self.links.append((t, where))

    # --- blocks
    def blocks(self, bs, where, only=None):
        for b in lst(bs, where):
            self.block(b, where, only)

    def block(self, b, where, only=None):
        kinds = ('h', 'p', 'ul', 'ol', 'table', 'callout', 'cards', 'chain', 'figure', 'image', 'issues', 'tool')
        k = one_kind(b, kinds, where)
        need(only is None or k in only, 'bad_kind', f'{where}: {k} not allowed here')
        self.counts['blocks'] += 1
        w = f'{where}.{k}'
        if k == 'h':
            keys(b, ('h', 'level'), where=w)
            need(b['level'] in (2, 3) and not isinstance(b['level'], bool), 'bad_value', w)
            self.run(b['h'], w)
        elif k == 'p':
            keys(b, ('p',), where=w)
            self.run(b['p'], w)
        elif k in ('ul', 'ol'):
            keys(b, (k,), where=w)
            for r in lst(b[k], w, 1):
                self.run(r, w)
        elif k == 'table':
            keys(b, ('table',), where=w)
            t = b['table']
            keys(t, ('head', 'rows', 'num'), where=w)
            n = len(lst(t['head'], w, 1))
            for r in t['head']:
                self.run(r, w, allow_empty=True)
            for row in lst(t['rows'], w, 1):
                need(len(lst(row, w)) == n, 'bad_length', w)
                for c in row:
                    self.run(c, w, allow_empty=True)
            cols = lst(t['num'], w)
            for c in cols:
                num(c, w, 0, n - 1, integer=True)
            need(len(set(cols)) == len(cols), 'dup_id', w)
        elif k == 'callout':
            keys(b, ('callout', 'label', 'body'), where=w)
            need(b['callout'] in ('why', 'why_general', 'at_plant', 'flag', 'note'), 'bad_value', w)
            self.run(b['label'], w)
            lst(b['body'], w, 1)
            self.blocks(b['body'], w, only=('p', 'ul', 'ol', 'table'))
        elif k == 'cards':
            keys(b, ('cards',), where=w)
            for c in lst(b['cards'], w, 1):
                lst(c, w, 2, 2)
                self.run(c[0], w)
                self.run(c[1], w)
        elif k == 'chain':
            keys(b, ('chain',), where=w)
            for r in lst(b['chain'], w, 2):
                self.run(r, w)
        elif k == 'figure':
            keys(b, ('figure',), where=w)
            self.figure_refs.append((ident(b['figure'], w), w))
        elif k == 'image':
            keys(b, ('image',), where=w)
            im = b['image']
            keys(im, ('file', 'w', 'h', 'alt', 'caption', 'credit'), where=w)
            need(isinstance(im['file'], str) and re.fullmatch(r'[a-z0-9][a-z0-9._-]{0,63}\.jxl', im['file'])
                 and '..' not in im['file'], 'bad_value', w)
            need(self.images is None or im['file'] in self.images, 'bad_ref', w)
            num(im['w'], w, 1, 20000, integer=True)
            num(im['h'], w, 1, 20000, integer=True)
            need(isinstance(im['alt'], str) and im['alt'], 'bad_value', w)
            self.run(im['caption'], w, allow_empty=True)
            self.run(im['credit'], w, allow_empty=True)
        elif k == 'issues':
            keys(b, ('issues',), where=w)
            for it in lst(b['issues'], w, 1):
                lst(it, w, 3, 3)
                need(it[0] in ('high', 'medium', 'low'), 'bad_value', w)
                self.run(it[1], w)
                self.run(it[2], w)
        else:
            keys(b, ('tool',), where=w)
            need(b['tool'] == 'kks_decoder', 'bad_value', w)

    # --- questions
    def question(self, q, where):
        need(isinstance(q, dict), 'bad_type', where)
        typ = q.get('type')
        base = ('type', 'id', 'q', 'src')
        if typ == 'choice':
            keys(q, base + ('options',), where=where)
        elif typ == 'order':
            keys(q, base + ('steps',), where=where)
        elif typ == 'scenario':
            keys(q, base + ('panel', 'options'), where=where)
        else:
            raise FormatError('bad_question', where)
        qid = ident(q['id'], where)
        need(not re.search(r'_[rfp]$', qid), 'bad_id', f'{where}: suffix')
        need(qid not in self.question_ids, 'dup_id', qid)
        self.question_ids.add(qid)
        self.counts['questions'] += 1
        self.run(q['q'], where)
        self.run(q['src'], where, allow_empty=True)
        if typ == 'order':
            for s in lst(q['steps'], where, 3, 10):
                self.run(s, where)
            return
        if typ == 'scenario':
            for r in lst(q['panel'], where, 1, 10):
                keys(r, ('name', 'value', 'state'), where=where)
                self.run(r['name'], where)
                self.run(r['value'], where)
                need(r['state'] in ('', 'ok', 'alarm', 'act'), 'bad_value', where)
        opts = lst(q['options'], where, 2, 6)
        right = 0
        for o in opts:
            keys(o, ('text', 'right', 'why'), where=where)
            self.run(o['text'], where)
            need(isinstance(o['right'], bool), 'bad_type', where)
            right += o['right']
            self.run(o['why'], where, allow_empty=True)
        need(right == 1, 'bad_question', f'{where}: {right} right options')

    def items(self, its, where, refs=False):
        for it in lst(its, where, 1):
            if refs and isinstance(it, dict) and 'ref' in it:
                keys(it, ('module', 'ref'), where=where)
                self.question_refs.append((it['module'], ident(it['ref'], where), where))
            else:
                keys(it, ('module', 'q'), where=where)
                self.question(it['q'], where)
            self.module_refs.append((it['module'], where))

    # --- pages
    def page(self, p):
        kind = p.get('kind')
        w = f"page {p.get('id')}"
        self.counts['pages'] += 1
        if kind == 'module':
            keys(p, ('kind', 'id', 'n', 'title', 'short', 'goals', 'warm', 'body', 'worked', 'practice'), ('bridge',),
                 where=w)
            before = set(self.question_ids)
            self.counts['modules'] += 1
            text(p['n'], w)
            self.run(p['title'], w)
            text(p['short'], w)
            for g in lst(p['goals'], w):
                self.run(g, w)
            self.question(p['warm'], w)
            self.blocks(p['body'], w)
            if p['worked'] is not None:
                keys(p['worked'], ('case', 'steps'), where=w)
                self.run(p['worked']['case'], w)
                for s in lst(p['worked']['steps'], w, 1):
                    lst(s, w, 2, 2)
                    self.run(s[0], w)
                    self.run(s[1], w)
            for q in lst(p['practice'], w):
                self.question(q, w)
            if 'bridge' in p:
                keys(p['bridge'], ('title', 'intro', 'questions'), where=w)
                self.run(p['bridge']['title'], w)
                self.run(p['bridge']['intro'], w, allow_empty=True)
                for q in lst(p['bridge']['questions'], w, 1):
                    self.question(q, w)
            self.module_questions[p['id']] = self.question_ids - before
            return
        common = ('kind', 'id', 'title', 'intro')
        if kind == 'placement':
            keys(p, common + ('items',), where=w)
            self.items(p['items'], w)
        elif kind == 'test':
            keys(p, common + ('items', 'draw', 'pass', 'on_pass', 'on_fail'), where=w)
            self.items(p['items'], w, refs=True)
            n = len(p['items']) if p['draw'] is None else num(p['draw'], w, 1, len(p['items']), integer=True)
            num(p['pass'], w, 0, n, integer=True)
            self.blocks(p['on_pass'], w)
            self.blocks(p['on_fail'], w)
        elif kind in ('vocab_drill', 'glossary'):
            keys(p, common, where=w)
            if kind == 'vocab_drill':
                need(len(self.doc['glossary']) >= 4, 'bad_value', f'{w}: drill needs 4 terms')
        elif kind == 'reading_drill':
            keys(p, common + ('items',), where=w)
            for it in lst(p['items'], w, 1):
                keys(it, ('cat', 'name', 'unit', 'context', 'values', 'rules', 'note'), where=w)
                need(isinstance(it['cat'], str) and it['cat'], 'bad_value', w)
                self.run(it['name'], w)
                text(it['unit'], w)
                self.run(it['context'], w, allow_empty=True)
                for v in lst(it['values'], w, 1):
                    num(v, w)
                for r in lst(it['rules'], w):
                    lst(r, w, 3, 3)
                    need(r[0] in ('>=', '>', '<=', '<'), 'bad_value', w)
                    num(r[1], w)
                    need(r[2] in ('alarm', 'act'), 'bad_value', w)
                self.run(it['note'], w, allow_empty=True)
        elif kind == 'page':
            keys(p, common + ('eyebrow', 'body'), where=w)
            text(p['eyebrow'], w)
            self.blocks(p['body'], w)
        else:
            raise FormatError('bad_kind', w)
        self.run(p['title'], w)
        self.blocks(p['intro'], w)


def judge(item, value):
    """Reading drill: the state of the first rule the value meets, else 'ok'."""
    for op, lim, state in item['rules']:
        if {'>=': value >= lim, '>': value > lim, '<=': value <= lim, '<': value < lim}[op]:
            return state
    return 'ok'


def check_course(doc, image_files=None, size=None):
    if size is not None:
        need(size <= MAX['bytes'], 'limit', 'file size')
    return Course(doc, image_files).check()


# ---------------------------------------------------------------- figures: validation

INPUTS_T = 't'


def check_table(t, where, paint=False):
    lst(t, where, 1, MAX['table'])
    prev = None
    run_len = 0
    for pt in t:
        lst(pt, where, 2, 2)
        x = num(pt[0], where)
        if paint:
            check_paint(pt[1], where, None, plain=True)
        else:
            num(pt[1], where)
        if prev is not None:
            need(x >= prev, 'bad_table', f'{where}: x decreases')
            run_len = run_len + 1 if x == prev else 1
            need(run_len < 3, 'bad_table', f'{where}: three points at one x')
        else:
            run_len = 1
        prev = x


def check_paint(p, where, names, plain=False, fill=True):
    if isinstance(p, str):
        need(p == 'none' or p in TOKENS or HEX.fullmatch(p), 'bad_paint', where)
        return
    need(not plain, 'bad_paint', where)
    need(isinstance(p, dict), 'bad_paint', where)
    if 'radial' in p:
        need(fill, 'bad_paint', f'{where}: gradient stroke')
        keys(p, ('radial',), where=where)
        prev = -1
        for s in lst(p['radial'], where, 2, 16):
            lst(s, where, 3, 3)
            num(s[0], where, 0, 1)
            need(s[0] > prev, 'bad_paint', where)
            prev = s[0]
            check_paint(s[1], where, None, plain=True)
            need(s[1] != 'none', 'bad_paint', where)
            num(s[2], where, 0, 1)
    elif 'stops' in p:
        keys(p, ('of', 'stops'), where=where)
        need(p['of'] in names, 'bad_ref', where)
        check_table(p['stops'], where, paint=True)
        for s in p['stops']:
            need(isinstance(s[1], str) and HEX.fullmatch(s[1]), 'bad_paint', f'{where}: stops need #rrggbb')
    elif 'steps' in p:
        keys(p, ('of', 'steps'), where=where)
        need(p['of'] in names, 'bad_ref', where)
        check_table(p['steps'], where, paint=True)
    else:
        raise FormatError('bad_paint', where)


def check_ref(r, where, names):
    if isinstance(r, str):
        need(r in names, 'bad_ref', where)
    else:
        num(r, where)


PLACEHOLDER = re.compile(r'\{\{|\}\}|\{([a-z_][a-z0-9_]{0,31})(?::(\+?)([0-6]))?\}|[{}]')


def check_template(s, where, names):
    need(isinstance(s, str), 'bad_type', where)
    for m in PLACEHOLDER.finditer(s):
        tok = m.group(0)
        if tok in ('{{', '}}'):
            continue
        need(m.group(1) is not None, 'bad_template', where)
        need(m.group(1) in names, 'bad_ref', where)


def check_text(t, where, names):
    if isinstance(t, str):
        return check_template(t, where, names)
    cases = lst(t, where, 1)
    for i, c in enumerate(cases):
        last = i == len(cases) - 1
        keys(c, ('text',) if last else ('when', 'text'), where=where)
        if not last:
            check_ref(c['when'], where, names)
        check_template(c['text'], where, names)


def check_figure(f, where, course=None):
    keys(f, ('title', 'caption', 'alt', 'w', 'h', 'scene'),
         ('period', 'slider', 'toggles', 'modes', 'values', 'status'), where=where)
    text(f['title'], where)
    if course:
        course.run(f['caption'], where, allow_empty=True)
    need(isinstance(f['alt'], str) and f['alt'], 'bad_value', f'{where}.alt')
    num(f['w'], where, 1, 4000, integer=True)
    num(f['h'], where, 1, 4000, integer=True)
    static = 'period' not in f
    if static:
        for k in ('slider', 'toggles', 'modes', 'status'):
            need(k not in f, 'static_inputs', f'{where}.{k}')
        names = set()
    else:
        num(f['period'], where, 1, 60)
        names = {'t', 'v', 'mode'}
    if 'slider' in f:
        s = f['slider']
        keys(s, ('label', 'init', 'text'), ('drive',), where=f'{where}.slider')
        text(s['label'], where)
        num(s['init'], where, 0, 1)
        if 'drive' in s:
            d = s['drive']
            keys(d, ('of', 'table'), where=f'{where}.drive')
            need(d['of'] == 't', 'bad_drive', where)
            check_table(d['table'], f'{where}.drive')
    for tg in f.get('toggles', []):
        keys(tg, ('key', 'label', 'on'), where=f'{where}.toggle')
        k = ident(tg['key'], where)
        need(k not in names, 'dup_id', k)
        names.add(k)
        text(tg['label'], where)
        need(isinstance(tg['on'], bool), 'bad_type', where)
    if 'modes' in f:
        seen = set()
        for m in lst(f['modes'], where, 2, 8):
            keys(m, ('key', 'label'), where=f'{where}.mode')
            need(ident(m['key'], where) not in seen, 'dup_id', m['key'])
            seen.add(m['key'])
            text(m['label'], where)
    values = lst(f.get('values', []), where, 0, MAX['values'])
    later = {pair[0] for pair in values if isinstance(pair, list) and len(pair) == 2 and isinstance(pair[0], str)}
    for pair in values:
        lst(pair, where, 2, 2)
        name = ident(pair[0], where)
        need(name not in names and name not in ('t', 'v', 'mode'), 'dup_id', name)
        check_node(pair[1], f'{where}.values.{name}', names, later)
        names.add(name)
    if 'slider' in f:
        check_text(f['slider']['text'], f'{where}.slider.text', names | {'v'})
    if 'status' in f:
        check_text(f['status'], f'{where}.status', names)
    counter = {'elements': 0, 'particles': 0}
    check_elements(f['scene'], f'{where}.scene', names, static, counter)
    need(counter['elements'] <= MAX['elements'], 'limit', where)
    need(counter['particles'] <= MAX['particles'], 'limit', where)


def check_node(n, where, names, later):
    k = one_kind(n, ('table', 'sum', 'product', 'select', 'follow', 'hold'), where)
    if k == 'table':
        keys(n, ('of', 'table'), ('step',), where=where)
        check_ref_node(n['of'], where, names, later, name_only=True)
        check_table(n['table'], where)
        need(n.get('step', True) is True or n.get('step') is False, 'bad_type', where)
    elif k in ('sum', 'product'):
        keys(n, (k,), where=where)
        for r in lst(n[k], where, 1):
            check_ref_node(r, where, names, later)
    elif k == 'select':
        keys(n, ('select', 'cases'), where=where)
        check_ref_node(n['select'], where, names, later, name_only=True)
        for r in lst(n['cases'], where, 1):
            check_ref_node(r, where, names, later)
    elif k == 'follow':
        keys(n, ('follow', 'rate'), ('rate_down', 'init'), where=where)
        check_ref_node(n['follow'], where, names, later, name_only=True)
        num(n['rate'], where, 1e-9)
        if 'rate_down' in n:
            num(n['rate_down'], where, 1e-9)
        if 'init' in n:
            num(n['init'], where)
    else:
        keys(n, ('hold', 'while'), where=where)
        check_ref_node(n['hold'], where, names, later, name_only=True)
        check_ref_node(n['while'], where, names, later, name_only=True)


def check_ref_node(r, where, names, later, name_only=False):
    if isinstance(r, str):
        need(r in names, 'forward_ref' if r in later else 'bad_ref', where)
    else:
        need(not name_only, 'bad_ref', where)
        num(r, where)


COMMON = ('fill', 'stroke', 'stroke_width', 'opacity', 'dash', 'cap', 'join', 'transform')


def check_common(e, where, names):
    for p in ('fill', 'stroke'):
        if p in e:
            check_paint(e[p], where, names, fill=p == 'fill')
    for p in ('stroke_width', 'opacity'):
        if p in e:
            check_ref(e[p], where, names)
    if 'dash' in e:
        for d in lst(e['dash'], where, 1, 8):
            num(d, where, 0)
    need(e.get('cap', 'butt') in ('butt', 'round', 'square'), 'bad_value', where)
    need(e.get('join', 'miter') in ('miter', 'round', 'bevel'), 'bad_value', where)
    for st in lst(e.get('transform', []), where, 0, 8):
        k = one_kind(st, ('translate', 'rotate', 'scale'), where)
        keys(st, (k,), where=where)
        for r in lst(st[k], where, *(3, 3) if k == 'rotate' else (2, 2)):
            check_ref(r, where, names)


def check_points(pts, where, names, lo, hi):
    for p in lst(pts, where, lo, hi):
        lst(p, where, 2, 2)
        for r in p:
            check_ref(r, where, names)


def check_path(d, where, names):
    cmds = lst(d, where, 1, 5000)
    for i, c in enumerate(cmds):
        lst(c, where, 1)
        need(c[0] in ('M', 'L', 'C', 'Z'), 'bad_path', where)
        need(i > 0 or c[0] == 'M', 'bad_path', f'{where}: first command')
        need(len(c) == {'M': 3, 'L': 3, 'C': 7, 'Z': 1}[c[0]], 'bad_path', where)
        for r in c[1:]:
            check_ref(r, where, names)


def check_elements(es, where, names, static, counter):
    for e in lst(es, where):
        counter['elements'] += 1
        k = one_kind(e, ('rect', 'circle', 'ellipse', 'line', 'poly', 'path', 'text', 'label', 'group', 'flow'), where)
        w = f'{where}.{k}'
        if k == 'flow':
            need(not static, 'static_inputs', w)
            keys(e, ('flow',), where=w)
            check_flow(e['flow'], w, names)
            counter['particles'] += e['flow']['count']
            continue
        if k == 'label':
            keys(e, ('label', 'at', 'to'), ('anchor',), where=w)
            text(e['label'], w)
            check_points([e['at']], w, names, 1, 1)
            check_points([e['to']], w, names, 1, 1)
            need(e.get('anchor', 'start') in ('start', 'end'), 'bad_value', w)
            continue
        extra = {'rect': ('rx',), 'line': ('arrow',), 'poly': ('closed',), 'group': ('clip',),
                 'text': ('at', 'anchor', 'size', 'font', 'weight')}.get(k, ())
        required = (k, 'at') if k == 'text' else (k,)
        keys(e, required, COMMON + extra, where=w)
        check_common(e, w, names)
        if k in ('rect', 'circle', 'ellipse', 'line'):
            for r in lst(e[k], w, *{'rect': (4, 4), 'circle': (3, 3), 'ellipse': (4, 4), 'line': (4, 4)}[k]):
                check_ref(r, w, names)
            if 'rx' in e:
                check_ref(e['rx'], w, names)
            if 'arrow' in e:
                need(isinstance(e['arrow'], bool), 'bad_type', w)
        elif k == 'poly':
            check_points(e['poly'], w, names, 2, 1024)
            need(isinstance(e.get('closed', False), bool), 'bad_type', w)
        elif k == 'path':
            check_path(e['path'], w, names)
        elif k == 'text':
            check_text(e['text'], w, names)
            check_points([e['at']], w, names, 1, 1)
            need(e.get('anchor', 'start') in ('start', 'middle', 'end'), 'bad_value', w)
            num(e.get('size', 12), w, 1, 200)
            need(e.get('font', 'body') in ('body', 'display', 'mono'), 'bad_value', w)
            need(e.get('weight', 400) in (400, 600, 700), 'bad_value', w)
        else:
            if 'clip' in e:
                keys(e['clip'], ('rect',), ('rx',), where=w)
                for r in lst(e['clip']['rect'], w, 4, 4):
                    check_ref(r, w, names)
                if 'rx' in e['clip']:
                    check_ref(e['clip']['rx'], w, names)
            check_elements(e['group'], w, names, static, counter)


def check_flow(fl, where, names):
    keys(fl, ('count', 'routes'), ('lanes', 'speed', 'r', 'fill', 'stroke', 'stroke_width', 'opacity', 'glyph',
                                   'along', 'hide', 'reverse', 'pile', 'wrap_x'), where=where)
    num(fl['count'], where, 1, 200, integer=True)
    for rt in lst(fl['routes'], where, 1, 16):
        keys(rt, ('path',), ('weight', 'lanes'), where=where)
        check_path(rt['path'], where, names)
        need(all(c[0] != 'Z' for c in rt['path']) and sum(c[0] == 'M' for c in rt['path']) == 1, 'bad_path',
             f'{where}: a route is one open subpath')
        if 'weight' in rt:
            check_ref(rt['weight'], where, names)
        if 'lanes' in rt:
            check_points(rt['lanes'], where, names, 1, 200)
    if 'lanes' in fl:
        check_points(fl['lanes'], where, names, 1, 200)
    for p in ('speed', 'r', 'opacity', 'stroke_width'):
        if p in fl:
            check_ref(fl[p], where, names)
    for p in ('fill', 'stroke'):
        if p in fl:
            check_paint(fl[p], where, names, plain=True)
    need(fl.get('glyph', 'dot') in ('dot', 'burst'), 'bad_value', where)
    need(fl.get('reverse', 'wrap') in ('wrap', 'pile'), 'bad_value', where)
    num(fl.get('pile', 0), where, 0)
    if 'wrap_x' in fl:
        lst(fl['wrap_x'], where, 2, 2)
        need(num(fl['wrap_x'][1], where) > num(fl['wrap_x'][0], where), 'bad_value', where)
    if 'along' in fl:
        keys(fl['along'], (), ('speed', 'r', 'opacity', 'lane', 'fill'), where=where)
        for k, t in fl['along'].items():
            check_table(t, f'{where}.along.{k}', paint=k == 'fill')
    for h in lst(fl.get('hide', []), where, 0, 8):
        keys(h, ('rect', 'when'), where=where)
        for r in lst(h['rect'], where, 4, 4):
            check_ref(r, where, names)
        check_ref(h['when'], where, names)


# ---------------------------------------------------------------- figures: evaluation

def table_at(t, u, step=False):
    if u < t[0][0]:
        return t[0][1]
    if step:
        y = t[0][1]
        for x, yy in t:
            if x <= u:
                y = yy
            else:
                break
        return y
    if u >= t[-1][0]:
        return t[-1][1]
    i = 0
    for j in range(len(t)):
        if t[j][0] <= u:
            i = j
        else:
            break
    (x0, y0), (x1, y1) = t[i], t[i + 1]
    return y0 + (y1 - y0) * (u - x0) / (x1 - x0)


def fmt_number(x, decimals, sign):
    q = Decimal(x).quantize(Decimal(1).scaleb(-decimals), rounding=ROUND_HALF_UP)
    if q == 0:
        q = abs(q)
    s = f'{q:f}'
    if s.startswith('-'):
        return '−' + s[1:]
    return ('+' + s) if sign else s


def fill_template(s, vals):
    def rep(m):
        tok = m.group(0)
        if tok == '{{':
            return '{'
        if tok == '}}':
            return '}'
        return fmt_number(vals[m.group(1)], int(m.group(3) or 0), m.group(2) == '+')
    return PLACEHOLDER.sub(rep, s)


def hex_mix(a, b, f):
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return '#' + ''.join('%02x' % math.floor(x + (y - x) * f + 0.5) for x, y in zip(ca, cb))


def colour_at(stops, u):
    if u < stops[0][0]:
        return stops[0][1]
    if u >= stops[-1][0]:
        return stops[-1][1]
    i = max(j for j in range(len(stops)) if stops[j][0] <= u)
    (x0, c0), (x1, c1) = stops[i], stops[i + 1]
    return hex_mix(c0, c1, (u - x0) / (x1 - x0))


def flatten(path, ref):
    """A route's polyline: M/L as they are, each cubic as 16 segments."""
    pts = []
    for c in path:
        if c[0] in ('M', 'L'):
            pts.append((ref(c[1]), ref(c[2])))
        elif c[0] == 'C':
            x0, y0 = pts[-1]
            x1, y1, x2, y2, x3, y3 = (ref(v) for v in c[1:])
            for s in range(1, 17):
                t = s / 16
                a, b, cc, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
                pts.append((a * x0 + b * x1 + cc * x2 + d * x3, a * y0 + b * y1 + cc * y2 + d * y3))
    segs = [math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1)]
    return pts, segs, sum(segs)


def point_at(pts, segs, dist):
    for i, s in enumerate(segs):
        if dist <= s or i == len(segs) - 1:
            f = 0 if s == 0 else min(1, max(0, dist / s))
            return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * f, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * f)
        dist -= s
    return pts[0]


def frac(x):
    return x - math.floor(x)


class Figure:
    """Evaluates one figure: the clock, the values, the flows, the resolved scene (docs/COURSES.md §9)."""

    def __init__(self, fig, reduce_motion=False):
        self.f = fig
        self.static = 'period' not in fig
        self.t = 0.0
        self.v = float(fig['slider']['init']) if 'slider' in fig else 0.0
        self.toggles = {tg['key']: 1.0 if tg['on'] else 0.0 for tg in fig.get('toggles', [])}
        self.mode = 0
        self.playing = not reduce_motion and not self.static
        self.state = {}                     # stateful nodes: name -> state
        self.first = True
        self.flows = []                     # (flow dict, particles)
        self._collect(fig['scene'])
        self.vals = {}
        self._step(0.0)

    def _collect(self, es):
        for e in es:
            if 'flow' in e:
                fl = e['flow']
                n = fl['count']
                self.flows.append((fl, [{'k': i / n, 'n': 0, 'route': None} for i in range(n)]))
            elif 'group' in e:
                self._collect(e['group'])

    # --- controls
    def set_slider(self, v):
        self.v = float(v)
        if 'drive' in self.f.get('slider', {}):
            self.playing = False

    def toggle(self, key):
        self.toggles[key] = 1.0 - self.toggles[key]
        self.t = 0.0
        self.playing = True

    def set_mode(self, i):
        self.mode = int(i)
        self.playing = True

    def play(self):
        self.playing = True

    def pause(self):
        self.playing = False

    def tick(self, elapsed):
        if self.static:
            return
        elapsed = min(0.05, elapsed)
        dt = 0.0
        if self.playing:
            dt = elapsed
            self.t = frac(self.t + dt / self.f['period'])
            if 'drive' in self.f.get('slider', {}):
                self.v = table_at(self.f['slider']['drive']['table'], self.t)
        self._step(dt)

    # --- evaluation
    def ref(self, r):
        return self.vals[r] if isinstance(r, str) else r

    def _step(self, dt):
        vals = {}
        if not self.static:
            vals.update({'t': self.t, 'v': self.v, 'mode': float(self.mode)})
            vals.update(self.toggles)
        self.vals = vals
        for name, node in self.f.get('values', []):
            vals[name] = self._node(name, node, dt)
        for fl, parts in self.flows:
            self._flow(fl, parts, dt)
        self.first = False

    def _node(self, name, n, dt):
        ref = self.ref
        if 'table' in n:
            return table_at(n['table'], self.vals[n['of']], n.get('step', False))
        if 'sum' in n:
            return sum(ref(r) for r in n['sum'])
        if 'product' in n:
            p = 1.0
            for r in n['product']:
                p *= ref(r)
            return p
        if 'select' in n:
            cs = n['cases']
            return ref(cs[min(len(cs) - 1, max(0, math.floor(self.vals[n['select']])))])
        if 'follow' in n:
            target = self.vals[n['follow']]
            if self.first:
                self.state[name] = n.get('init', target)
            o = self.state[name]
            k = n['rate'] if target >= o else n.get('rate_down', n['rate'])
            o = o + (target - o) * min(1.0, dt * k)
            self.state[name] = o
            return o
        # hold
        x, w = self.vals[n['hold']], self.vals[n['while']] >= 0.5
        held, prev = self.state.get(name, (x, False))
        if w and prev and not self.first:
            out = held
        else:
            out = x
        self.state[name] = (out, w)
        return out

    def _choose(self, fl, i, n):
        u = frac((i + n * fl['count']) * PHI)
        ws = [max(0.0, self.ref(rt.get('weight', 1))) for rt in fl['routes']]
        total = sum(ws)
        if total <= 0:
            return 0
        acc = 0.0
        for j, w in enumerate(ws):
            acc += w
            if acc > u * total:
                return j
        return len(ws) - 1

    def _flow(self, fl, parts, dt):
        geo = [flatten(rt['path'], self.ref) for rt in fl['routes']]
        along = fl.get('along', {})
        speed = self.ref(fl.get('speed', 0))
        r0 = self.ref(fl.get('r', 3))
        op0 = self.ref(fl.get('opacity', 1))
        pile = fl.get('pile', 0)
        hides = [([self.ref(v) for v in h['rect']], self.ref(h['when'])) for h in fl.get('hide', [])]
        for i, p in enumerate(parts):
            if p['route'] is None:
                p['route'] = self._choose(fl, i, 0)
            pts, segs, L = geo[p['route']]
            m = table_at(along['speed'], p['k']) if 'speed' in along else 1.0
            dk = 0.0 if L == 0 else speed * m * dt / L
            k = p['k'] + dk
            if fl.get('reverse') == 'pile' and dk < 0:
                k = max(k, 0.0 if L == 0 else min(1.0, pile * frac(i * PHI) / L))
            if k >= 1:
                k -= math.floor(k)
                p['n'] += 1
                p['route'] = self._choose(fl, i, p['n'])
            elif k < 0:
                k -= math.floor(k)
            p['k'] = k
            pts, segs, L = geo[p['route']]
            x, y = point_at(pts, segs, k * L)
            rt = fl['routes'][p['route']]
            lanes = rt.get('lanes', fl.get('lanes', [[0, 0]]))
            lx, ly = (self.ref(c) for c in lanes[i % len(lanes)])
            ls = table_at(along['lane'], k) if 'lane' in along else 1.0
            x, y = x + lx * ls, y + ly * ls
            if 'wrap_x' in fl:
                a, b = fl['wrap_x']
                x = a + (x - a) - (b - a) * math.floor((x - a) / (b - a))
            r = r0 * (table_at(along['r'], k) if 'r' in along else 1.0)
            op = op0 * (table_at(along['opacity'], k) if 'opacity' in along else 1.0)
            for (x0, y0, x1, y1), when in hides:
                if when >= 0.5 and x0 <= x <= x1 and y0 <= y <= y1:
                    op = 0.0
            fill = table_at(along['fill'], k, step=True) if 'fill' in along else fl.get('fill', 'accent')
            p.update(x=x, y=y, r=r, opacity=op, fill=fill)

    # --- results
    def text(self, t):
        if isinstance(t, str):
            return fill_template(t, self.vals)
        for c in t:
            if 'when' not in c or self.ref(c['when']) >= 0.5:
                return fill_template(c['text'], self.vals)

    def paint(self, p):
        if isinstance(p, str):
            return p
        if 'radial' in p:
            return p
        if 'stops' in p:
            return colour_at(p['stops'], self.vals[p['of']])
        return table_at(p['steps'], self.vals[p['of']], step=True)

    def scene(self):
        """The scene with every ref, paint, text and label resolved, and flows replaced by their particles."""
        return [self._resolve(e) for e in self.f['scene']]

    def _resolve(self, e):
        ref = self.ref
        out = {}
        for k, v in e.items():
            if k in ('rect', 'circle', 'ellipse', 'line'):
                out[k] = [ref(x) for x in v]
            elif k in ('poly',):
                out[k] = [[ref(a), ref(b)] for a, b in v]
            elif k == 'path':
                out[k] = [[c[0]] + [ref(x) for x in c[1:]] for c in v]
            elif k in ('fill', 'stroke'):
                out[k] = self.paint(v)
            elif k in ('stroke_width', 'opacity', 'rx'):
                out[k] = ref(v)
            elif k == 'transform':
                out[k] = [{kk: [ref(x) for x in vv] for kk, vv in st.items()} for st in v]
            elif k == 'text':
                out[k] = self.text(v)
            elif k in ('at', 'to'):
                out[k] = [ref(x) for x in v]
            elif k == 'clip':
                out[k] = {'rect': [ref(x) for x in v['rect']], 'rx': ref(v.get('rx', 0))}
            elif k == 'group':
                out[k] = [self._resolve(c) for c in v]
            elif k == 'flow':
                out[k] = {'particles': self._particles(v)}
                for kk in ('glyph', 'stroke', 'stroke_width'):
                    if kk in v:
                        out['flow'][kk] = ref(v[kk]) if kk == 'stroke_width' else v[kk]
            else:
                out[k] = v
        if 'label' in e:
            out['end'] = leader_end(e['label'], out['at'], out['to'], e.get('anchor', 'start'))
        return out

    def _particles(self, fl):
        for f, parts in self.flows:
            if f is fl:
                return [[p['x'], p['y'], p['r'], p['opacity'], p['fill']] for p in parts]

    def status(self):
        return self.text(self.f['status']) if 'status' in self.f else None

    def slider_text(self):
        return self.text(self.f['slider']['text']) if 'slider' in self.f else None


def leader_end(label, at, to, anchor):
    (x1, y1), (x2, y2) = at, to
    w = 6.3 * len(label)
    left = x2 - w if anchor == 'end' else x2
    right = left + w
    if x1 < left - 2:
        return [left - 4, y2 - 4]
    if x1 > right + 2:
        return [right + 4, y2 - 4]
    return [x1, y2 + 4 if y1 > y2 else y2 - 15]
