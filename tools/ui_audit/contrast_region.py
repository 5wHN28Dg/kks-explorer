"""WCAG contrast of text in a screenshot region: background = the most common colour, text = the pixel farthest from it.
Run: python3 contrast_region.py SHOT.png NAME=x0,y0,x1,y1 [NAME=...]   (needs Pillow)"""
import sys
from collections import Counter
from PIL import Image
def lum(c):
    def f(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = c[:3]
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)
def region(path, box):
    im = Image.open(path).convert('RGB').crop(box)
    px = list(im.getdata())
    bg = Counter(px).most_common(1)[0][0]
    fg = max(px, key=lambda p: abs(lum(p) - lum(bg)))
    return bg, fg, ratio(bg, fg)
if __name__ == '__main__':
    p = sys.argv[1]
    for spec in sys.argv[2:]:
        name, b = spec.split('=')
        bg, fg, r = region(p, tuple(map(int, b.split(','))))
        print(f'{name}: fg #{fg[0]:02x}{fg[1]:02x}{fg[2]:02x} on bg #{bg[0]:02x}{bg[1]:02x}{bg[2]:02x} = {r:.2f}:1')
