"""What the manuals' source files (tools/plant3d/manual_texts/<id>.py) are written with (docs/plant3d/REALISM.md §6.2.1):
blocks as COURSES.md's, and an inline markup the generator (manuals.py) turns into COURSES.md runs:

    **strong**   *emphasis*   `4–20 mA` (a number with its unit, kept on one line)   ~small~
    [words](#section)  [words](manual:pumps#section)  [words](kks:30MAG10CP002)
    [words](work:open_cover)  [words](workshop:pressure_transmitter/sensor_module)

A run's text is plain (no entities); `\\` before one of `*`~[]\\` writes it as it is."""


def S(id, title, blocks, src=()):
    """A section: its id, title, blocks and the ids of the sources it follows."""
    return {'id': id, 'title': title, 'blocks': list(blocks), 'src': list(src)}


def H(text):
    return {'h': text, 'level': 3}


def P(text):
    return {'p': text}


def UL(*items):
    return {'ul': list(items)}


def OL(*items):
    return {'ol': list(items)}


def TABLE(head, rows, num=()):
    return {'table': {'head': list(head), 'rows': [list(r) for r in rows], 'num': list(num)}}


def _callout(kind, label, body):
    return {'callout': kind, 'label': label, 'body': [P(b) if isinstance(b, str) else b for b in body]}


def WARNING(*body, label='Warning'):
    return _callout('warning', label, body)


def CAUTION(*body, label='Caution'):
    return _callout('caution', label, body)


def NOTE(*body, label='Note'):
    return _callout('note', label, body)


def FIG(kind, view):
    """A figure of the Workshop's scene of `kind` (`exploded` or `cut`); left out while the kind has none."""
    return {'figure': [kind, view]}


def TROUBLE(*rows):
    """The troubleshooting table: rows (symptom, cause, remedy[, cause id of §2.6])."""
    out = []
    for r in rows:
        row = {'symptom': r[0], 'cause': r[1], 'remedy': r[2]}
        if len(r) > 3 and r[3]:
            row['id'] = r[3]
        out.append(row)
    return {'trouble': out}


def UNIT():
    """The opened code's own parameters (the reader fills it in)."""
    return {'unit': True}


def SERIES():
    """The kit parameters' ranges for the manual's kinds (the generator fills it in from kit.json)."""
    return {'series': True}


def PARTS():
    """The spare parts list (the generator fills it in from the Workshop tree and the manual's consumables)."""
    return {'parts': True}
