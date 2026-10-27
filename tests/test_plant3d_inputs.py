"""Walkdown Plant's inputs go one way (docs/plant3d/MULTIPLAYER.md §3.1, milestone MP1): every input the app makes for
the plant goes through apps/plant3d/ui/inputs.gd, the path a session (MP2) takes over; in a session the session layer
(apps/plant3d/net/session.gd) alone gives the engine the host's committed inputs. No other script of the app calls the
engine's input methods or touches its input queue (apps/plant3d/tests/test_inputs.gd checks what the path does)."""
import os
import re
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(REPO, 'apps', 'plant3d')
PATH = os.path.join('ui', 'inputs.gd')
SESSION = os.path.join('net', 'session.gd')      # the committed inputs, in a session (MP2)
METHODS = ('op', 'ack', 'shelve', 'unshelve', 'fault', 'repair', 'repair_under', 'permit', 'lock', 'unlock',
           'remove_lock', 'role', 'release', 'task_ack', 'arrive', 'leave', 'read', 'say', 'pick', 'radio_call', 'jump',
           'ppe', 'zone', 'stop_act', 'apply_input', '_q')
# an engine as the app's scripts name it (the clock's, or a local `e`/`engine`/`eng`)
CALL = re.compile(r'\b(?:engine|e|eng|_engine|clock\.engine|ui\.clock\.engine)\s*\.\s*(%s)\s*\(' % '|'.join(METHODS))
QUEUE = re.compile(r'\b(?:engine|e|eng|_engine|clock\.engine)\s*\.\s*(queue|npc_queue)\s*\.\s*(append|push_back|insert|'
                   r'append_array)\s*\(')


def app_scripts():
    """Every .gd of the app (not its tests, the simulation itself, or the builder's offline tools)."""
    for top in ('app', 'ui', 'net'):
        for root, _, files in os.walk(os.path.join(APP, top)):
            if os.path.relpath(root, APP).startswith(os.path.join('net', 'tests')):
                continue
            for f in files:
                if f.endswith('.gd'):
                    yield os.path.relpath(os.path.join(root, f), APP)


class InputsPath(unittest.TestCase):
    def test_every_input_goes_through_inputs_gd(self):
        bad = []
        n = 0
        for rel in app_scripts():
            n += 1
            if rel in (PATH, SESSION):
                continue
            with open(os.path.join(APP, rel), encoding='utf-8') as f:
                for i, line in enumerate(f, 1):
                    code = line.split('#', 1)[0]
                    if CALL.search(code) or QUEUE.search(code):
                        bad.append(f'{rel}:{i}: {line.strip()}')
        self.assertGreater(n, 20, 'the app\'s scripts were not found')
        self.assertEqual(bad, [], 'inputs made around ui/inputs.gd')

    def test_the_check_finds_a_direct_input(self):
        """The patterns find the ways the app used to make inputs (before MP1)."""
        for line in ('clock.engine.op(o["kks"], o["do"], value, o.get("trip"))', 'e.permit(work, action, ui.me())',
                     'func(): ui.clock.engine.task_ack()', 'e.zone(sm.zone_ids[z], "in")', 'e.apply_input(x)',
                     'engine.queue.append(["ack", a])'):
            self.assertTrue(CALL.search(line) or QUEUE.search(line), line)
        for line in ('ui.inputs.op(kks, do)', 'inputs.task_ack()', '_mutex.lock()', 'f.read()'):
            self.assertFalse(CALL.search(line) or QUEUE.search(line), line)

    def test_inputs_gd_feeds_the_engine_alone(self):
        with open(os.path.join(APP, PATH), encoding='utf-8') as f:
            src = f.read()
        self.assertIn('e.apply_input(', src)
        self.assertIn('sink', src)


if __name__ == '__main__':
    unittest.main()
