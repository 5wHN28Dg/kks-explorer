#!/usr/bin/env python3
"""Plant P&ID / KKS Explorer - local server. Standard library only.
Run:  python3 app.py      then open http://localhost:8420 (phone: http://<laptop-ip>:8420, same Wi-Fi)."""
import json, os, re, sqlite3, time, uuid, base64, mimetypes, socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote
BASE=os.path.dirname(os.path.abspath(__file__)); DB=os.path.join(BASE,'plant.db'); PHOTOS=os.path.join(BASE,'photos'); PORT=8420
os.makedirs(PHOTOS,exist_ok=True)
def db():
    c=sqlite3.connect(DB); c.row_factory=sqlite3.Row; return c
def init():
    c=db(); c.executescript("""
    CREATE TABLE IF NOT EXISTS equipment(kks TEXT PRIMARY KEY, data TEXT NOT NULL, updated INTEGER);
    CREATE TABLE IF NOT EXISTS photos(id TEXT PRIMARY KEY, kks TEXT, file TEXT, caption TEXT, created INTEGER);
    CREATE TABLE IF NOT EXISTS reviews(tag_id TEXT PRIMARY KEY, data TEXT NOT NULL, updated INTEGER);
    CREATE TABLE IF NOT EXISTS links(proc TEXT, step INTEGER, kks TEXT, PRIMARY KEY(proc,step,kks));
    """); c.commit(); c.close()
class H(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def send(self,obj,code=200):
        b=json.dumps(obj).encode(); self.send_response(code); self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
    def file(self,path):
        if not os.path.isfile(path): return self.send({'error':'not found'},404)
        data=open(path,'rb').read(); self.send_response(200)
        self.send_header('Content-Type',mimetypes.guess_type(path)[0] or 'application/octet-stream')
        self.send_header('Content-Length',str(len(data))); self.send_header('Cache-Control','no-cache'); self.end_headers(); self.wfile.write(data)
    def body(self):
        n=int(self.headers.get('Content-Length',0)); return json.loads(self.rfile.read(n) or b'{}')
    def do_GET(self):
        p=unquote(urlparse(self.path).path)
        if p in('/','/index.html'): return self.file(os.path.join(BASE,'index.html'))
        if p.startswith('/data/') or p.startswith('/photos/'):
            full=os.path.normpath(os.path.join(BASE,p.lstrip('/')))
            if not any(full.startswith(os.path.join(BASE,d)+os.sep) for d in('data','photos')): return self.send({'error':'bad path'},400)
            return self.file(full)
        if p=='/api/state':
            c=db(); out={'equipment':{r['kks']:json.loads(r['data']) for r in c.execute('SELECT * FROM equipment')},
                'reviews':{r['tag_id']:json.loads(r['data']) for r in c.execute('SELECT * FROM reviews')},
                'photos':[dict(r) for r in c.execute('SELECT * FROM photos ORDER BY created')],
                'links':[dict(r) for r in c.execute('SELECT * FROM links')]}
            c.close(); return self.send(out)
        self.send({'error':'not found'},404)
    def do_POST(self):
        p=unquote(urlparse(self.path).path)
        try: d=self.body()
        except ValueError: return self.send({'error':'bad json'},400)
        c=db(); now=int(time.time())
        try:
            if p.startswith('/api/equipment/'):
                k=p.split('/')[-1]; c.execute('INSERT OR REPLACE INTO equipment VALUES(?,?,?)',(k,json.dumps(d),now))
            elif p.startswith('/api/review/'):
                t=p[len('/api/review/'):]; c.execute('INSERT OR REPLACE INTO reviews VALUES(?,?,?)',(t,json.dumps(d),now))
            elif p=='/api/links':
                c.execute('INSERT OR IGNORE INTO links VALUES(?,?,?)',(d['proc'],int(d['step']),d['kks']))
            elif p=='/api/links/delete':
                c.execute('DELETE FROM links WHERE proc=? AND step=? AND kks=?',(d['proc'],int(d['step']),d['kks']))
            elif p.startswith('/api/photos/'):
                k=p.split('/')[-1]; m=re.match(r'data:image/(\w+);base64,(.*)',d['dataUrl'],re.S)
                if not m: return self.send({'error':'bad image'},400)
                ext='jpg' if m.group(1) in('jpeg','jpg') else m.group(1); pid=uuid.uuid4().hex; fn=f'{pid}.{ext}'
                open(os.path.join(PHOTOS,fn),'wb').write(base64.b64decode(m.group(2)))
                c.execute('INSERT INTO photos VALUES(?,?,?,?,?)',(pid,k,fn,d.get('caption',''),now))
            elif p.startswith('/api/photos-delete/'):
                pid=p.split('/')[-1]; r=c.execute('SELECT file FROM photos WHERE id=?',(pid,)).fetchone()
                if r and os.path.exists(os.path.join(PHOTOS,r['file'])): os.remove(os.path.join(PHOTOS,r['file']))
                c.execute('DELETE FROM photos WHERE id=?',(pid,))
            else: return self.send({'error':'not found'},404)
            c.commit(); self.send({'ok':True})
        except (KeyError,TypeError,ValueError) as e: self.send({'error':f'bad request: {e}'},400)
        finally: c.close()
def lan_ip():
    try:
        s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(('8.8.8.8',80)); ip=s.getsockname()[0]; s.close(); return ip
    except Exception: return '127.0.0.1'
if __name__=='__main__':
    init(); print(f'\n  Plant P&ID / KKS Explorer\n  Laptop: http://localhost:{PORT}\n  Phone (same Wi-Fi): http://{lan_ip()}:{PORT}\n  Your data: {DB} and {PHOTOS}/\n  Ctrl+C to stop.\n')
    ThreadingHTTPServer(('0.0.0.0',PORT),H).serve_forever()
