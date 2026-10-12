"""The course files the program ships (data/courses): each is a valid course (ref/courses.py, the test-only reference
of docs/COURSES.md), named after its id, with its pictures present, in a list whose order has no ties. And the
fourth course, Instrumentation and control (`inc`): its figures are the ones tools/m6/inc_figures.py draws, every
worked number in its questions that can be recomputed is right, and it names no plant."""
import json, math, os, re, sys, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'm6'))
from ref import courses as K

DIR = os.path.join(ROOT, 'data', 'courses')


def load(name):
    with open(os.path.join(DIR, name), encoding='utf-8') as f:
        return json.load(f)


def text(x):
    """all the text of a run, block, question or page"""
    if isinstance(x, str):
        return x
    if isinstance(x, list):
        return ''.join(text(v) for v in x)
    if isinstance(x, dict):
        return ' '.join(text(v) for k, v in x.items() if k not in ('id', 'kind', 'file', 'to', 'figure', 'module', 'state'))
    return ''


class CourseFiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.names = sorted(n for n in os.listdir(DIR) if n.endswith('.json'))
        cls.images = {n for n in os.listdir(DIR) if n.endswith('.jxl')}
        cls.courses = {n: load(n) for n in cls.names}

    def test_every_file_is_a_valid_course(self):
        self.assertEqual(self.names, ['fnd.json', 'hrsg.json', 'inc.json', 'ppt.json'])
        for name, c in self.courses.items():
            size = os.path.getsize(os.path.join(DIR, name))
            counts = K.check_course(c, image_files=self.images, size=size)   # raises FormatError on any broken rule
            self.assertEqual(c['id'] + '.json', name)
            self.assertGreater(counts['questions'], 0, name)

    def test_order_has_no_ties_and_the_new_course_is_last(self):
        by_order = sorted(self.courses.values(), key=lambda c: c['order'])
        self.assertEqual([c['order'] for c in by_order], [1, 2, 3, 4])
        self.assertEqual([c['id'] for c in by_order], ['ppt', 'fnd', 'hrsg', 'inc'])

    def test_no_picture_is_left_over(self):
        used = set()

        def walk(x):
            if isinstance(x, dict):
                if isinstance(x.get('image'), dict):
                    used.add(x['image']['file'])
                for v in x.values():
                    walk(v)
            elif isinstance(x, list):
                for v in x:
                    walk(v)
        walk(list(self.courses.values()))
        self.assertEqual(used, self.images)

    def test_every_picture_has_its_credit(self):
        def walk(x, name):
            if isinstance(x, dict):
                im = x.get('image')
                if isinstance(im, dict):
                    credit = json.dumps(im['credit'])
                    self.assertIn('commons.wikimedia.org/wiki/File:', credit, im['file'])
                    self.assertIn('creativecommons.org/', credit, im['file'])
                    self.assertTrue(im['alt'] and im['caption'], im['file'])
                for v in x.values():
                    walk(v, name)
            elif isinstance(x, list):
                for v in x:
                    walk(v, name)
        walk(self.courses['inc.json'], 'inc')


class Inc(unittest.TestCase):
    """the Instrumentation and control course"""

    @classmethod
    def setUpClass(cls):
        cls.c = load('inc.json')
        cls.modules = [p for p in cls.c['pages'] if p['kind'] == 'module']

    def test_shape_follows_the_other_courses(self):
        c = self.c
        self.assertEqual((c['id'], c['order'], c['title']), ('inc', 4, 'Instrumentation and control'))
        self.assertEqual([p['n'] for p in self.modules], [str(i) for i in range(13)])
        for m in self.modules[1:]:
            self.assertTrue(m['worked'] and len(m['worked']['steps']) == 4, m['id'])
            self.assertGreaterEqual(len(m['practice']), 5, m['id'])
            self.assertGreaterEqual(len(m['goals']), 3, m['id'])
        kinds = [p['kind'] for p in c['pages'] if p['kind'] != 'module']
        self.assertEqual(kinds, ['placement', 'vocab_drill', 'test', 'glossary', 'page', 'page'])
        place = next(p for p in c['pages'] if p['kind'] == 'placement')
        per_module = {}
        for it in place['items']:
            per_module[it['module']] = per_module.get(it['module'], 0) + 1
        self.assertEqual(per_module, {m['id']: 2 for m in self.modules[1:]})    # two questions a module
        test = next(p for p in c['pages'] if p['kind'] == 'test')
        self.assertEqual({it['module'] for it in test['items']} - {m['id'] for m in self.modules}, set())
        self.assertEqual(test['pass'], math.ceil(len(test['items']) * 0.85))
        with_terms = {g['module'] for g in c['glossary']}
        self.assertEqual(with_terms, {m['id'] for m in self.modules[1:]})        # every module has its vocabulary

    def test_figures_are_the_drawn_ones(self):
        """a staleness check: the file was built from the figures as tools/m6/inc_figures.py draws them now"""
        import inc_figures
        drawn = inc_figures.build()
        own = {k: v for k, v in self.c['figures'].items() if k in drawn}
        self.assertEqual(set(own), set(drawn))                # every drawn figure is used, none is missing
        for fid, f in own.items():
            for key in ('w', 'h', 'alt', 'scene', 'period', 'values', 'slider', 'status'):
                self.assertEqual(f.get(key), json.loads(json.dumps(drawn[fid].get(key))), f'{fid}.{key}')
            self.assertNotEqual(f['title'], fid)              # the title and the caption come from the course text
            self.assertNotEqual(f['caption'], [fid])
        # only what version 1 of the format has: the validator above accepts the file, and nothing here is a new kind
        self.assertEqual(self.c['version'], 1)

    def test_names_no_plant(self):
        s = json.dumps(self.c, ensure_ascii=False)
        for word in ('Rumail', 'Basra'):
            self.assertNotIn(word, s)
        self.assertIsNone(re.search(r'\b1[0-2][A-Z]{3}\d{2}[A-Z]{2}\d{3}', s))      # no real-looking KKS code either

    def test_signal_conversions_in_the_text(self):
        """the conversion tables (Module 4 and the quick reference) follow the standard conversions"""
        ma = lambda f: 4 + 16 * f
        for pid in ('ma', 'quick'):
            table = next(b['table'] for b in next(p for p in self.c['pages'] if p['id'] == pid)['body']
                         if 'table' in b and text(b['table']['head']).startswith('Percent'))
            self.assertEqual(len(table['rows']), 5)
            for row in table['rows']:
                pct, cur, volt, psi = (float(re.match(r'[\d.]+', text(cell))[0]) for cell in row[:4])
                f = pct / 100
                self.assertAlmostEqual(cur, ma(f))
                self.assertAlmostEqual(volt, cur * 0.250)
                self.assertAlmostEqual(psi, 3 + 12 * f)

    def test_test_pages_say_how_many_questions_they_have(self):
        place = next(p for p in self.c['pages'] if p['kind'] == 'placement')
        final = next(p for p in self.c['pages'] if p['kind'] == 'test')
        self.assertEqual(len(place['items']), 24)
        self.assertIn('Twenty-four', text(place['intro']))
        self.assertEqual((len(final['items']), final['pass']), (20, 17))
        self.assertIn('Twenty mixed questions', text(final['intro']))
        self.assertIn('17 or more', text(final['intro']))

    def question(self, qid):
        for p in self.c['pages']:
            qs = ([p.get('warm')] + p.get('practice', [])) if p['kind'] == 'module' else \
                [it['q'] for it in p.get('items', []) if 'q' in it]
            for q in qs:
                if q and q['id'] == qid:
                    return q
        self.fail('no question ' + qid)

    def right(self, qid):
        r = [o for o in self.question(qid)['options'] if o['right']]
        self.assertEqual(len(r), 1, qid)
        return text(r[0]['text'])

    def test_tests_do_not_always_put_the_right_option_first(self):
        for kind in ('placement', 'test'):
            page = next(p for p in self.c['pages'] if p['kind'] == kind)
            where = [[o['right'] for o in it['q']['options']].index(True) for it in page['items']]
            for pos in (0, 1, 2):
                self.assertGreaterEqual(where.count(pos), len(where) // 5, f'{kind}: {where}')

    def test_worked_numbers(self):
        """the numeric answers, recomputed here from the question's own numbers"""
        num = lambda s: float(re.search(r'-?\d+(?:\.\d+)?', s.replace('−', '-'))[0])
        frac = lambda mA: (mA - 4) / 16
        checks = {
            's0': 100 * frac(12),                                  # 12 mA → 50%
            't1a': 150 - (-50),                                    # span
            't1b': (12.08 - 12.00) / 16 * 100,                     # % of span
            'm1b': 4.60 / 250 * 1000,                              # V across 250 Ω → mA
            'a1a': frac(10) * 800,
            'a1b': 4 + 16 * 10 / 16,
            'a1c': 100 + frac(8) * 200,
            'a1d': 24 - 0.020 * (250 + 30 + 250),                  # volts left at the transmitter
            'a1f': (24 - 10.5) / 0.020,                            # largest loop resistance
            'b1a': 350 * 2 * 500e-6,                               # ΔR = R × GF × ε
            'b1d': (130.8 - 100) / 0.385,
            'c1a': (250 - 50) / (450 - 50) * 100,
            'p1w': 100 * math.sqrt(frac(8)),
            'p1a': 100 * math.sqrt(0.49),
            'd1a': 1 + 18 / 2,
            'd1d': 10.0 - 9.4,
            'r1w': 2940 * 60 / 60,
            'r1a': 120 * 1500 / 60,
            'r1d': 60 / 1.0,                                       # one pulse in a 1 s gate, one pulse a turn → rpm
            'v1a': 3 + 12 * frac(8),
            'x1a': 10 * math.sqrt(0.5),
            'x1b': 197 / 7.87,
            'x1f': 3.0 / (2 * math.pi * 50) * 1000,                # µm peak
            'p_t1': 120 - 20, 'p_m2': 1.80 / 250 * 1000, 'p_a1': 100 * frac(16), 'p_a2': 4 + 16 * 0.40,
            'p_p1': 100 * math.sqrt(0.36), 'p_d2': 1 + 9 / 1, 'p_r1': 1500 * 60 / 60, 'p_v1': 3 + 12 * frac(12),
            'z6': frac(3.60 / 250 * 1000) * 10, 'z7': 50 + frac(12) * 300, 'z8': 24 - 0.020 * 400,
            'z9': 10 * 2 * 500e-6 / 4 * 1000, 'z10': (109.6 - 100) / 0.385, 'z12': 100 * 0.5 ** 2,
            'z16': 60 * 3000 / 60, 'z17': 3 + 12 * frac(16), 'z19': (10.0 - 8.0) / 7.87,
        }
        for qid, want in checks.items():
            got = num(self.right(qid))
            tol = 0.05 if qid in ('x1f', 'z19') else 0.01          # the two answers given as "about"
            self.assertTrue(math.isclose(got, want, rel_tol=tol, abs_tol=0.006), f'{qid}: the right option says {got}, computed {want}')
            if qid not in ('a1d', 'r1d', 'z9'):                    # no other option may give the same number (z9: the same number in volts)
                q = self.question(qid)
                others = [text(o['text']).replace('−', '-') for o in q['options'] if not o['right']]
                for o in others:
                    m = re.search(r'-?\d+(?:\.\d+)?', o)
                    if m:
                        self.assertFalse(math.isclose(float(m[0]), want, rel_tol=0.01), f'{qid}: a wrong option also says {m[0]}')

    def test_every_question_can_be_answered(self):
        ids = set()
        for p in self.c['pages']:
            qs = []
            if p['kind'] == 'module':
                qs = [p['warm']] + p['practice']
            elif p['kind'] in ('placement', 'test'):
                qs = [it['q'] for it in p['items'] if 'q' in it]
            for q in qs:
                self.assertNotIn(q['id'], ids)
                ids.add(q['id'])
                if q['type'] == 'order':
                    self.assertGreaterEqual(len(q['steps']), 3)
                    continue
                self.assertEqual(sum(1 for o in q['options'] if o['right']), 1, q['id'])
                texts = [text(o['text']) for o in q['options']]
                self.assertEqual(len(set(texts)), len(texts), q['id'])          # no two options alike
                if p['kind'] == 'module':                                        # practice explains every wrong pick
                    for o in q['options']:
                        self.assertTrue(o['why'], f'{q["id"]}: an option without feedback')


if __name__ == '__main__':
    unittest.main()
