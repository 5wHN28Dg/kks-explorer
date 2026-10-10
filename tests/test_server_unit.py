"""The server's systemd units (deploy/install-server-user.sh; deploy/install-server-system.sh for a machine without a
TPM2, added 2026-10-10) and build (2026-10-09: the deployed server held 7.4 GB):
- the unit caps the server's memory with MemoryMax, without swap, restarts it when it is killed, and never throttles
  it with MemoryHigh (throttling took the desktop down);
- the importer's own address-space limit (import_memory_mb) is below that cap, so an import stops itself first;
- the server is built with glibc's malloc (platform/linux/kks_server.nims), which gives freed memory back.
  .venv/bin/python -m unittest tests.test_server_unit"""
import os, re, subprocess, tempfile, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def user_unit_text():
    with open(os.path.join(REPO, 'deploy', 'install-server-user.sh')) as f:
        script = f.read()
    m = re.search(r'kks-server\.service" <<UNIT\n(.*?)\nUNIT\n', script, re.S)
    assert m, 'the unit heredoc was not found in install-server-user.sh'
    return m.group(1)


def system_unit_text(user='walkdown', home='/home/walkdown'):
    return subprocess.run([os.path.join(REPO, 'deploy', 'install-server-system.sh'), '--print-unit', user, home],
                          check=True, capture_output=True, text=True).stdout


UNITS = {'user': user_unit_text, 'system': system_unit_text}


def service_settings(unit):
    out, section = {}, None
    for line in unit.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('['):
            section = line
        elif section == '[Service]' and '=' in line:
            k, v = line.split('=', 1)
            out.setdefault(k, []).append(v)
    return out


def size(v):
    n, unit = re.fullmatch(r'(\d+)([KMG]?)', v).groups()
    return int(n) * {'': 1, 'K': 1 << 10, 'M': 1 << 20, 'G': 1 << 30}[unit]


class ServerUnit(unittest.TestCase):
    def test_memory_is_capped_and_a_killed_server_restarts(self):
        for kind, text in UNITS.items():
            with self.subTest(unit=kind):
                s = service_settings(text())
                self.assertIn('MemoryMax', s)
                cap = size(s['MemoryMax'][-1])
                # room for the importer it runs (the largest real sheet peaks near 1.85 GB resident) and the server,
                # well under the old 8G
                self.assertGreaterEqual(cap, 2 << 30)
                self.assertLessEqual(cap, 4 << 30)
                self.assertEqual(s.get('MemorySwapMax'), ['0'])
                self.assertEqual(s.get('Restart'), ['on-failure'])
                self.assertEqual(s.get('OOMPolicy'), ['continue'])

    def test_importer_stops_itself_below_the_cap(self):
        """2026-10-09: the importer's address-space limit was 6144 MB under a 3G cap, so a growing import was killed by
        the cgroup (no message) instead of stopping itself with one"""
        with open(os.path.join(REPO, 'platform', 'linux', 'src', 'kksl', 'server.nim')) as f:
            mb = int(re.search(r'importMemoryMb: (\d+)\)', f.read()).group(1))
        self.assertEqual(mb, 2560)
        for kind, text in UNITS.items():
            with self.subTest(unit=kind):
                self.assertLess(mb << 20, size(service_settings(text())['MemoryMax'][-1]))

    def test_never_memory_high(self):
        for kind, text in UNITS.items():
            with self.subTest(unit=kind):
                self.assertNotIn('MemoryHigh', service_settings(text()))

    def test_system_unit_runs_the_users_install_unprivileged(self):
        """a machine without a TPM2 (2026-10-10): a user service can't load the sealed key there, so the same install
        runs as a system service: as that user, with the machine's credential, writing only its state folder"""
        s = service_settings(system_unit_text('plant', '/srv/plant'))
        self.assertEqual(s['User'], ['plant'])
        self.assertNotIn('Group', s)  # the user's primary group, whatever its name (216/GROUP otherwise)
        self.assertEqual(s['Environment'], ['KKS_CONFIG=/srv/plant/kks-server/config.json'])
        self.assertEqual(s['ExecStart'], ['/srv/plant/kks-server/app/current/kks-server serve'])
        self.assertEqual(s['WorkingDirectory'], ['/srv/plant/kks-server/state'])
        self.assertEqual(s['LoadCredentialEncrypted'], ['kks-storage-key:/etc/credstore.encrypted/kks-storage-key'])
        self.assertEqual(s['ProtectSystem'], ['strict'])
        self.assertEqual(s['ReadWritePaths'], ['/srv/plant/kks-server/state'])
        for k in ('NoNewPrivileges', 'PrivateTmp', 'PrivateDevices', 'ProtectKernelTunables', 'ProtectKernelModules',
                  'ProtectControlGroups', 'RestrictNamespaces', 'LockPersonality', 'RestrictSUIDSGID'):
            self.assertEqual(s.get(k), ['true'], k)
        self.assertEqual(s['SystemCallArchitectures'], ['native'])
        self.assertEqual(s['CapabilityBoundingSet'], [''])
        self.assertEqual(s['RestrictAddressFamilies'], ['AF_INET AF_INET6 AF_UNIX AF_NETLINK'])

    def test_system_install_refuses_without_root(self):
        if os.geteuid() == 0:
            self.skipTest('needs an unprivileged user')
        r = subprocess.run([os.path.join(REPO, 'deploy', 'install-server-system.sh'), 'nobody'],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn('root', r.stderr)

    def install(self, tmp, **extra):
        """deploy/install-server-user.sh in a scratch home, with a stand-in compiler that writes the file named by -o:"""
        home, nim = os.path.join(tmp, 'home'), os.path.join(tmp, 'nim')
        os.makedirs(home)
        with open(nim, 'w') as f:
            f.write('#!/bin/sh\nfor a in "$@"; do case "$a" in -o:*) echo x > "${a#-o:}";; esac; done\n')
        os.chmod(nim, 0o755)
        env = dict(os.environ, HOME=home, NIM=nim, KKS_SYSTEM_UNIT_FILE=os.path.join(tmp, 'no-system-unit'))
        env.update(extra)
        env.pop('KKS_SERVER_HOME', None)
        # the install is read-only: callers make it writable again before the scratch folder goes
        r = subprocess.run([os.path.join(REPO, 'deploy', 'install-server-user.sh')], env=env, capture_output=True,
                           text=True)
        return r, home

    def test_user_install_for_a_system_unit_writes_no_user_unit_or_key(self):
        """KKS_SERVER_UNIT=system: the install stops before the user unit and the user-sealed key (two units on one
        database must never exist)"""
        with tempfile.TemporaryDirectory() as tmp:
            r, home = self.install(tmp, KKS_SERVER_UNIT='system')
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(os.path.exists(os.path.join(home, 'kks-server', 'app', 'current', 'kks-server')))
            self.assertTrue(os.path.exists(os.path.join(home, 'kks-server', 'config.json')))
            self.assertFalse(os.path.exists(os.path.join(home, 'kks-server', 'storage-key.cred')))
            self.assertFalse(os.path.exists(os.path.join(home, '.config', 'systemd', 'user', 'kks-server.service')))
            self.assertIn('install-server-system.sh', r.stdout)
            subprocess.run(['chmod', '-R', 'u+w', home])

    def test_user_install_rejects_an_unknown_unit_kind(self):
        with tempfile.TemporaryDirectory() as tmp:
            r, home = self.install(tmp, KKS_SERVER_UNIT='sytem')
            self.assertEqual(r.returncode, 2)
            self.assertEqual(os.listdir(home), [])

    def test_user_install_refuses_next_to_a_system_unit(self):
        """an update on the server run without KKS_SERVER_UNIT=system would write a user unit and a second key next to
        the system service"""
        with tempfile.TemporaryDirectory() as tmp:
            unit = os.path.join(tmp, 'kks-server.service')
            open(unit, 'w').close()
            r, home = self.install(tmp, KKS_SYSTEM_UNIT_FILE=unit)
            self.assertEqual(r.returncode, 1)
            self.assertIn('KKS_SERVER_UNIT=system', r.stderr)
            self.assertEqual(os.listdir(home), [])
        with tempfile.TemporaryDirectory() as tmp:
            unit = os.path.join(tmp, 'kks-server.service')
            open(unit, 'w').close()
            r, home = self.install(tmp, KKS_SYSTEM_UNIT_FILE=unit, KKS_SERVER_UNIT='system')
            self.assertEqual(r.returncode, 0, r.stderr)
            subprocess.run(['chmod', '-R', 'u+w', home])


class SystemInstall(unittest.TestCase):
    """deploy/install-server-system.sh's root path, under a scratch prefix with stand-ins for id, getent, systemctl and
    systemd-creds on PATH (the stand-in "seals" by copying its input)"""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(subprocess.run, ['rm', '-rf', self.tmp])
        self.home = os.path.join(self.tmp, 'home', 'plant')
        self.server = os.path.join(self.home, 'kks-server')
        os.makedirs(os.path.join(self.server, 'app', 'current'))
        os.makedirs(os.path.join(self.server, 'state'))
        exe = os.path.join(self.server, 'app', 'current', 'kks-server')
        open(exe, 'w').close()
        os.chmod(exe, 0o755)
        self.bin = os.path.join(self.tmp, 'bin')
        os.makedirs(self.bin)
        self.tool('id', 'if [ "$#" -eq 1 ]; then echo 0; elif [ "$2" = root0 ]; then echo 0; else echo 1000; fi')
        self.tool('getent', '[ "$2" = nobody-here ] && exit 2; echo "$2:x:1000:100::${FAKE_HOME}:/bin/sh"')
        self.tool('systemctl', 'echo "$@" >> "$FAKE_LOG"')
        self.tool('systemd-creds', '[ -n "${CREDS_FAIL:-}" ] && { head -c 5 > "$4"; exit 1; }; cat > "$4"')
        self.prefix = os.path.join(self.tmp, 'root')
        self.cred = self.prefix + '/etc/credstore.encrypted/kks-storage-key'
        self.unit = self.prefix + '/etc/systemd/system/kks-server.service'

    def tool(self, name, body):
        with open(os.path.join(self.bin, name), 'w') as f:
            f.write('#!/bin/sh\n' + body + '\n')
        os.chmod(os.path.join(self.bin, name), 0o755)

    def run_install(self, user='plant', home=None, **extra):
        env = dict(os.environ, PATH=self.bin + ':' + os.environ['PATH'], KKS_SYSTEM_PREFIX=self.prefix,
                   FAKE_HOME=home or self.home, FAKE_LOG=os.path.join(self.tmp, 'systemctl.log'))
        env.update(extra)
        return subprocess.run([os.path.join(REPO, 'deploy', 'install-server-system.sh'), user], env=env,
                              capture_output=True, text=True)

    def test_installs_the_unit_and_a_new_key_once(self):
        r = self.run_install()
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(self.unit) as f:
            self.assertEqual(f.read(), system_unit_text('plant', self.home))
        self.assertEqual(os.path.getsize(self.cred), 32)
        self.assertEqual(os.stat(self.cred).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(os.path.dirname(self.cred)).st_mode & 0o777, 0o700)
        with open(os.path.join(self.tmp, 'systemctl.log')) as f:
            self.assertEqual(f.read(), 'daemon-reload\n')  # nothing is started or enabled
        with open(self.cred, 'rb') as f:
            key = f.read()
        self.assertEqual(self.run_install().returncode, 0)
        with open(self.cred, 'rb') as f:
            self.assertEqual(f.read(), key, 'a second run made a new key')

    def refused(self, r, word):
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn(word, r.stderr)
        self.assertFalse(os.path.exists(self.unit))
        self.assertFalse(os.path.exists(self.cred))

    def test_refuses_a_new_key_for_an_existing_database(self):
        open(os.path.join(self.server, 'state', 'server.db'), 'w').close()
        self.refused(self.run_install(), 'server.db')

    def test_refuses_next_to_a_user_unit_or_user_key_and_says_not_to_delete_a_databases_key(self):
        open(os.path.join(self.server, 'storage-key.cred'), 'w').close()
        r = self.run_install()
        self.refused(r, 'do not delete')
        os.remove(os.path.join(self.server, 'storage-key.cred'))
        os.makedirs(os.path.join(self.home, '.config', 'systemd', 'user'))
        open(os.path.join(self.home, '.config', 'systemd', 'user', 'kks-server.service'), 'w').close()
        self.refused(self.run_install(), 'user unit')

    def test_refuses_root_an_unknown_user_a_missing_install_and_an_odd_path(self):
        self.refused(self.run_install(user='root0'), 'must not run as root')
        self.refused(self.run_install(user='nobody-here'), 'no such user')
        self.refused(self.run_install(home=os.path.join(self.tmp, 'empty')), 'install-server-user.sh')
        odd = os.path.join(self.tmp, 'my %home')
        os.makedirs(os.path.join(odd, 'kks-server', 'app', 'current'))
        exe = os.path.join(odd, 'kks-server', 'app', 'current', 'kks-server')
        open(exe, 'w').close()
        os.chmod(exe, 0o755)
        self.refused(self.run_install(home=odd), 'characters')

    def test_a_failed_sealing_leaves_no_credential_and_no_unit(self):
        self.refused(self.run_install(CREDS_FAIL='1'), '')
        r = self.run_install()  # and the next run seals a whole one
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(os.path.getsize(self.cred), 32)


if __name__ == '__main__':
    unittest.main()
