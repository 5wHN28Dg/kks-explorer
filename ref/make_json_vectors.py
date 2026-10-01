#!/usr/bin/env python3
"""Generate ref/vectors/v2-json.json: strict JSON reading (PROTOCOL-v2 §1, decision 0029). Byte strings every reader
must accept (with their typed value) or reject. FROZEN once the Nim core uses it.
  python3 ref/make_json_vectors.py [--write]"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ref import sjson as S

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vectors', 'v2-json.json')

ACCEPT = [
    ('null', b'null'), ('true', b'true'), ('false', b' false '), ('zero', b'0'), ('minus zero is the integer 0', b'-0'),
    ('integer', b'-12345'), ('largest 53-bit', b'9007199254740991'), ('above 53 bits is still an integer', b'9007199254740993'),
    ('largest int64', b'9223372036854775807'), ('smallest accepted int64', b'-9223372036854775807'),
    ('big integer', b'9223372036854775808'), ('big negative integer', b'-9223372036854775808'),
    ('huge integer', b'123456789012345678901234567890'),
    ('float with fraction', b'1.5'), ('float 1.0 stays a float', b'1.0'), ('exponent', b'1e3'), ('exponent sign', b'-2.5E-3'),
    ('minus zero float', b'-0.0'), ('tiny float', b'5e-324'), ('float rounding', b'0.1'), ('many digits', b'3.14159265358979323846264338327950288'),
    ('empty string', b'""'), ('escapes', b'"\\" \\\\ \\/ \\b \\f \\n \\r \\t"'), ('unicode escape', b'"\\u00dc\\u2603"'),
    ('surrogate pair escape', b'"\\ud83d\\ude00"'), ('raw UTF-8', '"Üß☃😀"'.encode()), ('DEL is allowed raw', b'"\x7f"'),
    ('empty array', b'[]'), ('empty object', b'{}'), ('whitespace everywhere', b' \t\r\n{ "a" : [ 1 , 2 ] }\n'),
    ('key order kept', b'{"b":1,"a":2}'), ('same key in different objects', b'{"a":{"a":1},"b":{"a":2}}'),
    ('keys differing only by escape form are different', b'{"\\u0061b":1,"ac":2}'),
    ('nested 128 deep', b'[' * 128 + b']' * 128),
    ('non-ASCII key', '{"ключ":1}'.encode()),
]

REJECT = [
    ('empty input', b''), ('only whitespace', b'  '), ('byte-order mark', b'\xef\xbb\xbf{}'),
    ('invalid UTF-8', b'"\xff"'), ('overlong UTF-8', b'"\xc0\xaf"'), ('raw surrogate in UTF-8', b'"\xed\xa0\x80"'),
    ('truncated UTF-8', b'"\xe2\x98"'),
    ('unpaired high surrogate escape', b'"\\ud800"'), ('unpaired low surrogate escape', b'"\\udc00"'),
    ('high surrogate then letter', b'"\\ud800a"'), ('surrogate in a key', b'{"\\ud800":1}'),
    ('duplicate key', b'{"a":1,"a":2}'), ('duplicate key, different values types', b'{"a":1,"b":2,"a":"x"}'),
    ('duplicate key via escape', b'{"a":1,"\\u0061":2}'), ('duplicate key nested', b'[{"x":{"k":1,"k":1}}]'),
    ('trailing comma in array', b'[1,]'), ('trailing comma in object', b'{"a":1,}'), ('leading comma', b'[,1]'),
    ('leading zero', b'01'), ('negative leading zero', b'-01'), ('leading zero float', b'00.5'), ('plus sign', b'+1'),
    ('bare dot', b'.5'), ('dot without digits', b'1.'), ('exponent without digits', b'1e'), ('NaN', b'NaN'),
    ('Infinity', b'Infinity'), ('minus Infinity', b'-Infinity'), ('hex', b'0x10'),
    ('raw newline in string', b'"a\nb"'), ('raw tab in string', b'"a\tb"'), ('raw NUL in string', b'"a\x00b"'),
    ('bad escape', b'"\\x41"'), ('short unicode escape', b'"\\u12"'), ('single quotes', b"'a'"),
    ('unquoted key', b'{a:1}'), ('comment', b'[1 /* x */]'), ('two values', b'1 2'), ('value then garbage', b'{}x'),
    ('NUL after value', b'{}\x00'), ('form feed is not whitespace', b'\x0c{}'), ('unclosed array', b'[1'),
    ('unclosed string', b'"abc'), ('true misspelled', b'tru'), ('nested 129 deep', b'[' * 129 + b']' * 129),
    ('object nested 129 deep', b'{"a":' * 129 + b'1' + b'}' * 129),
]


def build():
    V = {'protocol': 2, 'note': 'Strict JSON reading (PROTOCOL-v2 §1). Inputs are bytes (hex). Accepted inputs give the '
         'typed value: t = null|bool|int|big|float|str|arr|obj; int/big as decimal strings, float as the shortest '
         'round-trip decimal of the IEEE double, obj as [key, value] pairs in input order.'}
    acc = []
    for why, b in ACCEPT:
        v = S.loads(b)
        acc.append({'why': why, 'hex': b.hex(), 'value': S.typed(v)})
    rej = []
    for why, b in REJECT:
        try:
            S.loads(b)
        except S.StrictError:
            rej.append({'why': why, 'hex': b.hex()})
            continue
        raise AssertionError('accepted: ' + why)
    V['accept'], V['reject'] = acc, rej
    return V


def dump(V):
    return json.dumps(V, indent=1, sort_keys=True, ensure_ascii=False) + '\n'


if __name__ == '__main__':
    text = dump(build())
    if '--write' in sys.argv:
        with open(OUT, 'w', encoding='utf-8') as f:
            f.write(text)
    print('v2-json.json', len(text) // 1024, 'KB')
