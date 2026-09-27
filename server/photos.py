"""Photos are kept as JPEG XL at Butteraugli distance 1.0 (libjxl's "visually lossless", pillow-jxl's quality 90).
Measured 2026-09-27 on 8 photos at 1600 px (SSIMULACRA2, higher = better): the JPEG q85 the pages made before:
1212 KB, 79.0; JPEG q92: 1838 KB, 84.8; JXL d1.0: 1187 KB, 86.6; JXL quality 80 (d≈1.9): 680 KB, 78.9. So d1.0 costs
what JPEG q85 did at clearly better quality; saving space at the old quality would mean quality 80. Same setting in
android/app/.../Jxl.kt. Browsers without JXL support get a JPEG made from it (cached).

Needs Pillow + pillow-jxl-plugin (libjxl). Without them photos are stored as uploaded and JXL photos that came from
other devices are sent as they are (only browsers with JXL support show them); `app.py check` warns."""
import io, os, threading

try:
    from PIL import Image, ImageOps
    import pillow_jxl  # noqa: F401  (registers the JXL format with Pillow)
    AVAILABLE = True
except ImportError:
    AVAILABLE = False

DISTANCE_QUALITY = 90      # pillow-jxl-plugin's quality 90 = libjxl distance 1.0 (visually lossless)
EFFORT = 7                 # libjxl's default
JPEG_QUALITY = 90          # the fallback for browsers without JXL
MAX_SIDE = 4096            # clients send ≤ 1600 px; anything bigger is scaled down here
_lock = threading.Lock()


def magic(raw):
    for sig, ext in ((b'\xff\xd8\xff', 'jpg'), (b'\x89PNG', 'png'), (b'RIFF', 'webp'), (b'\xff\x0a', 'jxl'),
                     (b'\x00\x00\x00\x0cJXL ', 'jxl')):
        if raw.startswith(sig):
            return ext
    return None


def to_jxl(raw, ext):
    """-> (bytes, ext): the photo as JXL (orientation applied, metadata dropped), or unchanged if it is JXL already
    or no encoder is installed. Raises ValueError for data that isn't a readable image."""
    if ext == 'jxl' or not AVAILABLE:
        return raw, ext
    try:
        im = Image.open(io.BytesIO(raw))
        im = ImageOps.exif_transpose(im)
        im = im.convert('RGB')
    except Exception as e:
        raise ValueError(f'not a readable image ({e})')
    if max(im.size) > MAX_SIDE:
        im.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, format='JXL', quality=DISTANCE_QUALITY, effort=EFFORT, exif=b'', lossless_jpeg=False)
    return out.getvalue(), 'jxl'


def jpeg_fallback(path, cache_dir):
    """A JPEG of the JXL photo at `path` (made once, kept in cache_dir). -> its path, or None if it can't be made."""
    if not AVAILABLE:
        return None
    name = os.path.splitext(os.path.basename(path))[0] + '.jpg'
    out = os.path.join(cache_dir, name)
    if os.path.isfile(out):
        return out
    with _lock:   # one conversion at a time: a page full of photos shouldn't start dozens at once
        if os.path.isfile(out):
            return out
        try:
            im = Image.open(path).convert('RGB')
        except Exception:
            return None
        os.makedirs(cache_dir, exist_ok=True)
        im.save(out + '.part', format='JPEG', quality=JPEG_QUALITY, optimize=True)
        os.replace(out + '.part', out)
    return out
