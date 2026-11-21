"""Evidence for #449: the web sign-in screen on a fresh synthetic server (setup done as 'boss', sign-up on and off),
in three engines; 320 px wide, 412 px phone, 200 % zoom (as 640 px at device scale 2 + text), light and dark.
  KKS_SERVER=... python web_signin_shots.py OUTDIR"""
import os, sys, tempfile, shutil
REPO = os.environ['KKS_REPO']
sys.path.insert(0, os.path.join(REPO, 'platform', 'linux', 'e2e'))
from test_web_v2 import start_server, Client
from playwright.sync_api import sync_playwright
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
d = tempfile.mkdtemp(prefix='kks-ev-')
cfg = {'address': '127.0.0.1', 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
       'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(d, 'server.db'),
       'storage_key_file': os.path.join(d, 'storage.key'), 'plant_dir': os.path.join(d, 'plant-data'), 'backup_dir': os.path.join(d, 'backups')}
srv, setup = start_server(os.environ['KKS_SERVER'], d, cfg)
base = 'http://127.0.0.1:%d' % cfg['port']
try:
    boss = Client(base)
    boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password', 'full_name': 'The Manager', 'position': 'Plant manager'})
    with sync_playwright() as p:
        for eng in ('chromium', 'firefox', 'webkit'):
            b = p[eng].launch()
            for signup in (False, True):
                boss.req('POST', '/api/signup-code', {'code': 'team-7391-plant' if signup else ''})
                for scheme in ('light', 'dark'):
                    for name, vp, zoom in (('320', {'width': 320, 'height': 640}, 1), ('phone412', {'width': 412, 'height': 846}, 1), ('zoom200', {'width': 640, 'height': 800}, 2)):
                        if not signup and name != 'phone412': continue
                        ctx = b.new_context(viewport={'width': vp['width'] // zoom, 'height': vp['height'] // zoom}, device_scale_factor=zoom, color_scheme=scheme)
                        pg = ctx.new_page(); pg.goto(base + '/')
                        pg.locator('#kov form #forgotPw').wait_for()
                        f = os.path.join(out, f'web-{eng}-signin-{"signup-" if signup else ""}{name}-{scheme}.png')
                        pg.screenshot(path=f, full_page=True); ctx.close()
            b.close()
finally:
    srv.terminate(); srv.wait(5); shutil.rmtree(d, ignore_errors=True)
