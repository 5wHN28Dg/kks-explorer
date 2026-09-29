#!/usr/bin/env python3
"""KKS Explorer for your own laptop: the double-click entry point (packaged with PyInstaller, packaging/).

Starts the app in peer mode (docs/ARCHITECTURE.md: this computer is one person's device), opens the browser, and shows
a small window with Open / Quit. Your data lives in the usual per-user folder, not next to the program, so a new
version is just a new folder:
  Windows  %APPDATA%\\KKS Explorer        Linux  ~/.local/share/kks-explorer        ($KKS_HOME overrides)
Starting it again while it runs only opens the browser.

  desktop.py              normal start
  desktop.py --no-window  no window (console only; Ctrl+C stops)
  desktop.py --self-test  start in a temporary folder, check the app answers, stop (used after each build)"""
import json, os, socket, sys, tempfile, threading, time, urllib.request, webbrowser

APP = 'KKS Explorer'
FROZEN = getattr(sys, 'frozen', False)


def program_dir():
    return getattr(sys, '_MEIPASS', os.path.dirname(os.path.abspath(__file__)))


def user_dir():
    if os.environ.get('KKS_HOME'):
        return os.environ['KKS_HOME']
    if sys.platform == 'win32':
        return os.path.join(os.environ.get('APPDATA') or os.path.expanduser('~'), APP)
    return os.path.join(os.environ.get('XDG_DATA_HOME') or os.path.expanduser('~/.local/share'), 'kks-explorer')


def answers(port):
    """Is KKS Explorer (not something else) already listening on this port?"""
    try:
        with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/config', timeout=1.5) as r:
            return 'mode' in json.loads(r.read())
    except Exception:
        return False


def free(port):
    with socket.socket() as s:
        try:
            s.bind(('127.0.0.1', port))
            return True
        except OSError:
            return False


def prepare(home):
    """config.json in the user folder: peer mode, the plant data shipped with this version, state kept here."""
    os.makedirs(home, exist_ok=True)
    path = os.path.join(home, 'config.json')
    cfg = {}
    if os.path.exists(path):
        with open(path) as f:
            cfg = json.load(f)
    cfg.setdefault('mode', 'peer')
    cfg.setdefault('port', 8420)
    cfg.setdefault('plant_name', APP)
    for k, v in (('db', 'plant.db'), ('photos_dir', 'photos'), ('backup_dir', 'backups'), ('plant_dir', 'plant-data')):
        cfg.setdefault(k, v)
    cfg['data_dir'] = os.path.join(program_dir(), 'data')   # KKS tables + courses; the plant data comes by sync (§19)
    with open(path, 'w') as f:
        json.dump(cfg, f, indent=2)
    return path, cfg


def run(home, window=True, on_ready=None, log=True):
    from server import updates
    if on_ready is None and updates.handoff(home, sys.argv):   # a newer verified version was installed: run that one
        return 0
    if FROZEN:
        updates.cleanup(home)
    path, cfg = prepare(home)
    port = cfg['port']
    if answers(port):   # already running: just show it
        webbrowser.open(f'http://localhost:{port}/')
        return 0
    if not free(port):  # something else holds it: take the next free port and remember it
        port = next(p for p in range(port + 1, port + 50) if free(p))
        cfg['port'] = port
        with open(path, 'w') as f:
            json.dump(cfg, f, indent=2)
    if sys.stdout is None or (FROZEN and log):   # a windowed program has no console: keep a log instead
        log = open(os.path.join(home, 'kks-explorer.log'), 'a', buffering=1, encoding='utf-8')
        sys.stdout = sys.stderr = log
    os.environ['KKS_CONFIG'] = path
    import app
    url = f'http://localhost:{port}/'
    ready = threading.Event()
    box = {}

    def hooked(httpd):
        box['httpd'] = httpd
        ready.set()
    app.ON_READY = hooked
    server = threading.Thread(target=app.main, args=(['serve'],), daemon=True)
    server.start()
    if not ready.wait(60):
        print('the server did not start; see the log')
        return 1
    stop = lambda: box['httpd'].shutdown()
    if on_ready:
        rc = on_ready(url)
        stop(); server.join(30)
        return rc
    webbrowser.open(url)
    if window and _window(url, stop):
        server.join(30)
        return 0
    print(f'{APP} is running at {url}  (Ctrl+C to stop)')
    try:
        while server.is_alive():
            time.sleep(0.5)
    except KeyboardInterrupt:
        stop(); server.join(30)
    return 0


def _window(url, stop):
    """A small always-there window, so a double-clicked program can be closed. -> False if no GUI is possible."""
    try:
        import tkinter as tk
        root = tk.Tk()
    except Exception:
        return False
    root.title(APP)
    root.resizable(False, False)
    tk.Label(root, text=f'{APP} is running on this computer.', padx=18, pady=10).pack()
    tk.Label(root, text='Closing this window stops it (and syncing).', fg='#666', padx=18).pack()
    row = tk.Frame(root, pady=12)
    row.pack()
    tk.Button(row, text='Open', width=12, command=lambda: webbrowser.open(url)).pack(side='left', padx=6)

    def quit_():
        root.title(f'{APP}: stopping…')
        root.update()
        stop()
        root.destroy()
    tk.Button(row, text='Quit', width=12, command=quit_).pack(side='left', padx=6)
    root.protocol('WM_DELETE_WINDOW', quit_)
    root.mainloop()
    return True


def self_test():
    """Start from a temporary folder, check the page, the API and a whole plant setup work, stop. -> exit code"""
    home = tempfile.mkdtemp(prefix='kks-selftest-')
    os.environ['KKS_HOME'] = home
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
    with open(os.path.join(home, 'config.json'), 'w') as f:
        json.dump({'port': port, 'sync_port': 0, 'discovery': False, 'update_check': False}, f)

    def check(url):
        def get(p, body=None):
            req = urllib.request.Request(url.rstrip('/') + p, data=None if body is None else json.dumps(body).encode(),
                                         headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.read()
        assert b'KKS' in get('/'), 'index.html missing'
        assert json.loads(get('/api/config'))['mode'] == 'peer'
        get('/api/node/new-plant', {'plant': 'Self test', 'username': 'tester', 'full_name': 'Self Test'})
        assert json.loads(get('/api/me'))['user']['role'] == 'manager'
        assert json.loads(get('/data/kks.json'))['systems'], 'KKS tables missing'
        # no plant data ships with the program (M5b): a new plant has none until its manager publishes some
        assert not os.path.exists(os.path.join(program_dir(), 'data', 'sheets.json')), 'plant data bundled with the program'
        assert json.loads(get('/api/sync/status'))['plant_data']['version'] is None
        # photos: stored as JPEG XL (libjxl bundled), served as they are
        get('/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'dataUrl': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAFElEQVR4nGM8UaHBgA0wYRUdtBIAHicBeAYWg8oAAAAASUVORK5CYII='}})
        photo = json.loads(get('/api/state'))['photos'][0]
        assert photo['file'].endswith('.jxl'), f'photo kept as {photo["file"]}, not JPEG XL'
        assert get('/photos/' + photo['file']).startswith(b'\xff\x0a'), 'photo not served as JPEG XL'
        # Learning (M4): the courses are there, progress is written as a private entry and read back
        assert b'course-bridge.js' in get('/data/courses/3-hrsg-course.html'), 'courses missing'
        get('/api/progress', {'course': 'hrsg', 'data': {'solved': '{"x":true}'}})
        assert json.loads(get('/api/progress?course=hrsg'))['data']['solved'] == '{"x":true}', 'progress not kept'
        print(f'self-test OK ({home})')
        return 0
    try:
        return run(home, window=False, on_ready=check, log=False)
    finally:
        import shutil
        if sys.stdout not in (sys.__stdout__, None):
            sys.stdout.close()
        shutil.rmtree(home, ignore_errors=True)


if __name__ == '__main__':
    if '--self-test' in sys.argv:
        sys.exit(self_test())
    sys.exit(run(user_dir(), window='--no-window' not in sys.argv))
