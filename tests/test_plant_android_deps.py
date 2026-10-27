"""Walkdown Plant's Android build tools (decision 0070):
- every library Gradle downloads a jar of (apps/plant3d/android-gradle-verification.xml) is in a lockfile under
  apps/plant3d/android-locks/, which the required vulnerability and license scan (osv-scanner) reads: nothing the build
  runs escapes the scan (lint and aapt2, in detached configurations, are mirrored in a locked one);
- no lockfile and no verification entry holds a version below a pin of apps/plant3d/android-gradle-pins.gradle;
- build.sh applies the pins and installs the lockfiles.
  .venv/bin/python -m unittest tests.test_plant_android_deps"""
import glob, os, re, unittest
import xml.etree.ElementTree as ET

PLANT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'apps', 'plant3d'))
NS = '{https://schema.gradle.org/dependency-verification}'


def verified_jars(xml_text):
    """group:name:version of every component with a .jar artifact in a Gradle verification file"""
    out = set()
    for c in ET.fromstring(xml_text).iter(NS + 'component'):
        if any(a.get('name', '').endswith('.jar') for a in c.iter(NS + 'artifact')):
            out.add('%s:%s:%s' % (c.get('group'), c.get('name'), c.get('version')))
    return out


def every_component(xml_text):
    return {'%s:%s:%s' % (c.get('group'), c.get('name'), c.get('version'))
            for c in ET.fromstring(xml_text).iter(NS + 'component')}


def locked(texts):
    out = set()
    for t in texts:
        for line in t.splitlines():
            if line and not line.startswith('#') and not line.startswith('empty='):
                out.add(line.split('=', 1)[0])
    return out


def pins(groovy):
    """the `patched` map of the pins script, netty's modules included"""
    body = groovy[groovy.index('def patched = ['):]
    body = body[:body.index(']\n')]
    out = dict(re.findall(r"'([\w.\-]+:[\w.\-]+)': '([\w.\-]+)'", body))
    m = re.search(r"\[([^\]]*)\]\.each \{ patched\[\"io\.netty:netty-\$it\"\.toString\(\)\] = '([\w.\-]+)' \}", groovy)
    for mod in re.findall(r"'([\w\-]+)'", m.group(1)):
        out['io.netty:netty-' + mod] = m.group(2)
    return out


def older(a, b):   # as the pins script's `older`
    num = lambda v: [int(p) if p.isdigit() else 0 for p in re.split(r'[.-]', v)]
    x, y = num(a), num(b)
    for i in range(max(len(x), len(y))):
        d = (x[i] if i < len(x) else 0) - (y[i] if i < len(y) else 0)
        if d:
            return d < 0
    return False


def below_pins(coords, pinned):
    return sorted(c for c in coords if c.rsplit(':', 1)[0] in pinned and older(c.rsplit(':', 1)[1], pinned[c.rsplit(':', 1)[0]]))


def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


class PlantAndroidDeps(unittest.TestCase):
    def setUp(self):
        self.xml = read(os.path.join(PLANT, 'android-gradle-verification.xml'))
        self.locks = [read(p) for p in glob.glob(os.path.join(PLANT, 'android-locks', '**', '*gradle.lockfile'), recursive=True)]
        self.pins = pins(read(os.path.join(PLANT, 'android-gradle-pins.gradle')))

    def test_lockfiles_named_for_the_scan(self):
        names = sorted(os.path.relpath(p, os.path.join(PLANT, 'android-locks'))
                       for p in glob.glob(os.path.join(PLANT, 'android-locks', '**', '*.lockfile'), recursive=True))
        self.assertEqual(names, ['assetPackInstallTime/buildscript-gradle.lockfile', 'assetPackInstallTime/gradle.lockfile',
                                 'buildscript-gradle.lockfile', 'gradle.lockfile'])

    def test_every_jar_is_locked(self):
        jars = verified_jars(self.xml)
        self.assertGreater(len(jars), 100)
        self.assertEqual(sorted(jars - locked(self.locks)), [])

    def test_nothing_below_a_pin(self):
        self.assertIn('com.google.guava:guava', self.pins)
        self.assertEqual(self.pins['io.netty:netty-codec-http'], '4.1.137.Final')
        self.assertEqual(below_pins(locked(self.locks), self.pins), [])
        self.assertEqual(below_pins(every_component(self.xml), self.pins), [])

    def test_build_sh_installs_them(self):
        sh = read(os.path.join(PLANT, 'build.sh'))
        self.assertIn('cp "$HERE/android-gradle-pins.gradle" "$HERE/android/build/walkdown-pins.gradle"', sh)
        self.assertIn("apply from: 'walkdown-pins.gradle'", sh)
        self.assertIn('cp "$HERE/android-locks/$l" "$HERE/android/build/$l"', sh)
        self.assertIn('PLANT_GRADLE_WRITE_VERIFICATION needs the targets android-debug and android-release', sh)

    def test_checkers(self):
        x = ('<verification-metadata xmlns="https://schema.gradle.org/dependency-verification"><components>'
             '<component group="g" name="a" version="1.0"><artifact name="a-1.0.jar"/><artifact name="a-1.0.pom"/></component>'
             '<component group="g" name="parent" version="2"><artifact name="parent-2.pom"/></component>'
             '</components></verification-metadata>')
        self.assertEqual(verified_jars(x), {'g:a:1.0'})
        self.assertEqual(locked(['# c\ng:a:1.0=classpath\nempty=x\n']), {'g:a:1.0'})
        self.assertEqual(below_pins({'g:a:1.0', 'g:b:1.0'}, {'g:a': '1.0.1'}), ['g:a:1.0'])
        self.assertTrue(older('4.1.93.Final', '4.1.137.Final'))
        self.assertTrue(older('32.0.1-jre', '33.7.2-jre'))
        self.assertFalse(older('2.0.6.1', '2.0.6.1'))
        self.assertTrue(older('2.0.6', '2.0.6.1'))


if __name__ == '__main__':
    unittest.main()
