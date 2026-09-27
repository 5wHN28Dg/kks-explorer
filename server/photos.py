"""Photos are kept as JPEG XL at Butteraugli distance 1.9, effort 9 (decided by the user 2026-09-27).
Measured 2026-09-27 on 8 photos at 1600 px (SSIMULACRA2, higher = better): the JPEG q85 the pages made before:
1212 KB, 79.0; JXL d1.0: 1187 KB, 86.6; JXL d1.9: 680 KB, 78.9 → same quality as before at ~56% of the size.
Effort 9 vs 7 (another 8 photos): 805 vs 877 KB, 4.0 vs 0.43 s per photo on a 16-thread desktop. Same settings in
android/app/.../Jxl.kt. Nothing is converted back to JPEG: pages without JXL support decode it themselves (common.js,
libjxl compiled to WebAssembly; the Android app decodes natively).

Needs Pillow + pillow-jxl-plugin (libjxl). Without them photos are stored as uploaded; `app.py check` warns."""
import io

try:
    from PIL import Image, ImageOps
    import pillow_jxl  # noqa: F401  (registers the JXL format with Pillow)
    AVAILABLE = True
except ImportError:
    AVAILABLE = False

QUALITY = 80               # pillow-jxl-plugin maps quality q to distance 0.1 + (100 - q) * 0.09: 80 → 1.9
EFFORT = 9
MAX_SIDE = 4096            # clients send ≤ 1600 px; anything bigger is scaled down here


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
    im.save(out, format='JXL', quality=QUALITY, effort=EFFORT, exif=b'', lossless_jpeg=False)
    return out.getvalue(), 'jxl'
