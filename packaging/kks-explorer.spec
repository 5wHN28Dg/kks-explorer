# PyInstaller spec for the desktop app (docs/ARCHITECTURE.md M2c). Build from the repository folder:
#   pyinstaller --noconfirm packaging/kks-explorer.spec        → dist/KKS Explorer/
# One folder, not one file: a one-file build unpacks itself on every start (slow) and trips antivirus more often.
# Not included: the P&ID importer (pymupdf, opencv: ~300 MB; adding sheets stays an admin job on a server).
import os, sys

ROOT = os.path.abspath(os.path.join(SPECPATH, '..'))
shell = ['VERSION', 'index.html', 'admin.html', 'common.js', 'tiles.js', 'kks-wasm.js', 'kks-wasm-worker.js', 'course-bridge.js',
         'learning.html', 'course.html', 'course.js', 'course-figure.js', 'course.css', 'sw.js', 'manifest.webmanifest', 'icon.svg', 'icon-192.png', 'icon-512.png']
datas = [(os.path.join(ROOT, f), '.') for f in shell] + [(os.path.join(ROOT, 'data'), 'data'), (os.path.join(ROOT, 'vendor'), 'vendor')]

a = Analysis(
    [os.path.join(ROOT, 'desktop.py')],
    pathex=[ROOT],
    datas=datas,
    hiddenimports=['app', 'server.engine', 'server.migrate_v1', 'server.syncsvc', 'server.node', 'server.invites',
                   'server.photos', 'server.progress', 'zeroconf', 'pillow_jxl', 'PIL.JpegImagePlugin', 'PIL.PngImagePlugin', 'PIL.WebPImagePlugin'],
    excludes=['fitz', 'pymupdf', 'cv2', 'numpy', 'extractor', 'tests', 'pytest', 'PIL.ImageQt', 'PIL.ImageTk'],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name='KKS Explorer',
    console=False,                      # a window program on Windows; the Tk window replaces the console
    icon=os.path.join(ROOT, 'icon-512.png'),
    upx=False,                          # UPX-packed programs are flagged by antivirus more often
)
coll = COLLECT(exe, a.binaries, a.datas, name='KKS Explorer', upx=False)
