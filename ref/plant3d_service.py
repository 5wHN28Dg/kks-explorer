"""A part kind's service file (docs/plant3d/REALISM.md §2.4, §2.16; milestone HW2): what the Workshop leaves out of its
scope, keyed by its component ids. Not read by the engine: the content tool makes the model's hand actions, meters and
HART ops from it, and the app's work view takes its words (the actions' titles, the states' and meters' words) and
anchors from it. Checked here so that both read only a checked file."""
import re

from ref.plant3d import FormatError, need, keys, ident  # noqa: F401
from ref.courses import is_num

IDENT = re.compile(r'[a-z_][a-z0-9_]*\Z')
ALIAS_MAX, STATE_MAX = 8, 6
KKS = re.compile(r'[0-9A-Z]{1,16}\Z')


def _text(x, w, n):
    need(isinstance(x, str) and 0 < len(x) <= n, 'bad_value', f'{w}: text of 1–{n} characters')


def _name(x, w):
    need(isinstance(x, str) and re.fullmatch(r'[$@]?_?[a-z0-9_]+', x or '') is not None and len(x) <= 40, 'bad_value',
         f'{w}: a value name (with $_ for the alias, @_ for the loop)')


def check(s, workshop, tools, rel):
    """s: the parsed file; workshop: its kind's checked Workshop data; tools: tools.json's ids (or None)."""
    need(isinstance(s, dict), 'bad_type', rel)
    keys(s, ('format', 'version', 'part', 'sources', 'equipment', 'states', 'values', 'actions', 'meters', 'hart'),
         ('consts',), rel)
    need(s['format'] == 'walkdown-plant-service' and s['version'] == 1, 'bad_value', f'{rel}: format and version')
    need(s['part'] == workshop['part'], 'bad_ref', f'{rel}: part')
    need(tools is not None, 'missing_key', f'{rel}: a service file needs tools.json')
    comps = set(workshop['components']) | set(workshop.get('fasteners', {}))
    srcs = set()
    for x in s['sources']:
        keys(x, ('id', 'cite'), ('url',), f'{rel}: source')
        ident(x['id'], f'{rel}: source')
        need(x['id'] not in srcs, 'dup_id', f'{rel}: source {x["id"]}')
        srcs.add(x['id'])
        _text(x['cite'], f'{rel}: source {x["id"]}', 400)
    need(1 <= len(s['equipment']) <= 64, 'limit', f'{rel}: 1–64 pieces of equipment')
    seen = set()
    for e in s['equipment']:
        w = f'{rel}: equipment'
        keys(e, ('kks', 'alias', 'loop'), (), w)
        need(isinstance(e['kks'], str) and KKS.match(e['kks']) is not None, 'bad_value', f'{w}: kks')
        for k, n in (('alias', ALIAS_MAX), ('loop', 16)):
            need(isinstance(e[k], str) and IDENT.match(e[k]) is not None and len(e[k]) <= n, 'bad_id',
                 f'{w} {e["kks"]}: {k}, an identifier of at most {n} characters (§2.4)')
        need(e['alias'] not in seen and e['kks'] not in seen, 'dup_id', f'{w} {e["kks"]}')
        seen |= {e['alias'], e['kks']}
    made = set()
    for c, v in s.get('consts', []):
        ident(c, f'{rel}: const')
        need(isinstance(v, (int, float)) and not isinstance(v, bool), 'bad_type', f'{rel}: const {c}')
        made.add(c)
    for i, x in enumerate(s['states']):
        w = f'{rel}: state {i}'
        need(isinstance(x, list) and len(x) == 3, 'bad_type', w)
        comp, st, words = x
        need(comp in comps, 'bad_ref', f'{w}: {comp} is not in the Workshop\'s tree')
        need(isinstance(st, str) and IDENT.match(st) is not None and len(st) <= STATE_MAX, 'bad_id',
             f'{w}: a state of at most {STATE_MAX} characters (§2.4)')
        _text(words, w, 200)
        need(f'$_{comp}_{st}' not in made, 'dup_id', w)
        made.add(f'$_{comp}_{st}')
    for name, node in s['values']:
        _name(name, f'{rel}: value')
        need(name not in made, 'dup_id', f'{rel}: value {name}')
        need(isinstance(node, dict) and len(node) == 1, 'bad_type', f'{rel}: value {name}: one node')
        made.add(name)
    # the loop's values, the model's own content (the ohms a wet terminal side reads: HW3)
    loop = {'$_ma', '$_ma_tx', '@_tx', '@_trim', '$_ohm_v'}
    acts = set()
    for a in s['actions']:
        keys(a, ('action', 'title', 'component'), ('set', 'input', 'range', 'tools', 'wrong', 'needs', 'minutes',
                                                   'anchors', 'sources'), f'{rel}: action')
        w = f'{rel}: action {a["action"]}'
        ident(a['action'], w)
        need((a['action'], a['component']) not in acts and a['action'] not in {x for x, _ in acts}, 'dup_id', w)
        acts.add((a['action'], a['component']))
        _text(a['title'], w, 80)
        need(a['component'] in comps, 'bad_ref', f'{w}: {a["component"]} is not in the Workshop\'s tree')
        for t in a.get('tools', []) + list(a.get('wrong', {})):
            need(t in tools, 'bad_ref', f'{w}: tool {t} is not in tools.json')
        for t, sentence in a.get('wrong', {}).items():
            _text(sentence, f'{w}: wrong {t}', 200)
        for n, sentence in a.get('needs', []):
            need(n in made, 'bad_ref', f'{w}: needs {n}, which the file doesn\'t make')
            _text(sentence, f'{w}: needs {n}', 200)
        # a value the person gives (HW3: the loop test's current) is written into a component state, in its range
        need('set' in a or 'input' in a, 'missing_key', f'{w}: set or input')
        need(('input' in a) == ('range' in a), 'missing_key', f'{w}: an input comes with its range')
        for n in list(a.get('set', {})) + ([a['input']] if 'input' in a else []):
            need(isinstance(n, str) and n.startswith('$_') and n in made and n not in dict(s['values']), 'bad_ref',
                 f'{w}: sets {n}, not a component state')
        if 'range' in a:
            need(isinstance(a['range'], list) and len(a['range']) == 2 and all(is_num(x) for x in a['range'])
                 and a['range'][0] <= a['range'][1], 'bad_number', f'{w}: range')
        for x in a.get('sources', []):
            need(x in srcs, 'bad_ref', f'{w}: source {x}')
    ids = set()
    for mt in s['meters']:
        keys(mt, ('id', 'title', 'point', 'tool_kind', 'mode', 'value', 'needs', 'else'), ('unit',), f'{rel}: meter')
        w = f'{rel}: meter {mt["id"]}'
        need(mt['id'] not in ids, 'dup_id', w)
        ids.add(mt['id'])
        _text(mt['title'], w, 80)
        for n in [mt['value']] + mt['needs'] + ([mt['else']] if isinstance(mt['else'], str) else []):
            need(n in made or n in loop, 'bad_ref', f'{w}: {n}, which nothing makes')
    for h in s['hart']:
        keys(h, ('do', 'title', 'input', 'range', 'hart'), ('unit', 'sources', 'needs'), f'{rel}: HART op')
        _text(h['title'], f'{rel}: HART op', 80)
        need(h['input'] in loop | made and h['hart'] in made, 'bad_ref', f'{rel}: HART op {h["do"]}')
        for n, sentence in h.get('needs', []):
            need(n in made or n in loop, 'bad_ref', f'{rel}: HART op {h["do"]}: needs {n}, which nothing makes')
            _text(sentence, f'{rel}: HART op {h["do"]}: a need\'s sentence', 200)
    for a in s['actions']:     # (the anchors are the generator's: the content build checks them, WORKSHOP.md §4.1)
        for n in a.get('anchors', []):
            ident(n, f'{rel}: action {a["action"]}: anchor')
    return s
