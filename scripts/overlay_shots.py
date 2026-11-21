"""Evidence for #462: the web's other overlay screens (the CSS change reaches them all) at 320 px and 200 % zoom, in three
engines, on a fresh synthetic server: sign-in before setup, the setup form, sign-up, the password-link form and a link
that is not valid.  KKS_REPO=... KKS_SERVER=... python overlay_shots.py OUTDIR"""
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
SIZES = (('320', 320, 640, 1), ('zoom200', 320, 400, 2))
def shoot(p, stage, screens):
    for eng in ('chromium', 'firefox', 'webkit'):
        b = p[eng].launch()
        for screen, url, act in screens:
            for name, w, h, z in SIZES:
                ctx = b.new_context(viewport={'width': w, 'height': h}, device_scale_factor=z)
                pg = ctx.new_page(); pg.goto(base + url); pg.locator('#kov form, #kov .box').first.wait_for()
                if act: act(pg); pg.wait_for_timeout(300)
                pg.screenshot(path=os.path.join(out, f'web-{eng}-{screen}-{name}.png')); ctx.close()
        b.close()
try:
    with sync_playwright() as p:
        shoot(p, 'pre', [('signin-before-setup', '/', None), ('setup-form', '/#setup=' + setup, None)])
        boss = Client(base)
        boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password', 'full_name': 'The Manager', 'position': 'Plant manager'})
        boss.req('POST', '/api/signup-code', {'code': 'team-7391-plant'})
        boss.req('POST', '/api/users', {'username': 'ali', 'full_name': 'Ali Test', 'position': 'Operator'})
        users = boss.req('GET', '/api/users')
        uid = [u['id'] for u in (users['users'] if isinstance(users, dict) else users) if u['username'] == 'ali'][0]
        link = boss.req('POST', '/api/users/%d/reset' % uid, {})['link']
        shoot(p, 'post', [('signup-form', '/', lambda pg: pg.locator('#signup').click()),
                          ('password-link-form', '/#' + link.split('#', 1)[1], None),
                          ('password-link-not-valid', '/#reset=not-a-token', None)])
finally:
    srv.terminate(); srv.wait(5); shutil.rmtree(d, ignore_errors=True)
