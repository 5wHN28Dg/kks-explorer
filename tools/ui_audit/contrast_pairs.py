"""WCAG contrast ratios of fixed colour pairs (Walkdown Plant's panel colours and the GNOME drawing's tag outline
colours, also at alpha 0.75 over white). Edit the lists to check other pairs; the functions lin/L/over/cr are reused by
other audit scripts. Run: python3 contrast_pairs.py"""
import sys
def lin(c): return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
def L(rgb): r,g,b = [lin(x) for x in rgb]; return 0.2126*r+0.7152*g+0.0722*b
def over(fg, a, bg): return tuple(f*a+b*(1-a) for f,b in zip(fg,bg))
def cr(a,b): la,lb = sorted([L(a),L(b)], reverse=True); return (la+0.05)/(lb+0.05)
if __name__ == '__main__':
    W=(1,1,1); K=(0,0,0)
    panel_on_black = over((0.08,0.09,0.11),0.92,K); panel_on_white = over((0.08,0.09,0.11),0.92,W)
    btn=(0.2,0.23,0.28); dim=(0.75,0.75,0.75)
    for nm,fg,bg in [("white on panel(white sky)",W,panel_on_white),("DIM on panel(white sky)",dim,panel_on_white),
        ("white on button",W,btn),("disabled 0.5 on btn-disabled",(0.5,)*3,(0.13,0.14,0.16)),
        ("focus ring vs button",(1,0.75,0.2),btn),("focus ring vs panel",(1,0.75,0.2),panel_on_white),
        ("button vs panel (border)",btn,panel_on_white),("panel border vs panel",(0.3,0.33,0.38),panel_on_white),
        ("prio1 on panel",(0.95,0.2,0.15),panel_on_white),("prio2",(1,0.65,0),panel_on_white),("prio3",(0.95,0.9,0.2),panel_on_white),
        ("OK on panel",(0.45,0.9,0.45),panel_on_white),("BAD on panel",(1,0.45,0.4),panel_on_white),
        ("prio1 vs prio2 (lum)",(0.95,0.2,0.15),(1,0.65,0)),
        ]:
        print(f"{nm:35s} {cr(fg,bg):5.2f}")
    print('-- GNOME tag colours vs white / #121212-ish')
    for nm,c in [("verified",(0.15,0.6,0.25)),("review",(0.95,0.55,0.0)),("pending",(0.55,0.2,0.75)),("auto",(0.1,0.4,0.9)),
                 ("cov both",(0.18,0.63,0.26)),("cov equip",(0.9,0.59,0.0)),("cov plate",(0.12,0.47,0.9)),("cov none",(0.86,0.16,0.16))]:
        print(f"{nm:12s} solid {cr(c,W):4.2f}  at a=.75 {cr(over(c,.75,W),W):4.2f}")
