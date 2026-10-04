#!/usr/bin/env python3
"""A procedure from another document (an engineering procedure, a work instruction) into the plant's data.

  python3 tools/procedure_import.py SPEC.json PLANT_DIR OUT_DIR

SPEC.json (plant-specific: keep it with the plant data, never in this repository):
  {"procedure": {"id", "title", "path": [...], "source", "intro",
                 "steps": [{"text", "kks": ["HAJ80AA501", ...], "photo": "fig2.jpg", "caption": "...",
                            "field": {"k": "...", "v": "..."}}]},
   "units": ["11", "12"]}
- `kks` without the unit: the document writes "xx…" for every unit. Each code is linked for every unit in `units`
  whose tag is on the plant's drawings (PLANT_DIR/tags.json), so a link always opens a drawing.
- `photo` (relative to SPEC.json) goes to every linked code as a photo: JPEG XL like the apps send (at most 1600 px on
  the longer side, distance 1.9, effort 7; needs cjxl).
- `field` sets that custom field on every linked code (equipment `custom`, PROTOCOL-v2 §9).

Writes PLANT_DIR/procedures.json (the procedure added or replaced, with its `source`; publish it with
`kks-server publish-data PLANT_DIR`) and OUT_DIR/submissions.json for `kks-server submit-file`: links, photos and
fields, written as the manager. Their client_ids are derived from the content, so running both again adds nothing."""
import base64, hashlib, json, os, subprocess, sys, tempfile


def jxl(path):
    from PIL import Image
    im = Image.open(path).convert('RGB')
    side = max(im.size)
    if side > 1600:
        im = im.resize((im.width * 1600 // side, im.height * 1600 // side), Image.LANCZOS)
    with tempfile.TemporaryDirectory() as d:
        png, out = os.path.join(d, 'in.png'), os.path.join(d, 'out.jxl')
        im.save(png)
        subprocess.run(['cjxl', png, out, '-d', '1.9', '-e', '7', '--quiet'], check=True)
        return open(out, 'rb').read()


def cid(*parts):
    return 'imp-' + hashlib.sha256('\x1f'.join(parts).encode()).hexdigest()[:40]


def main(spec_path, plant_dir, out_dir):
    spec = json.load(open(spec_path))
    pr, units = spec['procedure'], spec.get('units', ['11'])
    on_drawings = {t['kks'] for t in json.load(open(os.path.join(plant_dir, 'tags.json'))) if t.get('kks')}
    procs = json.load(open(os.path.join(plant_dir, 'procedures.json')))
    steps, subs, missing = [], [], []
    for n, st in enumerate(pr['steps'], 1):
        steps.append({'n': n, 'text': st['text']})
        codes = []
        for c in st.get('kks', []):
            found = [u + c for u in units if u + c in on_drawings]
            codes += found
            if not found:
                missing.append(c)
        for k in codes:
            subs.append({'kind': 'link', 'payload': {'proc': pr['id'], 'step': n, 'kks': k, 'on': True},
                         'client_id': cid('link', pr['id'], str(n), k)})
        if st.get('photo') and codes:
            data = jxl(os.path.join(os.path.dirname(os.path.abspath(spec_path)), st['photo']))
            url = 'data:image/jxl;base64,' + base64.b64encode(data).decode()
            for k in codes:
                subs.append({'kind': 'photo', 'payload': {'kks': k, 'caption': st.get('caption', ''), 'dataUrl': url},
                             'client_id': cid('photo', pr['id'], k, hashlib.sha256(data).hexdigest())})
        if st.get('field'):
            f = {'k': st['field']['k'], 'v': st['field']['v']}
            for k in codes:
                subs.append({'kind': 'equipment', 'payload': {'kks': k, 'changes': {'custom': [f]}, 'base': {'custom': []}},
                             'client_id': cid('field', k, f['k'], f['v'])})
    entry = {'id': pr['id'], 'title': pr['title'], 'path': pr.get('path', []), 'source': pr.get('source', ''),
             'intro': pr.get('intro', ''), 'steps': steps}
    procs = [p for p in procs if p['id'] != pr['id']] + [entry]
    tmp = os.path.join(plant_dir, 'procedures.json.tmp')
    with open(tmp, 'w') as f:
        json.dump(procs, f, ensure_ascii=False, indent=1)
    os.replace(tmp, os.path.join(plant_dir, 'procedures.json'))
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'submissions.json'), 'w') as f:
        json.dump(subs, f)
    kinds = {}
    for s in subs:
        kinds[s['kind']] = kinds.get(s['kind'], 0) + 1
    print(f"{pr['id']}: {len(steps)} steps in procedures.json; submissions {kinds}")
    if missing:
        print('not on any drawing (not linked):', ', '.join(sorted(set(missing))))


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
