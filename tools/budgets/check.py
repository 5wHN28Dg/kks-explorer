"""Compare the measured medians with budgets.json (NAT-7, WEB-15, OTH-5).
  python3 tools/budgets/check.py RESULTS_DIR [SUMMARY.md]
Reads every *.json under RESULTS_DIR (budgetlib.write's format). Every threshold measured in CI must have a value:
a missing one fails like a value past its threshold. Startup and memory of a platform marked "release-test" are
measured on the device before a release (docs/m6/MEASUREMENTS.md), not here; its installed size is checked here.
Writes a Markdown table to SUMMARY.md (or $GITHUB_STEP_SUMMARY) and exits 1 on any failure."""
import glob, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import budgetlib  # noqa: E402


def expected(b):
    """[(key, 'max'|'min', threshold, label)] for everything CI must measure"""
    out = []
    for bn in b.get('web', {}).get('bundles', []):
        out.append((f'web.bundles[{bn["name"]}]', 'max', bn['maxKB'], f'bundle {bn["name"]} ({bn["compression"]}), KB'))
    lab = b.get('web', {}).get('lab')
    if lab:
        for k, label in (('lcpMs', 'lab LCP, ms'), ('cls', 'lab CLS'), ('tbtMs', 'lab TBT, ms')):
            out.append((f'web.lab.{k}', 'max', lab[k], label))
    for plat, m in b.get('native', {}).items():
        if m.get('measuredWhere', 'ci') == 'ci':
            out.append((f'native.{plat}.startupMs', 'max', m['startupMs'], f'{plat} startup, ms'))
            out.append((f'native.{plat}.memoryMB', 'max', m['memoryMB'], f'{plat} memory, MB'))
        out.append((f'native.{plat}.installedSizeMB', 'max', m['installedSizeMB'], f'{plat} installed size, MB'))
    for c in b.get('custom', []):
        if c['measuredWhere'] == 'ci':
            d = 'max' if 'max' in c else 'min'
            out.append((f'custom[{c["name"]}]', d, c[d], f'{c["name"]}, {c["unit"]}'))
    return out


def main():
    results = {}
    for f in sorted(glob.glob(os.path.join(sys.argv[1], '**', '*.json'), recursive=True)):
        if os.path.basename(f) == 'all-results.json':
            continue
        with open(f, encoding='utf-8') as fh:
            for k, v in json.load(fh).get('metrics', {}).items():
                if k in results:
                    sys.exit(f'{k} measured twice ({f})')
                results[k] = v
    rows, failed = [], []
    for key, d, limit, label in expected(budgetlib.budgets()):
        v = results.get(key)
        if v is None:
            failed.append(f'{key}: not measured')
            rows.append((label, f'{d} {limit}', 'not measured', '', 'FAIL'))
            continue
        bad = v['value'] > limit if d == 'max' else v['value'] < limit
        if bad:
            failed.append(f'{key}: {v["value"]} is past its {d} {limit}')
        rows.append((label, f'{d} {limit}', str(v['value']), ', '.join(map(str, v['runs'])), 'FAIL' if bad else 'ok'))
    md = ['| Metric | Budget | Median | Runs | |', '|---|---|---|---|---|']
    md += ['| ' + ' | '.join(r) + ' |' for r in rows]
    text = '\n'.join(md) + '\n'
    print(text)
    summary = sys.argv[2] if len(sys.argv) > 2 else os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as f:
            f.write('## Budgets (budgets.json)\n\n' + text)
    with open(os.path.join(sys.argv[1], 'all-results.json'), 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2)
    if failed:
        print('Past the budget or not measured:\n  ' + '\n  '.join(failed))
        sys.exit(1)


main()
