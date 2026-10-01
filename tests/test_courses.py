"""The course content format (docs/COURSES.md) against ref/vectors/courses-v1.json, using the test-only reference in
ref/courses.py. Every course renderer (Nim core, web UI) must pass the same file."""
import json, math, os, sys, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from ref import courses as K, make_course_vectors as G


def close(a, b, path='', tol=1e-6):
    """Deep compare; numbers to `tol`. Returns the first difference or None."""
    if isinstance(a, bool) or isinstance(b, bool) or a is None or b is None or isinstance(a, str):
        return None if a == b else f'{path}: {a!r} != {b!r}'
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return None if math.isclose(a, b, abs_tol=tol) else f'{path}: {a} != {b}'
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return f'{path}: length {len(a)} != {len(b)}'
        for i, (x, y) in enumerate(zip(a, b)):
            d = close(x, y, f'{path}[{i}]', tol)
            if d:
                return d
        return None
    if isinstance(a, dict) and isinstance(b, dict):
        if set(a) != set(b):
            return f'{path}: keys {sorted(set(a) ^ set(b))}'
        for k in a:
            d = close(a[k], b[k], f'{path}.{k}', tol)
            if d:
                return d
        return None
    return f'{path}: {type(a).__name__} != {type(b).__name__}'


class Courses(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(G.OUT, encoding='utf-8') as f:
            cls.V = json.load(f)

    def test_file_is_frozen(self):
        with open(G.OUT, encoding='utf-8') as f:
            self.assertEqual(f.read(), G.dump(G.build()))

    def test_valid(self):
        for c in self.V['valid']:
            self.assertEqual(K.check_course(c['course'], set(c['images'])), c['counts'], c['why'])

    def test_rejects(self):
        for r in self.V['reject']:
            with self.assertRaises(K.FormatError, msg=r['why']) as cm:
                K.check_course(r['course'], set(r.get('images', ['photo-1.jxl'])))
            self.assertEqual(cm.exception.code, r['code'], r['why'])

    def test_frames(self):
        figures = self.V['valid'][0]['course']['figures']
        for run in self.V['frames']:
            ev = K.Figure(figures[run['figure']], reduce_motion=run['reduce_motion'])
            for n, step in enumerate(run['steps']):
                e = step['event']
                if e[0] == 'tick':
                    ev.tick(e[1])
                elif e[0] == 'slider':
                    ev.set_slider(e[1])
                elif e[0] == 'toggle':
                    ev.toggle(e[1])
                elif e[0] == 'mode':
                    ev.set_mode(e[1])
                elif e[0] == 'play':
                    ev.play()
                elif e[0] == 'pause':
                    ev.pause()
                if step['state'] is not None:
                    got = json.loads(json.dumps(G.snapshot(ev)))
                    diff = close(got, step['state'], f"{run['figure']} step {n} {e}")
                    self.assertIsNone(diff, diff)

    def test_units(self):
        U = self.V['units']
        for c in U['table']:
            for u, y in c['at']:
                self.assertAlmostEqual(K.table_at(c['table'], u, c['step']), y, 9)
        for x, d, sgn, s in U['format']:
            self.assertEqual(K.fmt_number(x, d, sgn), s)
        for s, vals, out in U['template']:
            self.assertEqual(K.fill_template(s, vals), out)
        for stops, u, c in U['colour']:
            self.assertEqual(K.colour_at(stops, u), c)
        for lab, at, to, anc, end in U['leader']:
            self.assertIsNone(close(K.leader_end(lab, at, to, anc), end))
        for v, state in U['judge']['cases']:
            self.assertEqual(K.judge(U['judge']['item'], v), state)
        for f in U['flatten']:
            pts, segs, L = K.flatten(f['path'], lambda r: r)
            self.assertIsNone(close([list(p) for p in pts], f['points']))
            self.assertAlmostEqual(L, f['length'], 9)

    def test_round_half_away_from_zero(self):
        # the rule every renderer must follow, including exact binary halves
        self.assertEqual(K.fmt_number(2.5, 0, False), '3')
        self.assertEqual(K.fmt_number(-2.5, 0, False), '−3')
        self.assertEqual(K.fmt_number(0.125, 2, False), '0.13')
        self.assertEqual(K.fmt_number(2.675, 2, False), '2.67')   # 2.675 is 2.67499999… in binary
        self.assertEqual(K.fmt_number(-0.3, 0, True), '+0')


if __name__ == '__main__':
    unittest.main()
