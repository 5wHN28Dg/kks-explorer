"""A JPEG XL codestream's width and height, read from its header without decoding (the e2e suites check the size
of a stored photo with it, decision 0074; no djxl needed)."""


def jxl_size(blob):
    """a JPEG XL codestream's width and height, from its size header (ISO/IEC 18181-1 SizeHeader); ValueError for
    anything else (the container format included: photos are stored as bare codestreams)"""
    if blob[:2] != b'\xff\x0a':
        raise ValueError('not a JPEG XL codestream')
    bits = int.from_bytes(blob[2:12], 'little')
    pos = 0
    def u(n):
        nonlocal bits, pos
        v = (bits >> pos) & ((1 << n) - 1); pos += n; return v
    def u32():
        return [lambda: 1 + u(9), lambda: 1 + u(13), lambda: 1 + u(18), lambda: 1 + u(30)][u(2)]()
    small = u(1)
    if small:
        h = (u(5) + 1) * 8
    else:
        h = u32()
    ratio = u(3)
    if ratio == 0:
        w = (u(5) + 1) * 8 if small else u32()
    else:
        w = h * [1, 12, 4, 3, 16, 5, 2][ratio - 1] // [1, 10, 3, 2, 9, 4, 1][ratio - 1]
    return (w, h)
