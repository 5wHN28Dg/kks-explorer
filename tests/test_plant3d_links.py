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
        self.assertEqual(caps, ['runFullTrust'])                # no network: the plant app has none (0054)

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

    def test_walkdown_takes_what_it_registers(self):
        takes = re.search(r'const WALKDOWN_TAKES: Array = \[(.*?)\]', read(PLANT, 'ui', 'links_in.gd')).group(1)
        registered = []
        for path in ['android/app2/src/main/AndroidManifest.xml', 'packaging/windows/AppxManifest.xml.in']:
            if re.search(r'scheme="walkdown"|Protocol Name="walkdown"', read(ROOT, path)):
                registered.append(path)
        for dirpath, _, files in os.walk(os.path.join(ROOT, 'apps')):
            for f in files:
                if f.endswith('.desktop') and 'x-scheme-handler/walkdown;' in read(dirpath, f):
                    registered.append(f)
        # Walkdown registers no walkdown:// scheme today: the plant offers no link out. When it does, say which
        # kinds it opens in WALKDOWN_TAKES (and the other way round).
        self.assertEqual(bool(takes.strip()), bool(registered), (takes, registered))


if __name__ == '__main__':
    unittest.main()
