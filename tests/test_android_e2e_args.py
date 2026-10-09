"""The Android e2e scripts test the APK they are given (android/app2/e2e): test_app2 takes the command line's first
arguments as its own and deletes them when it is imported, so a script that imports it must read its own first.
test_update read them after, ran on whatever debug APK sat at the default path, and the 0.10.0 release rehearsal
"failed" because that path held the 9.9.9 build. No emulator needed: the scripts are only imported.
  .venv/bin/python -m unittest tests.test_android_e2e_args"""
import os, subprocess, sys, unittest

E2E = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'android', 'app2', 'e2e'))

# script -> (its arguments, the module variables they must end up in)
SCRIPTS = {
    'test_update': (['/x/app.apk', '/x/newer.apk', '/x/kks_server'], ['APK', 'NEWER', 'SERVER']),
    'test_direct': (['/x/app.apk', '/x/kks_server'], ['APK', 'SERVER']),
    'test_app2': (['/x/app.apk', '/x/kks_server', '/x/kks_import'], ['APK', 'SERVER', 'IMPORTER']),
}


def imported(module, args, names):
    code = ('import sys; d, mod, names = sys.argv.pop(1), sys.argv.pop(1), sys.argv.pop(1).split(","); '
            'sys.path.insert(0, d); m = __import__(mod); print("\\n".join(str(getattr(m, n)) for n in names))')
    r = subprocess.run([sys.executable, '-c', code, E2E, module, ','.join(names), *args],
                       capture_output=True, text=True, cwd=E2E, timeout=60)
    assert r.returncode == 0, r.stderr
    return r.stdout.splitlines()


class Args(unittest.TestCase):
    def test_scripts_use_their_arguments(self):
        for module, (args, names) in SCRIPTS.items():
            with self.subTest(module):
                self.assertEqual(imported(module, args, names), args)


if __name__ == '__main__':
    unittest.main()
