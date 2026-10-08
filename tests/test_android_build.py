"""The Android app's build files (android/app2):
- every library the Kotlin code imports is declared in build.gradle.kts, not only reached through another library
  (#71, DEP-2): an upgrade elsewhere must not move or drop it unseen;
- the debug and rehearsal builds' test hooks answer only the adb shell and the system (#43): every component their
  manifest exports is guarded by a permission.
  .venv/bin/python -m unittest tests.test_android_build"""
import glob, os, re, unittest
import xml.etree.ElementTree as ET

APP = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'android', 'app2'))
A = '{http://schemas.android.com/apk/res/android}'

# import prefix -> the start of the coordinate that must be declared for it (longest prefix wins)
LIBS = {
    'androidx.compose.ui': 'androidx.compose.ui:ui',
    'androidx.compose.foundation': 'androidx.compose.foundation:foundation',
    'androidx.compose.runtime': 'androidx.compose.runtime:runtime',
    'androidx.compose.material3': 'androidx.compose.material3:material3',
    'androidx.activity': 'androidx.activity:activity',
    'androidx.core': 'androidx.core:core',
    'androidx.work': 'androidx.work:work-runtime',
    'kotlinx.coroutines': 'org.jetbrains.kotlinx:kotlinx-coroutines-',
}
# the platform and the language: nothing to declare
PLATFORM = ('android.', 'java.', 'javax.', 'kotlin.', 'kks.', 'org.json.', 'org.w3c.', 'org.xml.', 'dalvik.')


def declared(gradle):
    body = gradle[gradle.index('\ndependencies {'):]
    return re.findall(r'^\s*implementation\("([^"]+)"\)', body, re.M)


def missing(imports, deps):
    out = set()
    for imp in imports:
        if imp.startswith(PLATFORM):
            continue
        pre = max((p for p in LIBS if imp == p or imp.startswith(p + '.')), key=len, default=None)
        if pre is None:
            out.add(imp + ' (unknown library: add it to LIBS and declare it)')
        elif not any(d.startswith(LIBS[pre]) for d in deps):
            out.add(LIBS[pre])
    return sorted(out)


class Dependencies(unittest.TestCase):
    def test_imports_declared(self):
        imports = set()
        for f in glob.glob(os.path.join(APP, 'src', '**', '*.kt'), recursive=True):
            with open(f, encoding='utf-8') as fh:
                imports |= set(re.findall(r'^import\s+([\w.]+)', fh.read(), re.M))
        self.assertTrue(any(i.startswith('kotlinx.coroutines') for i in imports))
        with open(os.path.join(APP, 'build.gradle.kts'), encoding='utf-8') as fh:
            deps = declared(fh.read())
        self.assertEqual(missing(imports, deps), [])

    def test_checker(self):
        self.assertEqual(missing({'kotlinx.coroutines.launch'}, ['androidx.work:work-runtime-ktx:2.11.2']),
                         ['org.jetbrains.kotlinx:kotlinx-coroutines-'])
        self.assertEqual(missing({'kotlinx.coroutines.launch', 'android.os.Bundle'},
                                 ['org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0']), [])
        self.assertEqual(len(missing({'com.example.thing.X'}, [])), 1)


class TestHooks(unittest.TestCase):
    def test_debug_exports_guarded(self):
        root = ET.parse(os.path.join(APP, 'src', 'debug', 'AndroidManifest.xml')).getroot()
        comps = [c for c in root.iter() if c.tag in ('receiver', 'service', 'provider', 'activity')]
        self.assertTrue(comps)
        for c in comps:
            if c.get(A + 'exported') == 'true':
                self.assertEqual(c.get(A + 'permission'), 'android.permission.DUMP', c.get(A + 'name'))


if __name__ == '__main__':
    unittest.main()
