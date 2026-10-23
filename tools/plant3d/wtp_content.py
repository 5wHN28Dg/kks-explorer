"""The water treatment plant's procedures and tour (docs/plant3d/WATER-TREATMENT.md §7): the tour of milestone W1, and
W2's start-up from cold (`wtp_start`), a filter's backwash (`filter_backwash`) and an RO train's stop with its flush
(`ro_stop_flush`); W3's cleaning of an RO train in place (`ro_cip`) and a mixed bed's regeneration (`mb_regeneration`).
The model is wtp_model.py."""
from train_content import k, tour, step, op


def wtp_start():
    """From a stopped WTP (scenario wtp_cold): intake, chlorination, coagulant and polymer, clarifiers to a stable
    state, filters, filtered water to the cooling tower, an RO train with its flush, the degasser, a mixed bed, and the
    transfer to the plant's demineralised water tank (WATER-TREATMENT §7)."""
    S = [
        step('mixer', ['Start the rapid mixer (', k('00GBD10AM001'), ').'], ['00GBD10AM001'],
             [op('00GBD10AM001', 'start')], 'mx_run',
             ['The coagulant has to be spread through the water in seconds: an intense mix, then slow '
              'flocculation.']),
        step('coag', ['Set the coagulant dose to the season\'s jar-test value, 30 mg/L, at the coagulant skid (',
                      k('00GBN10BB001'), '), and start coagulant pump A (', k('00GBN10AP001'), ').'],
             ['00GBN10BB001', '00GBN10AP001'],
             [op('00GBN10BB001', 'set', 30), op('00GBN10AP001', 'start')], 'cg_on',
             ['Ferric chloride neutralises the charge on the clay particles so that they gather into flocs. Too '
              'little and the clarifiers carry floc over; too much does no better and makes more sludge. A flood '
              'needs more (up to 80 mg/L).'], ordered=True),
        step('polymer', ['Start polymer dosing pump A (', k('00GBN20AP001'), ').'], ['00GBN20AP001'],
             [op('00GBN20AP001', 'start')], 'pl_run',
             ['A fraction of a milligram per litre binds the small flocs into large ones that settle fast.']),
        step('hypo', ['Start hypochlorite dosing pump A (', k('00GBN30AP001'), ').'], ['00GBN30AP001'],
             [op('00GBN30AP001', 'start')], 'hy_run',
             ['1–2 mg/L of chlorine keeps algae and slime out of the clarifiers and filters. It must be taken out '
              'again before the RO.']),
        step('rw_a', ['Start raw water pump A (', k('00GAF10AP001'), ') at the intake.'], ['00GAF10AP001'],
             [op('00GAF10AP001', 'start')], 'cg_dosing',
             ['One pump first: the raw water main fills without a surge; the second follows once the flow is '
              'steady. The dosing pumps, ready and running, dose as soon as the water flows.']),
        step('rw_b', ['Start raw water pump B (', k('00GAF10AP002'), '): the plant\'s full flow, about 1,050 m³/h.'],
             ['00GAF10AP002'], [op('00GAF10AP002', 'start')], 'wt_raw_ok'),
        step('clarify', ['Watch the clarified water turbidity (', k('00GBD11CQ001'), ', ', k('00GBD12CQ001'),
                         ') settle below 2 NTU.'], ['00GBD11CQ001', '00GBD12CQ001'], (), 'cl_stable',
             ['The sludge blanket has to form before the clarifiers clear: the filters behind them would block '
              'quickly on turbid water.'], go='walk'),
        step('sludge', ['Start the sludge filter press (', k('00GBS20AT001'), '): the clarifiers\' sludge goes to the '
                        'thickener (', k('00GBS10AT001'), ').'], ['00GBS20AT001', '00GBS10AT001'],
             [op('00GBS20AT001', 'start')], 'fp_cmd',
             ['Without it the thickener fills in a few hours of the clock and its sludge comes back over the weir.']),
        step('filtered', ['The filters are in service. Wait for the filtered water tank (', k('00GBL10BB001'),
                          ') to fill above 70 %.'], ['00GBL10BB001'], (), 'ft_70'),
        step('makeup', ['Start cooling tower makeup pump A (', k('00GHB10AP001'), ').'], ['00GHB10AP001'],
             [op('00GHB10AP001', 'start')], 'mk_avail',
             ['The first train\'s cooling tower basin takes its makeup from here: without it the basin falls.']),
        step('service', ['Start service water pump A (', k('00GHA10AP001'), '): it feeds the RO.'], ['00GHA10AP001'],
             [op('00GHA10AP001', 'start')], 'sw_p_ok'),
        step('chem', ['Start the RO\'s chemical dosing: sodium bisulphite (', k('00GCN10AP001'), '), antiscalant (',
                      k('00GCN20AP001'), ') and acid (', k('00GCE10AP001'), ').'],
             ['00GCN10AP001', '00GCN20AP001', '00GCE10AP001'],
             [op('00GCN10AP001', 'start'), op('00GCN20AP001', 'start'), op('00GCE10AP001', 'start')], 'chem_on',
             ['Bisulphite takes out the chlorine, which would destroy the polyamide membranes; antiscalant and acid '
              'keep salts from scaling them as the concentrate thickens.']),
        step('orp', ['Check the RO feed ORP (', k('00GCB21CQ002'), ') below 230 mV.'], ['00GCB21CQ002'], (),
             'ro_a_orp_ok', ['Above 300 mV the RO trips: free chlorine reaches the membranes.']),
        step('degasser', ['Start the degasser blower (', k('00GCH10AN001'), ').'], ['00GCH10AN001'],
             [op('00GCH10AN001', 'start')], 'dg_cmd',
             ['It strips the carbon dioxide the RO lets through, which would otherwise load the mixed beds.']),
        step('ro_a', ['Start RO train A (', k('00GCB21AT001'), '): a 30-minute low-pressure flush, then the '
                      'high-pressure pump (', k('00GCB21AP001'), ') ramps up with the permeate to drain for the first '
                      'hour.'], ['00GCB21AT001', '00GCB21AP001'], [op('00GCB21AT001', 'start')], 'ro_a_is3',
             ['The flush pushes air and the stagnant water out at 2–4 bar: a membrane must not see a pressure '
              'shock. The first permeate is poor until the elements have flushed out ([FT] §5.2).']),
        step('mb_a', ['Start mixed bed feed pump A (', k('00GCK10AP001'), ') and watch mixed bed A\'s outlet '
                      'conductivity (', k('00GCF11CQ001'), ') below 0.1 µS/cm.'],
             ['00GCK10AP001', '00GCF11CQ001'], [op('00GCK10AP001', 'start')], 'mb_a_making'),
        step('transfer', ['Start demineralised water transfer pump A (', k('00GHC10AP001'), '): the plant\'s '
                          'demineralised water tank (', k('00GHC10BB001'), ') fills.'],
             ['00GHC10AP001', '00GHC10BB001'], [op('00GHC10AP001', 'start')], 'tr_flowing',
             ['The hotwell\'s makeup and the HRSG\'s losses come from that tank.']),
    ]
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'wtp_start',
            'title': 'Water treatment plant: start-up from cold', 'kind': 'procedure', 'scenario': 'wtp_cold',
            'intro': [{'p': ['Start the water treatment plant from standstill, from the river to the demineralised '
                             'water the train is fed with. Its own control desk (', k('00CWD10'), ') works it; the '
                             'main control room only sees its overview.']}],
            'steps': S}


def filter_backwash():
    """A gravity filter's backwash by its sequence ([10SS] §4.3.1): drain down, air scour, air and water, rinse."""
    S = [
        step('check', ['Filter 1 (', k('00GBB11AT001'), ') has the highest head loss (', k('00GBB11CP001'),
                       '): 1.4 m of the 2.2 m at which it is due.'], ['00GBB11CP001'], go='walk'),
        step('tank', ['Check the filtered water tank (', k('00GBL10BB001'), ') is above 40 %: a backwash takes '
                      'about 360 m³.'], ['00GBL10BB001'], (), 'ft_bw_ok'),
        step('wash', ['Start the backwash of filter 1 (', k('00GBB11AT001'), ') and follow its steps: the backwash '
                      'pump (', k('00GBR10AP001'), ') and the air scour blower (', k('00GBR10AN001'), ') run by '
                      'themselves.'], ['00GBB11AT001'],
             [op('00GBB11AT001', 'backwash')], 'fl1_clean',
             ['Air first loosens the dirt from the grains; water at 45 m/h then lifts the bed and carries it to '
              'waste. One filter at a time: the others take its flow meanwhile.']),
        step('back', ['Filter 1 is back in service with a clean bed; check the filtered water tank recovers above '
                      '70 %.'], ['00GBL10BB001'], (), 'ft_70'),
    ]
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'filter_backwash',
            'title': 'Water treatment plant: backwash a gravity filter', 'kind': 'procedure', 'scenario': 'cold_iron',
            'intro': [{'p': ['Backwash a gravity filter before its head loss reaches the 2.2 m at which its water '
                             'would break through.']}],
            'steps': S}


def ro_stop_flush():
    """An RO train's normal stop: the high-pressure pump stops and the train is flushed with permeate until the
    concentrate matches the feed ([FT] p. 109, p. 125)."""
    S = [
        step('stop', ['Stop RO train A (', k('00GCB21AT001'), '): the high-pressure pump stops and the train is '
                      'flushed with permeate for 30 minutes.'], ['00GCB21AT001'],
             [op('00GCB21AT001', 'stop')], 'ro_a_stopped',
             ['Concentrate left standing in the vessels would scale the membranes: the flush pushes it out with '
              'water without antiscalant until the concentrate is as clean as the feed.']),
        step('mb', ['Stop mixed bed feed pump A (', k('00GCK10AP001'), '): no permeate comes to the degassed water '
                    'tank (', k('00GCK10BB001'), ') now.'], ['00GCK10AP001', '00GCK10BB001'],
             [op('00GCK10AP001', 'stop')]),
    ]
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'ro_stop_flush',
            'title': 'Water treatment plant: stop an RO train and flush it', 'kind': 'procedure',
            'scenario': 'cold_iron',
            'intro': [{'p': ['Stop RO train A as for a planned outage, with its flush.']}],
            'steps': S}


def ro_cip():
    """RO B cleaned in place ([FT] §6.3, tables 35–37; [TSB] p. 2, p. 8–12): a high-pH cleaning, then a low-pH one,
    each recirculated through one stage at a time, soaked and flushed; the wastes neutralised in the pit."""
    def clean(sid, what, c):
        return step(sid, [f'Clean RO train B (', k('00GCB22AT001'), f') with the {what} solution: the CIP pump (',
                          k('00GCB30AP001'), ') recirculates it through the first stage, then the second, the elements '
                          'soak, and permeate flushes the solution to the neutralisation pit.'],
                    ['00GCB22AT001', '00GCB30AP001'], [op('00GCB22AT001', 'clean')], f'ro_b_{c}_cleaned',
                    ['One stage at a time, at 6–10 m³/h a vessel and under 4 bar: the flow lifts the foulant off the '
                     'membranes without pressing it in. About two and a half hours of the clock.'])
    S = [
        step('check', ['RO train B (', k('00GCB22AT001'), ') came off line for its cleaning: its normalised permeate '
                       'flow (', k('00GCB22CF001'), ') is down to 89 %, more than 10 % under its clean value. RO A '
                       'carries the plant meanwhile.'], ['00GCB22CF001'], (), 'ro_b_nflow_l0',
             ['Normalised flow corrects the permeate flow for temperature and pressure: a fall of 10 %, a rise of 5–10 % '
              'in salt passage or of 15 % in differential pressure calls for a cleaning ([FT] §6.3).'], go='walk'),
        step('fill', ['Fill the CIP tank (', k('00GCB30BB001'), ') with RO permeate.'], ['00GCB30BB001'],
             [op('00GCB30BB001', 'fill')], 'cip_water',
             ['Permeate, free of chlorine and hardness: tap or filtered water would scale or oxidise the membranes.']),
        step('caustic', ['Dose caustic soda into the tank (0.1 % NaOH, pH 12) and start its heater (', k('00GCB30AH001'),
                         '): the solution must be at pH 11.5–12 and 30–35 °C.'], ['00GCB30BB001', '00GCB30AH001'],
             [op('00GCB30BB001', 'add_caustic'), op('00GCB30AH001', 'start')], 'cip_alk_ok',
             ['High pH first: it takes off the colloids, the organics and the biofilm, which an acid would only fix '
              'to the membrane. Warm it works faster, but polyamide takes pH 12 only up to 35 °C.']),
        clean('clean_alk', 'high-pH', 'alk'),
        step('drain_alk', ['Stop the heater (', k('00GCB30AH001'), ') and drain the CIP tank (', k('00GCB30BB001'),
                           ') to the neutralisation pit.'], ['00GCB30BB001', '00GCB30AH001'],
             [op('00GCB30AH001', 'stop'), op('00GCB30BB001', 'drain')], 'cip_idle'),
        step('fill2', ['Fill the CIP tank (', k('00GCB30BB001'), ') with permeate again.'], ['00GCB30BB001'],
             [op('00GCB30BB001', 'fill')], 'cip_water'),
        step('acid', ['Dose hydrochloric acid into the tank (0.2 % HCl, pH 2) and wait for its pH (', k('00GCB30CQ001'),
                      ') under 2.5.'], ['00GCB30BB001', '00GCB30CQ001'], [op('00GCB30BB001', 'add_acid')],
             'cip_acid_ok', ['Low pH takes off the scale (calcium carbonate, metal oxides) the antiscalant did not '
                             'hold back.']),
        clean('clean_acid', 'low-pH', 'acid'),
        step('drain_acid', ['Drain the CIP tank (', k('00GCB30BB001'), ') to the neutralisation pit.'],
             ['00GCB30BB001'], [op('00GCB30BB001', 'drain')], 'cip_idle'),
        step('flow', ['RO B\'s normalised permeate flow (', k('00GCB22CF001'), ') is back above 98 %: the train is '
                      'clean and ready as the standby train.'], ['00GCB22CF001'], (), 'ro_b_nflow_ok',
             ['A cleaning restores most of the flow, never all of it: what is left builds up over the membranes\' '
              'life until they are replaced.']),
        step('pit', ['Start the neutralisation batch at the pit (', k('00GNR10BB001'), '): the caustic and acid '
                     'wastes are dosed to pH 6.5–8.5, mixed and checked, then discharged.'],
             ['00GNR10BB001', '00GNR10CQ001'], [op('00GNR10BB001', 'neutralise')], 'nr_on',
             ['The two wastes partly neutralise each other; the acid\'s is the larger, so the batch doses caustic. '
              'The discharge is allowed only between pH 6 and 9.']),
    ]
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'ro_cip',
            'title': 'Water treatment plant: clean an RO train in place', 'kind': 'procedure',
            'scenario': 'wtp_normal',
            'intro': [{'p': ['Clean RO train B with the CIP skid (', k('00GCB30BB001'), '): a high-pH cleaning, then a '
                             'low-pH one, the wastes neutralised in the pit before they are discharged.']}],
            'steps': S}


def mb_regeneration():
    """Mixed bed A regenerated ([MB] p. 2–3): the standby bed in service first, then backwash and separation, settle,
    drain, the regenerants together, displacement, drain, air mix, refill, final rinse; the wastes neutralised."""
    S = [
        step('mb_b', ['Mixed bed A (', k('00GCF11AT001'), ') is near exhaustion. Put mixed bed B (', k('00GCF12AT001'),
                      ') in service and start its feed pump (', k('00GCK10AP002'), ').'],
             ['00GCF12AT001', '00GCK10AP002', '00GCF11CQ002'],
             [op('00GCF12AT001', 'in_service'), op('00GCK10AP002', 'start')], 'mb_b_making',
             ['Silica breaks through first, before the conductivity rises: the bed is changed over before it '
              'spoils the demineralised water tanks.'], ordered=True),
        step('mb_a_off', ['Stop mixed bed feed pump A (', k('00GCK10AP001'), ') and put mixed bed A in standby.'],
             ['00GCK10AP001', '00GCF11AT001'],
             [op('00GCK10AP001', 'stop'), op('00GCF11AT001', 'standby')], 'mb_a_taken', ordered=True),
        step('regen', ['Start the regeneration of mixed bed A (', k('00GCF11AT001'), '): backwash and separation, '
                       'settling, drain down.'], ['00GCF11AT001'], [op('00GCF11AT001', 'regenerate')], 'mb_a_rdy',
             ['The backwash lifts the bed: the anion resin, lighter, settles above the cation resin, so each can take '
              'its own regenerant.']),
        step('inject', ['Check the acid (', k('00GCP10BB001'), ') and caustic (', k('00GCP20BB001'), ') tanks, and '
                        'start the injection of the regenerants.'], ['00GCP10BB001', '00GCP20BB001', '00GCF11AT001'],
             [op('00GCF11AT001', 'inject')], 'mb_a_airrdy',
             ['Hydrochloric acid from below restores the cation resin, caustic soda from above the anion resin; both '
              'leave by the collector at the interface. Three bed volumes of slow rinse push them out.']),
        step('blower', ['Start the resin mixing blower (', k('00GCP30AN001'), ').'], ['00GCP30AN001'],
             [op('00GCP30AN001', 'start')], 'gp_air_cmd'),
        step('air', ['Start the air mix of mixed bed A (', k('00GCF11AT001'), '): the sequence stops the blower, '
                     'refills the bed slowly and rinses it to under 0.1 µS/cm (', k('00GCF11CQ001'), ').'],
             ['00GCF11AT001', '00GCF11CQ001'], [op('00GCF11AT001', 'air_mix')], 'mb_a_sb',
             ['Mixed again, each grain of anion resin sits beside a cation one: the water meets hundreds of '
              'exchanges in series, which is how a mixed bed polishes to under 0.1 µS/cm.']),
        step('pit', ['Start the neutralisation batch at the pit (', k('00GNR10BB001'), ').'],
             ['00GNR10BB001', '00GNR10CQ001'], [op('00GNR10BB001', 'neutralise')], 'nr_on',
             ['The regenerants\' excess reaches the pit as acid: the batch doses caustic to pH 6.5–8.5 before the '
              'discharge.']),
    ]
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'mb_regeneration',
            'title': 'Water treatment plant: regenerate a mixed bed', 'kind': 'procedure', 'scenario': 'wtp_normal',
            'intro': [{'p': ['Change over to mixed bed B and regenerate mixed bed A, then neutralise its wastes.']}],
            'steps': S}


def procedures():
    return [wtp_start(), filter_backwash(), ro_stop_flush(), ro_cip(), mb_regeneration(), wtp_tour()]


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
