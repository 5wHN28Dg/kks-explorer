"""The water treatment plant's model, sounds and tour for milestone W1 (docs/plant3d/MILESTONES.md: walkable; its
behaviour, screens, alarms and procedures are W2's). The WTP is in service whenever the first train's scenarios run
(WATER-TREATMENT.md §8: "the WTP is in service in cold_iron"), so here its running machines turn and sound at a
constant speed: one stream of each kind runs, the standby ones stand still. W2 replaces the constants with the
model of WATER-TREATMENT.md §5."""
from train_model import M
from train_content import k, tour

# what runs (the running half of each pair; WATER-TREATMENT §2: raw water 2 of 3, one RO and mixed bed stream)
RUNNING_4POLE = ['00GAF10AP001', '00GAF10AP002', '00GHB10AP001', '00GHA10AP001', '00GCK10AP001', '00GHC10AP001']
RUNNING_HP = ['00GCB21AP001']
RUNNING_BLOWERS = ['00GCH10AN001']
SPEED_4POLE = 24.7          # rev/s: a four-pole motor (1,482 rpm), as motor_small's tones assume
SPEED_2POLE = 49.5          # rev/s: the RO high-pressure pumps' two-pole motors (2,970 rpm), ro_hp_pump's tones


def models():
    """intake's and wtp's models, in plant.json's area order (wtp before intake)."""
    w = M('wtp')
    w.const('wtp_in_service', 1)
    i = M('intake')
    i.const('intake_in_service', 1)
    for m, run in ((i, 'intake_in_service'), (w, 'wtp_in_service')):
        for code in RUNNING_4POLE:
            if (code.startswith('00GAF')) == (m is i):
                m.b(kks=code, anim='shaft', of=run, scale=SPEED_4POLE)
                m.b(kks=code, sound='motor_small', gain={'of': run, 'table': [[0, 0], [1, 0.8]]})
    for code in RUNNING_HP:
        w.b(kks=code, anim='shaft', of='wtp_in_service', scale=SPEED_2POLE)
        w.b(kks=code, sound='ro_hp_pump', gain={'of': 'wtp_in_service', 'table': [[0, 0], [1, 1]]})
    for code in RUNNING_BLOWERS:
        w.b(kks=code, anim='shaft', of='wtp_in_service', scale=25)
        w.b(kks=code, sound='motor_small', gain={'of': 'wtp_in_service', 'table': [[0, 0], [1, 0.6]]})
    return [w, i]


def wtp_tour():
    return tour('wtp_path', 'Tour: the water treatment plant, from the river to the demineralised water tank',
                'Follow the water from the river through the intake, the clarifiers and filters, reverse osmosis, the '
                'degasser and the mixed beds to the demineralised water the HRSG is fed with.',
                [(['The bar screen (', k('00GAA10AT001'), ') keeps logs and rubbish out of the intake channel; the '
                   'travelling band screens behind it (', k('00GAA10AT002'), ', ', k('00GAA10AT003'),
                   ') catch what is larger than 9.5 mm.'], ['00GAA10AT001', '00GAA10AT002', '00GAA10AT003']),
                 (['Three vertical raw water pumps (', k('00GAF10AP001'), ') stand over the wet well, two running. '
                   'They send the river water through the buried raw water main (', k('00GAC10BR010'),
                   ') to the treatment plant.'], ['00GAF10AP001', '00GAF10AP002', '00GAF10AP003']),
                 (['The rapid mixer (', k('00GBD10AM001'), ') mixes the coagulant into the water in seconds: the '
                   'fine clay particles start to gather into flocs.'], ['00GBD10AM001']),
                 (['The clarifiers (', k('00GBD11AT001'), ', ', k('00GBD12AT001'), ') let the flocs settle; the '
                   'clear water spills over the weirs into the launder round the wall. Its bridge, up the stair, '
                   'carries the rake\'s drive.'], ['00GBD11AT001', '00GBD12AT001']),
                 (['The gravity filters (', k('00GBB10'), '): six cells of sand and anthracite, their valves in the '
                   'gallery under the deck, seen from its ends. A filter whose head loss grows is backwashed with air and water.'],
                  ['00GBB10']),
                 (['The filtered water tank (', k('00GBL10BB001'), ') feeds the cooling tower makeup pumps (',
                   k('00GHB10AP001'), ') and the service water pumps, which also feed the RO.'],
                  ['00GBL10BB001', '00GHB10AP001']),
                 (['Cartridge filters (', k('00GCB11AT001'), ') of 5 µm protect the membranes; sodium bisulphite has '
                   'taken the chlorine out before them.'], ['00GCB11AT001', '00GCB12AT001']),
                 (['The high-pressure pump (', k('00GCB21AP001'), ') raises the feed to about 12 bar; the RO train (',
                   k('00GCB21AT001'), ') passes three quarters of it through the membranes as permeate.'],
                  ['00GCB21AP001', '00GCB21AT001']),
                 (['The degasser (', k('00GCH10AT001'), ') blows the carbon dioxide out of the permeate before the '
                   'mixed beds.'], ['00GCH10AT001']),
                 (['The mixed beds (', k('00GCF11AT001'), ') polish the water to under 0.1 µS/cm.'],
                  ['00GCF11AT001', '00GCF12AT001']),
                 (['The demineralised water tanks (', k('00GCL10BB001'), ') store about four days of the plant\'s '
                   'needs; the transfer pumps (', k('00GHC10AP001'), ') send it to the train.'],
                  ['00GCL10BB001', '00GHC10AP001']),
                 (['The plant\'s demineralised water tank (', k('00GHC10BB001'), ') beside the auxiliary boiler: '
                   'the makeup of the water-steam cycle comes from here.'], ['00GHC10BB001'])])
