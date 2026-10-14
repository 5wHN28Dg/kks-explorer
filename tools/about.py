#!/usr/bin/env python3
"""The About content every Walkdown program shows, in one file: data/about.json (format below).

  python3 tools/about.py           write data/about.json
  python3 tools/about.py --check   exit 1 if data/about.json is not what this would write (tests/test_about.py does it)

Made from:
- the Flatpak metainfo (apps/gnome/flatpak/io.github._5wHN28Dg.walkdown.metainfo.xml): name, one-line summary,
  developer, licence, home page;
- tools/about/components.json: the third-party parts each program ships or uses, their licences, and which program
  has them (the versions of pinned sources come from pinned-sources.cdx.json);
- tools/about/licenses/*.txt (the standard licence texts) and tools/about/notices/*.txt (a part's own licence file,
  with its copyright lines, as its source ships it);
- the course photos' credits (data/courses/*.json).
The version is not in it: each program knows its own (VERSION at build time) and the commit it was built from.

data/about.json (format "walkdown-about", version 1): an object with
  name, summary, developer: strings
  license: {id (SPDX), name, url}            Walkdown's own licence
  notice: string                             the free-software and no-warranty notice
  links: {homepage, issues, help}            URLs
  source: {repository, commit_url}           commit_url has "{commit}" where a build's commit goes
  platforms: {server|web|gnome|windows|android: {title, note}}
  components: [{id, name, version (string or null), license (SPDX expression), license_name (it in words),
                license_ids: [the SPDX ids of `licenses` it is used under],
                url, use, platforms: {<platform>: "bundled" | "system"}, notice (string or null)}]
      "bundled": the program carries it (built in, or in its package); "system": it uses the copy the operating
      system or the Flatpak runtime provides (then `version` does not apply). notice: the part's own licence file
      (copyright lines and terms) where its licence asks for them to go with the program.
  licenses: {<SPDX id>: {name, url, text}}   every licence a component is used under; text: its full text, or null
                                             where each component's notice carries its terms (BSD, MIT, ...)
  photos: [{file, text, links: [{text, url}]}]   the course pictures' credits (text: the credit as the course
                                             writes it; links: the links in it, in order)
"""
import argparse, json, os, re, sys
import xml.etree.ElementTree as ET

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT = os.path.join('data', 'about.json')
METAINFO = os.path.join('apps', 'gnome', 'flatpak', 'io.github._5wHN28Dg.walkdown.metainfo.xml')
SRC = os.path.join('tools', 'about')
PLATFORMS = ('server', 'web', 'gnome', 'windows', 'android')
REPOSITORY = 'https://github.com/5wHN28Dg/kks-explorer'


def read(repo, *p):
    with open(os.path.join(repo, *p), encoding='utf-8') as f:
        return f.read()


def metainfo(repo):
    root = ET.fromstring(read(repo, METAINFO))
    homepage = root.find("url[@type='homepage']").text.strip()
    return {'name': root.findtext('name').strip(), 'summary': root.findtext('summary').strip(),
            'developer': root.findtext('developer/name').strip(), 'license': root.findtext('project_license').strip(),
            'homepage': homepage}


def pinned(repo):
    """{name: version} of pinned-sources.cdx.json, with a leading v dropped (v0.12.0 -> 0.12.0)"""
    doc = json.loads(read(repo, 'pinned-sources.cdx.json'))
    return {c['name']: re.sub(r'^v(?=\d)', '', c['version']) for c in doc['components']}


def runs_text(runs):
    out = []
    for r in runs:
        out.append(r if isinstance(r, str) else runs_text(r.get('link') or r.get('runs') or []))
    return ''.join(out)


def photos(repo):
    """every course picture's credit, once per file, in file name order: its text (the course's runs as plain text)
    and its links ([{text, url}], in order)"""
    found = {}

    def links(runs, out):
        for r in runs:
            if isinstance(r, dict):
                if r.get('to', {}).get('url'):
                    out.append({'text': runs_text(r['link']), 'url': r['to']['url']})
                links(r.get('link') or r.get('runs') or [], out)
        return out

    def walk(x, where):
        if isinstance(x, dict):
            im = x.get('image')
            if isinstance(im, dict):
                p = {'file': im['file'], 'text': runs_text(im['credit']).strip(), 'links': links(im['credit'], [])}
                if not p['text']:
                    raise SystemExit(f'{where}: {im["file"]} has no credit')
                if found.setdefault(im['file'], p) != p:
                    raise SystemExit(f'{where}: {im["file"]} is credited differently in two places')
            for v in x.values():
                walk(v, where)
        elif isinstance(x, list):
            for v in x:
                walk(v, where)

    d = os.path.join(repo, 'data', 'courses')
    for n in sorted(os.listdir(d)):
        if n.endswith('.json'):
            walk(json.loads(read(repo, 'data', 'courses', n)), n)
    return [found[k] for k in sorted(found)]


def license_name(expr, known):
    """an SPDX expression in words: 'Apache-2.0 OR BSD-3-Clause' -> 'Apache License 2.0 or BSD 3-Clause License'"""
    words = {'AND': 'and', 'OR': 'or', 'WITH': 'with'}
    return ' '.join(words.get(t) or (known[t]['name'] if t in known else t) for t in expr.split())


def build(repo=REPO):
    m = metainfo(repo)
    src = json.loads(read(repo, SRC, 'components.json'))
    versions = pinned(repo)
    licenses, comps = {}, []
    for lid in sorted({m['license']} | {i for c in src['components'] for i in c['license_ids']}):
        meta = src['licenses'].get(lid)
        if meta is None:
            raise SystemExit(f'{SRC}/components.json: licence {lid} has no entry under "licenses"')
        licenses[lid] = {'name': meta['name'], 'url': meta['url'],
                         'text': read(repo, SRC, 'licenses', lid + '.txt') if meta.get('text') else None}
    for c in src['components']:
        if set(c['platforms']) - set(PLATFORMS) or set(c['platforms'].values()) - {'bundled', 'system'}:
            raise SystemExit(f'{c["id"]}: platforms must be among {PLATFORMS}, each "bundled" or "system"')
        version = versions[c['pinned']] if 'pinned' in c else c.get('version')
        notice = read(repo, SRC, 'notices', c['notice'] + '.txt') if c.get('notice') else None
        if not c['license_ids'] or any(i not in re.findall(r'[\w.+-]+', c['license']) for i in c['license_ids']):
            raise SystemExit(f'{c["id"]}: every one of license_ids must be in its licence expression')
        comps.append({'id': c['id'], 'name': c['name'], 'version': version, 'license': c['license'],
                      'license_name': license_name(c['license'], src['licenses']), 'license_ids': c['license_ids'], 'url': c['url'], 'use': c['use'],
                      'platforms': {p: c['platforms'][p] for p in PLATFORMS if p in c['platforms']}, 'notice': notice})
    own = licenses[m['license']]
    return {'format': 'walkdown-about', 'version': 1,
            'name': m['name'], 'summary': m['summary'], 'developer': m['developer'],
            'license': {'id': m['license'], 'name': own['name'], 'url': own['url']},
            'notice': src['notice'],
            'links': {'homepage': m['homepage'], 'issues': REPOSITORY + '/issues', 'help': REPOSITORY + '/wiki'},
            'source': {'repository': REPOSITORY, 'commit_url': REPOSITORY + '/tree/{commit}'},
            'platforms': {p: src['platforms'][p] for p in PLATFORMS},
            'components': comps, 'licenses': licenses, 'photos': photos(repo)}


def text(doc):
    return json.dumps(doc, ensure_ascii=False, indent=1) + '\n'


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--file', default=os.path.join(REPO, OUT), help='the file to write or check (default: %(default)s)')
    a = ap.parse_args(argv)
    want = text(build())
    path = a.file
    if a.check:
        have = open(path, encoding='utf-8').read() if os.path.exists(path) else ''
        if have != want:
            print(f'{path} is not current: run python3 tools/about.py', file=sys.stderr)
            return 1
        return 0
    with open(path, 'w', encoding='utf-8') as f:
        f.write(want)
    print(f'wrote {path} ({len(want.encode())} bytes)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
