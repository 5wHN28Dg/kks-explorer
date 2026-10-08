"""The JSON courses in the browser client (decision 0035), in Chromium, Firefox and WebKit, against the Nim server
with the program's data/courses (no plant data needed): the course list, every page of every course without a
script error, every figure drawn, answering questions (progress in the v1 localStorage keys), an ordering question,
the test page, both drills and the KKS decoder; keyboard-only answering on one page.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_course_web.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server); screenshots go to $KKS_SHOTS (/tmp/kks-course-shots)."""
import json, os, re, shutil, subprocess, sys, tempfile, unittest
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
SHOTS = os.environ.get('KKS_SHOTS', '/tmp/kks-course-shots')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import free_port, Client, CSP_WATCH

COURSES = {}
for cid in ('ppt', 'fnd', 'hrsg'):
    with open(os.path.join(REPO, 'data', 'courses', cid + '.json'), encoding='utf-8') as f:
        COURSES[cid] = json.load(f)

# a canvas counts as drawn when it has pixels that are not the background
DRAWN = """(c) => { const x = c.getContext('2d'), d = x.getImageData(0, 0, c.width, c.height).data; let n = 0;
  for (let i = 3; i < d.length; i += 16) if (d[i] > 0) n++; return n }"""


class CourseWeb(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-course-web-')
        cls.port = free_port()
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups')}
        with open(os.path.join(cls.dir, 'config.json'), 'w') as f:
            json.dump(cfg, f)
        cls.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(cls.dir, 'config.json')], cwd=cls.dir,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = cls.server.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', open(line.split('setup link file: ', 1)[1].strip()).read() if 'setup link file: ' in line else line)   # the link is in a 0600 file (#69)
            if m: setup = m[1]
            if 'server on' in line: break
        cls.base = 'http://127.0.0.1:%d' % cls.port
        assert Client(cls.base).req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                           'full_name': 'The Manager'}).get('ok')
        os.makedirs(SHOTS, exist_ok=True)

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def test_list_api(self):
        c = Client(self.base)
        c.req('POST', '/api/login', {'username': 'boss', 'password': 'a long password'})
        got = c.req('GET', '/api/courses')['courses']
        self.assertEqual([x['id'] for x in got], ['ppt', 'fnd', 'hrsg'])
        self.assertEqual([len(x['questions']) for x in got], [70, 76, 67])   # module questions (tests excluded)

    def run_engine(self, name):
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            ctx = browser.new_context(viewport={'width': 1280, 'height': 900})
            ctx.add_init_script(CSP_WATCH)
            r = ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                                 headers={'Origin': self.base})
            self.assertTrue(r.ok, r.text())
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(self.base + '/learning.html')
            page.wait_for_selector('a.course')
            self.assertEqual(page.locator('a.course').count(), 3)
            self.assertIn('course.html?c=ppt', page.locator('a.course').first.get_attribute('href'))
            for cid, course in COURSES.items():
                page.goto(f'{self.base}/course.html?c={cid}')
                page.wait_for_selector('#main h1')
                for pg in course['pages']:
                    page.evaluate(f"location.hash = {json.dumps(pg['id'])}")
                    page.wait_for_function(f"() => document.title.includes({json.dumps(pg['kind'] == 'module' and pg['short'] or '')})")
                    figs = [b['figure'] for b in pg.get('body', []) if 'figure' in b]
                    if figs:
                        page.wait_for_timeout(250)
                        canvases = page.locator('#main canvas')
                        self.assertEqual(canvases.count(), len(figs), f'{cid}/{pg["id"]}')
                        for i in range(canvases.count()):
                            self.assertGreater(canvases.nth(i).evaluate(DRAWN), 50, f'{cid}/{pg["id"]} figure {figs[i]}')
                self.assertEqual(errors, [], f'{name} {cid}')
            # answering: the right option of fnd's first practice question, then a wrong one of the next
            fnd = COURSES['fnd']
            m = next(p for p in fnd['pages'] if p['kind'] == 'module' and p['practice'])
            page.goto(f'{self.base}/course.html?c=fnd#{m["id"]}')
            page.wait_for_selector('#main h1')
            q = m['practice'][0]
            right = next(i for i, o in enumerate(q['options']) if o['right'])
            box = page.locator(f'[aria-labelledby="q-{q["id"]}"]')
            box.locator('.opt').nth(right).click()
            self.assertIn('Right.', box.locator('.fb').first.inner_text())
            solved = json.loads(page.evaluate("localStorage.getItem('fnd.solved')"))
            self.assertTrue(solved.get(q['id']))
            self.assertEqual(json.loads(page.evaluate("localStorage.getItem('fnd.last')")), m['id'])
            # an ordering question placed right
            order = [(p, q) for p in COURSES['hrsg']['pages'] if p['kind'] == 'module' for q in p['practice'] if q['type'] == 'order']
            if order:
                mp, oq = order[0]
                page.goto(f'{self.base}/course.html?c=hrsg#{mp["id"]}')
                page.wait_for_selector('#main h1')
                box = page.locator(f'[aria-labelledby="q-{oq["id"]}"]')
                for i in range(len(oq['steps'])):
                    box.locator(f'.pool .step[data-i="{i}"]').click()
                box.get_by_role('button', name='Check order').click()
                self.assertIn('All in the right order', box.locator('.fb').inner_text())
            # the test page: answer everything with the first option; a result appears and finalBest is kept
            page.goto(f'{self.base}/course.html?c=ppt#final')
            page.wait_for_selector('#main h1')
            acts = page.locator('#main .act[role=group]')
            for i in range(acts.count()):
                acts.nth(i).locator('.opt').first.click()
            self.assertIn('finished', page.locator('#main .score').inner_text())
            self.assertIsNotNone(page.evaluate("localStorage.getItem('ppt.finalBest')"))
            # drills and the decoder
            page.goto(f'{self.base}/course.html?c=hrsg#drill')
            page.wait_for_selector('.drill-card .reading')
            page.locator('.judge .opt').first.click()
            self.assertTrue(page.locator('#main .fb').count() >= 1)
            page.goto(f'{self.base}/course.html?c=ppt#drill')
            page.wait_for_selector('.drill-card .reading')
            page.locator('#main .opts .opt').first.click()
            page.goto(f'{self.base}/course.html?c=ppt#kks')
            page.wait_for_selector('#main table')
            self.assertIn('LAB', page.locator('#main table').inner_text())
            # keyboard only: Tab to the first option of the warm-up and press Enter
            page.goto(f'{self.base}/course.html?c=fnd#{m["id"]}')
            page.wait_for_selector('#main h1')
            page.locator(f'[aria-labelledby="q-{m["warm"]["id"]}"] .opt').first.focus()
            page.keyboard.press('Enter')
            self.assertTrue(page.locator(f'[aria-labelledby="q-{m["warm"]["id"]}"] .fb').count() >= 1)
            page.screenshot(path=os.path.join(SHOTS, name + '-module.png'), full_page=False)
            self.assertEqual(errors, [], name)
            browser.close()

    def keyboard(self, name):
        """keyboard only: the rail, answering, the order question, the figure's slider; and what assistive technology
        gets from the accessibility tree (roles and names)"""
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            ctx = browser.new_context(viewport={'width': 1280, 'height': 900})
            ctx.add_init_script(CSP_WATCH)
            ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                             headers={'Origin': self.base})
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(f'{self.base}/course.html?c=fnd#start')
            page.wait_for_selector('#main h1')
            # Tab reaches the rail; Enter on a rail link opens that page and moves focus to its heading
            focused = None
            for _ in range(40):
                page.keyboard.press('Tab')
                focused = page.evaluate("document.activeElement && document.activeElement.textContent")
                if focused and 'Units' in focused:
                    break
            self.assertIn('Units', focused or '', name + ': Tab never reached the rail')
            page.keyboard.press('Enter')
            page.wait_for_function("() => location.hash === '#units' && document.activeElement.tagName === 'H1'", timeout=5000)
            # Tab onward reaches the warm-up's first option; Enter answers it
            for _ in range(80):
                page.keyboard.press('Tab')
                if page.evaluate("document.activeElement.classList.contains('opt')"):
                    break
            self.assertTrue(page.evaluate("document.activeElement.classList.contains('opt')"), name + ': no option by Tab')
            page.keyboard.press('Enter')
            page.wait_for_selector('#main .fb')
            # an order question by keyboard (hrsg has them): place every step with Enter, then check
            order = [(pg, q) for pg in COURSES['hrsg']['pages'] if pg['kind'] == 'module' for q in pg['practice'] if q['type'] == 'order']
            mp, oq = order[0]
            page.goto(f'{self.base}/course.html?c=hrsg#{mp["id"]}')
            page.wait_for_selector('#main h1')
            box = page.locator(f'[aria-labelledby="q-{oq["id"]}"]')
            for i in range(len(oq['steps'])):
                box.locator(f'.pool .step[data-i="{i}"]').focus()
                page.keyboard.press('Enter')
            box.get_by_role('button', name='Check order').focus()
            page.keyboard.press('Enter')
            self.assertIn('All in the right order', box.locator('.fb').inner_text())
            # the gate figure's slider by keyboard: arrows move it and pause the drive
            page.goto(f'{self.base}/course.html?c=fnd#mech')
            page.wait_for_selector('#main h1')
            sl = page.get_by_role('slider', name='Opening')
            sl.focus()
            v0 = sl.input_value()
            for _ in range(20):
                page.keyboard.press('ArrowRight')
            self.assertNotEqual(sl.input_value(), v0)
            self.assertEqual(page.locator('figure.vis').first.get_by_role('button').first.inner_text(), 'Play')
            # the accessibility tree: the figure is an image named by its title; questions are named groups; headings
            self.assertEqual(page.get_by_role('img', name='Gate valve cutaway').count(), 1)
            warm = next(pg for pg in COURSES['fnd']['pages'] if pg['id'] == 'mech')['warm']
            self.assertEqual(page.get_by_role('group', name=warm['q'][0] if isinstance(warm['q'][0], str) else None).count(), 1)
            self.assertEqual(page.get_by_role('heading', level=1).count(), 1)
            self.assertGreater(page.get_by_role('heading', level=2).count(), 2)
            self.assertEqual(errors, [], name)
            browser.close()

    def links(self, name):
        """#42: a course's outside link goes to href only if it is https; a javascript: or data: URL from course data
        becomes about:blank and runs nothing when clicked"""
        course = json.loads(json.dumps(COURSES['fnd']))
        course['pages'][0]['body'].insert(0, {'p': [
            {'link': ['evil'], 'to': {'url': 'javascript:window.pwned=1'}}, ' ',
            {'link': ['data'], 'to': {'url': 'data:text/html,<script>parent.pwned=2</script>'}}, ' ',
            {'link': ['plain'], 'to': {'url': 'http://example.invalid/'}}, ' ',
            {'link': ['good'], 'to': {'url': 'https://example.invalid/page'}}]})
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            ctx = browser.new_context(service_workers='block')
            ctx.add_init_script(CSP_WATCH)
            ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                             headers={'Origin': self.base})
            ctx.route('**/data/courses/fnd.json', lambda r: r.fulfill(status=200, content_type='application/json',
                                                                       body=json.dumps(course)))
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(f'{self.base}/course.html?c=fnd#{course["pages"][0]["id"]}')
            page.wait_for_selector('#main a:text-is("good")')
            hrefs = {t: page.get_attribute(f'#main a:text-is("{t}")', 'href') for t in ('evil', 'data', 'plain', 'good')}
            self.assertEqual(hrefs, {'evil': 'about:blank', 'data': 'about:blank', 'plain': 'about:blank',
                                     'good': 'https://example.invalid/page'}, name)
            page.evaluate('window.pwned = 0')
            page.locator('#main a:text-is("evil")').click(modifiers=[])
            page.wait_for_timeout(300)
            self.assertEqual(page.evaluate('window.pwned'), 0, name)
            self.assertEqual(errors, [], name)
            # the page's policy (#8) is enforced, and the tests see a violation: a script added inline doesn't run
            page.evaluate("() => { const s = document.createElement('script'); s.textContent = 'window.pwned = 3'; document.body.append(s) }")
            page.wait_for_timeout(300)
            self.assertEqual(page.evaluate('window.pwned'), 0, name)
            self.assertTrue(any('CSP violation: script-src' in e for e in errors), (name, errors))
            browser.close()

    def test_links_chromium(self): self.links('chromium')
    def test_links_firefox(self): self.links('firefox')
    def test_links_webkit(self): self.links('webkit')

    def test_keyboard_chromium(self): self.keyboard('chromium')
    def test_keyboard_firefox(self): self.keyboard('firefox')
    def test_keyboard_webkit(self): self.keyboard('webkit')

    def test_chromium(self): self.run_engine('chromium')
    def test_firefox(self): self.run_engine('firefox')
    def test_webkit(self): self.run_engine('webkit')


if __name__ == '__main__':
    unittest.main()
