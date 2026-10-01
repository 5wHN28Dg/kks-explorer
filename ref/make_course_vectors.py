#!/usr/bin/env python3
"""Generate ref/vectors/courses-v1.json: synthetic test vectors for the course content format (docs/COURSES.md).
Synthetic on purpose: no plant content in the public vectors. FROZEN once a renderer uses it.
  python3 ref/make_course_vectors.py [--write]"""
import copy, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ref import courses as K

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vectors', 'courses-v1.json')


def R6(x):
    """Round floats for the file (readers compare to 1e-6)."""
    if isinstance(x, float):
        r = round(x, 9)
        return 0.0 if r == 0 else r
    if isinstance(x, list):
        return [R6(v) for v in x]
    if isinstance(x, dict):
        return {k: R6(v) for k, v in x.items()}
    return x


def choice(id, right=1):
    return {'type': 'choice', 'id': id, 'q': ['Which one?'], 'src': [],
            'options': [{'text': ['A'], 'right': right == 0, 'why': ['Because A.']},
                        {'text': ['B'], 'right': right == 1, 'why': []},
                        {'text': ['C'], 'right': right == 2, 'why': [{'b': ['No.']}]}]}


FIG_STATIC = {'title': 'A static chart', 'caption': ['A chart.'], 'alt': 'Two axes and a curve.', 'w': 200, 'h': 100,
              'scene': [{'line': [10, 90, 190, 90], 'stroke': 'muted'},
                        {'path': [['M', 10, 90], ['C', 60, 10, 140, 10, 190, 60]], 'stroke': 'accent', 'stroke_width': 2},
                        {'text': 'flow', 'at': [100, 98], 'anchor': 'middle', 'size': 10, 'fill': 'muted'}]}

FIG_VALVE = {
    'title': 'A valve', 'caption': ['Drag the slider.'], 'alt': 'A pipe with a sliding gate.', 'w': 300, 'h': 120,
    'period': 4,
    'slider': {'label': 'Opening', 'init': 0.5,
               'drive': {'of': 't', 'table': [[0, 0], [0.5, 1], [1, 0]]},
               'text': [{'when': 'shut', 'text': 'Closed'}, {'text': '{pct}% open'}]},
    'values': [['pct', {'product': ['v', 100]}],
               ['gate_y', {'of': 'v', 'table': [[0, 60], [1, 10]]}],
               ['flow', {'of': 'v', 'table': [[0, 0], [0.2, 50], [0.2, 60], [1, 100]]}],
               ['shut', {'of': 'v', 'table': [[0, 1], [0.01, 0]], 'step': True}],
               ['bottom', {'sum': ['gate_y', 50]}]],
    'scene': [{'rect': [0, 40, 300, 40], 'fill': 'accent', 'opacity': 0.2},
              {'flow': {'count': 5, 'routes': [{'path': [['M', 0, 60], ['L', 300, 60]]}], 'lanes': [[0, -10], [0, 10]],
                        'speed': 'flow', 'hide': [{'rect': [140, 0, 160, 'bottom'], 'when': 1}]}},
              {'rect': [140, 'gate_y', 20, 50], 'fill': 'muted', 'stroke': 'ink'},
              {'label': 'Gate', 'at': [150, 'gate_y'], 'to': [200, 20]},
              {'label': 'Seat', 'at': [150, 100], 'to': [120, 110], 'anchor': 'end'},
              {'label': 'Pipe', 'at': [20, 30], 'to': [10, 10]}],
    'status': '{pct:1}% open, flow {flow:+2} units'}

FIG_NODES = {
    'title': 'Nodes', 'caption': [], 'alt': 'Everything the value graph can do.', 'w': 100, 'h': 100, 'period': 2,
    'toggles': [{'key': 'on', 'label': 'Switch', 'on': False}],
    'modes': [{'key': 'a', 'label': 'A'}, {'key': 'b', 'label': 'B'}, {'key': 'c', 'label': 'C'}],
    'values': [['target', {'of': 't', 'table': [[0, 0], [0.5, 10]], 'step': True}],
               ['smooth', {'follow': 'target', 'rate': 4, 'rate_down': 1, 'init': 2}],
               ['wave', {'of': 't', 'table': [[0, -1.5], [0.25, 2.5], [0.5, -0.5], [1, -1.5]]}],
               ['frozen_while', {'of': 'mode', 'table': [[0, 0], [2, 1]], 'step': True}],
               ['held', {'hold': 'wave', 'while': 'frozen_while'}],
               ['pick', {'select': 'mode', 'cases': ['wave', 7, 'held']}],
               ['sw', {'select': 'on', 'cases': [0, 'smooth']}],
               ['mix', {'sum': ['pick', 'sw', -0.25]}],
               ['neg', {'product': ['mix', -1, 0.5]}],
               ['hot', {'of': 'mix', 'table': [[-2, 0], [8, 1]]}]],
    'scene': [{'circle': [50, 50, 'hot'], 'fill': {'of': 'hot', 'stops': [[0, '#0000ff'], [1, '#ff0000']]},
               'stroke': {'of': 'mix', 'steps': [[-100, 'ink'], [0, 'act']]}, 'stroke_width': 'hot',
               'transform': [{'translate': ['neg', 0]}, {'rotate': ['wave', 50, 50]}, {'scale': [1, 'hot']}]},
              {'group': [{'poly': [[0, 0], ['mix', 'neg']], 'stroke': 'ink'}], 'clip': {'rect': [0, 0, 'hot', 100], 'rx': 2},
               'opacity': 'hot'},
              {'text': [{'when': 'on', 'text': 'on {smooth:3}'}, {'text': 'off {{{wave:+1}}}'}], 'at': [5, 95],
               'font': 'mono', 'weight': 700, 'fill': 'ink'}],
    'status': 'mix {mix:2} neg {neg:+0} held {held:1}'}

FIG_FLOWS = {
    'title': 'Flows', 'caption': [], 'alt': 'Particles on routes.', 'w': 200, 'h': 200, 'period': 3,
    'slider': {'label': 'Split', 'init': 0.25, 'text': '{v:2}'},
    'values': [['upper', {'of': 'v', 'table': [[0, 1], [1, 0]]}],
               ['spd', {'of': 't', 'table': [[0, 120], [0.5, 120], [0.5, -60], [1, -60]]}],
               ['ring', {'of': 't', 'table': [[0, 1], [1, 3]]}]],
    'scene': [
        {'flow': {'count': 7, 'speed': 90, 'r': 2, 'fill': 'accent',
                  'routes': [{'path': [['M', 0, 50], ['L', 200, 50]], 'weight': 'upper'},
                             {'path': [['M', 0, 150], ['C', 60, 100, 140, 200, 200, 150]], 'weight': 'v',
                              'lanes': [[0, 0], [0, 6], [3, -6]]}],
                  'along': {'speed': [[0, 1], [0.5, 2], [1, 1]], 'r': [[0, 1], [1, 2]], 'opacity': [[0, 1], [1, 0.2]],
                            'lane': [[0, 0], [0.5, 1], [1, 0]], 'fill': [[0, 'accent'], [0.6, 'act']]}}},
        {'flow': {'count': 6, 'speed': 'spd', 'reverse': 'pile', 'pile': 30,
                  'routes': [{'path': [['M', 20, 100], ['L', 180, 100]]}], 'stroke': 'ink', 'stroke_width': 0.5}},
        {'flow': {'count': 5, 'speed': 70, 'wrap_x': [40, 160], 'lanes': [[0, 0], [37, 0], [71, 0]],
                  'routes': [{'path': [['M', 40, 20], ['L', 120, 40], ['L', 120, 80]]}], 'glyph': 'burst', 'r': 'ring',
                  'stroke': 'act', 'stroke_width': 2, 'opacity': 0.8,
                  'hide': [{'rect': [100, 0, 140, 60], 'when': 'upper'}]}},
        {'flow': {'count': 3, 'speed': -45, 'routes': [{'path': [['M', 10, 190], ['L', 10, 110]]}]}}],
    'status': 'split {v:3}'}


def course():
    body = [{'h': ['Section'], 'level': 2}, {'h': ['Sub', {'i': ['section']}], 'level': 3},
            {'p': ['Pressure ', {'num': '12.44 MPa.a'}, ' is ', {'b': ['high']}, '. See ',
                   {'term': ['a relief valve'], 'gloss': 'Relief valve'}, ', ',
                   {'link': ['the next course'], 'to': {'course': 'other'}}, ', ',
                   {'link': ['the drill'], 'to': {'page': 'drill'}}, ', ',
                   {'link': ['this valve'], 'to': {'kks': '11LAB70AA501'}}, ' and ',
                   {'link': ['a standard'], 'to': {'url': 'https://example.org/std'}},
                   {'small': [' (small print)']}, '.']},
            {'ul': [['one'], ['two']]}, {'ol': [['first'], ['second']]},
            {'table': {'head': [['Name'], ['Value']], 'rows': [[['a'], ['1']], [['b'], []]], 'num': [1]}},
            {'callout': 'why', 'label': ['Why it matters'], 'body': [{'p': ['Because.']}]},
            {'callout': 'at_plant', 'label': ['At the plant'], 'body': [{'ul': [['here']]}]},
            {'cards': [[['Guess'], ['Answer first.']], [['Work'], ['Step by step.']]]},
            {'chain': [['fuel'], ['heat'], ['power']]},
            {'figure': 'valve'}, {'figure': 'chart'},
            {'image': {'file': 'photo-1.jxl', 'w': 1600, 'h': 1200, 'alt': 'A valve', 'caption': ['A valve.'],
                       'credit': ['Photo: someone, ', {'link': ['CC BY 4.0'], 'to': {'url': 'https://creativecommons.org/licenses/by/4.0'}}]}},
            {'tool': 'kks_decoder'}]
    m1 = {'kind': 'module', 'id': 'intro', 'n': '0', 'title': ['Start'], 'short': 'Start', 'goals': [['Know it.']],
          'warm': choice('w0', 0), 'body': body, 'worked': None, 'practice': []}
    m2 = {'kind': 'module', 'id': 'valves', 'n': '1', 'title': ['Valves'], 'short': 'Valves', 'goals': [],
          'warm': choice('w1'), 'body': [{'figure': 'nodes'}, {'figure': 'flows'}],
          'worked': {'case': ['How much flow?'], 'steps': [[['Look'], ['At the gate.']], [['Result'], ['61%.']]]},
          'practice': [choice('p1a', 2),
                       {'type': 'order', 'id': 'p1b', 'q': ['Order them.'], 'steps': [['one'], ['two'], ['three']],
                        'src': ['Manual §1']},
                       {'type': 'scenario', 'id': 'p1c', 'q': ['What now?'], 'src': [],
                        'panel': [{'name': ['Level'], 'value': ['+470 mm ↑'], 'state': 'alarm'},
                                  {'name': ['Flow'], 'value': ['305 t/h'], 'state': ''}],
                        'options': [{'text': ['Trip'], 'right': False, 'why': []},
                                    {'text': ['Reduce feed'], 'right': True, 'why': ['Yes.']}]}],
          'bridge': {'title': ['Bridge to the next course'], 'intro': [], 'questions': [choice('b1')]}}
    pages = [m1, m2,
             {'kind': 'placement', 'id': 'place', 'title': ['Placement'], 'intro': [],
              'items': [{'module': 'intro', 'q': choice('pl1')}, {'module': 'valves', 'q': choice('pl2')}]},
             {'kind': 'test', 'id': 'final', 'title': ['Final check'], 'intro': [{'p': ['Answer all.']}],
              'items': [{'module': 'intro', 'q': choice('f1')}, {'module': 'valves', 'q': choice('f2')},
                        {'module': 'valves', 'q': choice('f3')}, {'module': 'valves', 'ref': 'b1'}], 'draw': 2, 'pass': 2,
              'on_pass': [{'p': ['Done.']}], 'on_fail': [{'p': ['Revisit these:']}]},
             {'kind': 'vocab_drill', 'id': 'drill', 'title': ['Vocabulary'], 'intro': []},
             {'kind': 'reading_drill', 'id': 'reading', 'title': ['Readings'], 'intro': [],
              'items': [{'cat': 'Levels', 'name': ['Drum level'], 'unit': 'mm', 'context': ['at load'],
                         'values': [-50, 400, 450, -460, 560], 'note': ['Alarm +400 / −450, trip +550.'],
                         'rules': [['>=', 550, 'act'], ['<=', -550, 'act'], ['>=', 400, 'alarm'], ['<=', -450, 'alarm']]}]},
             {'kind': 'glossary', 'id': 'gloss', 'title': ['Glossary'], 'intro': []},
             {'kind': 'page', 'id': 'issues', 'title': ['Issues'], 'eyebrow': 'Reference', 'intro': [],
              'body': [{'issues': [['high', ['Units'], ['Gauge or absolute?']], ['low', ['Typo'], ['Minor.']]]}]}]
    gloss = [{'term': t, 'meaning': [m], 'module': mod} for t, m, mod in (
        ('Relief valve', 'opens above a set pressure', 'valves'), ('Gate valve', 'isolates', 'valves'),
        ('Globe valve', 'throttles', 'valves'), ('Efficiency', 'output over input', 'intro'))]
    return {'format': 'kks-course', 'version': 1, 'id': 'demo', 'title': 'Demo course', 'short': 'Demo', 'order': 1,
            'figures': copy.deepcopy({'valve': FIG_VALVE, 'chart': FIG_STATIC, 'nodes': FIG_NODES, 'flows': FIG_FLOWS}),
            'glossary': gloss, 'pages': pages}


def minimal():
    return {'format': 'kks-course', 'version': 1, 'id': 'tiny', 'title': 'Tiny', 'short': 'Tiny', 'order': 0,
            'figures': {}, 'glossary': [],
            'pages': [{'kind': 'page', 'id': 'only', 'title': ['Only'], 'eyebrow': '', 'intro': [], 'body': [{'p': ['Hi']}]}]}


def mutations():
    """(why, code, function that breaks a copy of the demo course)."""
    def page(d, pid):
        return next(p for p in d['pages'] if p['id'] == pid)

    def fig(d, fid):
        return d['figures'][fid]
    M = [
        ('unknown top-level key', 'unknown_key', lambda d: d.update(extra=1)),
        ('missing pages', 'missing_key', lambda d: d.pop('pages')),
        ('version 2', 'bad_version', lambda d: d.update(version=2)),
        ('capital letter in course id', 'bad_id', lambda d: d.update(id='Demo')),
        ('two pages with one id', 'dup_id', lambda d: d['pages'].append(copy.deepcopy(d['pages'][-1]))),
        ('empty run', 'bad_length', lambda d: page(d, 'intro')['body'].append({'p': []})),
        ('two kinds in one block', 'bad_kind', lambda d: page(d, 'intro')['body'].append({'p': ['a'], 'h': ['b']})),
        ('heading level 1', 'bad_value', lambda d: page(d, 'intro')['body'].append({'h': ['x'], 'level': 1})),
        ('table row too short', 'bad_length',
         lambda d: page(d, 'intro')['body'][5]['table']['rows'].append([['only one']])),
        ('numeric column out of range', 'bad_number', lambda d: page(d, 'intro')['body'][5]['table'].update(num=[2])),
        ('figure inside a callout', 'bad_kind',
         lambda d: page(d, 'intro')['body'][6]['body'].append({'figure': 'valve'})),
        ('link to a missing page', 'bad_ref',
         lambda d: page(d, 'intro')['body'].append({'p': [{'link': ['x'], 'to': {'page': 'nowhere'}}]})),
        ('http link', 'bad_link',
         lambda d: page(d, 'intro')['body'].append({'p': [{'link': ['x'], 'to': {'url': 'http://example.org'}}]})),
        ('KKS link with spaces', 'bad_link',
         lambda d: page(d, 'intro')['body'].append({'p': [{'link': ['x'], 'to': {'kks': '11 LAB 70'}}]})),
        ('unknown glossary term', 'bad_ref',
         lambda d: page(d, 'intro')['body'].append({'p': [{'term': ['x'], 'gloss': 'Nothing'}]})),
        ('missing figure', 'bad_ref', lambda d: page(d, 'intro')['body'].append({'figure': 'nope'})),
        ('unused figure', 'unused_figure', lambda d: d['figures'].update(spare=copy.deepcopy(FIG_STATIC))),
        ('image that is not JPEG XL', 'bad_value', lambda d: page(d, 'intro')['body'][12]['image'].update(file='a.jpg')),
        ('choice with two right options', 'bad_question',
         lambda d: page(d, 'valves')['practice'][0]['options'][0].update(right=True)),
        ('choice with one option', 'bad_length',
         lambda d: page(d, 'valves')['practice'][0].update(options=page(d, 'valves')['practice'][0]['options'][:1])),
        ('order with two steps', 'bad_length', lambda d: page(d, 'valves')['practice'][1]['steps'].pop()),
        ('scenario reading state', 'bad_value',
         lambda d: page(d, 'valves')['practice'][2]['panel'][0].update(state='red')),
        ('question id with a copy suffix', 'bad_id', lambda d: page(d, 'valves')['practice'][0].update(id='p1a_r')),
        ('question id used twice', 'dup_id', lambda d: page(d, 'valves')['practice'][1].update(id='p1a')),
        ('test item from a missing module', 'bad_ref', lambda d: page(d, 'final')['items'][0].update(module='gone')),
        ('test item refers to another module\'s question', 'bad_ref',
         lambda d: page(d, 'final')['items'][3].update(module='intro')),
        ('test item refers to a missing question', 'bad_ref', lambda d: page(d, 'final')['items'][3].update(ref='zz')),
        ('test item with a question and a reference', 'unknown_key',
         lambda d: page(d, 'final')['items'][3].update(q=choice('f9'))),
        ('placement item by reference', 'missing_key',
         lambda d: page(d, 'place')['items'].append({'module': 'valves', 'ref': 'b1'})),
        ('bridge without questions', 'bad_length', lambda d: page(d, 'valves')['bridge'].update(questions=[])),
        ('bridge without a title', 'missing_key', lambda d: page(d, 'valves')['bridge'].pop('title')),
        ('test pass mark above the draw', 'bad_number', lambda d: page(d, 'final').update(**{'pass': 3})),
        ('reading drill rule operator', 'bad_value',
         lambda d: page(d, 'reading')['items'][0]['rules'].append(['==', 1, 'act'])),
        ('unknown page kind', 'bad_kind', lambda d: page(d, 'gloss').update(kind='quiz')),
        ('glossary term twice', 'dup_id', lambda d: d['glossary'].append(copy.deepcopy(d['glossary'][0]))),
        # figures
        ('figure without alt text', 'bad_value', lambda d: fig(d, 'valve').update(alt='')),
        ('static figure with a status', 'static_inputs', lambda d: fig(d, 'chart').update(status='x')),
        ('static figure with a flow', 'static_inputs',
         lambda d: fig(d, 'chart')['scene'].append(copy.deepcopy(FIG_VALVE['scene'][1]))),
        ('period 0', 'bad_number', lambda d: fig(d, 'valve').update(period=0)),
        ('drive over the slider value', 'bad_drive', lambda d: fig(d, 'valve')['slider']['drive'].update(of='v')),
        ('value reads a later value', 'forward_ref', lambda d: fig(d, 'valve')['values'][0][1].update(product=['gate_y', 2])),
        ('value reads an unknown name', 'bad_ref', lambda d: fig(d, 'valve')['values'][0][1].update(product=['nope', 2])),
        ('value named like an input', 'dup_id', lambda d: fig(d, 'valve')['values'].append(['t', {'sum': [1]}])),
        ('table x decreases', 'bad_table', lambda d: fig(d, 'valve')['values'][1][1].update(table=[[1, 0], [0, 1]])),
        ('three table points at one x', 'bad_table',
         lambda d: fig(d, 'valve')['values'][1][1].update(table=[[0, 0], [0.5, 1], [0.5, 2], [0.5, 3]])),
        ('follow with rate 0', 'bad_number', lambda d: fig(d, 'nodes')['values'][1][1].update(rate=0)),
        ('unknown paint token', 'bad_paint', lambda d: fig(d, 'valve')['scene'][0].update(fill='blue')),
        ('colour scale with a token', 'bad_paint',
         lambda d: fig(d, 'nodes')['scene'][0]['fill']['stops'].append([2, 'ink'])),
        ('gradient on a stroke', 'bad_paint',
         lambda d: fig(d, 'valve')['scene'][0].update(stroke={'radial': [[0, 'ink', 1], [1, 'ink', 0]]})),
        ('template with an unknown name', 'bad_ref', lambda d: fig(d, 'valve').update(status='{nope}')),
        ('template with a stray brace', 'bad_template', lambda d: fig(d, 'valve').update(status='50 {% open')),
        ('text cases: last one has a condition', 'unknown_key',
         lambda d: fig(d, 'valve')['slider'].update(text=[{'when': 'shut', 'text': 'x'}, {'when': 'shut', 'text': 'y'}])),
        ('path starting with a line', 'bad_path', lambda d: fig(d, 'chart')['scene'][1]['path'].insert(0, ['L', 0, 0])),
        ('route with a close', 'bad_path',
         lambda d: fig(d, 'valve')['scene'][1]['flow']['routes'][0]['path'].append(['Z'])),
        ('flow of 201 particles', 'bad_number', lambda d: fig(d, 'valve')['scene'][1]['flow'].update(count=201)),
        ('wrap_x reversed', 'bad_value', lambda d: fig(d, 'flows')['scene'][2]['flow'].update(wrap_x=[160, 40])),
        ('unknown element key', 'unknown_key', lambda d: fig(d, 'valve')['scene'][0].update(blur=2)),
        ('number too large', 'bad_number', lambda d: fig(d, 'chart')['scene'][0].update(line=[0, 0, 1e9, 0])),
        ('boolean where a number goes', 'bad_number', lambda d: fig(d, 'chart')['scene'][0].update(line=[0, 0, True, 0])),
    ]
    return M


def frames():
    """Event scripts per figure and the evaluation after each step."""
    scripts = {
        'valve': [('tick', 0.02)] * 3 + [('tick', 0.5), ('tick', 0.05), ('slider', 0.001), ('tick', 0.05),
                                          ('slider', 0.9), ('tick', 0.04), ('play',), ('tick', 0.05), ('pause',),
                                          ('tick', 0.05)],
        'nodes': [('tick', 0.05)] * 6 + [('toggle', 'on'), ('tick', 0.05), ('tick', 0.05), ('mode', 2), ('tick', 0.05),
                                         ('tick', 0.05), ('tick', 0.05), ('mode', 1), ('tick', 0.05), ('mode', 2),
                                         ('tick', 0.05)] + [('tick', 0.05)] * 20,
        'flows': [('tick', 0.05)] * 8 + [('slider', 0.9)] + [('tick', 0.05)] * 30 + [('tick', 0.05)] * 5,
        'chart': [('tick', 0.05)],
    }
    out = []
    for fid, events in scripts.items():
        f = course()['figures'][fid]
        for reduce in (False, True) if fid == 'valve' else (False,):
            ev = K.Figure(f, reduce_motion=reduce)
            steps = [{'event': ['init'], 'state': snapshot(ev)}]
            for e in events:
                if e[0] == 'tick':
                    ev.tick(e[1])
                elif e[0] == 'slider':
                    ev.set_slider(e[1])
                elif e[0] == 'toggle':
                    ev.toggle(e[1])
                elif e[0] == 'mode':
                    ev.set_mode(e[1])
                elif e[0] == 'play':
                    ev.play()
                else:
                    ev.pause()
                steps.append({'event': list(e), 'state': snapshot(ev) if e[0] == 'tick' else None})
            out.append({'figure': fid, 'reduce_motion': reduce, 'steps': [R6(s) for s in steps]})
    return out


def snapshot(ev):
    return {'t': ev.t, 'v': ev.v, 'playing': ev.playing, 'values': dict(ev.vals), 'scene': ev.scene(),
            'status': ev.status(), 'slider_text': ev.slider_text()}


def units():
    """Small functions every renderer implements identically."""
    tables = [[[0, 0], [1, 10]], [[0, 5]], [[0, 0], [0.5, 1], [0.5, 3], [1, 4]], [[-1, 2], [0, 2], [2, -2]]]
    probes = [-2, -1, 0, 0.25, 0.5, 0.75, 1, 1.5, 3]
    U = {'table': [{'table': t, 'step': s, 'at': [[u, K.table_at(t, u, s)] for u in probes]}
                   for t in tables for s in (False, True)]}
    U['format'] = [[x, d, sgn, K.fmt_number(x, d, sgn)] for x, d, sgn in [
        (0, 0, False), (0, 0, True), (-0.4, 0, False), (-0.4, 0, True), (0.5, 0, False), (-0.5, 0, False),
        (1.5, 0, False), (2.5, 0, False), (2.675, 2, False), (-1.005, 2, True), (1234567.891, 1, False),
        (0.125, 2, False), (-7.25, 1, True), (99.95, 1, False), (1e-7, 6, False), (-3, 0, True), (3, 3, True)]]
    U['template'] = [[s, vals, K.fill_template(s, vals)] for s, vals in [
        ('{a}', {'a': 2.5}), ('{a:2} and {b:+1}', {'a': 1 / 3, 'b': -0.04}), ('{{{a}}}', {'a': 7}),
        ('no fields', {}), ('{a:+0}°', {'a': -0.2})]]
    U['colour'] = [[stops, u, K.colour_at(stops, u)] for stops, u in [
        ([[0, '#000000'], [1, '#ffffff']], 0.5), ([[0, '#000000'], [1, '#ffffff']], 0.502),
        ([[0, '#102030'], [10, '#ff8000'], [20, '#00ff00']], 15), ([[0, '#102030'], [10, '#ff8000']], -5),
        ([[0, '#102030'], [10, '#ff8000']], 10)]]
    U['leader'] = [[lab, at, to, anc, K.leader_end(lab, at, to, anc)] for lab, at, to, anc in [
        ('Gate', [150, 60], [200, 20], 'start'), ('Seat', [150, 100], [120, 110], 'end'),
        ('Pipe', [20, 30], [10, 10], 'start'), ('Pipe', [20, 5], [10, 10], 'start'), ('Longer label', [40, 90], [30, 50], 'end')]]
    item = {'rules': [['>=', 550, 'act'], ['<=', -550, 'act'], ['>=', 400, 'alarm'], ['<', -450, 'alarm'], ['>', 100, 'alarm']]}
    U['judge'] = {'item': item, 'cases': [[v, K.judge(item, v)] for v in (-600, -550, -450, -451, 0, 100, 101, 400, 549, 550)]}
    U['choose'] = []
    for weights in ([1, 1], [0.25, 0.75], [0, 1], [0, 0], [3, 0, 1]):
        fl = {'count': 5, 'routes': [{'path': [['M', 0, 0], ['L', 1, 0]], 'weight': w} for w in weights]}
        ev = K.Figure({'title': 'x', 'caption': [], 'alt': 'x', 'w': 1, 'h': 1, 'period': 1, 'scene': [{'flow': fl}]})
        U['choose'].append({'count': 5, 'weights': weights,
                            'routes': [[ev._choose(fl, i, n) for n in range(4)] for i in range(5)]})
    U['flatten'] = []
    for path in ([['M', 0, 0], ['L', 3, 4], ['L', 3, 10]], [['M', 0, 0], ['C', 0, 10, 10, 10, 10, 0]]):
        pts, segs, L = K.flatten(path, lambda r: r)
        U['flatten'].append({'path': path, 'points': [list(p) for p in pts], 'length': L,
                             'at': [[d, list(K.point_at(pts, segs, d))] for d in (0, L / 3, L / 2, L)]})
    return R6(U)


def build():
    V = {'format': 'kks-course', 'version': 1,
         'note': 'Course format vectors (docs/COURSES.md). Numbers compare to 1e-6. Readers must load every valid '
                 'course with the given counts, refuse every reject with its code, and reproduce every frame.'}
    demo = course()
    V['valid'] = [{'why': 'every block, page, question and figure feature', 'course': demo,
                   'images': ['photo-1.jxl'], 'counts': K.check_course(demo, {'photo-1.jxl'})},
                  {'why': 'the smallest course', 'course': minimal(), 'images': [],
                   'counts': K.check_course(minimal(), set())}]
    rej = []
    for why, code, fn in mutations():
        d = course()
        fn(d)
        try:
            K.check_course(d, {'photo-1.jxl'})
        except K.FormatError as e:
            assert e.code == code, (why, e.code, code)
            rej.append({'why': why, 'code': code, 'course': d})
            continue
        raise AssertionError('accepted: ' + why)
    rej.append({'why': 'image file not in the published version', 'code': 'bad_ref', 'course': demo, 'images': []})
    try:
        K.check_course(demo, set())
        raise AssertionError('accepted missing image')
    except K.FormatError as e:
        assert e.code == 'bad_ref'
    V['reject'] = rej
    V['frames'] = frames()
    V['units'] = units()
    return V


def dump(V):
    return json.dumps(V, indent=None, sort_keys=True, ensure_ascii=False, separators=(',', ':')) + '\n'


if __name__ == '__main__':
    text = dump(build())
    if '--write' in sys.argv:
        with open(OUT, 'w', encoding='utf-8') as f:
            f.write(text)
    print('courses-v1.json', len(text) // 1024, 'KB')
