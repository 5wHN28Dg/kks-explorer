"""data/about.json, the About content every Walkdown program shows (tools/about.py; the user, 2026-10-15):
- it is what tools/about.py makes from its sources now (a change to the metainfo, the third-party list, a licence or a
  course credit without running the tool fails here);
- name, summary, developer, licence and home page are the Flatpak metainfo's; the links are the repository's;
- the version of every pinned third-party part is the one pinned-sources.cdx.json pins, and what ships of the pinned
  sources is listed for the programs that carry it; the Android parts cover every library group of the release build's
  lockfile, at the versions the lockfile has;
- every course picture has its credit; every licence a part names is there, with its full text where a part has no
  notice of its own; nothing in it names a plant or a person of the project;
- every build that packs data/ packs about.json too (Flatpak, MSIX, the server's install).
  .venv/bin/python -m unittest tests.test_about"""
import json, os, re, subprocess, sys, tempfile, unittest, urllib.parse
import xml.etree.ElementTree as ET

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, os.path.join(REPO, 'tools'))
import about  # noqa: E402

ABOUT = os.path.join(REPO, 'data', 'about.json')


def load():
    with open(ABOUT, encoding='utf-8') as f:
        return json.load(f)


class About(unittest.TestCase):
    def test_current(self):
        self.assertEqual(about.main(['--check']), 0, 'run python3 tools/about.py and commit data/about.json')

    def test_check_notices_a_stale_file(self):
        """the check itself, on a copy: the same file passes, a changed one or none is reported"""
        with tempfile.TemporaryDirectory() as tmp:
            f = os.path.join(tmp, 'about.json')
            self.assertEqual(about.main(['--file', f]), 0)
            self.assertEqual(about.main(['--check', '--file', f]), 0)
            with open(f, encoding='utf-8') as fh:
                good = fh.read()
            with open(f, 'w', encoding='utf-8') as fh:
                fh.write(good.replace('"Walkdown contributors"', '"Someone else"', 1))
            self.assertEqual(about.main(['--check', '--file', f]), 1)
            os.remove(f)
            self.assertEqual(about.main(['--check', '--file', f]), 1)

    def test_settled_content(self):
        d = load()
        root = ET.parse(os.path.join(REPO, about.METAINFO)).getroot()
        self.assertEqual((d['format'], d['version']), ('walkdown-about', 1))
        self.assertEqual(d['name'], 'Walkdown')
        self.assertEqual(d['summary'], root.findtext('summary'))
        self.assertEqual(d['developer'], 'Walkdown contributors')
        self.assertEqual(d['license']['id'], 'AGPL-3.0-or-later')
        with open(os.path.join(REPO, 'LICENSE'), encoding='utf-8') as f:
            self.assertEqual(d['licenses']['AGPL-3.0-or-later']['text'], f.read())
        self.assertEqual(d['links'], {'homepage': 'https://github.com/5wHN28Dg/kks-explorer',
                                      'issues': 'https://github.com/5wHN28Dg/kks-explorer/issues',
                                      'help': 'https://github.com/5wHN28Dg/kks-explorer/wiki'})
        self.assertEqual(d['source']['commit_url'].replace('{commit}', 'abc'), 'https://github.com/5wHN28Dg/kks-explorer/tree/abc')
        self.assertEqual(set(d['platforms']), {'server', 'web', 'gnome', 'windows', 'android'})
        self.assertNotIn('app_version', d)   # each program says its own version

    def test_pinned_versions(self):
        with open(os.path.join(REPO, 'pinned-sources.cdx.json'), encoding='utf-8') as f:
            pins = {c['name']: c['version'] for c in json.load(f)['components']}
        by = {c['id']: c for c in load()['components']}
        for cid, name in (('libjxl', 'libjxl'), ('highway', 'highway'), ('brotli', 'brotli'), ('skcms', 'skcms'),
                          ('zxing-cpp', 'zxing-cpp'), ('zlib', 'zlib'), ('nim', 'nim'), ('mupdf', 'mupdf'),
                          ('mingw-w64', 'llvm-mingw')):
            self.assertEqual(by[cid]['version'], pins[name].lstrip('v'), cid)
        # SQLite's amalgamation is pinned by its number: 3530400 = 3.53.4
        a, b, c = (int(x) for x in by['sqlite']['version'].split('.'))
        self.assertEqual(pins['sqlite-amalgamation'], '%d%02d%02d00' % (a, b, c))
        # what ships where (pinned-sources.cdx.json's descriptions say which programs use them)
        for cid in ('libjxl', 'highway', 'brotli', 'skcms', 'zxing-cpp', 'libzueci', 'llvm-runtime'):
            for p in ('web', 'windows', 'android'):
                self.assertEqual(by[cid]['platforms'].get(p), 'bundled', (cid, p))
        self.assertEqual(by['zxing-cpp']['platforms']['gnome'], 'bundled')   # the Flatpak builds it
        for p in ('server', 'gnome', 'windows', 'android'):
            self.assertEqual(by['nim']['platforms'][p], 'bundled', p)
        self.assertEqual(by['mupdf']['platforms'], {'server': 'bundled'})
        for p in ('windows', 'android'):
            self.assertEqual(by['sqlite']['platforms'][p], 'bundled')

    def test_android_libraries(self):
        """every library group of the release build is listed, at the lockfile's version"""
        with open(os.path.join(REPO, 'android', 'app2', 'gradle.lockfile'), encoding='utf-8') as f:
            deps = [line.split('=')[0] for line in f if 'releaseRuntimeClasspath' in line]
        self.assertGreater(len(deps), 20)
        with open(os.path.join(REPO, about.SRC, 'components.json'), encoding='utf-8') as f:
            src = [c for c in json.load(f)['components'] if 'maven' in c]
        for c in src:
            self.assertIn(c['maven'], deps, c['id'])
            if c['version']:
                self.assertEqual(c['maven'].rsplit(':', 1)[1], c['version'], c['id'])
            self.assertEqual(c['platforms'], {'android': 'bundled'})
        for dep in deps:
            group = dep.split(':')[0]
            self.assertTrue(any(group == g or (g.endswith('.') and group.startswith(g)) for c in src for g in c['maven_groups']), dep)

    def test_licences_and_notices(self):
        d = load()
        for c in d['components']:
            self.assertTrue(c['license_ids'], c['id'])
            for lid in c['license_ids']:
                self.assertIn(lid, d['licenses'], c['id'])
                # the licence's full text is here, or the part's own notice carries its terms
                # (a system's library comes with the system's copy of its licence; SQLite's asks for nothing)
                self.assertTrue(d['licenses'][lid]['text'] or c['notice'] or set(c['platforms'].values()) == {'system'}
                                or lid == 'blessing', (c['id'], lid))
            self.assertTrue(set(c['platforms']) <= set(d['platforms']) and c['platforms'], c['id'])
            self.assertTrue(c['url'].startswith('https://'), c['id'])
        # BSD and MIT licences ask for the copyright notice and terms to go with binaries: every part we carry has its
        # own notice
        for c in d['components']:
            if 'bundled' in c['platforms'].values() and set(c['license_ids']) & {'BSD-2-Clause', 'BSD-3-Clause', 'MIT', 'ISC', 'IJG', 'FTL', 'OFL-1.1', 'MIT-Modern-Variant'}:
                self.assertTrue(c['notice'], c['id'])
        for lid in ('Apache-2.0', 'OFL-1.1', 'FTL', 'AGPL-3.0-or-later', 'LLVM-exception'):
            self.assertTrue(d['licenses'][lid]['text'], lid)

    def test_course_credits(self):
        d = load()
        files = sorted(n for n in os.listdir(os.path.join(REPO, 'data', 'courses')) if n.endswith('.jxl'))
        self.assertEqual([p['file'] for p in d['photos']], files)
        for p in d['photos']:
            self.assertTrue(p['text'], p['file'])
            for link in p['links']:
                self.assertIn(link['text'], p['text'])
                self.assertTrue(link['url'].startswith('https://'), p['file'])
        commons = [p for p in d['photos'] if 'Wikimedia Commons' in p['text']]
        self.assertGreater(len(commons), 20)
        for p in commons:   # the licence (a link, or public domain) and the picture's page
            urls = [urllib.parse.urlsplit(link['url']) for link in p['links']]
            self.assertTrue(any(u.hostname == 'creativecommons.org' for u in urls) or 'Public domain' in p['text'], p['file'])
            self.assertTrue(any(u.hostname == 'commons.wikimedia.org' and u.path.startswith('/wiki/File:') for u in urls), p['file'])

    def test_names_no_plant_or_person(self):
        """public content: our side of it names no plant and no member of the project (third parties' copyright
        notices are theirs and stay as they are)"""
        d = load()
        ours = json.dumps({k: v for k, v in d.items() if k not in ('components', 'licenses', 'photos')})
        ours += json.dumps([{k: v for k, v in c.items() if k != 'notice'} for c in d['components']])
        self.assertNotRegex(ours, r'(?i)@|rumail|basra|kar electrical|sinohydro|shandong')
        self.assertNotRegex(json.dumps(d), r'(?i)rumail|basra')

    def test_every_package_carries_it(self):
        def read(*p):
            with open(os.path.join(REPO, *p), encoding='utf-8') as f:
                return f.read()
        self.assertIn('install -Dm644 data/about.json /app/share/walkdown/data/about.json',
                      read('apps', 'gnome', 'flatpak', 'io.github._5wHN28Dg.walkdown.yml'))
        self.assertRegex(read('packaging', 'windows', 'make-msix.sh'), r'cp "\$REPO/data/about.json" "\$W/layout/data/"')
        self.assertIn('"$REPO/data/about.json"', read('deploy', 'install-server-user.sh'))
        self.assertRegex(read('android', 'app2', 'build.gradle.kts'), r'val copyData [^\n]*\n[^\n]*include\([^)]*"about\.json"')


if __name__ == '__main__':
    unittest.main()
