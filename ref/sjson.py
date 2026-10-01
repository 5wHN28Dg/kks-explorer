"""Strict JSON reading (PROTOCOL-v2 §1, decision 0029), test-only reference. Built on Python's parser with hooks, so
it is an implementation independent of the Nim core's hand-written reader.

typed(value) gives the vectors' typed form, which keeps integers, big integers and floats apart:
  {"t": "null"|"bool"|"int"|"big"|"float"|"str"|"arr"|"obj", "v": …}   (obj: [[key, node], …] in input order)"""
import json

MAX_DEPTH = 128
INT_MAX = 2 ** 63 - 1


class StrictError(ValueError):
    pass


class Float(float):
    """A float read from the input (kept apart from integers even when integral, e.g. 1.0)."""


def _pairs(pairs):
    seen = set()
    for k, _ in pairs:
        if k in seen:
            raise StrictError('duplicate key')
        seen.add(k)
    return dict(pairs)


def _const(name):
    raise StrictError('not JSON: ' + name)


def loads(data):
    if not isinstance(data, (bytes, bytearray)):
        raise TypeError('bytes expected')
    if data[:3] == b'\xef\xbb\xbf':
        raise StrictError('byte-order mark')
    try:
        text = bytes(data).decode('utf-8', errors='strict')
    except UnicodeDecodeError:
        raise StrictError('not UTF-8')
    try:
        v = json.loads(text, object_pairs_hook=_pairs, parse_constant=_const, parse_float=lambda s: Float(s),
                       strict=True)
    except json.JSONDecodeError as e:
        raise StrictError(str(e))
    except RecursionError:
        raise StrictError('too deep')
    _walk(v, 0)
    return v


def _walk(v, depth):
    if isinstance(v, (list, dict)):
        depth += 1
        if depth > MAX_DEPTH:
            raise StrictError('too deep')
        for x in (v.values() if isinstance(v, dict) else v):
            _walk(x, depth)
        if isinstance(v, dict):
            for k in v:
                _str(k)
    elif isinstance(v, str):
        _str(v)


def _str(s):
    try:
        s.encode('utf-8', errors='strict')
    except UnicodeEncodeError:
        raise StrictError('unpaired surrogate')


def typed(v):
    if v is None:
        return {'t': 'null'}
    if isinstance(v, bool):
        return {'t': 'bool', 'v': v}
    if isinstance(v, Float):
        return {'t': 'float', 'v': repr(float(v))}
    if isinstance(v, int):
        return {'t': 'int' if -INT_MAX <= v <= INT_MAX else 'big', 'v': str(v)}
    if isinstance(v, str):
        return {'t': 'str', 'v': v}
    if isinstance(v, list):
        return {'t': 'arr', 'v': [typed(x) for x in v]}
    return {'t': 'obj', 'v': [[k, typed(x)] for k, x in v.items()]}
