#!/usr/bin/env python3
"""The web client's download size, tracked against a committed baseline (web-size.json).

  python3 tools/web_size.py            compare with web-size.json; exit 1 if any size differs (prints the table)
  python3 tools/web_size.py --update   write the current sizes to web-size.json (commit it; explain growth in the PR)

The Walkdown server sends these files as they are (no compression), so their bytes are what a browser downloads from
it. A proxy in front (a tunnel, a CDN) may compress text files on the way; the sizes here are the uncompressed ones.
- shell: the service worker's SHELL_FILES (read from sw.js, so this list can't drift from it) and sw.js itself:
  every browser that opens the app fetches them.
- on demand: the rest of vendor/kks (the photo encoder, the non-SIMD fallbacks) and the course fonts, fetched only
  when a page needs them.
- courses: the course content (data/courses: the JSON and its pictures) and data/kks.json, fetched by a course page.
Any change, smaller or larger, needs the baseline updated, so the file always records what ships."""
import argparse, json, os, re, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BASELINE = 'web-size.json'


def shell_files(repo):
    src = open(os.path.join(repo, 'sw.js'), encoding='utf-8').read()
    m = re.search(r'SHELL_FILES\s*=\s*\[([^\]]*)\]', src)
    if not m:
        raise SystemExit('sw.js: no SHELL_FILES list found')
    body = m.group(1)
    entries = re.findall(r"'([^'\n]+)'", body)
    # only plain single-quoted entries: anything else (a comment, other quotes, an expression) would be counted
    # wrongly or not at all, so it stops the check instead
    if re.sub(r"'[^'\n]+'|[\s,]", '', body):
        raise SystemExit('sw.js: SHELL_FILES must be a plain list of single-quoted paths for tools/web_size.py')
    files = {'sw.js'}
    for p in entries:
        files.add('index.html' if p == '/' else p.lstrip('/'))
    return sorted(files)


def on_demand_files(repo, shell):
    out = []
    for d, keep in (('vendor/kks', lambda n: n.endswith(('.js', '.wasm'))), ('vendor/fonts', lambda n: n.endswith('.woff2'))):
        for n in sorted(os.listdir(os.path.join(repo, d))):
            p = f'{d}/{n}'
            if keep(n) and os.path.isfile(os.path.join(repo, p)) and p not in shell:
                out.append(p)
    return out


def course_files(repo):
    d = os.path.join(repo, 'data', 'courses')
    return ['data/kks.json'] + [f'data/courses/{n}' for n in sorted(os.listdir(d)) if n.endswith(('.json', '.jxl'))]


def measure(repo):
    shell = shell_files(repo)
    groups = {'shell': shell, 'on demand': on_demand_files(repo, set(shell)), 'courses': course_files(repo)}
    result = {}
    for g, files in groups.items():
        sizes = {}
        for p in files:
            f = os.path.join(repo, p)
            if not os.path.isfile(f):
                raise SystemExit(f'{p}: listed but missing')
            sizes[p] = os.path.getsize(f)
        result[g] = {'total': sum(sizes.values()), 'files': sizes}
    return result


def diff(old, new):
    """[(group, file or '(total)', old bytes or None, new bytes or None)] for everything that changed"""
    rows = []
    for g in sorted(set(old) | set(new)):
        o, n = old.get(g, {'total': 0, 'files': {}}), new.get(g, {'total': 0, 'files': {}})
        for p in sorted(set(o['files']) | set(n['files'])):
            a, b = o['files'].get(p), n['files'].get(p)
            if a != b:
                rows.append((g, p, a, b))
        if o['total'] != n['total']:
            rows.append((g, '(total)', o['total'], n['total']))
    return rows


def fmt(rows):
    lines = [f'{"group":10} {"file":42} {"baseline":>10} {"now":>10} {"change":>9}']
    for g, p, a, b in rows:
        ch = (b or 0) - (a or 0)
        lines.append(f'{g:10} {p:42} {"-" if a is None else a:>10} {"-" if b is None else b:>10} {ch:>+9}')
    return '\n'.join(lines)


def summary(m):
    return ', '.join(f'{g} {m[g]["total"]:,} bytes' for g in ('shell', 'on demand', 'courses'))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--update', action='store_true', help='write the current sizes to web-size.json')
    ap.add_argument('--repo', default=REPO, help=argparse.SUPPRESS)
    a = ap.parse_args(argv)
    now = measure(a.repo)
    path = os.path.join(a.repo, BASELINE)
    if a.update:
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(now, f, indent=1, sort_keys=True)
            f.write('\n')
        print(f'{BASELINE}: ' + summary(now))
        return 0
    old = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
    rows = diff(old, now)
    print(summary(now))
    if rows:
        print(fmt(rows))
        print(f'\nThe web client\'s size changed. Run `python3 tools/web_size.py --update`, commit {BASELINE}, and say in '
              'the PR why any growth is worth it.')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
