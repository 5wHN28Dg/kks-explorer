"""Shared by the budget scripts (budgets.json, .github/workflows/budgets.yml): reading the budgets, writing results.

A result file is JSON: {"metrics": {KEY: {"value": median, "runs": [...], "unit": ...}}, "where": ..., "notes": ...}.
KEY names the threshold it is compared with in budgets.json:
  native.<platform>.startupMs | memoryMB | installedSizeMB
  web.bundles[<name>]   web.lab.lcpMs | cls | tbtMs
  custom[<name>]
check.py reads every result file and compares."""
import json, os, statistics

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))


def budgets():
    with open(os.path.join(REPO, 'budgets.json'), encoding='utf-8') as f:
        return json.load(f)


def runs_for(section, name=None):
    """the number of runs budgets.json states for a native platform, the web lab or a custom metric"""
    b = budgets()
    if section == 'native':
        return int(b['native'][name]['runs'])
    if section == 'lab':
        return int(b['web']['lab']['runs'])
    for c in b.get('custom', []):
        if c['name'] == name:
            return int(c.get('runs', 1))
    raise KeyError(name)


def median(xs):
    return statistics.median(xs)


def write(path, metrics, **extra):
    """metrics: {KEY: (runs list, unit)}; the median of the runs is the value compared"""
    out = {'metrics': {k: {'value': median(r), 'runs': r, 'unit': u} for k, (r, u) in metrics.items()}}
    out.update(extra)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=2)
    for k, v in out['metrics'].items():
        print(f'{k}: median {v["value"]} {v["unit"]} of {v["runs"]}', flush=True)
    return out


def tree_bytes(*paths):
    """bytes of the regular files under the paths (symlinks not followed: a link is not a second copy)"""
    n = 0
    for p in paths:
        if os.path.isfile(p) and not os.path.islink(p):
            n += os.path.getsize(p)
            continue
        for d, _, fs in os.walk(p):
            for f in fs:
                q = os.path.join(d, f)
                if not os.path.islink(q):
                    n += os.path.getsize(q)
    return n


MB = 1024 * 1024
