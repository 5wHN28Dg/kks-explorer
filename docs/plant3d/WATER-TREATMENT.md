# Walkdown Plant: the water treatment plant (content plan)

**Status: DRAFT 2026-10-22**, before any content or code. Format: docs/PLANT3D.md (format 1 for the process; format 2
for the people who work it). Decision: 0065. Layout on the site: SITE.md. The user's decision (2026-10-22): a generic
plant from river water to demineralised water, walkable and operable like the train, with procedures, alarms and
faults.

**Everything here is invented** (R1): sizes are round values in the ranges the public sources below give for the
class of plant, chosen to be plausible, not taken from any plant.

## 1. Sources

- [FT] DuPont FilmTec Reverse Osmosis / Nanofiltration Technical Manual, form 45-D01504-en rev. 20:
  https://www.dupont.com/content/dam/water/amer/us/en/water/public/documents/en/RO-NF-FilmTec-Manual-45-D01504-en.pdf
- [TSB] Hydranautics TSB107, Foulants and cleaning procedures: https://www.lenntech.com/data-sheets/Hydranautics-TSB107-L.pdf
- [10SS] Recommended Standards for Water Works ("Ten States Standards"), 2018:
  https://healthweb-back.health.ny.gov/environmental/water/drinking/regulations/docs/2018_recommended_standards.pdf
- [MB] DuPont Tech Fact, Recommended operating conditions for mixed bed units, 45-D01127-en rev. 3:
  https://www.lenntech.com/Data-sheets/DuPont-Operating-Conditions-Mixed-Bed-L.pdf
- [IAPWS] IAPWS TGD3-10(2015), Volatile treatments for the steam-water circuits of fossil and combined cycle/HRSG
  power plants: https://iapws.org/documents/techguide/Volatile.download
- [IEPA] Irish EPA, Water Treatment Manuals: Coagulation, Flocculation and Clarification (2002):
  https://susana.org/_resources/documents/default/3-4171-7-1617182302.pdf
- [MFGM] US EPA Membrane Filtration Guidance Manual, EPA 815-R-06-009:
  https://www.deq.nd.gov/Publications/MF/MembraneFiltrationGuide.pdf
- [EPRI] EPRI, Water & Sustainability vol. 3 (2002): https://www.circleofblue.org/wp-content/uploads/2010/08/EPRI-Volume-3.pdf
- KKS letters: [E2] of FIRST-TRAIN.md §1 (Eskom KKS Key Part Standard 348-694071 rev. 6), pages as given.

Numbers marked (ours) have no public source found: they are our estimates, inside the sourced ranges where there
are any.

## 2. What it makes, and for whom

| | Design value | Source |
|---|---|---|
| Cooling tower makeup (both trains at base load, hot day) | ~850 m³/h of clarified, filtered water; cycles of concentration 3–5 | [EPRI] p. 3-5 (CCPP with a tower: 230 gal/MWh makeup at 5 cycles); ours for the hot day |
| Demineralised water | ~30 m³/h on average, more at start-ups | ours: HRSG blowdown and losses of about 1–2 % of ~600 t/h of steam (6–12 m³/h), plus start-ups, sampling, closed cooling and service needs and the mixed beds' own rinse water |
| Raw water taken | ~1,000 m³/h (makeup, the RO feed, service water, ~5 % for sludge and backwash) | ours |
| Demin plant | 2 streams × 40 m³/h (one in service, one standby or regenerating) | ours |
| Demin storage | 2 tanks × 1,500 m³ (about four days at the average draw, a day and a half of start-ups), with a floating cover against CO₂ | ours; the cover [IAPWS] §6.8 |
| Makeup quality | conductivity < 0.1 µS/cm, silica < 10 µg/kg | [IAPWS] §6.8 and table 4 |

The river is turbid and changes with the season: 20 NTU in the dry months, up to 500 NTU in a flood (a scenario
`ext` value, `river_ntu`); its salts about 1,000 mg/L (`river_tds`).

## 3. The process, step by step

| # | Stage (codes §4) | Design | Source |
|---|---|---|---|
| 1 | Intake: bar screen, two travelling band screens, three raw water pumps (vertical turbine) | screen velocity ≤ 0.15 m/s; bars 75 mm, band mesh 9.5 mm; pumps 3 × 50 %, ~550 m³/h each | 40 CFR 125.94 (0.5 ft/s); EPA 316(b) (3/8 in mesh); pumps ours |
| 2 | Pre-chlorination (sodium hypochlorite) at the intake | 1–2 mg/L, against growth in the clarifiers and filters | ours |
| 3 | Rapid mix with coagulant (ferric chloride) | G ≥ 750 s⁻¹, ≤ 30 s; dose 20–80 mg/L by the season (jar tests) | [10SS] §4.2.2; dose ours inside [IEPA] p. 17 |
| 4 | Flocculation with polymer, two solids-contact clarifiers | polymer 0.05–0.3 mg/L; upflow ≤ 2.4 m/h, so 2 × 50 %, Ø ~17 m; sludge bled 1–2 % of the flow, 2–3 min every 30 min | [10SS] §4.2.5; polymer NHMRC guidelines; [IEPA] §5.3.5 |
| 5 | Gravity multimedia filters (sand and anthracite): six cells, five in service | ~8 m/h; bed 0.75 m; backwash by head loss (2.2 m) or 36 h: air scour 1 m³/min/m², then water at 45 m/h for 10 min | [10SS] §4.3.1 (5–10 m/h; air 0.9–1.5; water ≥ 37 m/h); trigger and run length ours |
| 6 | Filtered water tank and pumps: cooling tower makeup, service water, RO feed | tank 1,000 m³ | ours |
| 7 | Ultrafiltration | **not built** (0065): the media filters give SDI < 5, enough for the RO at a conservative flux | [FT] table 22 |
| 8 | Dechlorination (sodium bisulphite), antiscalant, cartridge filters 5 µm | SBS 1.8–3 mg per mg of free chlorine; ORP alarm 250 mV, RO trip at 300 mV; antiscalant 3 mg/L; cartridge ΔP change at 1 bar | [TSB] p. 1; [FT] p. 61, p. 67; ORP limits and antiscalant ours (vendors give 175–300 mV and 2–5 mg/L) |
| 9 | Reverse osmosis, two trains: HP pump, 2:1 array of six-element vessels (6 + 3) | 75 % recovery: 53 m³/h in, 40 out; flux ~20 L/m²h (feed SDI < 5); feed ~12 bar; rejection ~99 % (permeate ~25 µS/cm) | [FT] p. 82, p. 91 (12–16 gfd, SDI < 5), p. 98–100; pressure and rejection ours |
| 10 | Forced-draft degasser on the permeate, degassed water tank | CO₂ to ~5 mg/L | [FT] p. 33 (where to degas); the outlet value is vendors' (5–15 mg/L) |
| 11 | Mixed beds, two (one per stream) | ≥ 24 m/h; bed 1.5 m; run ≥ 24 h (here about three days on RO permeate); regeneration ~4 h | [MB] p. 1–3 |
| 12 | Demin tanks, transfer pumps to the plant's demin tank `00GHC10BB001` (first train, `bop`) | | |
| 13 | Neutralisation pit for regeneration and CIP wastes; discharge at pH 6–9 | acid and caustic dosed into the pit, mixed by an agitator | 40 CFR 423.12(b)(1) |
| 14 | Sludge: thickener, filter press | thickened to 3–5 % solids, cake 15–30 % | vendors' ranges; ours |
| 15 | Sample panel and laboratory: turbidity, SDI, ORP, pH, conductivity, silica | | |

**RO cleaning (CIP):** when normalised permeate flow falls 10 %, salt passage rises 5–10 % or ΔP rises 15 %: high-pH
cleaning (0.1 % NaOH, pH 12, ≤ 35 °C) then low-pH (0.2 % HCl, pH 1–2), each recirculated 1 h at 6–10 m³/h per vessel,
≤ 4 bar, one stage at a time ([FT] §6.3, tables 35–37; [TSB] p. 2, p. 8–12).

**RO start and stop:** flush at 2–4 bar for 30 min, start the HP pump against an open concentrate valve, ramp slowly,
permeate to drain for the first hour ([FT] §5.2); at every stop flush with permeate without antiscalant until the
concentrate matches the feed ([FT] p. 109, p. 125).

**Mixed bed regeneration** ([MB] p. 2–3): backwash and separation 25 min, settle 5 min, drain down, acid (HCl 5 %,
~90 g/L of resin) and caustic (NaOH 4 %, ~100 g/L) injected together 40 min, displacement 3 bed volumes, drain,
air mix 10 min, refill, final rinse to < 0.1 µS/cm (about 30 min).

## 4. KKS codes (generic, G = 0)

From [E2] p. 34–44 and p. 80–85; our convention where the key leaves a choice (as FIRST-TRAIN.md §1): process steps
by the key's step letters (B filtering, D precipitation, F ion exchange, H degassing, K intermediate storage, L
storage outside the treatment, N chemical supply, P regeneration, R flushing and residue, including neutralisation,
S sludge thickening), parallel streams by units (11, 12), equipment AN numbers as FIRST-TRAIN §1.

| Code | What (our words) | Key and source |
|---|---|---|
| 00GAA10AT001, AT002–003 | Bar screen; travelling band screens A, B | GAA intake, mechanical [E2] p. 34; AT |
| 00GAA10CL001 | Intake level | |
| 00GAF10AP001–003 | Raw water pumps A, B, C | GAF raw water pumping [E2] p. 34 |
| 00GAC10BR010 | Raw water main | GAC piping [E2] p. 34 |
| 00GBN30 | Hypochlorite dosing (pre-chlorination) | GBN chemical supply [E2] p. 34–36 |
| 00GBD10AM001 | Rapid mixer | GBD precipitation; AM mixers |
| 00GBD11AT001, 00GBD12AT001 | Clarifiers A, B | AT separating units |
| 00GBD11CQ001, 00GBD12CQ001 | Clarified water turbidity | CQ analysis |
| 00GBN10, 00GBN20 | Coagulant (ferric chloride) and polymer dosing: tanks BB001, pumps AP001–002 | GBN |
| 00GBB11AT001 … 00GBB16AT001 | Gravity filters 1–6 | GBB filtering |
| 00GBB11CP001 … 00GBB16CP001 | Filter head loss | |
| 00GBR10AP001–002, 00GBR10AN001–002 | Backwash pumps, air scour blowers | GBR flushing water |
| 00GBL10BB001 | Filtered water tank | GBL storage outside the treatment |
| 00GHB10AP001–002 | Cooling tower makeup pumps (to 30PAR10) | GHB distribution after decarbonisation [E2] p. 39 |
| 00GHA10AP001–002 | Service water pumps | GHA |
| 00GCN10, 00GCN20, 00GCE10 | SBS, antiscalant, acid dosing | GCN chemical supply; GCE acid dosing [E2] p. 36–38 |
| 00GCB11AT001, 00GCB12AT001 | Cartridge filters A, B | GCB filtering |
| 00GCB21AP001, 00GCB22AP001 | RO high-pressure pumps A, B | (RO is not in the key: placed under GCB, our convention) |
| 00GCB21AT001, 00GCB22AT001 | RO trains A, B | |
| 00GCB21CQ001, CQ002, CP001, CP002, CF001 | RO permeate conductivity, feed ORP, feed (HP pump discharge) pressure, HP pump suction pressure, permeate flow (also on B) | |
| 00GCB11CP001, 00GCB12CP001 | Cartridge filter differential pressure | |
| 00GCH10AT001, 00GCH10AN001 | Degasser tower, its blower | GCH degasification |
| 00GCK10BB001, 00GCK10AP001–002 | Degassed water tank, mixed bed feed pumps | GCK intermediate storage |
| 00GCF11AT001, 00GCF12AT001 | Mixed beds A, B | GCF ion exchanger |
| 00GCF11CQ001, CQ002 (and 12) | Mixed bed outlet conductivity, silica | |
| 00GCP10BB001, 00GCP20BB001, 00GCP30AN001 | Regeneration acid and caustic tanks; resin mixing air blower | GCP regeneration |
| 00GCL10BB001, BB002 | Demin water tanks A, B | GCL storage outside the treatment |
| 00GHC10AP001–002 | Demin transfer pumps to 00GHC10BB001 | GHC distribution after demineralisation [E2] p. 39–40 (as built, the first train's 00GHC10BB001 is the plant's demin tank) |
| 00GNR10BB001, AP001–002, AM001, CQ001 | Neutralisation pit, discharge pumps, agitator, pH | GNR neutralisation [E2] p. 40–42 |
| 00GBS10AT001, 00GBS20AT001 | Sludge thickener, filter press | GBS sludge thickener |
| 00QUG10 | WTP sample panel | QUG water treatment sampling [E2] p. 74–75 |
| 00UGA10, 00UGL10, 00UGD10, 00UGE10, 00UGQ10, 00UTS10 | Intake structure, flocculator and clarifiers, treatment building (RO, demin, lab), neutralisation, sludge dewatering building, chemical storage | UG*, UTS [E2] p. 80–84 |

The plant's `kks` tables gain these letters (meanings in our own words, as FIRST-TRAIN.md §1).

## 5. The model (format 1)

- **Two speeds.** Hydraulics (a pump's start, pressures, flows) run in model time like the train. **Inventories**
  that take hours or days on site (tanks, a filter's head loss, a mixed bed's exhaustion, the RO's fouling, sludge)
  run at clock rates: their `integrate` gains are multiplied by the clock's `day_scale` (PLANT3D.md §16.1), so the
  demin tank empties over the right number of clock hours and a mixed bed runs about three clock days (the content
  tool reads `day_scale` from plant.json). Sequence step times (a backwash, a regeneration) are clock durations
  divided by `day_scale`: the regeneration's ~4 hours are 40 model minutes.
- **Where the two speeds meet** (§8): the plant's demin tank `00GHC10BB001` and the cooling tower basin keep the
  first train's model rates. A flow between a clock-rate inventory and a model-rate one is counted at each end at that
  end's rate: the transfer pumps' 40 m³/h fill the plant's tank at 40 m³/h of model time and empty the WTP's demin
  tanks at 240 m³/h of model time (× 6). Mass is not conserved across the tie, deliberately: the WTP's slow
  inventories must move within a played shift, the train's fast ones must not race.

- **Values (the main ones):** `river_ntu`, `river_tds` (ext); raw water flow from the pumps and their discharge
  valve; coagulant ratio (dose ÷ the demand table of `river_ntu`) → clarified turbidity (a table: under-dosed → the
  clarifier carries floc over; over-dosed → no better, more sludge); sludge blanket level (integrates solids − blowdown);
  each filter's head loss (integrates turbidity × flow; a backwash resets it) → filtered turbidity (rises past
  2.2 m: breakthrough); SDI from filtered turbidity and the cartridge (table); free chlorine after SBS → ORP; each RO
  train's fouling (integrates SDI over time; CIP resets most of it, not all) → feed pressure needed, normalised flow,
  ΔP, permeate conductivity (river TDS × salt passage, worse with fouling and at start-up until flushed); degasser CO₂
  (blower on or off); each mixed bed's exhaustion (integrates permeate conductivity × flow) → outlet conductivity and
  silica (low until 90 % used, then a rising table); tank levels; neutralisation pit pH (acid and caustic wastes in,
  dosing, a lag); thickener level.
- **Machines:** one per filter (in service → draining → air scour → air and water → rinse → standby; one filter in
  backwash at a time), one per RO train (stopped → flushing → starting → in service → stopping and flushing → CIP
  high pH → CIP low pH → rinse), one per mixed bed (in service → backwash → settle → drain → regenerants → displace →
  drain → air mix → refill → final rinse → standby), the neutralisation batch (fill → dose → mix → check → discharge).
- **Interlocks:** a raw water pump stops on intake level low-low; dosing pumps run only with their stream's flow (the
  coagulant and SBS pumps start and stop with it); the second filter's backwash waits for the first; an RO train's
  permeate goes to drain while its conductivity is high (> 50 µS/cm) or for the start-up's first minutes; a mixed bed
  whose outlet conductivity passes 0.2 µS/cm goes to recirculation and the standby bed is offered; the demin transfer
  pumps stop on the demin tank's low-low level; the pit discharge pumps run only between pH 6 and 9 (permissive and
  interlock).
- **Trips** (each with its alarm, first-out group per RO train): RO HP pump on low suction pressure (< 1 bar: a
  clogged cartridge, a stopped feed pump), high discharge pressure (> 16 bar), ORP high (> 300 mV for 10 s: chlorine
  reaches the membranes); a raw water pump on motor overload; a mixed bed feed pump on degassed tank low-low.

## 6. Alarms

| Code | ISA | Alarm | Limit | Prio |
|---|---|---|---|---|
| 00GAA10CL001 | LAL / LALL | Intake level low / low-low (raw water pump trip) | −1.0 / −1.5 m | 2 / 1 |
| 00GAF10AP001–003 | — | Raw water pump tripped | motor trip | 2 |
| 00GBD11CQ001, 00GBD12CQ001 | QAH | Clarified water turbidity high | > 5 NTU | 2 |
| 00GBN10BB001 | LAL | Coagulant day tank low | < 20 % | 3 |
| 00GBB11CP001–00GBB16CP001 | PDAH | Filter head loss high: backwash due | > 2.2 m | 3 |
| 00GBL10BB001 | LAL | Filtered water tank low | < 30 % | 2 |
| 00GCB21CQ002, 00GCB22CQ002 | QAH / QAHH | RO feed ORP high / high-high (RO trip) | > 250 / > 300 mV | 2 / 1 |
| 00GCB11CP001, 00GCB12CP001 | PDAH | Cartridge filter ΔP high | > 1.0 bar | 3 |
| 00GCB21CP001, 00GCB22CP001 | PAH / PAHH | RO feed pressure high / high-high (RO trip) | > 15 / > 16 bar | 2 / 1 |
| 00GCB21CP002, 00GCB22CP002 | PALL | RO HP pump suction pressure low-low (RO trip) | < 1 bar | 1 |
| 00GCB21CF001, 00GCB22CF001 | FAL | RO normalised permeate flow low: CIP due | −10 % | 3 |
| 00GCB21CQ001, 00GCB22CQ001 | QAH | RO permeate conductivity high (to drain) | > 50 µS/cm | 2 |
| 00GCF11CQ001, 00GCF12CQ001 | QAH | Mixed bed outlet conductivity high (exhausted) | > 0.2 µS/cm | 2 |
| 00GCF11CQ002, 00GCF12CQ002 | QAH | Mixed bed outlet silica high | > 20 µg/kg | 2 |
| 00GCL10BB001–002 | LAL / LALL | Demin tank low / low-low (transfer pumps trip) | < 25 / < 10 % | 2 / 1 |
| 00GNR10CQ001 | QAH, QAL | Neutralisation pit pH out of range (discharge blocked) | > 9 or < 6 | 3 |
| 00GBS10AT001 | LAH | Thickener sludge level high | > 80 % | 3 |

## 7. Operations, procedures and faults

- **Operated** from the WTP's own local control panel (an `operator_desk` in the treatment building with its own
  screens, PLANT3D.md §7.11: a WTP overview and screens for pretreatment, RO, demin, chemicals and wastes) and in the
  field; the main control room shows the WTP overview only (read, not operate: as many plants run their WTP).
- **Procedures** (format 1, each run in the model alone by the tests): `wtp_start` (intake to demin tanks from a
  stopped plant: screens, raw water pumps, chlorination, coagulant and polymer by the season's dose, clarifiers to a
  stable blanket, filters, filtered water to the tower, then an RO train with its flush, the degasser, a mixed bed,
  transfer); `filter_backwash`; `ro_cip`; `mb_regeneration`; `ro_stop_flush`; and a tour `wtp_path` (river to
  demin tank).
- **Faults** (trainer's and conditional; every one repairable as format 1's, PLANT3D.md §7.8): flood (`river_ntu` to
  500: the coagulant must follow or the clarifiers carry over and the filters block), coagulant pump failure, SBS pump
  failure (ORP rises, the RO trips: if the trainee resets and restarts without fixing, the membranes take chlorine
  damage, a fault only an overhaul repairs), cartridge clogging (suction pressure falls), fast membrane fouling
  (CIP due early), early mixed bed exhaustion (silica first), a transfer pump trip with a train starting (the demin
  tank falls: the hotwell makeup of the first train is limited, FIRST-TRAIN.md §4 "The hotwell"), a filter
  underdrain fault (one filter's turbidity high after backwash), a neutralisation pH probe drift.
- **Scenarios:** `wtp_normal` (one RO and MB stream in service, a filter due for backwash, a mixed bed near
  exhaustion: the first hour holds the day's work), `wtp_cold` (all stopped, tanks at 60 %), `wtp_flood`.
- **Staff** (format 2, STAFF.md): the WTP operator's rounds and the sequences, the chemist's samples, the mechanical
  technician's cartridge change under a permit (the RO train isolated), the I&C technician's ORP and conductivity
  calibrations.

## 8. Ties to the train

- The cooling tower makeup valve `30PAR10AA001` gets its water from the makeup pumps `00GHB10AP001–002` and the
  filtered water tank: with the tank empty or the pumps stopped, the makeup flow is 0 and the basin falls (the alarms
  of FIRST-TRAIN.md §5).
- The plant's demin tank `00GHC10BB001` is filled by the transfer pumps and feeds the hotwell makeup and the HRSG's
  losses; its level becomes a value (in the first train it was taken as always available).
- These change the first train's model, so its vectors are made again in that milestone (MILESTONES.md W1), as with
  every content change; the cold start's procedure gains no step (the WTP is in service in `cold_iron`).

## 8a. As built in W1 (walkable, 2026-10-22)

The content tools make it (`tools/plant3d/wtp_areas.py`, `wtp_content.py`); the layout is SITE.md's. What W1 settled
that the plan above leaves open:
- **Codes on things that are not one part:** each gravity filter's code (`00GBB11AT001` …) is on the number board at
  its cell on the operating deck (a `sign` part, coded); the bank is `00GBB10`. Each dosing skid is coded by its day
  tank (`…BB001`), its metering pumps (`…AP001`, `AP002`) are parts of their own on it. The degasser's blower
  `00GCH10AN001` is a blower package beside the tower. The rapid mixer `00GBD10AM001` is the agitator; its tank is
  `00GBD10BB001`. The intake's channel and wet well is `00GAA10BB001`; the laboratory bench `00QUG20`.
- **The WTP control desk** `00CWD10` (an `operator_desk`) stands in its control room; its screens come with W2's
  `desks`, until then it says that the screens are worked in the control room.
- **What runs:** the WTP is in service (§8); until W2's model, the running half of each pair (raw water pumps A and
  B, makeup pump A, service water pump A, RO stream A, mixed bed feed pump A, transfer pump A, the degasser's blower)
  turns and sounds at a constant speed, the others stand still. The RO high-pressure pumps have a sound of their own
  (`ro_hp_pump`), which makes the treatment building a hearing-protection area.
- **Not built in W1:** the pressure filters of PLANT3D.md §18.6 (the gravity filters do their work), the backwash
  and air scour lines inside the gallery (their pumps' lines end under the ground), the sludge lines to the
  thickener and the press.

## 8b. As built in W2 (operable, 2026-10-23)

The model is `tools/plant3d/wtp_model.py` (areas `wtp` and `intake`, about 580 values), its screens
`tools/plant3d/train_screens.py`, its procedures `wtp_content.py`. What W2 settled that the plan above leaves open:
- **The clock.** `day_scale` is 6 (PLANT3D.md §16.1) until plant.json has its `clock` (milestone S1): the content
  tool then reads it from there. The clock-rate inventories: the filtered water, degassed water and demin tanks, the
  coagulant day tank, the neutralisation pit, each filter's head loss, each RO train's fouling, each mixed bed's
  exhaustion and the thickener (a lag of 2 clock hours). The pumps, pressures, ORP, conductivities and sequences run in
  model time; a sequence's step is its clock time ÷ 6 (an RO flush of 30 min is 5 model minutes).
- **The ties (§8).** The basin's makeup flow is the valve's flow times `ct_mk_sup`, a `delay` of the WTP's
  `mk_avail` (a makeup pump running and the filtered water tank above 5 %): exactly 1 while the WTP supplies, so the
  first train's values are unchanged. The plant's demin tank `00GHC10BB001` (300 m³, model rate, 80 % at the start) is
  a value: filled by the transfer pumps through its level valve (full flow below 85 %, shut at 95 %), drawn by the
  hotwell makeup and the HRSG's losses (8 m³/h while it makes steam); the hotwell makeup needs it above 3 %
  (`hw_mk_ok`); its low alarm (LAL 30 %) is on the train's Auxiliaries screen. The transfer flow is counted at the
  train's rate there and at the clock's in the WTP's tanks (§5). In `cold_iron` and `hot_restart` the WTP is in service,
  and the first train's format 1 vectors keep every value, event and input they had.
- **Simplified:** the demin tanks fill from a common header and the transfer pumps draw on both; the filtered
  water tank overflows back to the clarifiers' inlet above 90 % (raw water flow is not controlled); the clarifiers
  are a lag of 10 model minutes on a dose-ratio table, without a sludge blanket of their own; the backwash's pump B
  and blower B are standby without operations; an RO trip stops the train without its flush (the trainee flushes it,
  `ro_stop_flush`); chlorine damage to the membranes, CIP and the mixed beds' regeneration are W3's.
- **The scenario `wtp_cold`** is the first train at cold iron with the WTP stopped and its tanks at 60 % (the plant's
  demin tank too). A scenario can't set a machine's state, so RO A, which is in service in the train's scenarios,
  is stopped by its state `ro_a_park`: set in `wtp_cold`, it moves the train to `stopped` at the first step.
- **Desks (PLANT3D.md §14):** the WTP's screens (overview, pretreatment, filters, RO, demin, wastes) are on its own
  desk `00CWD10`; its overview is on the main control room's desks too, and holds only measurements, so nothing of
  the WTP is worked from there. The app works a desk's screens within 6 m of it (the main control room by its area).
- **Faults:** the raw water pumps' overloads, the band screens blocked, the coagulant and bisulphite pumps failing,
  a cartridge filter clogging, an RO concentrate valve stuck, a leaking O-ring, fast fouling, a mixed bed exhausting
  early, a demin tank's drain left open, the transfer pumps' overloads, the pit's pH probe drifting, the plant's demin
  tank drained. Each repaired at its equipment.
- **Procedures:** `wtp_start` (from `wtp_cold`, 17 steps, about 23 model minutes), `filter_backwash` and
  `ro_stop_flush` (from `cold_iron`).
- **Model cost:** the joined model grew from 1,112 to 1,696 values; a step takes about 1.45 times as long
  (apps/plant3d/sim/README.md).

## 9. Not built (deliberately)

Ultrafiltration, EDI and a second RO pass (0065); chemical unloading from tankers; the water's real chemistry (no
ion balances: tables, as the train has no steam tables beyond samples, PLANT3D.md §13); potable water and sewage
treatment (shown as buildings in the site, not operated).
