"""NAT-7: installed sizes, in MB (MiB) of file bytes.
  python3 tools/budgets/sizes.py windows Walkdown.exe OUT.json   the MSIX's files, laid out as make-msix.sh does
  python3 tools/budgets/sizes.py flatpak BUILD_DIR OUT.json      the Flatpak's /app (flatpak-builder's BUILD_DIR/files)
  python3 tools/budgets/sizes.py android APP.apk OUT.json        the release APK (its libraries are stored
                                                                 uncompressed and used in place: decision 0046)
Windows: an MSIX installs its files unpacked (WindowsApps), so the installed size is the package layout:
packaging/windows/make-msix.sh copies the exe, data/courses/*.json and *.jxl, vendor/fonts/*.woff2, three logos from
icon-512.png and AppxManifest.xml. The same files are counted here (the logos made the same way, with Pillow)."""
import glob, os, shutil, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import budgetlib  # noqa: E402

REPO = budgetlib.REPO


def windows_layout(exe):
    from PIL import Image
    w = tempfile.mkdtemp(prefix='kks-msix-layout-')
    os.makedirs(os.path.join(w, 'Assets'))
    os.makedirs(os.path.join(w, 'data', 'courses'))
    os.makedirs(os.path.join(w, 'vendor', 'fonts'))
    shutil.copy(exe, w)
    for f in glob.glob(os.path.join(REPO, 'data', 'courses', '*.json')) + glob.glob(os.path.join(REPO, 'data', 'courses', '*.jxl')):
        shutil.copy(f, os.path.join(w, 'data', 'courses'))
    for f in glob.glob(os.path.join(REPO, 'vendor', 'fonts', '*.woff2')):
        shutil.copy(f, os.path.join(w, 'vendor', 'fonts'))
    src = Image.open(os.path.join(REPO, 'icon-512.png')).convert('RGBA')
    for name, px in (('Square44x44Logo', 44), ('Square150x150Logo', 150), ('StoreLogo', 50)):
        src.resize((px, px), Image.LANCZOS).save(os.path.join(w, 'Assets', name + '.png'))
    shutil.copy(os.path.join(REPO, 'packaging', 'windows', 'AppxManifest.xml.in'), os.path.join(w, 'AppxManifest.xml'))
    return w


def main():
    kind, path, out = sys.argv[1:4]
    if kind == 'windows':
        d = windows_layout(path)
        n = budgetlib.tree_bytes(d)
        print('exe', round(os.path.getsize(path) / budgetlib.MB, 2), 'MB; layout', round(n / budgetlib.MB, 2), 'MB')
        shutil.rmtree(d)
    elif kind == 'flatpak':
        n = budgetlib.tree_bytes(os.path.join(path, 'files'))
        big = sorted(((os.path.getsize(os.path.join(d, f)), os.path.relpath(os.path.join(d, f), path))
                      for d, _, fs in os.walk(os.path.join(path, 'files')) for f in fs
                      if not os.path.islink(os.path.join(d, f))), reverse=True)[:8]
        for size, f in big:
            print(f'{size / budgetlib.MB:8.2f} MB  {f}')
    elif kind == 'android':
        n = os.path.getsize(path)
    else:
        sys.exit(__doc__)
    platform = {'windows': 'windows', 'flatpak': 'linux', 'android': 'android'}[kind]
    budgetlib.write(out, {f'native.{platform}.installedSizeMB': ([round(n / budgetlib.MB, 2)], 'MB')})


main()
