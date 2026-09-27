"""Build the Learning courses (M4, docs/ARCHITECTURE.md §8) from source/courses/*.html into data/courses/.

Each course is copied unchanged except for two lines:
- the Google Fonts links become one link to the vendored fonts (vendor/fonts/courses.css), so courses work offline
  and never contact Google;
- `<script src="/course-bridge.js" data-course="ppt">` goes before the course's own script: it keeps the course's
  localStorage progress in step with this device's private log entries (see course-bridge.js).
File names stay the same: the courses link to each other by name. Also writes data/courses/courses.json
(id = the course's localStorage prefix, title, file, question ids, SHA-256 of the source).

    python3 tools/build_courses.py [--fonts]     # --fonts: download the fonts again (vendor/fonts)
"""
import hashlib, json, os, re, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC, OUT, FONTS = (os.path.join(ROOT, p) for p in ('source/courses', 'data/courses', 'vendor/fonts'))
GOOGLE = ('https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:ital,wght@0,400;0,700;1,400'
          '&family=Barlow+Semi+Condensed:wght@500;600;700&family=JetBrains+Mono:wght@400;600&display=swap')
OFL = (('AtkinsonHyperlegible', 'atkinsonhyperlegible'), ('BarlowSemiCondensed', 'barlowsemicondensed'),
       ('JetBrainsMono', 'jetbrainsmono'))


def fonts():
    """Latin + Latin Extended woff2 files of the three families, a CSS file pointing at them, the licenses."""
    ua = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36'
    css = urllib.request.urlopen(urllib.request.Request(GOOGLE, headers={'User-Agent': ua})).read().decode()
    os.makedirs(FONTS, exist_ok=True)
    out = ['/* The fonts of the courses (M4), vendored from Google Fonts so courses work offline and never contact Google.',
           '   Latin + Latin Extended only. SIL Open Font License 1.1: see OFL-*.txt. Made by tools/build_courses.py --fonts. */']
    for subset, block in re.findall(r'/\* ([a-z-]+) \*/\s*(@font-face \{.*?\})', css, re.S):
        if subset not in ('latin', 'latin-ext'):
            continue
        fam = re.search(r"font-family: '([^']+)'", block)[1]
        w = re.search(r'font-weight: (\d+)', block)[1]
        italic = re.search(r'font-style: (\w+)', block)[1] == 'italic'
        url = re.search(r'url\((https://[^)]+\.woff2)\)', block)[1]
        name = f"{fam.replace(' ', '')}-{w}{'i' if italic else ''}-{subset}.woff2"
        with open(os.path.join(FONTS, name), 'wb') as f:
            f.write(urllib.request.urlopen(url).read())
        out.append(block.replace(url, name))
    with open(os.path.join(FONTS, 'courses.css'), 'w') as f:
        f.write('\n'.join(out) + '\n')
    for fam, d in OFL:
        with open(os.path.join(FONTS, f'OFL-{fam}.txt'), 'wb') as f:
            f.write(urllib.request.urlopen(f'https://raw.githubusercontent.com/google/fonts/main/ofl/{d}/OFL.txt').read())
    sums = []
    for name in sorted(os.listdir(FONTS)):
        if name.endswith(('.woff2', '.css')):
            with open(os.path.join(FONTS, name), 'rb') as f:
                sums.append(f'{hashlib.sha256(f.read()).hexdigest()}  {name}')
    with open(os.path.join(FONTS, 'SHA256SUMS'), 'w') as f:
        f.write('\n'.join(sums) + '\n')


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
    if '--fonts' in sys.argv or not os.path.exists(os.path.join(FONTS, 'courses.css')):
        fonts()
    build()
