"""Godot 4's binary Variant encoding (`var_to_bytes`, core/io/marshalls.cpp), for the values the plant engine's state
digest holds (docs/PLANT3D.md §17.14): null, bool, int, float, String, untyped Array and the packed arrays of bytes,
32- and 64-bit integers and doubles. Test-only reference, like ref/plant3d.py: the app's engine encodes its own state
with Godot's var_to_bytes, and tests/test_plant3d_sim.py checks the two agree byte for byte.

Each value is a 4-byte little-endian header, the type in its low 16 bits and flags above, then the value:
    null      header only                       bool       u32 0 or 1
    int       i32, or i64 with flag 1 << 16 when it doesn't fit in 32 bits
    float     f32, or f64 with flag 1 << 16 when the single-precision value isn't the same double
    String    u32 byte length, UTF-8, zero bytes to a multiple of 4
    Array     u32 count, then each element (untyped: no type header field)
    Packed…   u32 count, then the elements raw (bytes padded with zeros to a multiple of 4)
"""
import struct

NIL, BOOL, INT, FLOAT, STRING, ARRAY = 0, 1, 2, 3, 4, 28
PACKED_BYTE, PACKED_INT32, PACKED_INT64, PACKED_FLOAT64 = 29, 30, 31, 33
FLAG_64 = 1 << 16


class Packed:
    """A packed array of `kind` (PACKED_BYTE, PACKED_INT32, PACKED_INT64 or PACKED_FLOAT64)."""
    __slots__ = ('kind', 'items')

    def __init__(self, kind, items):
        self.kind, self.items = kind, list(items)


def _pad(b):
    return b + b'\0' * (-len(b) % 4)


def encode(v, out=None):
    """The bytes var_to_bytes(v) gives in Godot 4.7 (no objects)."""
    o = bytearray() if out is None else out
    if v is None:
        o += struct.pack('<I', NIL)
    elif v is True or v is False:
        o += struct.pack('<II', BOOL, 1 if v else 0)
    elif isinstance(v, int):
        if -2 ** 31 <= v < 2 ** 31:
            o += struct.pack('<Ii', INT, v)
        else:
            o += struct.pack('<Iq', INT | FLAG_64, v)
    elif isinstance(v, float):
        # single precision when the float32 cast gives the same double back (as C's `float f = d; double(f) == d`)
        try:
            f = struct.unpack('<f', struct.pack('<f', v))[0]
        except OverflowError:
            f = None
        if f is not None and f == v:
            o += struct.pack('<If', FLOAT, v)
        else:
            o += struct.pack('<Id', FLOAT | FLAG_64, v)
    elif isinstance(v, str):
        b = v.encode('utf-8')
        o += struct.pack('<II', STRING, len(b)) + _pad(b)
    elif isinstance(v, (list, tuple)):
        o += struct.pack('<II', ARRAY, len(v))
        for x in v:
            encode(x, o)
    elif isinstance(v, Packed):
        n = len(v.items)
        if v.kind == PACKED_BYTE:
            o += struct.pack('<II', PACKED_BYTE, n) + _pad(bytes(v.items))
        else:
            fmt = {PACKED_INT32: 'i', PACKED_INT64: 'q', PACKED_FLOAT64: 'd'}[v.kind]
            o += struct.pack('<II', v.kind, n) + struct.pack('<%d%s' % (n, fmt), *v.items)
    else:
        raise TypeError(f'no Variant encoding for {type(v).__name__}')
    return o
