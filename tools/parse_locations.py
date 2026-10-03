#!/usr/bin/env python3
"""Parse 'KKS LOCATION HRSG.pdf' (Word table: KKS | Level (cabinet) | Cabinet | Description | Direction) into
plant-data/locations.json (then: kks-server publish-data, wiki: Server). Needs poppler's pdftotext. The list has no unit prefix, so entries are keyed by the 9/10-char
KKS body (e.g. LAB93AA001) and apply to any unit number.
Usage: python3 tools/parse_locations.py "source/KKS LOCATION HRSG.pdf" [plant-data/locations.json]"""
import html, json, re, subprocess, sys
COLS = [('kks', 0), ('level', 160), ('cabinet', 255), ('desc', 350), ('direction', 445)]  # left edges, PDF points
KKS = re.compile(r'^[A-Z]{3}\d{2}[A-Z]{2}\d{3,4}$')

def col(x):
    return [n for n, x0 in COLS if x >= x0][-1]

def parse(pdf):
    out = subprocess.run(['pdftotext', '-bbox', pdf, '-'], capture_output=True, text=True, check=True).stdout
    rows = []
    for pno, pg in enumerate(out.split('<page')[1:], 1):
        words = [(float(m[2]), float(m[1]), html.unescape(m[3])) for m in
                 re.finditer(r'xMin="([\d.]+)" yMin="([\d.]+)" [^>]*>([^<]*)<', pg)]
        words.sort()
        page_rows = []
        for y, x, w in words:
            if col(x) == 'kks' and KKS.match(w):
                page_rows.append({'y': y, 'page': pno, 'kks': w, 'level': [], 'cabinet': [], 'desc': [], 'direction': []})
            elif page_rows and col(x) != 'kks':
                # wrapped cell text belongs to the last row that starts at or above this line
                r = [r for r in page_rows if r['y'] <= y + 2][-1]
                r[col(x)].append((y, x, w))
        rows += page_rows
    res = []
    for r in rows:
        e = {'kks': r['kks'], 'page': r['page']}
        for c in ('level', 'cabinet', 'desc', 'direction'):
            words = sorted(r[c], key=lambda t: (round(t[0]), t[1]))
            v = ' '.join(w for _, _, w in words).strip()
            if v and v != '*': e[c] = v
        res.append(e)
    return res

def elevation(level):
    """'3m' / '0.0m' -> 3.0 / 0.0; 'OUT HRSG' -> None."""
    m = re.fullmatch(r'(\d+(?:\.\d+)?)\s*m', level or '')
    return float(m[1]) if m else None

if __name__ == '__main__':
    pdf = sys.argv[1]; dst = sys.argv[2] if len(sys.argv) > 2 else 'plant-data/locations.json'
    res = parse(pdf)
    for e in res:
        z = elevation(e.get('level'))
        if z is not None: e['elev_m'] = z
    head = json.dumps({'source': pdf.split('/')[-1], 'note': 'No unit prefix in source; matched on KKS without the 2-digit unit.'})
    with open(dst, 'w') as f:  # one entry per line so diffs stay readable
        f.write(head[:-1] + ',\n "entries": [\n' + ',\n'.join('  ' + json.dumps(e) for e in res) + '\n]}\n')
    print(len(res), 'rows ->', dst)
