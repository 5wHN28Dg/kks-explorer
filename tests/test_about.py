"""data/about.json, the About content every Walkdown program shows (tools/about.py; the user, 2026-10-15):
- it is what tools/about.py makes from its sources now (a change to the metainfo, the third-party list, a licence or a
  course credit without running the tool fails here);
- name, summary, developer, licence and home page are the Flatpak metainfo's; the links are the repository's;
- the version of every pinned third-party part is the one pinned-sources.cdx.json pins, and what ships of the pinned
  sources is listed for the programs that carry it; the Android parts cover every library group of the release build's
  lockfile, at the versions the lockfile has;
- every course picture has its credit; every licence a part names is there, with its full text where a part has no
  notice of its own; nothing in it names a plant or a person of the project;
- every part used under Apache-2.0 that a program carries has its upstream NOTICE file with its notice, or is recorded
  as having none, with where that was checked; the Kotlin libraries record what code from other projects the app
  keeps of them;
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

    def test_apache_notices(self):
        """Apache License 2.0, 4(d): a work that comes with a NOTICE file is passed on with a readable copy of it. Every
        part used under Apache-2.0 that a program carries says whether it has one: its text (shown with the part's
        notice, verbatim) and where it comes from, or where it was checked that there is none (the user, 2026-10-15)"""
        with open(os.path.join(REPO, about.SRC, 'components.json'), encoding='utf-8') as f:
            src = json.load(f)['components']
        by = {c['id']: c for c in load()['components']}
        used = set()
        apache = [c for c in src if 'Apache-2.0' in re.findall(r'[\w.+-]+', c['license'])]
        self.assertGreaterEqual(len(apache), 12)
        for c in apache:
            rec = c.get('apache_notice')
            if 'bundled' not in c['platforms'].values():
                continue
            self.assertIsInstance(rec, dict, c['id'])
            where = rec.get('from') or rec.get('none')
            self.assertTrue(isinstance(where, str) and len(where) > 20, c['id'])
            if c.get('version') or c.get('pinned'):
                self.assertIn(by[c['id']]['version'], where, c['id'])   # checked at the version that ships
            if 'file' in rec:
                used.add(rec['file'] + '.txt')
                with open(os.path.join(REPO, about.SRC, 'notices', rec['file'] + '.txt'), encoding='utf-8') as f:
                    text = f.read()
                self.assertIn('Its NOTICE file, ' + rec['from'] + ':\n\n' + text, by[c['id']]['notice'])
            else:
                self.assertEqual(set(rec), {'none'}, c['id'])
        # the NOTICE files found (kept verbatim in tools/about/notices/*-NOTICE.txt) all go with their part
        found = {n for n in os.listdir(os.path.join(REPO, about.SRC, 'notices')) if n.endswith('-NOTICE.txt')}
        self.assertEqual(used, found)
        self.assertGreaterEqual(found, {'kotlin-NOTICE.txt', 'kotlinx-coroutines-NOTICE.txt', 'mupdf-droid-NOTICE.txt'})
        self.assertIn('Copyright (c) 2005-2008, The Android Open Source Project', by['mupdf-fonts']['notice'])
        self.assertIn('Copyright 2016-2024 JetBrains s.r.o and contributors', by['kotlinx-coroutines']['notice'])

    def test_apache_notice_required(self):
        """the tool itself refuses a carried Apache-2.0 part that doesn't say, a malformed record, and a record on a
        part that isn't under Apache-2.0; a part only the system provides needs none"""
        def comp(**kw):
            c = {'id': 'x', 'name': 'X', 'license': 'Apache-2.0 OR MIT', 'platforms': {'android': 'bundled'}}
            c.update(kw)
            return c
        texts = {'n': 'Copyright 2026 Someone\n'}
        for bad in (comp(), comp(apache_notice={}), comp(apache_notice={'none': ' '}),
                    comp(apache_notice={'file': 'n'}), comp(apache_notice={'none': 'checked', 'file': 'n', 'from': 'x'}),
                    comp(license='MIT', apache_notice={'none': 'checked'})):
            with self.assertRaises(SystemExit, msg=bad):
                about.with_apache_notice(bad, None, texts.__getitem__)
        self.assertIsNone(about.with_apache_notice(comp(platforms={'server': 'system'}), None, texts.__getitem__))
        self.assertEqual(about.with_apache_notice(comp(apache_notice={'none': 'checked here'}), 'own', texts.__getitem__), 'own')
        self.assertEqual(about.with_apache_notice(comp(apache_notice={'file': 'n', 'from': 'its NOTICE at v1'}), 'own\n', texts.__getitem__),
                         'own\n\n\nIts NOTICE file, its NOTICE at v1:\n\nCopyright 2026 Someone\n')
        self.assertEqual(about.with_apache_notice(comp(apache_notice={'file': 'n', 'from': 'w'}), None, texts.__getitem__),
                         'Its NOTICE file, w:\n\nCopyright 2026 Someone\n')

    def test_code_from_other_projects(self):
        """the Kotlin standard library and kotlinx.coroutines each record, at the version that ships, what code derived
        from other projects they hold and what of it the shrunk app keeps (the standard library's kotlin.time.Instant
        comes from ThreeTen-Backport, BSD-3-Clause, whose licence asks for its notice with binaries), so a version
        change is checked again (the user, 2026-10-15)"""
        with open(os.path.join(REPO, about.SRC, 'components.json'), encoding='utf-8') as f:
            src = {c['id']: c for c in json.load(f)['components']}
        for cid in ('kotlin-stdlib', 'kotlinx-coroutines'):
            rec = src[cid].get('third_party')
            self.assertTrue(isinstance(rec, str) and len(rec) > 40, cid)
            # checked at the version that ships (the whole version: 2.4.2 is not 2.4.20)
            self.assertRegex(rec, r'(?<![\w.])v?' + re.escape(src[cid]['version']) + r'(?![\w]|\.\d)', cid)
        self.assertIn('ThreeTen-Backport', src['kotlin-stdlib']['third_party'])
        # the record holds while the app's own code doesn't use the ThreeTen-derived part (kotlin.time.Instant, Clock)
        uses = []
        for root, _, files in os.walk(os.path.join(REPO, 'android', 'app2', 'src')):
            for n in files:
                if n.endswith(('.kt', '.java')):
                    with open(os.path.join(root, n), encoding='utf-8') as f:
                        if re.search(r'kotlin\.time\.(\*|Instant|Clock)|\bClock\.System\b', f.read()):
                            uses.append(n)
        self.assertEqual(uses, [], 'the app uses kotlin.time.Instant or Clock (ThreeTen-Backport, BSD-3-Clause): '
                                   'show its notice in About and update the record')

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



class PlantAbout(unittest.TestCase):
    """apps/plant3d/about.json (tools/about.py --plant): current, and every asset the plant's build fetches is in
    it, CC0 with the licence's full text."""
    def test_current(self):
        self.assertEqual(about.main(['--plant', '--check']), 0, 'run python3 tools/about.py --plant and commit it')

    def test_every_fetched_asset_is_listed(self):
        with open(os.path.join(REPO, 'apps', 'plant3d', 'about.json'), encoding='utf-8') as f:
            d = json.load(f)
        with open(os.path.join(REPO, 'apps', 'plant3d', 'kit', 'fetch_textures.sh'), encoding='utf-8') as f:
            fetch = f.read()
        fetched = set(re.findall(r'^[0-9a-f]{64} (\w+) ', fetch, re.M))
        sky = re.search(r'^SKY_NAME=(\S+)$', fetch, re.M).group(1)
        names = {a['source'].rsplit('/', 1)[-1] for a in d['assets']}
        for n in fetched:
            self.assertIn(n + '_2K-JPG.zip', {x.replace('get?file=', '') for x in names}, n)
        self.assertIn(sky, names)
        voice = [a for a in d['assets'] if 'voice/build.sh' in a['pinned_by']]
        for a in d['assets']:
            if a not in voice:
                self.assertEqual(a['license'], 'CC0-1.0', a['id'])
        self.assertIn('CC0 1.0 Universal', d['licenses']['CC0-1.0']['text'])

    def test_the_voice_codecs_code_is_listed_with_its_notices(self):
        """wdp_voice (decision 0069): every source apps/plant3d/voice/build.sh fetches is in About, under its
        permissive licence, with its own licence file (copyright lines and terms) in full"""
        with open(os.path.join(REPO, 'apps', 'plant3d', 'about.json'), encoding='utf-8') as f:
            d = json.load(f)
        with open(os.path.join(REPO, 'apps', 'plant3d', 'voice', 'build.sh'), encoding='utf-8') as f:
            urls = re.findall(r'^fetch \S+ (https://\S+) [0-9a-f]{64}$', f.read(), re.M)
        self.assertEqual(len(urls), 3)
        by_source = {a['source']: a for a in d['assets']}
        for u in urls:
            self.assertIn(u, by_source)
            a = by_source[u]
            self.assertIn(a['license'], ('BSD-3-Clause', 'MIT'), a['id'])
            self.assertIn('voice/build.sh', a['pinned_by'])
            self.assertIn('Copyright', a['notice'])
            self.assertIn('THE SOFTWARE IS PROVIDED "AS IS"' if a['license'] == 'MIT' else 'Redistribution and use',
                          a['notice'])
            self.assertIn(a['license'], d['licenses'])
        # the runtimes linked into the libraries (Android and Windows: LLVM's; Windows: MinGW-w64's; Linux: GCC's)
        ids = {a['id']: a for a in d['assets']}
        for i in ('llvm-runtime', 'mingw-w64', 'gcc-runtime'):
            self.assertIn(i, ids)
        apache = d['licenses']['Apache-2.0 WITH LLVM-exception']['text']
        self.assertIn('Apache License', apache)
        self.assertIn('LLVM Exceptions to the Apache 2.0 License', apache)
        self.assertIn('MinGW-w64', ids['mingw-w64']['notice'])
        # the SpeexDSP file compiled in carries its own notice, and libopus's files' copyright holders are all named
        self.assertIn('Thorvald Natvig', by_source['https://downloads.xiph.org/releases/speex/speexdsp-1.2.1.tar.gz']['notice'])
        opus = by_source['https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz']['notice']
        for holder in ('Koen Vos', 'Cisco Systems', 'Google Inc.', 'Parrot', 'Vidyo', 'John Ridges'):
            self.assertIn(holder, opus)

if __name__ == '__main__':
    unittest.main()
