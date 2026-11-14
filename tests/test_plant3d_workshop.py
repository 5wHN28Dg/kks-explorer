"""Walkdown Plant's Workshop data files (docs/plant3d/WORKSHOP.md §4, milestone K1a; ref/plant3d_workshop.py): the
committed files pass and are what tools/plant3d/make_content.py makes (test_plant3d's own check), the data-only fixture
kind passes, and each rule refuses what it should (strict JSON, keys, ids of at most 16 characters, lengths, sealing,
fastener joins, sources cited and used, the assembly placing everything once in an order that passes its needs, the
views, the plant's content check refusing a file named for another part).
  .venv/bin/python -m unittest tests.test_plant3d_workshop"""
import copy, json, os, unittest
from ref import plant3d as P
from ref import plant3d_workshop as W
from ref.courses import FormatError

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
DATA = os.path.join(REPO, 'data', 'plant3d')
FIXTURE = os.path.join(REPO, 'apps', 'plant3d', 'tests', 'fixtures', 'workshop_gadget.json')


class WorkshopData(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = P.load_dir(DATA)
        cls.b = P.check_files(cls.files)
        with open(FIXTURE, 'rb') as f:
            cls.fixture = W.loads(f.read())

    def refused(self, w, code, kit=True):
        with self.assertRaises(FormatError) as cm:
            W.check(w, self.b.kit if kit else None, 'w', parts={'test_gadget'})
        self.assertEqual(cm.exception.code, code, str(cm.exception))
        return str(cm.exception)

    def test_the_transmitter_passes(self):
        w = self.b.workshop['pressure_transmitter']
        self.assertEqual(w['components'], 14)
        self.assertEqual(w['fasteners'], 2)
        for c, d in json.loads(self.files['workshop/pressure_transmitter.json'])['components'].items():
            self.assertLessEqual(len(c), 16, c)
            self.assertTrue(d['sources'], c)

    def test_the_steam_turbine_passes(self):
        w = self.b.workshop['steam_turbine']
        self.assertEqual(w['components'], 54)
        self.assertEqual(w['fasteners'], 3)
        d = json.loads(self.files['workshop/steam_turbine.json'])
        self.assertEqual(d['context'], ['axis_z', 'shaft_lo', 'shaft_hi'])
        order = [s['place'] for s in d['assembly']]
        # the overhaul's order (K4a): taken apart, the upper lagging comes off first, the rotor after the upper
        # casings, the bearing caps and the coupling's bolts
        undo = order[::-1]
        self.assertEqual(undo[0], 'lagging_upper')
        for before in ('casing_upper', 'joint_bolts', 'inner_upper', 'inner_bolts', 'carrier_upper', 'cap_f',
                       'cap_r', 'thrust_upper', 'thrust_lower', 'coupling_bolts', 'brg_f_upper', 'brg_r_upper', 'glands_upper'):
            self.assertLess(undo.index(before), undo.index('rotor'), before)

    def test_the_gas_turbine_passes(self):
        w = self.b.workshop['gas_turbine']
        self.assertEqual(w['components'], 84)
        self.assertEqual(w['fasteners'], 2)
        d = json.loads(self.files['workshop/gas_turbine.json'])
        self.assertEqual(d['context'], ['axis_z', 'shaft_lo', 'shaft_hi'])
        for c, x in d['components'].items():
            self.assertLessEqual(len(c), 16, c)
            self.assertTrue(x['sources'], c)
        undo = [s['place'] for s in d['assembly']][::-1]
        # a major inspection's take-apart (K5a, GER-3620P): the combustion parts out before any casing is lifted
        # (each can's end cover, then its liner, its casing and its transition piece), the upper casings and their
        # stator rows and nozzles, the bearings and the coupling before the rotor is lifted
        first_casing = min(undo.index(c) for c in ('comp_upper', 'cdc_upper', 'tshell_upper'))
        for k in ['%02d' % (i + 1) for i in range(12)]:
            self.assertLess(undo.index('cover_' + k), undo.index('liner_' + k))
            self.assertLess(undo.index('liner_' + k), undo.index('can_' + k))
            self.assertLess(undo.index('can_' + k), undo.index('tp_' + k))
            self.assertLess(undo.index('tp_' + k), first_casing)
        for before in ('comp_upper', 'comp_bolts', 'cdc_upper', 'tshell_upper', 'cvanes_upper', 'igv_upper',
                       'tnoz1_u', 'tnoz2_u', 'tnoz3_u', 'brg1_cover', 'brg1_upper', 'brg2_upper', 'thrust',
                       'coupling_bolts'):
            self.assertLess(undo.index(before), undo.index('rotor'), before)
        self.assertLess(undo.index('comp_bolts'), undo.index('comp_upper'))
        for after in ('brg1_lower', 'brg2_lower', 'cvanes_lower', 'igv_lower', 'tnoz1_l', 'comp_lower'):
            self.assertGreater(undo.index(after), undo.index('rotor'), after)
        # (K5b) a turning machine is never opened, and a gas turbine runs only closed: nothing may be out or opened
        self.assertEqual(d['views']['open_running']['allowed'], [])
        self.assertIn('turning gear', d['views']['open_running']['why'])
        self.assertEqual(d['views']['run_exploded']['allowed'], [])

    def test_the_vertical_pump_passes(self):
        # K6: a wet-pit vertical turbine pump, two stages, its vertical motor's tree from parts_common.gd motor_v
        d = json.loads(self.files['workshop/pump_vertical.json'])
        self.assertEqual(self.b.workshop['pump_vertical']['components'], 23)
        self.assertEqual(set(d['fasteners']), {'head_bolts', 'joint_bolts_1', 'joint_bolts_2'})
        self.assertEqual(d['params'], {'flow_m3h': 550, 'head_m': 30, 'motor_kw': 75, 'pit_depth': 6.5})
        undo = [s['place'] for s in d['assembly']][::-1]
        # taken apart (Goulds VIT §6, Flowserve VTP §6.8): the coupling, then the motor lifted off, the seal, the head
        # unbolted, the column from the top down, the bowls last, each impeller off its taperlock after its bowl
        for a, b in (('coupling', 'motor'), ('coupling', 'seal'), ('drip_cover', 'motor'), ('motor', 'head'),
                     ('seal', 'head'), ('head_bolts', 'head'), ('head', 'column_1'), ('column_1', 'column_2'),
                     ('column_2', 'column_3'), ('column_3', 'discharge_case'), ('discharge_case', 'bowl_2'),
                     ('bowl_2', 'impeller_2'), ('impeller_2', 'bowl_1'), ('bowl_1', 'impeller_1'),
                     ('impeller_1', 'suction_bell')):
            self.assertLess(undo.index(a), undo.index(b), (a, b))
        # the vertical motor: cover, fan, top bracket, then the rotor lifted out; every step of it says its order is
        # derived from the build (the user, 2026-11-09)
        for a, b in (('drip_cover', 'fan'), ('fan', 'end_shield_nde'), ('end_shield_nde', 'rotor')):
            self.assertLess(undo.index(a), undo.index(b), (a, b))
        mot = {'motor', 'end_shield_de', 'end_shield_nde', 'drip_cover', 'fan', 'rotor', 'bearing_thrust',
               'bearing_guide', 'terminal_box'}
        for st in d['assembly']:
            if st['place'] in mot:
                self.assertIn('derived from how the motor is built', ' '.join(st.get('why', [])), st['place'])
        # no grille here: the pumps manual's comes_with (grille -> fan_cowl) needs both or neither
        self.assertNotIn('fan_cowl', d['components'])
        self.assertNotIn('mixed', json.dumps(d))   # (no source read calls these impellers mixed-flow)

    def test_the_motor_and_the_pump_pass(self):
        # K6: the motor's tree is written once (tools/plant3d/workshop/motor.py) and the pump carries it under `motor`
        motor = json.loads(self.files['workshop/motor.json'])
        pump = json.loads(self.files['workshop/pump_horizontal.json'])
        self.assertEqual(self.b.workshop['motor']['components'], 11)
        self.assertEqual(self.b.workshop['pump_horizontal']['components'], 22)
        mine = set(motor['components']) - {'stator', 'baseplate'}
        self.assertTrue(mine <= set(pump['components']), mine - set(pump['components']))
        for c in mine:
            self.assertEqual(motor['components'][c], pump['components'][c], c)
        # the motor's order is derived from the build, not a manual (the user, 2026-11-09): every step of it says so
        for d in (motor, pump):
            for st in d['assembly']:
                if st['place'] in mine | {'stator', 'de_bolts', 'cowl_screws'}:
                    self.assertIn('derived from how the motor is built', ' '.join(st.get('why', [])), st['place'])
        # taken apart (the reverse): the cowl before the fan, the fan before the non-drive-end shield, the drive-end
        # shield before the rotor, the rotor before its bearings come off
        undo = [s['place'] for s in motor['assembly']][::-1]
        for a, b in (('fan_cowl', 'fan'), ('fan', 'end_shield_nde'), ('end_shield_de', 'rotor'),
                     ('end_shield_nde', 'rotor')):
            self.assertLess(undo.index(a), undo.index(b), (a, b))
        # the pump (Goulds 3196, Flowserve Mark 3): the guard and the coupling off, the casing bolts out with the motor
        # left standing (the spacer coupling), the impeller and the casing cover off before the shaft leaves the frame
        undo = [s['place'] for s in pump['assembly']][::-1]
        for a, b in (('guard', 'coupling'), ('coupling', 'casing_bolts'), ('frame', 'motor'),
                     ('casing_bolts', 'impeller'), ('impeller', 'shaft'), ('casing_cover', 'shaft'),
                     ('end_cover', 'shaft'), ('seal', 'shaft')):
            self.assertLess(undo.index(a), undo.index(b), (a, b))
        # the fan (wider than the stator's bore) off before the rotor is drawn out; the baseplate there first
        for d in (pump, motor):
            needs = {st['place']: [n[0] for n in st.get('needs', [])] for st in d['assembly']}
            self.assertIn('rotor', needs['fan'])
        self.assertIn('baseplate', needs['stator'])
        self.assertEqual(pump['params']['head_m'], 40)   # the end-suction pump (the multi-stage one has no tree yet)

    def test_the_control_valve_passes(self):
        # K6: the pneumatic control valve (Fisher easy-e ES body and trim, Fisher 667 actuator)
        v = json.loads(self.files['workshop/valve_control.json'])
        self.assertEqual(self.b.workshop['valve_control']['components'], 15)
        self.assertEqual(v['params'], {'dn': 150, 'actuator': 'pneumatic'})
        self.assertEqual(set(v['fasteners']), {'bonnet_bolts', 'casing_bolts'})
        undo = [s['place'] for s in v['assembly']][::-1]
        # taken apart (the reverse): the tubing and the positioner, the stem connector before the actuator's casing
        # comes apart (667: never part it under spring force) and before the actuator leaves the bonnet; the
        # actuator off before the packing (ES: replacing packing); the bonnet nuts, the bonnet, then the plug and
        # stem, the cage, the seat ring (ES §3.3)
        for a, b in (('tubing', 'positioner'), ('positioner', 'stem_connector'), ('stem_connector', 'casing_bolts'),
                     ('stem_connector', 'yoke'), ('casing_bolts', 'upper_casing'), ('upper_casing', 'diaphragm'),
                     ('diaphragm', 'actuator_stem'), ('yoke', 'packing'), ('packing', 'bonnet'),
                     ('bonnet_bolts', 'bonnet'), ('bonnet', 'plug_stem'), ('plug_stem', 'cage'), ('cage', 'seat_ring')):
            self.assertLess(undo.index(a), undo.index(b), (a, b))
        # every step cites the valve's or the actuator's manual; the spring's says where the 667's really sits
        steps = {st['place']: st for st in v['assembly']}
        self.assertIn('yoke', ' '.join(steps['spring']['why']))
        for st in v['assembly']:
            self.assertTrue(set(st['sources']) & {'fisher_es', 'fisher_667', 'dvc6200'}, st['place'])

    def test_the_hand_and_motor_operated_valves_pass(self):
        # K6: the gate valve (Crane), the globe valve under a multi-turn electric actuator (Crane, AUMA SA) and the
        # butterfly valve under a part-turn one (Bray Series 35/36, AUMA SQ)
        cases = {'valve_gate': (8, {'dn': 300, 'actuator': 'manual'}, {'bonnet_bolts'}),
                 'valve_globe': (10, {'dn': 50, 'rating': 'pn160', 'actuator': 'electric'},
                                 {'bonnet_bolts', 'actuator_bolts'}),
                 'valve_butterfly': (9, {'dn': 250, 'actuator': 'electric'}, {'actuator_bolts'})}
        for part, (n, params, fast) in cases.items():
            v = json.loads(self.files['workshop/%s.json' % part])
            self.assertEqual(self.b.workshop[part]['components'], n, part)
            self.assertEqual(v['params'], params, part)
            self.assertEqual(set(v['fasteners']), fast, part)
        undo = lambda part: [s['place'] for s in json.loads(self.files['workshop/%s.json' % part])['assembly']][::-1]
        # the gate valve taken apart (Crane p. 14): the packing, the bonnet nuts, the bonnet, the stem, then the wedge;
        # the seat rings never come out (the last in the reverse: they stay)
        u = undo('valve_gate')
        for a, b in (('packing', 'bonnet_bolts'), ('bonnet_bolts', 'bonnet'), ('bonnet', 'stem'), ('stem', 'wedge'),
                     ('handwheel', 'stem_nut'), ('stem_nut', 'bonnet')):
            self.assertLess(u.index(a), u.index(b), (a, b))
        # the globe valve (Crane §J, p. 18): the actuator off first (its bolts before it), then the packing, the
        # bonnet nuts, the bonnet, the stem and the disc
        u = undo('valve_globe')
        self.assertEqual(u[0], 'actuator_bolts')
        for a, b in (('actuator', 'packing'), ('packing', 'bonnet_bolts'), ('bonnet_bolts', 'bonnet'),
                     ('bonnet', 'stem'), ('stem', 'disc')):
            self.assertLess(u.index(a), u.index(b), (a, b))
        # the butterfly valve (Bray §13.1): the actuator off, the shaft out with its packing, the disc, the seat
        u = undo('valve_butterfly')
        self.assertEqual(u[0], 'actuator_bolts')
        for a, b in (('actuator', 'packing'), ('packing', 'shaft'), ('shaft', 'disc'), ('disc', 'liner')):
            self.assertLess(u.index(a), u.index(b), (a, b))

    def test_context(self):
        w = copy.deepcopy(self.fixture)
        w.pop('params', None)
        w['context'] = ['shaft_lo']
        W.check(w, None, 'w', parts={'test_gadget'})
        for bad, code in ((['nowhere'], 'bad_ref'), (['shaft_lo', 'shaft_lo'], 'dup_id'), ([], 'bad_length'),
                          ('shaft_lo', 'bad_type')):
            w['context'] = bad
            self.refused(w, code, kit=False)
        w['context'] = ['shaft_lo']
        w['params'] = {}
        self.refused(w, 'unknown_key', kit=False)

    def test_beyond(self):
        w = copy.deepcopy(self.fixture)
        g = next(iter(w['fasteners'].values()))
        g['joins'] = g['joins'][:1]
        self.refused(w, 'bad_length', kit=False)
        g['beyond'] = 'the next machine'
        W.check(w, None, 'w', parts={'test_gadget'})
        g['beyond'] = ''
        self.refused(w, 'bad_type', kit=False)

    def test_the_fixture_kind_passes(self):
        s = W.check(self.fixture, None, 'fixture', parts={'test_gadget'})
        self.assertEqual((s['components'], s['fasteners'], s['steps']), (3, 1, 4))
        # without being named as a fixture's kind it is no part
        with self.assertRaises(FormatError) as cm:
            W.check(self.fixture, self.b.kit, 'fixture')
        self.assertEqual(cm.exception.code, 'bad_ref')

    def test_strict_json(self):
        with self.assertRaises(FormatError) as cm:
            W.loads(b'{"format": "walkdown-plant-workshop", "format": 1}')
        self.assertEqual(cm.exception.code, 'bad_json')

    def test_keys_and_format(self):
        w = copy.deepcopy(self.fixture)
        w['torque'] = {}
        self.refused(w, 'unknown_key')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['torque_nm'] = 12     # torque and tools belong to the service file (§4.4)
        self.refused(w, 'unknown_key')
        w = copy.deepcopy(self.fixture)
        w['version'] = 2
        self.refused(w, 'bad_version')
        w = copy.deepcopy(self.fixture)
        del w['components']
        self.refused(w, 'missing_key')

    def test_ids_of_at_most_16(self):
        w = copy.deepcopy(self.fixture)
        w['components']['a_very_long_name_x'] = w['components'].pop('core')     # 18 characters
        self.refused(w, 'bad_id')
        w = copy.deepcopy(self.fixture)
        w['components']['abcdefghijklmnop'] = w['components'].pop('core')       # 16: fine, if nothing refers to core
        w['assembly'] = [s for s in w['assembly'] if s['place'] != 'core']
        w['assembly'][1]['needs'] = [['base', 'a', 'b']]
        w['assembly'].append({'place': 'abcdefghijklmnop', 'text': ['x'], 'sources': ['fixture']})
        W.check(w, None, 'w', parts={'test_gadget'})

    def test_texts_and_sealing(self):
        w = copy.deepcopy(self.fixture)
        w['components']['base']['name'] = 'x' * 61
        self.refused(w, 'bad_type')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['does'] = ''
        self.refused(w, 'bad_type')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['sealed'] = True
        self.refused(w, 'missing_key')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['sealed_why'] = 'Never opened.'
        self.refused(w, 'unknown_key')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['sealed'] = False
        self.refused(w, 'bad_value')

    def test_fasteners(self):
        w = copy.deepcopy(self.fixture)
        w['fasteners']['lid_screws']['joins'] = ['lid']
        self.refused(w, 'bad_length')
        w = copy.deepcopy(self.fixture)
        w['fasteners']['lid_screws']['joins'] = ['lid', 'nothing']
        self.refused(w, 'bad_ref')
        w = copy.deepcopy(self.fixture)
        w['fasteners']['base'] = w['fasteners'].pop('lid_screws')
        self.refused(w, 'dup_id')

    def test_sources(self):
        w = copy.deepcopy(self.fixture)
        w['components']['base']['sources'] = []
        self.refused(w, 'bad_length')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['sources'] = ['nowhere']
        self.refused(w, 'bad_ref')
        w = copy.deepcopy(self.fixture)
        w['sources'].append({'id': 'spare', 'cite': 'Cited by nothing', 'url': 'https://example.org/spare'})
        self.refused(w, 'unused')
        w = copy.deepcopy(self.fixture)
        w['sources'][0]['url'] = 'http://example.org/'
        self.refused(w, 'bad_link')
        w = copy.deepcopy(self.fixture)
        w['assembly'][0]['sources'] = []
        self.refused(w, 'bad_length')

    def test_assembly(self):
        w = copy.deepcopy(self.fixture)
        w['assembly'] = w['assembly'][:-1]             # the screws never placed
        self.refused(w, 'missing')
        w = copy.deepcopy(self.fixture)
        w['assembly'].append(copy.deepcopy(w['assembly'][0]))
        self.refused(w, 'dup_id')
        w = copy.deepcopy(self.fixture)
        w['assembly'][1], w['assembly'][2] = w['assembly'][2], w['assembly'][1]   # the lid before the core it needs
        self.refused(w, 'bad_order')
        w = copy.deepcopy(self.fixture)
        w['assembly'][2]['needs'][0] = ['ghost', 'a', 'b']
        self.refused(w, 'bad_ref')
        w = copy.deepcopy(self.fixture)
        w['assembly'][2]['needs'][0] = ['core', 'only one sentence']
        self.refused(w, 'bad_length')
        w = copy.deepcopy(self.fixture)
        w['assembly'][0]['text'] = 'not a run'
        self.refused(w, 'bad_type')
        w = copy.deepcopy(self.fixture)
        w['assembly'].insert(0, w['assembly'].pop())   # the screws before the lid and base they join
        self.refused(w, 'bad_order')

    def test_odd_values_are_refused_not_crashes(self):
        for path, value in ((('components', 'base', 'sources'), [['fixture']]),
                            (('fasteners', 'lid_screws', 'joins'), [['lid'], 'base']),
                            (('components', 'base', 'sources'), ['fixture', 'fixture'])):
            w = copy.deepcopy(self.fixture)
            w[path[0]][path[1]][path[2]] = value
            with self.assertRaises(FormatError, msg=str(value)):
                W.check(w, None, 'w', parts={'test_gadget'})
        w = copy.deepcopy(self.fixture)
        w['views'] = {'xray_all': [{}]}
        self.refused(w, 'bad_ref')

    def test_views(self):
        w = copy.deepcopy(self.fixture)
        w['views'] = {'xray_all': ['lid'], 'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}], 'keep': ['core']},
                      'run_exploded': {'allowed': ['lid'], 'why': 'Only the lid may be off while it runs.'},
                      'open_running': {'allowed': ['lid'], 'why': 'Switch it off first: only the lid opens live.'}}
        W.check(w, None, 'w', parts={'test_gadget'})
        w['views']['open_running']['allowed'] = ['ghost']
        self.refused(w, 'bad_ref')
        w['views']['open_running'] = {'allowed': ['lid']}
        self.refused(w, 'missing_key')
        del w['views']['open_running']
        w['views']['cutaway']['planes'][0]['normal'] = [1, 1, 0]
        self.refused(w, 'bad_number')
        w = copy.deepcopy(self.fixture)
        w['views'] = {'xray_all': ['ghost']}
        self.refused(w, 'bad_ref')
        w = copy.deepcopy(self.fixture)
        w['views'] = {'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}] * 3}}
        self.refused(w, 'bad_length')

    def test_the_content_check_reads_them(self):
        files = dict(self.files)
        files['workshop/pump_horizontal.json'] = files['workshop/pressure_transmitter.json']
        with self.assertRaises(FormatError) as cm:
            P.check_files(files)
        self.assertEqual(cm.exception.code, 'bad_ref')
        files = dict(self.files)
        w = json.loads(files['workshop/pressure_transmitter.json'])
        w['params'] = {'no_such_param': 1}
        files['workshop/pressure_transmitter.json'] = json.dumps(w).encode()
        with self.assertRaises(FormatError) as cm:
            P.check_files(files)
        self.assertEqual(cm.exception.code, 'unknown_key')
        files = dict(self.files)
        files['workshop/bench/x.json'] = b'{}'      # a bench model (K3) for a kind with no Workshop data file
        with self.assertRaises(FormatError) as cm:
            P.check_files(files)
        self.assertEqual(cm.exception.code, 'bad_ref')
        files = dict(self.files)
        files['workshop/benches/x.json'] = b'{}'    # no other folder
        with self.assertRaises(FormatError) as cm:
            P.check_files(files)
        self.assertEqual(cm.exception.code, 'unknown_key')


if __name__ == '__main__':
    unittest.main()
