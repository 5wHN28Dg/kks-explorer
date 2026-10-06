"""Build the Learning courses (M4, https://github.com/5wHN28Dg/kks-explorer/wiki/Architecture-v1 §8) from source/courses/*.html into data/courses/.

Each course is copied unchanged except for two lines:
- the Google Fonts links become one link to the vendored fonts (vendor/fonts/courses.css), so courses work offline
  and never contact Google;
- `<script src="/course-bridge.js" data-course="ppt">` goes before the course's own script: it keeps the course's
  localStorage progress in step with this device's private log entries (see course-bridge.js).
File names stay the same: the courses link to each other by name. Also writes data/courses/courses.json
(id = the course's localStorage prefix, title, file, question ids, SHA-256 of the source).

    python3 tools/build_courses.py [--fonts]     # --fonts: download the fonts again (vendor/fonts)
    python3 tools/build_courses.py --ttf         # the same faces as TTF for the Android app (vendor/fonts/ttf)
"""
import hashlib, json, os, re, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC, OUT, FONTS = (os.path.join(ROOT, p) for p in ('source/courses', 'data/courses', 'vendor/fonts'))

# The fonts are pinned (DEP-8; listed in pinned-sources.cdx.json): each file is fetched from the exact URL below and
# checked against its SHA-256, and the script stops on a mismatch before writing anything. Recorded on 2026-10-06:
# the downloads were byte-identical to the files committed in vendor/fonts. The URLs are the ones Google's CSS gave
# (https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:ital,wght@0,400;0,700;1,400
# &family=Barlow+Semi+Condensed:wght@500;600;700&family=JetBrains+Mono:wght@400;600&display=swap: woff2 for a
# browser's user agent, TTF for a plain HTTP client). To move to newer fonts, read that CSS and change the pins.
GSTATIC = 'https://fonts.gstatic.com/s/'
# The @font-face unicode ranges of the two subsets, as Google's CSS gave them when the fonts were vendored (since
# then its latin-ext range ends at U+20C4, for the same files); courses.css is written from these.
RANGES = {
    'latin': 'U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, '
             'U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD',
    'latin-ext': 'U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, '
                 'U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF',
}
WOFF2 = (  # family, style, weight, subset, URL under GSTATIC, SHA-256 (in the order of courses.css)
    ('Atkinson Hyperlegible', 'italic', 400, 'latin-ext', 'atkinsonhyperlegible/v12/9Bt43C1KxNDXMspQ1lPyU89-1h6ONRlW45G056IkUwCybQ.woff2', '90d887d541fe6e912d15f826aae6ca1190efcf172b65401704472475ed771049'),
    ('Atkinson Hyperlegible', 'italic', 400, 'latin', 'atkinsonhyperlegible/v12/9Bt43C1KxNDXMspQ1lPyU89-1h6ONRlW45G056IqUwA.woff2', 'bc8825fd435d4aa8e31449937826d583a7daaae15a83832c91b38375131ebf08'),
    ('Atkinson Hyperlegible', 'normal', 400, 'latin-ext', 'atkinsonhyperlegible/v12/9Bt23C1KxNDXMspQ1lPyU89-1h6ONRlW45G07JIoSwQ.woff2', '61eeb0eb8b881a84d069e67be1723f5b353b0b9b866ad8e7ad9dba66cdc4dabd'),
    ('Atkinson Hyperlegible', 'normal', 400, 'latin', 'atkinsonhyperlegible/v12/9Bt23C1KxNDXMspQ1lPyU89-1h6ONRlW45G04pIo.woff2', 'd64ba838ef5472bba248620ec4fd8b5aa7cf0db2908e0bb230600caf279ba7bc'),
    ('Atkinson Hyperlegible', 'normal', 700, 'latin-ext', 'atkinsonhyperlegible/v12/9Bt73C1KxNDXMspQ1lPyU89-1h6ONRlW45G8Wbc9eiWPVFw.woff2', '840ced16f975d8abc2594b436d0206649e0c2a7327e36750ff849d3d37c3c02e'),
    ('Atkinson Hyperlegible', 'normal', 700, 'latin', 'atkinsonhyperlegible/v12/9Bt73C1KxNDXMspQ1lPyU89-1h6ONRlW45G8Wbc9dCWP.woff2', '140e2bd25a7315c8a062508391426b0d8c3297400c947b8d847be28f73a199f0'),
    ('Barlow Semi Condensed', 'normal', 500, 'latin-ext', 'barlowsemicondensed/v16/wlpigxjLBV1hqnzfr-F8sEYMB0Yybp0mudRfi6m_CWslu50.woff2', '5e07c7d621bb57be13250d12c8c7ba71b84c6f71ad2080bc2ee9d3dd533b3579'),
    ('Barlow Semi Condensed', 'normal', 500, 'latin', 'barlowsemicondensed/v16/wlpigxjLBV1hqnzfr-F8sEYMB0Yybp0mudRfi6m_B2sl.woff2', '0d7513795eaf8fdab7f340144841bd2d9fac7d9303c03aa6b525a2c908e9b371'),
    ('Barlow Semi Condensed', 'normal', 600, 'latin-ext', 'barlowsemicondensed/v16/wlpigxjLBV1hqnzfr-F8sEYMB0Yybp0mudRfp66_CWslu50.woff2', '5a58c6c9887c7306399176e96bdeb0c2c3b2935a43f89e25ac4e342b03631843'),
    ('Barlow Semi Condensed', 'normal', 600, 'latin', 'barlowsemicondensed/v16/wlpigxjLBV1hqnzfr-F8sEYMB0Yybp0mudRfp66_B2sl.woff2', 'f158417e9207b5362f9b71a2fe779ce5bb836ad972f38445c3163af39d2c998d'),
    ('Barlow Semi Condensed', 'normal', 700, 'latin-ext', 'barlowsemicondensed/v16/wlpigxjLBV1hqnzfr-F8sEYMB0Yybp0mudRfw6-_CWslu50.woff2', '109b73c772cc798422a6879f32c96ad646cb65f5c211933cb05f60c4fc2ab540'),
    ('Barlow Semi Condensed', 'normal', 700, 'latin', 'barlowsemicondensed/v16/wlpigxjLBV1hqnzfr-F8sEYMB0Yybp0mudRfw6-_B2sl.woff2', 'fb958c8c20a05552ac8a85d925d96028d52565792650e941a5fe96b6997aa5cb'),
    # JetBrains Mono is a variable font: Google serves the same file for 400 and 600
    ('JetBrains Mono', 'normal', 400, 'latin-ext', 'jetbrainsmono/v24/tDbv2o-flEEny0FZhsfKu5WU4zr3E_BX0PnT8RD8yKwBNntkaToggR7BYRbKPx7cwhsk.woff2', 'db5ff4db83e580426280e9337a58dc57d3a83784a1b03ad80914651594441d52'),
    ('JetBrains Mono', 'normal', 400, 'latin', 'jetbrainsmono/v24/tDbv2o-flEEny0FZhsfKu5WU4zr3E_BX0PnT8RD8yKwBNntkaToggR7BYRbKPxDcwg.woff2', '83c005d49d8a6a50474c73a5a36ac0468076e9c4a29da7bdb14995d80560a5be'),
    ('JetBrains Mono', 'normal', 600, 'latin-ext', 'jetbrainsmono/v24/tDbv2o-flEEny0FZhsfKu5WU4zr3E_BX0PnT8RD8yKwBNntkaToggR7BYRbKPx7cwhsk.woff2', 'db5ff4db83e580426280e9337a58dc57d3a83784a1b03ad80914651594441d52'),
    ('JetBrains Mono', 'normal', 600, 'latin', 'jetbrainsmono/v24/tDbv2o-flEEny0FZhsfKu5WU4zr3E_BX0PnT8RD8yKwBNntkaToggR7BYRbKPxDcwg.woff2', '83c005d49d8a6a50474c73a5a36ac0468076e9c4a29da7bdb14995d80560a5be'),
)
TTF = (  # file in vendor/fonts/ttf, URL under GSTATIC, SHA-256
    ('AtkinsonHyperlegible-400.ttf', 'atkinsonhyperlegible/v12/9Bt23C1KxNDXMspQ1lPyU89-1h6ONRlW45GE5Q.ttf', 'daa4fc7275d21266748afad0563d8f57e075933686ca6995f06ed8619e99e9e4'),
    ('AtkinsonHyperlegible-700.ttf', 'atkinsonhyperlegible/v12/9Bt73C1KxNDXMspQ1lPyU89-1h6ONRlW45G8WbcNcw.ttf', 'b5d9490cf95d925a28ab7b1560e76385134c9bca6cd2d83eee1e51d8c7b1295f'),
    ('BarlowSemiCondensed-500.ttf', 'barlowsemicondensed/v16/wlpigxjLBV1hqnzfr-F8sEYMB0Yybp0mudRfi6mPAA.ttf', 'c2b046235fb4c2f81ca58bbdca2313e9681758295b129931853324ade56180c9'),
    ('BarlowSemiCondensed-600.ttf', 'barlowsemicondensed/v16/wlpigxjLBV1hqnzfr-F8sEYMB0Yybp0mudRfp66PAA.ttf', 'cb75439ae401f77624d5b268ea25fd7556e34803fccbd2f92e937a4f3856a1da'),
    ('BarlowSemiCondensed-700.ttf', 'barlowsemicondensed/v16/wlpigxjLBV1hqnzfr-F8sEYMB0Yybp0mudRfw6-PAA.ttf', '6098b66ce7d608dcea8c6a2eeacfdeeee5416e0e0c12a2318595d3dd8c5babef'),
    ('JetBrainsMono-400.ttf', 'jetbrainsmono/v24/tDbY2o-flEEny0FZhsfKu5WU4zr3E_BX0PnT8RD8yKxjPQ.ttf', '44ce4a84f20d60f24539bd0cef11f79c29e38609e0f8adf18551c9794a5d9dc3'),
    ('JetBrainsMono-600.ttf', 'jetbrainsmono/v24/tDbY2o-flEEny0FZhsfKu5WU4zr3E_BX0PnT8RD8FqtjPQ.ttf', 'df54dbfafba61d4911eb3dab9bba2d20531fb009f01d64dd42fa96ab862584d8'),
)
OFL_COMMIT = '7085eb89a950e85db5b166b7a58d414544b4140c'   # of github.com/google/fonts
OFL = (('AtkinsonHyperlegible', 'atkinsonhyperlegible', 'f32d22b3908fcad2c86a74000614ec22e6a7f66ea7e867e616026a27aebdc143'),
       ('BarlowSemiCondensed', 'barlowsemicondensed', '186d750eb496a4c17a76385f82be6aea2ac1cf2de074a811d63786cf374ea73f'),
       ('JetBrainsMono', 'jetbrainsmono', 'b2fe5e8987594e9ffd1d2ca52a2f5d73eb8335243893c5d6254b5ad69269591d'))


_downloads = {}   # URL -> bytes: JetBrains Mono's two weights are one file


def fetch(url, sha256):
    """The bytes at url, or exit if their SHA-256 is not the pinned one."""
    if url not in _downloads:
        _downloads[url] = urllib.request.urlopen(url).read()
    got = hashlib.sha256(_downloads[url]).hexdigest()
    if got != sha256:
        raise SystemExit(f'{url}: SHA-256 {got}, expected {sha256} (pinned in tools/build_courses.py)')
    return _downloads[url]


def write_all(d, files):
    os.makedirs(d, exist_ok=True)
    for name, data in files.items():
        with open(os.path.join(d, name), 'wb') as f:
            f.write(data)


def fonts():
    """Latin + Latin Extended woff2 files of the three families, a CSS file pointing at them, the licenses."""
    out = ['/* The fonts of the courses (M4), vendored from Google Fonts so courses work offline and never contact Google.',
           '   Latin + Latin Extended only. SIL Open Font License 1.1: see OFL-*.txt. Made by tools/build_courses.py --fonts. */']
    files = {}
    for fam, style, weight, subset, url, sha in WOFF2:
        name = f"{fam.replace(' ', '')}-{weight}{'i' if style == 'italic' else ''}-{subset}.woff2"
        files[name] = fetch(GSTATIC + url, sha)
        out.append(f"@font-face {{\n  font-family: '{fam}';\n  font-style: {style};\n  font-weight: {weight};\n"
                   f"  font-display: swap;\n  src: url({name}) format('woff2');\n  unicode-range: {RANGES[subset]};\n}}")
    files['courses.css'] = ('\n'.join(out) + '\n').encode()
    for fam, d, sha in OFL:
        files[f'OFL-{fam}.txt'] = fetch(f'https://raw.githubusercontent.com/google/fonts/{OFL_COMMIT}/ofl/{d}/OFL.txt', sha)
    write_all(FONTS, files)
    # the order of `sha256sum *.woff2 *.css` in a UTF-8 locale (punctuation ignored), as in the committed file
    names = sorted((n for n in files if n.endswith('.woff2')), key=lambda n: re.sub(r'[^a-z0-9]', '', n.lower()))
    sums = [f'{hashlib.sha256(files[n]).hexdigest()}  {n}' for n in names + ['courses.css']]
    with open(os.path.join(FONTS, 'SHA256SUMS'), 'w') as f:
        f.write('\n'.join(sums) + '\n')


def ttf():
    """The same faces as TrueType for the Android app (its Typeface reads TTF/OTF, not WOFF2; decision 0036): the
    weights the course figures use, from Google Fonts like the WOFF2 files (it serves TTF to a plain HTTP client).
    Into vendor/fonts/ttf/ with their SHA-256."""
    files = {name: fetch(GSTATIC + url, sha) for name, url, sha in TTF}
    write_all(os.path.join(FONTS, 'ttf'), files)
    sums = [f'{hashlib.sha256(data).hexdigest()}  {name}' for name, data in files.items()]
    with open(os.path.join(FONTS, 'ttf', 'SHA256SUMS'), 'w') as f:
        f.write('\n'.join(sorted(sums, key=lambda x: x.split()[1])) + '\n')


def build():
    os.makedirs(OUT, exist_ok=True)
    courses = []
    for name in sorted(os.listdir(SRC)):
        if not name.endswith('.html'):
            continue
        with open(os.path.join(SRC, name), encoding='utf-8') as f:
            html = f.read()
        prefix = re.search(r"localStorage\.getItem\('([a-z]+)\.'", html)[1]
        title = re.search(r'<title>(.*?)</title>', html, re.S)[1].strip()
        questions = sorted(set(re.findall(r"[^A-Za-z0-9_$.]([QOS])\('([^']+)'", html)), key=lambda q: q[1])
        links = re.findall(r'<link rel="(?:preconnect|stylesheet)" href="https://fonts\.(?:googleapis|gstatic)\.com[^>]*>\n?', html)
        if len(links) != 3:
            raise SystemExit(f'{name}: expected the 3 Google Fonts links, found {len(links)}')
        html = html.replace(links[0], '<link rel="stylesheet" href="/vendor/fonts/courses.css">\n', 1)
        for link in links[1:]:
            html = html.replace(link, '', 1)
        i = html.index('<script>')
        html = html[:i] + f'<script src="/course-bridge.js" data-course="{prefix}"></script>\n' + html[i:]
        if 'googleapis' in html or 'gstatic' in html:
            raise SystemExit(f'{name}: still refers to Google Fonts')
        with open(os.path.join(OUT, name), 'w', encoding='utf-8') as f:
            f.write(html)
        with open(os.path.join(SRC, name), 'rb') as f:
            sha = hashlib.sha256(f.read()).hexdigest()
        courses.append({'id': prefix, 'title': title, 'file': name, 'questions': [q for _, q in questions], 'source_sha256': sha})
        print(f'{name}: {prefix}, "{title}", {len(questions)} questions')
    with open(os.path.join(OUT, 'courses.json'), 'w') as f:
        json.dump(courses, f, indent=1)


if __name__ == '__main__':
    if '--ttf' in sys.argv:
        ttf()
        raise SystemExit(0)
    if '--fonts' in sys.argv or not os.path.exists(os.path.join(FONTS, 'courses.css')):
        fonts()
    build()
