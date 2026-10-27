"""Links into and out of Walkdown Plant (docs/PLANT3D.md §6, decisions 0054 and 0056): each platform registers the
walkdown-plant:// scheme and hands the URI to the app, and the plant app's list of link kinds Walkdown opens
(apps/plant3d/ui/links_in.gd WALKDOWN_TAKES) matches what Walkdown registers."""
import os
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLANT = os.path.join(ROOT, 'apps', 'plant3d')


def read(*p):
    with open(os.path.join(*p), encoding='utf-8') as f:
        return f.read()


class PlantLinks(unittest.TestCase):
    def test_flatpak_network(self):
        """Multiplayer (0068): the Flatpak shares the network (a static permission; the app opens no socket outside a
        session)."""
        y = read(PLANT, 'flatpak', 'io.github._5wHN28Dg.WalkdownPlant.yml')
        self.assertRegex(y, r'(?m)^  - --share=network\b')

    def test_flatpak_desktop_file(self):
        d = read(PLANT, 'flatpak', 'io.github._5wHN28Dg.WalkdownPlant.desktop')
        self.assertIn('MimeType=x-scheme-handler/walkdown-plant;', d.splitlines())
        self.assertRegex(d, r'(?m)^Exec=godot-runner -- %u$')    # an argument after --: never one of Godot's options

    def test_msix_manifest(self):
        ns = {'f': 'http://schemas.microsoft.com/appx/manifest/foundation/windows10',
              'uap3': 'http://schemas.microsoft.com/appx/manifest/uap/windows10/3'}
        m = ET.fromstring(read(PLANT, 'msix', 'AppxManifest.xml.in'))
        self.assertEqual(m.find('f:Identity', ns).get('Name'), 'WalkdownPlant')
        app = m.find('f:Applications/f:Application', ns)
        self.assertEqual(app.get('Executable'), 'WalkdownPlant.exe')
        p = app.find('f:Extensions/uap3:Extension/uap3:Protocol', ns)
        self.assertEqual((p.get('Name'), p.get('Parameters')), ('walkdown-plant', '-- "%1"'))
        caps = [c.get('Name') for c in m.find('f:Capabilities', ns)]
        # the network for multiplayer sessions only (0068): the Internet and the LAN; nothing else
        self.assertEqual(caps, ['internetClient', 'privateNetworkClientServer', 'runFullTrust'])

    def test_android_export_plugin(self):
        e = read(PLANT, 'addons', 'walkdown_plant_android', 'export.gd')
        self.assertIn('const SCHEME := "walkdown-plant"', e)
        self.assertIn('android.intent.action.VIEW', e)
        self.assertIn('android:exported=\\"true\\"', e)
        self.assertIn('res://addons/walkdown_plant_android/plugin.cfg', read(PLANT, 'project.godot'))
        presets = read(PLANT, 'export_presets.cfg')
        for block in presets.split('[preset.')[1:]:
            if 'platform="Android"' in block:
                opts = presets.split('[preset.' + block.split(']')[0] + '.options]')[1].split('[preset.')[0]
                self.assertIn('gradle_build/use_gradle_build=true', opts)   # the plugin's manifest needs Gradle
                # multiplayer (0068): INTERNET, and the multicast lock for the LAN query (MULTIPLAYER.md §9.3); no other
                # permission (RECORD_AUDIO is MP5's, asked at run time)
                self.assertEqual(sorted(x for x in re.findall(r'(?m)^permissions/([a-z_]+)=true$', opts)),
                                 ['change_wifi_multicast_state', 'internet'])

    def test_walkdown_takes_what_it_registers(self):
        """Walkdown registers walkdown:// on Android, GNOME (and its Flatpak) and Windows (decision 0058), and the
        plant offers links out of exactly the kinds Walkdown's reader (core/src/kks/applink.nim) opens"""
        takes = re.search(r'const WALKDOWN_TAKES: Array = \[(.*?)\]', read(PLANT, 'ui', 'links_in.gd')).group(1)
        takes = re.findall(r'"([a-z]+)"', takes)
        reader = re.findall(r'AppLink\(kind: "([a-z]+)"', read(ROOT, 'core', 'src', 'kks', 'applink.nim'))
        self.assertEqual(sorted(takes), sorted(set(reader)))
        self.assertEqual(sorted(takes), ['course', 'kks'])

        ns = {'a': 'http://schemas.android.com/apk/res/android'}
        A = '{http://schemas.android.com/apk/res/android}'
        man = ET.fromstring(read(ROOT, 'android', 'app2', 'src', 'main', 'AndroidManifest.xml'))
        with_scheme = []
        for act in man.find('application').findall('activity'):
            for f in act.findall('intent-filter'):
                if any(d.get(A + 'scheme') == 'walkdown' for d in f.findall('data')):
                    with_scheme.append(act.get(A + 'name'))
                    self.assertEqual([x.get(A + 'name') for x in f.findall('action')], ['android.intent.action.VIEW'])
                    self.assertEqual(sorted(c.get(A + 'name') for c in f.findall('category')),
                                     ['android.intent.category.BROWSABLE', 'android.intent.category.DEFAULT'])
                    self.assertEqual(act.get(A + 'exported'), 'true')
        # one windowless activity takes links and hands them to MainActivity (0058), not the launcher activity itself
        self.assertEqual(with_scheme, ['kks.explorer.LinkActivity'])

        d = read(ROOT, 'apps', 'gnome', 'flatpak', 'io.github._5wHN28Dg.walkdown.desktop')
        self.assertIn('MimeType=x-scheme-handler/walkdown;', d.splitlines())
        self.assertRegex(d, r'(?m)^Exec=walkdown %u$')
        y = read(ROOT, 'apps', 'gnome', 'flatpak', 'io.github._5wHN28Dg.walkdown.yml')
        self.assertIn('apps/gnome/flatpak/io.github._5wHN28Dg.walkdown.desktop -t /app/share/applications', y)

        wns = {'f': 'http://schemas.microsoft.com/appx/manifest/foundation/windows10',
               'uap3': 'http://schemas.microsoft.com/appx/manifest/uap/windows10/3'}
        m = ET.fromstring(read(ROOT, 'packaging', 'windows', 'AppxManifest.xml.in'))
        app = m.find('f:Applications/f:Application', wns)
        self.assertEqual(app.get('Executable'), 'Walkdown.exe')
        protos = [(p.get('Name'), p.get('Parameters')) for p in app.findall('f:Extensions/uap3:Extension/uap3:Protocol', wns)]
        self.assertEqual(protos, [('walkdown', '"%1"')])

if __name__ == '__main__':
    unittest.main()
