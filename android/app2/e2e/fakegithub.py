"""Helpers for the emulator tests: a fake GitHub serving a signed release, and the emulator's "System UI isn't
responding" dialog (it eats taps)."""
import http.server, json, os, sys, threading, time
sys.path.insert(0, os.path.dirname(__file__))
import adbui as ui  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
HOST = '10.0.2.2'          # this machine, seen from the emulator
sys.path.insert(0, REPO)
from tools import release  # noqa: E402


def calm():
    """the emulator's "System UI isn't responding" dialog eats taps (CLAUDE.md, M3c): wait it out"""
    for _ in range(3):
        if ui.present("isn't responding"):
            ui.tap('Wait', exact=True)
            time.sleep(1)


class FakeGitHub:
    """GitHub's releases/latest with a release.json signed by a test key, and the files"""
    def __init__(self, files):
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        key = Ed25519PrivateKey.generate()
        self.pub = release.public_b64u(key)
        version = open(os.path.join(REPO, 'VERSION')).read().strip()
        m = release.manifest(version, files)
        self.blobs = {n: open(p, 'rb').read() for n, p in files.items()}
        self.blobs['release.json'] = m
        self.blobs['release.json.sig'] = release.sign(m, key).encode()
        me = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                if self.path == '/repos/x/releases/latest':
                    base = f'http://{HOST}:{self.server.server_address[1]}/f/'
                    body = json.dumps({'assets': [{'name': n, 'browser_download_url': base + n} for n in me.blobs]}).encode()
                elif self.path.startswith('/f/') and self.path[3:] in me.blobs:
                    body = me.blobs[self.path[3:]]
                else:
                    self.send_response(404); self.end_headers(); return
                self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
                self.wfile.write(body)
        self.httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.api = f'http://{HOST}:{self.httpd.server_address[1]}/repos/x/releases/latest'


