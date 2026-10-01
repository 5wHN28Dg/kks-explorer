"""course-figure.js (decision 0035) against ref/vectors/courses-v1.json in Chromium, Firefox and WebKit: the frames
(clock, values, flows, resolved scene, texts) and the unit cases, compared to 1e-6 by the same deep compare as
tests/test_courses.py.
  /path/to/venv-with-playwright/bin/python tests/web/test_course_figure.py
WebKit on Linux may need PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=1 (see platform/linux/e2e/test_web_v2.py)."""
import json, os, sys, unittest
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(REPO, 'tests'))
from test_courses import close

RUN = r"""(V) => {
  const out = {frames: [], units: {}};
  const figs = V.valid[0].course.figures;
  for (const run of V.frames) {
    const ev = new KCF.Figure(figs[run.figure], run.reduce_motion), got = [];
    for (const step of run.steps) {
      const e = step.event;
      if (e[0] === 'tick') ev.tick(e[1]); else if (e[0] === 'slider') ev.setSlider(e[1]);
      else if (e[0] === 'toggle') ev.toggle(e[1]); else if (e[0] === 'mode') ev.setMode(e[1]);
      else if (e[0] === 'play') ev.play(); else if (e[0] === 'pause') ev.pause();
      got.push(step.state === null ? null : {t: ev.t, v: ev.v, playing: ev.playing, values: {...ev.vals},
               scene: ev.scene(), status: ev.status(), slider_text: ev.sliderText()});
    }
    out.frames.push(got);
  }
  const U = V.units;
  out.units.table = U.table.map(c => c.at.map(([u]) => KCF.tableAt(c.table, u, c.step)));
  out.units.format = U.format.map(([x, d, s]) => KCF.fmtNumber(x, d, s));
  out.units.template = U.template.map(([s, vals]) => KCF.fillTemplate(s, vals));
  out.units.colour = U.colour.map(([st, u]) => KCF.colourAt(st, u));
  out.units.leader = U.leader.map(([l, a, t, an]) => KCF.leaderEnd(l, a, t, an));
  out.units.flatten = U.flatten.map(f => { const [p, s, L] = KCF.flatten(f.path, r => r);
    return {points: p, length: L, at: f.at.map(([d]) => KCF.pointAt(p, s, d))}; });
  out.units.choose = U.choose.map(c => { const fl = {count: c.count, routes: c.weights.map(w => ({path: [['M', 0, 0], ['L', 1, 0]], weight: w}))};
    const ev = new KCF.Figure({title: 'x', caption: [], alt: 'x', w: 1, h: 1, period: 1, scene: [{flow: fl}]});
    return [...Array(c.count).keys()].map(i => [0, 1, 2, 3].map(n => ev.choose(fl, i, n))); });
  return out;
}"""


class CourseFigure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(REPO, 'ref', 'vectors', 'courses-v1.json'), encoding='utf-8') as f:
            cls.V = json.load(f)
        with open(os.path.join(REPO, 'course-figure.js'), encoding='utf-8') as f:
            cls.js = f.read()

    def check(self, engine):
        with sync_playwright() as p:
            b = getattr(p, engine).launch()
            pg = b.new_page()
            pg.set_content('<!doctype html><meta charset=utf-8><body></body>')
            pg.add_script_tag(content=self.js)
            got = pg.evaluate(RUN, self.V)
            b.close()
        V = self.V
        for run, frames in zip(V['frames'], got['frames']):
            for n, (step, st) in enumerate(zip(run['steps'], frames)):
                if step['state'] is not None:
                    d = close(st, step['state'], f"{engine} {run['figure']} step {n} {step['event']}")
                    self.assertIsNone(d, d)
        U = V['units']
        for c, ys in zip(U['table'], got['units']['table']):
            self.assertIsNone(close(ys, [y for _, y in c['at']], 'table'))
        self.assertEqual(got['units']['format'], [s for *_, s in U['format']])
        self.assertEqual(got['units']['template'], [o for *_, o in U['template']])
        self.assertEqual(got['units']['colour'], [c for *_, c in U['colour']])
        self.assertIsNone(close(got['units']['leader'], [e for *_, e in U['leader']], 'leader'))
        for f, g in zip(U['flatten'], got['units']['flatten']):
            self.assertIsNone(close(g, {'points': f['points'], 'length': f['length'], 'at': [p for _, p in f['at']]}, 'flatten'))
        self.assertEqual(got['units']['choose'], [c['routes'] for c in U['choose']])

    def test_chromium(self): self.check('chromium')
    def test_firefox(self): self.check('firefox')
    def test_webkit(self): self.check('webkit')


if __name__ == '__main__':
    unittest.main()
