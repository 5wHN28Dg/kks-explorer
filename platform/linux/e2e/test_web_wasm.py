"""Our own libjxl and zxing-cpp WebAssembly build (decision 0037) in Chromium, Firefox and WebKit, against the Nim
server: decoding a course picture (both the SIMD and the scalar variant), a photo encoded to JPEG XL in the browser
and stored as such by the server (the server refuses anything else), a QR code written and read back.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_wasm.py
Needs djxl for the server-side check of the photo."""
import base64, json, os, re, shutil, subprocess, sys, tempfile, unittest
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import free_port, Client

PAGE_JS = r"""async () => {
  const W = await import('/kks-wasm.js');
  const out = {variant: W.variant};
  // decode a course picture with each variant
  const bytes = new Uint8Array(await (await fetch('/data/courses/ppt-01.jxl')).arrayBuffer());
  const d = await W.jxlDecode(bytes);
  out.decoded = [d.width, d.height, d.rgba.length];
  const scalar = await (await import('/vendor/kks/kks.js')).default();
  const p = scalar._kks_malloc(bytes.length), wh = scalar._kks_malloc(8);
  scalar.HEAPU8.set(bytes, p);
  const o = scalar._kks_jxl_decode(p, bytes.length, wh);
  out.scalar = o ? [scalar.HEAPU32[wh >> 2], scalar.HEAPU32[(wh >> 2) + 1]] : null;
  // encode a drawing, as a photo would be
  const c = document.createElement('canvas'); c.width = 640; c.height = 480;
  const g = c.getContext('2d'); g.fillStyle = '#3c5a96'; g.fillRect(0, 0, 640, 480); g.fillStyle = '#f0f0f0'; g.fillRect(200, 150, 240, 180);
  const t0 = performance.now();
  out.dataUrl = await K.jxlEncode(c, 1.9, 7);
  out.encodeMs = performance.now() - t0;
  // a QR code written, drawn 4 px per module, read back
  const text = '{"kks_invite":1,"token":"abc-ÄÖ"}';
  const q = await W.qrWrite(text), s = 4, n = q.side * s, lum = new Uint8Array(n * n);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) lum[y * n + x] = q.modules[Math.floor(y / s) * q.side + Math.floor(x / s)];
  out.qr = await W.qrRead(lum, n, n);
  out.qrSide = q.side;
  return out;
}"""


class WebWasm(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-web-wasm-')
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
        cls.boss = Client(cls.base)
        assert cls.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager'}).get('ok')
        cls.boss.req('POST', '/api/login', {'username': 'boss', 'password': 'a long password'})

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def run_engine(self, name):
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            ctx = browser.new_context()
            ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                             headers={'Origin': self.base})
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(self.base + '/learning.html')
            page.wait_for_function("() => typeof K !== 'undefined' && K.me")
            cfg = page.evaluate("K.cfg.photo_upload")
            self.assertEqual(cfg['type'], 'image/jxl')
            out = page.evaluate(PAGE_JS)
            # the photo through the API, as index.html sends it
            r = page.evaluate("d => K.api('/api/submit', {kind: 'photo', payload: {kks: '11LAB70AA501', caption: 'from ' + d.n, dataUrl: d.u}})",
                              {'n': name, 'u': out['dataUrl']})
            # the admin's invite QR is drawn through zxing-cpp; read it back from the SVG's squares
            page.goto(self.base + '/admin.html')
            page.wait_for_function("() => typeof qrSvg === 'function' && typeof K !== 'undefined' && K.me")
            invite = page.evaluate("""async () => { const W = await import('/kks-wasm.js');
              const box = document.createElement('div'); box.append(await qrSvg('{"kks_invite":1,"code":"x"}'));
              const svg = box.querySelector('svg[aria-label="Invite QR code"]'), n = svg.viewBox.baseVal.width, s = 4;
              const dark = new Set([...svg.querySelector('path').getAttribute('d').matchAll(/M(\\d+),(\\d+)/g)].map(m => m[1] + ',' + m[2]));
              const lum = new Uint8Array(n * s * n * s);
              for (let y = 0; y < n * s; y++) for (let x = 0; x < n * s; x++) lum[y * n * s + x] = dark.has(Math.floor(x / s) + ',' + Math.floor(y / s)) ? 0 : 255;
              return W.qrRead(lum, n * s, n * s) }""")
            page.goto(self.base + '/learning.html')
            page.wait_for_function("() => typeof K !== 'undefined' && K.me")
            refused = page.evaluate("""() => K.api('/api/submit', {kind: 'photo', payload: {kks: '11LAB70AA501',
                dataUrl: document.createElement('canvas').toDataURL('image/png')}}).then(() => 'stored', e => e.message)""")
            browser.close()
        self.assertEqual(errors, [], name)
        self.assertEqual(out['variant'], 'simd', name + ': every current engine has WebAssembly SIMD')
        self.assertEqual(out['decoded'][:2], out['scalar'], name + ': the two variants decode alike')
        self.assertEqual(out['decoded'][2], out['decoded'][0] * out['decoded'][1] * 4)
        self.assertEqual(out['qr'], '{"kks_invite":1,"token":"abc-ÄÖ"}', name)
        self.assertIn(r.get('status'), ('approved', 'pending'), r)
        self.assertIn('JPEG XL', refused)
        self.assertIn('kks_invite', invite or '', name + ': the invite QR did not read back')
        ph = [x for x in self.boss.req('GET', '/api/state')['photos'] if x.get('caption') == 'from ' + name][0]
        self.assertTrue(ph['file'].endswith('.jxl'), ph)
        blob = self.boss.op.open(self.boss.base + '/photos/' + ph['file']).read()
        self.assertEqual(blob[:2], b'\xff\x0a')
        if shutil.which('djxl'):
            jxl, png = os.path.join(self.dir, name + '.jxl'), os.path.join(self.dir, name + '.png')
            with open(jxl, 'wb') as f: f.write(blob)
            subprocess.run(['djxl', jxl, png], check=True, capture_output=True)
            ident = subprocess.run(['python3', '-c', 'import struct,sys; d=open(sys.argv[1],"rb").read(); print(struct.unpack(">II", d[16:24]))', png],
                                   capture_output=True, text=True).stdout.strip()
            self.assertEqual(ident, '(640, 480)')
        print('%s: encode 640×480 at effort 7 took %.0f ms; QR %d modules' % (name, out['encodeMs'], out['qrSide']))

    def test_chromium(self): self.run_engine('chromium')
    def test_firefox(self): self.run_engine('firefox')
    def test_webkit(self): self.run_engine('webkit')


if __name__ == '__main__':
    unittest.main()
