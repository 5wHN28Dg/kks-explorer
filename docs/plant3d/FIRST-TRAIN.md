# Walkdown Plant: the first train (content plan)

**Status: DRAFT 2026-10-15**, before any content or code (decision 0054). Format: docs/PLANT3D.md (format 1). The
user's first goal (2026-10-15): one gas turbine with its generator, its HRSG, the steam turbine hall with the steam
turbine and generator, and a wet cooling tower with a water-cooled condenser and circulating water pumps, walkable
and operable through a cold start with faked behaviour, alarms and sounds, meeting the frame rules on the Note 9 and
the laptop. The rest of the 2-2-1 plant (R2) comes later from the same kit.

**Everything here is invented** (R1): the plant, its layout, its sizes and its codes. Codes follow the public KKS
key (§1); sizes are round, typical values for the class of machine, chosen to be plausible, not taken from any
plant. The content exists since 2026-10-16 (`data/plant3d`, made by `tools/plant3d/make_content.py`) and is now the
source of the codes, positions and numbers; "As built" notes below record where it settled what this plan left
open.

## 1. KKS codes

**Sources** (public; VGB's own key tables are sold and licensed, so meanings below are short and in our own words, and
the plant's decoder table holds only the codes this plant uses):
- [W] German Wikipedia, "Kraftwerk-Kennzeichensystem": https://de.wikipedia.org/wiki/Kraftwerk-Kennzeichensystem
- [E1] Eskom, "KKS Coding Standard" 240-93576498 Rev 1 (a utility's generic coding rules, published in a public
  tender): https://www.etenders.gov.za/home/Download/?blobName=2c66bb9c-a4bb-4ee4-9e60-b850846444d7.pdf&downloadedFileName=240-93576498+-+KKS+Coding+Standard.pdf
- [E2] Eskom, "KKS Key Part Standard" 348-694071 Rev 6 (an extract of the function and equipment keys, published in a
  public tender): https://www.etenders.gov.za/home/Download?blobName=fd360d64-41e6-464a-9a24-bf7aaf68a5cb.pdf&downloadedFileName=348-694071+KKS+Key+Part+Standard+Rev+6.pdf
- [H] handbook copies seen only in search excerpts (the MB gas turbine group, which [E2] lacks): McGraw-Hill
  AccessEngineering "Appendix I: KKS System" (https://www.accessengineeringlibrary.com/content/book/9780071809894/back-matter/appendix9)
  and a manufacturer's KKS handbook. Lower confidence: to re-check against the printed key before the format freezes.
- Licensing: vgbe, "KKS Documents and Licensing" (2023):
  https://www.vgbe.energy/wp-content/uploads/2023/04/KKS-Licensing-2023-01-01-EXT.pdf

**As built (2026-10-16):** the content uses every code below, and more of the same kinds (pipes `…BR…`, transmitters
and gauges, the auxiliary steam and demineralised water tank instruments `00QHA10CP001`, `00GHC10CL001`). Where the
table leaves a choice:
- the HRSG's inlet duct and casing are one piece of equipment, `10HNA10` (the kit's `hrsg` part); the heating
  surfaces in it are `hrsg_module` pieces with their system codes (`10HAH30`, `10HAJ10`, …, `10HAC30AC001`/`AC002`);
  `10UHA10` is the roof platform, `10UHN10` the stack platform;
- the GT's exhaust diffuser (x 60–80) is `10MBR10`, carrying the twelve thermocouples;
- the steam turbine is two pieces, `30MAA10` (HP) and `30MAB10` (the IP/LP casing); `30MAC10`, the LP section of
  that casing, has no piece of its own (format 1 has no component level);
- `10MBM10` and `10MBY10` are the systems of the flame detectors and speed probes, which are fixed to the GT.

**Rules used** ([E1], [W]): code = G, F0, F1F2F3, FN, then A1A2, AN, A3.
- **G** (level 0): `0` common plant, `1` gas turbine train 1 (GT1, its generator, HRSG 1), `2` train 2 (later),
  `3` the steam turbine unit (ST, its generator, condenser, circulating water and cooling tower, which serve it
  alone). A unit is what can feed the grid on its own [E1].
- **F0** `0`: no identical parallel systems in format 1.
- **FN** in decades along the flow [E1]. **Our convention** where no public rule was found: in the HRSG the pressure
  levels take decades, LP 10, IP 20, HP 30 (the two HP economiser stages are heating surfaces 10HAC30AC001 and
  AC002 of one system, not two decades: decades go per process segment, units only for parallel streams [E1]); the drums are `BB`
  vessels under their evaporator (HAD); the HP bypass is placed under MAN with the LP bypass (MAN10 HP, MAN20 LP).
- **AN for valves** [E1]: 001–099 control valves, 101–199 motor-operated on/off, 201–299 pneumatic, hydraulic or
  solenoid, 401–499 drains and vents, 501–599 hand valves, 901–999 safety valves. Measurements [E1]: 001–099
  analogue to the control room (transmitters), 301–399 binary (switches), 401–499 test points, 501–599 local
  (gauges, glasses). Pumps and fans
  of one duty: 001, 002, 003 = A, B, C.

| Code | What (our words) | Key letters and source |
|---|---|---|
| **Gas turbine train 1 (G = 1)** | | |
| 10MBA10 | Gas turbine 1 (compressor and turbine, one rotor) | MBA [H] |
| 10MBD10CY001–004 | GT bearing vibration | MBD bearings [H]; CY [E2] |
| 10MBJ10 | GT start-up system: static frequency converter (the generator as motor) | MBJ start-up unit [H] |
| 10MBK10AE001 | GT turning gear | MBK gear incl. turning gear [H]; AE [E2] |
| 10MBL10AT001 | Air intake filter house | MBL intake air [H]; AT [E2] |
| 10MBM10 | Combustion system | MBM [H] |
| 10MBM10CB001–002 | Flame detectors | CB radiation, incl. flame monitoring [W] |
| 10MBP10AA201, AA001 | Fuel gas stop valve, fuel gas control valve | MBP gaseous fuel [H] |
| 10MBP10CP001 | Fuel gas pressure | CP [E2] |
| 10MBR10CT001–012 | Exhaust temperature thermocouples (spread from them) | MBR exhaust [H]; CT [E2] |
| 10MBV10AP001, AP002 | GT lube oil pumps (AC main, DC emergency) | MBV lube oil [H]; AP [E2] |
| 10MBV10CP001–003 | GT lube oil header pressure (2 out of 3 for the trip) | |
| 10MBY10CS001–003 | GT speed | MBY electrical control and protection [H]; CS [E2] |
| 10MKA10 | Generator 1 | MKA [E2] |
| 10MKC10 | Generator 1 excitation | MKC [E2] |
| 10MKA10CT001–006 | Stator winding temperatures | |
| 10BAC10 | Generator 1 circuit breaker | BAC [E2], [W] |
| 10BAT10 | Step-up transformer 1 | BAT [E2], [W] |
| 10BBT10 | Unit auxiliary transformer 1 | BBT [E2] |
| 10UMB10 | GT 1 hall | UMB [E2], [W] |
| **HRSG 1 (G = 1)** | | |
| 10HNA10 | Inlet duct and casing gas path | HNA ducts [E2] |
| 10HNE10 | Stack | HNE [E2]; structure 10UHN10 |
| 10HAC10, 10HAD10 | LP economiser, LP evaporator | HAC, HAD [E2] |
| 10HAD10BB001 | LP drum with integral deaerator | BB [E2] |
| 10HAD10CL001 | LP drum level | |
| 10HAC20, 10HAD20, 10HAH20 | IP economiser, evaporator, superheater | HAH [E2] |
| 10HAD20BB001 | IP drum | |
| 10HAC30, 10HAD30, 10HAH30 | HP economiser (two stages: AC001, AC002), HP evaporator, HP superheater | |
| 10HAD30BB001 | HP drum | |
| 10HAD30CL001–003 | HP drum level (3 transmitters; 2 out of 3 for the trips) | CL [E2] |
| 10HAD30CL501 | HP drum level glass (local) | |
| 10HAD30CP001 | HP drum pressure | |
| 10HAJ10 | Reheater | HAJ [E2] |
| 10HAN30AA401–404, 10HAN30AA001 | HP superheater drains; HP start-up vent (control valve) | HAN drains and vents [E2] |
| 10HAN30BS001 | HP start-up vent silencer | BS silencer: as [H], to re-check against the printed key |
| 10LAC10AP001, AP002 | HP/IP feedwater pumps A, B | LAC [E2] |
| 10LAB30AA001 | HP feedwater control valve | LAB [E2] |
| 10LAE30AA001 | HP superheater spray control valve | LAE [E2], [W] |
| 10LBA30, 10LBA10 | HP steam, LP steam from HRSG 1 (decades as the HRSG: LP 10, HP 30) | LBA [E2] |
| 10LBA30CT001 | HP steam temperature | |
| 10LAC10CF001–002 | Feedwater pump A, B flow | CF [E2] |
| 30MAA10CT001 | HP turbine inlet steam temperature (superheat computed from it and the pressure) | |
| 30PAD10CY001–010 | Cooling tower fan vibration | CY [E2] |
| 10LBB10, 10LBC10 | Hot reheat, cold reheat (train 1 side) | LBB, LBC [E2] |
| 10LCQ10BB001 | Blowdown tank | LCQ [E2] |
| 10UHA10 | HRSG 1 structure | UHA [E2] |
| **Steam turbine unit (G = 3)** | | |
| 30MAA10, 30MAB10, 30MAC10 | HP turbine; IP and LP turbines (one IP/LP casing) | MAA, MAB, MAC [E2], [W] |
| 30MAD10CG001 | ST axial displacement (the thrust bearing's protection) | CG position [E2] |
| 30MAA10AA201, AA001 | HP stop valve, HP control valve | |
| 30MAD10CY001–008 | ST bearing vibration | MAD [E2]; CY |
| 30MAG10AC001 | Condenser | MAG [E2], [W]; AC |
| 30MAG10BB001 | Hotwell | |
| 30MAG10CP001–003 | Condenser pressure (2 out of 3 for the trip) | |
| 30MAG10CL001 | Hotwell level | |
| 30MAJ10AP001, AP002 | Vacuum pumps (liquid ring) A, B | MAJ air evacuation [E2] |
| 30MAK10AE001 | ST turning gear | MAK gear (incl. turning gear [H]) |
| 30MAN10AA001, 30MAN20AA001 | HP bypass valve, LP bypass valve | MAN bypass station [E2] (our placement of the HP bypass) |
| 30MAV10AP001, AP002, 30MAV20AP001 | ST lube oil pumps (AC, DC emergency), jacking oil pump | MAV [E2] |
| 30MAV10CP001–003 | ST lube oil pressure | |
| 30MAW10AA001 | Gland steam supply control valve | MAW [E2] |
| 30MAY10CS001–003 | ST speed | MAY [E2] |
| 30MKA10, 30MKC10, 30BAC10, 30BAT10 | ST generator, excitation, breaker, step-up transformer | |
| 30LCB10AP001, AP002 | Condensate extraction pumps A, B | LCB [E2] |
| 30LCA10AA001 | Condensate minimum flow (recirculation) valve | LCA [E2] |
| 30LCE10AA001 | LP bypass spray valve | LCE [E2] |
| 30PAC10AP001–003 | Circulating water pumps A, B, C | PAC [E2], [W] |
| 30PAC10AA101–103 | CW pump discharge valves (motor-operated butterfly) | |
| 30PAC10CP501–503 | CW pump discharge pressure gauges | |
| 30PAB10BR010, 30PAB20BR010 | CW supply, CW return | PAB [E2], [W] |
| 30PAB10AA401–404 | Condenser water box vents | |
| 30PAB10CF001 | CW flow | CF [E2] |
| 30PAD10 | Cooling tower | PAD [E2] |
| 30PAD10AN001–010 | Cooling tower fans 1–10 | AN [E2] (no own group for the fans) |
| 30PAD10BB001, CL001 | Cooling tower basin, its level | |
| 30PAR10AA001 | Cooling tower makeup control valve | PAR [E2] |
| 30UMA10, 30UQA10, 30URA10 | Turbine hall, CW pump house, cooling tower structure | UMA, UQA, URA [E2] |
| **Common (G = 0)** | | |
| 00QFA10AN001, AN002 | Instrument air compressors | QFA [E2] |
| 00QFB10CP001 | Instrument air header pressure | QFB [E2] |
| 00PGC10AP001, AP002 | Closed cooling water pumps | PGC [E2] |
| 00PGB10AC001 | Closed cooling water cooler | PGB [E2] |
| 00QHA10 | Auxiliary boiler | QHA [E2] |
| 00LBG10 | Auxiliary steam header | LBG [E2] |
| 00GHC10BB001 | Demineralised water tank | GHC [E2] |
| 00UCA10 | Control building | UCA [E2] |

## 2. The plant and the train

- **Configuration (R2):** two gas turbine trains (a heavy-duty gas turbine of about 250 MW, 50 Hz, 3,000 rpm, with an
  air-cooled generator; a horizontal, natural-circulation HRSG with three pressures and reheat; a stack without a
  bypass), one steam turbine of about 270 MW (an HP casing and a combined IP/LP casing, down exhaust) with a
  hydrogen- or air-cooled generator, one water-cooled condenser, one mechanical-draft wet cooling tower. Only train 1
  is built in the first goal; the steam turbine, condenser, circulating water and cooling tower are built whole,
  because train 2 later shares them.
- **Design values (round, plausible, invented):**

| | Value |
|---|---|
| Gas turbine | ~250 MW at 35 °C ambient; exhaust ~620 kg/s at ~600 °C; natural gas only |
| HRSG | HP 120 bar(a) / 560 °C, ~70 kg/s; reheat 28 bar(a) / 560 °C; LP 5 bar(a) / 250 °C; integral deaerator on the LP drum |
| Steam turbine | ~135 MW with one train, ~270 MW with two; sliding pressure; HP and LP bypass to the condenser |
| Condenser | about 10 kPa(a) at full load on a hot day (wet bulb ~25 °C, cold water ~30 °C); two halves (divided water boxes) |
| Circulating water | 3 × 50 % vertical pumps, 15,000 m³/h each at ~22 m head, ~1.25 MW motors; ΔT ~12.6 K across the condenser at full load (below) |
| Cooling tower | 10 cells (2 rows of 5), 16 × 16 m each, 9.5 m fans of ~200 kW; basin under the whole tower |
| Electrical | generators to step-up transformers and the grid; unit auxiliary transformers; the gas turbine starts with a static frequency converter (the generator as a motor) |

Heat balance check (order of magnitude, what a trainee might compute): the exhaust gives the HRSG about 620 kg/s ×
1.1 kJ/kg·K × (600 − 90) K ≈ 350 MW; with ~135 MW made by the steam turbine, each train sends about 220 MW to the
condenser. One train with one pump (on its curve it runs out a little past its 15,000 m³/h when it is alone; the model's
flow table shows it): 220 MW / (4.19 kJ/kg·K × 4,170 kg/s) ≈ 12.6 K across the condenser; two trains
with two pumps the same. Cold water at ~30 °C + 12.6 K + a terminal difference of ~4 K gives ~47 °C, about
10 kPa(a). A second pump with one train lowers the rise to ~6 K and the pressure to ~7.5 kPa(a): a reason for the
trainee to weigh pump power against vacuum (§4). Ten cells for ~440 MW and 30,000 m³/h are ~3,000 m³/h per cell, a
usual size for 16 m cells.

## 3. Layout (plot plan)

Plant coordinates in metres, x east, y north, z up, origin at the south-west corner of the turbine hall's ground
floor. Ground at z = 0. Train 2 is the mirror of train 1 across y = 0 (later).

```
 y
 80 ┤                 ┌──────── GT1 hall ─────────┐┌─ HRSG 1 ────────────────┐ (stack)
 60 ┤                 │ GEN1   GT1  ▒intake▒      ││ ═════════════════════ ◯ │
    ┤                 └────────────────────────────┘└─────────────────────────┘
 45 ┤   [GSU1][UAT1]        [feed pumps 1]   [HRSG 1 platforms, drums at +32]
    ┤   ──────── road ────────────────────────────────────────────────────────────────── road ──
 25 ┤ ┌ control ┐  ┌────────── turbine hall (30UMA) ──────────┐  [demin tank]   ┌ CW pump house ┐┌────── cooling tower, 2 × 5 cells ──────┐
  0 ┤ │ building│  │ GEN3  ST (HP | IP/LP)   op. floor +12 m  │  [aux boiler]   │ 3 × CW pumps  ││ ▢ ▢ ▢ ▢ ▢                               │
    ┤ └─────────┘  │ condenser below LP, CEPs in pit −6 m    │                  └──────────────┘│ ▢ ▢ ▢ ▢ ▢   basin                       │
−25 ┤              └──────────────────────────────────────────┘ ═══ CW supply/return (DN 2200, buried) ═══╡└───────────────────────────────────────┘
    ┼──────┬───────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬── x
        −40      0        40        80       120       160       200       240       280
```

| Area (`id`) | Plan bounds (x0, y0 – x1, y1) | What is in it |
|---|---|---|
| `control` | −40, −15 – −10, 15 | control building: control room (the trainee's start), electrical rooms, battery room door |
| `st` | 0, −25 – 80, 25 | turbine hall 80 × 50 m, 32 m high, crane; ground floor, mezzanine +6 m, operating floor +12 m; ST on a table foundation; condenser under the LP casing, its water boxes and the condensate extraction pumps in a pit down to −6 m; ST lube oil, gland steam and vacuum pumps; generator 3 at the west end; HP/LP bypass valves |
| `gt1` | 0, 50 – 80, 92 | GT1 hall 80 × 30 m (y 50–80), 20 m high: generator 1 at the west (cold-end drive), GT1 at x 30–60 on axis y = 65, air intake filter house on the roof, exhaust diffuser out of the east wall; lube oil skid, SFC and excitation rooms, fuel gas skid north of the hall (y 82–90) |
| `hrsg1` | 80, 45 – 175, 85 | inlet duct x 80–95; HRSG casing x 95–150, 22 m wide (y 54–76), 30 m high; drums on top at +32 (HP, IP, LP/deaerator); stack x 160, y 65, Ø 7 m, 60 m; feedwater pumps and blowdown tank at grade south of the casing; stairs to every drum platform |
| `trafo1` | −30, 40 – 0, 60 | the transformer yard: step-up transformer 1, unit auxiliary transformer 1 and (as built) the steam turbine's step-up transformer 30BAT10 |
| `bop` | 85, −25 – 135, 25 | auxiliary boiler house, demineralised water tank, instrument air compressors, closed cooling water pumps and heat exchangers |
| `cw` | 140, −20 – 165, 20 | CW pump house: 3 vertical pumps in a wet pit fed from the tower basin, discharge valves, the CW supply and return headers |
| `ct` | 170, −35 – 260, 35 | cooling tower: 2 rows of 5 cells (x 175–255, y −16–16), fan decks at +14, stair towers at both ends, basin −2 m, makeup and blowdown |
| `rack` | 80, −25 – 85, 45 | (as built) the pipe rack between the turbine hall and `bop`, over the road: an area of its own so the rack has somewhere to stand |

**As built:** the steam pipes enter the steam turbine from below the operating floor (the kit's turbine nozzles
point down), so they run on the rack's tiers at +8 and +10 and under the +12 floor; the CW supply runs at −4.5 m
along y = −30 and the return at −12 m along y = −33, so the two cross without meeting.

The CW pipes (DN 2200) run buried along y ≈ −30, south of every area, from the pump house to the turbine hall and
come up into the condenser pit (−6 m) from below (PLANT3D.md §4 has the supply pipe as its example); the return goes to the tower's hot water distribution at +12. The HRSG's main steam, hot and cold
reheat and LP steam leave the top of HRSG 1 and run on a pipe rack along x ≈ 82 (between the turbine hall and `bop`) south into the turbine hall's east wall at +12.
Pipes belong to the area where they start and may cross other areas (PLANT3D.md §3).
Roads at least 5 m wide between the areas (the 5 m strips between `st`, `bop`, `cw` and `ct`), except where machines join: GT1's exhaust diffuser runs straight into HRSG 1's inlet duct at x = 80. Every area has a way in on foot, and the overview map reads like a plot plan.

## 4. The cold start: what must be operable, and how it is faked

Starting state (`cold_iron` scenario): ambient 35 °C, wet bulb 25 °C; grid available, the auxiliary transformers energised; every
machine stopped; turning gears off; water systems filled; HRSG drums cold at their start-up level; condenser and
turbine at atmospheric pressure; the alarms a stopped plant would raise (condenser pressure high 30MAG10CP001–003, GT and ST lube oil
pressure low 10MBV10CP001–003 and 30MAV10CP001–003) are **suppressed by design** while their machine is at
standstill with its oil pumps or vacuum pumps off (PLANT3D.md §7.6 `suppress`), and come alive as each system
starts; the lube oil low-low trips and the condenser pressure high-high trip start **latched** and can be reset only
once their cause has cleared (the scenario's `latched`), so the trainee learns to read and reset trips before a
start.

The trainee works from the control room screens and in the field. About 40 minutes of play (fast-forward in the
long waits, PLANT3D.md §7.9) stand for about 4 hours of a real cold start.

**As built (2026-10-16):**
- **Time.** The cold start run by its procedure in the model alone takes 110 min of model time; with fast-forward
  wherever §7.9 allows it that is about 10 min of the trainee's time, walking and reading on top. The HRSG warm-up
  sets the pace: at minimum GT load the HP drum's saturation temperature rises about 3.5 K/min, and the steam
  turbine may roll at 40 bar.
- **Alarms of a system still being started** are suppressed by design until its value is first in the normal range
  after a start (lube oil 2.0 bar, instrument air 6.5 bar, condenser below 13 kPa(a)), and again once the machine is
  at standstill with its pumps off. Without this the low-pressure alarms would sound at every correct start.
- **Step 4:** a CW pump's start is *refused* unless its discharge valve stands at 10–20 % (the permissive of
  PLANT3D.md §7.2's example); the pressure surge of a start against an open valve is therefore not modelled, and has
  no alarm in §5 either.
- **Interlocks:** a stopped CW pump closes its discharge valve; low lube oil pressure with the AC pump selected
  starts the DC pump (GT and ST); a tripped closed cooling water pump starts the standby one; condenser pressure
  high-high, no CW flow or no condensate pump puts both bypass controllers in manual (closed).
- **Trips beyond the list below:** the generator protection opens a generator breaker in the step after its machine
  tripped (`gen1_trip_prot`, `gen3_trip_prot`, first-out group of their machine); a closed cooling water pump trips
  on its motor fault. The GT's exhaust spread trips at 60 K for 3 s (the alarm of §5 is at 30 K); compressor surge is
  a fall of compressor discharge pressure of 1.5 bar against its 5 s average; GT bearing vibration trips at 25 mm/s
  on any bearing for 2 s.
- **The hotwell** has a makeup that opens below 0 mm and a spill to the demineralised water tank above +50 mm, so
  the level holds through the start.
- **Trainer faults** (the scenario's faults without a condition, PLANT3D.md §7.8) make every trip and interlock
  fire, each fan's and each pump's included; the tests run each, most from the end of the cold start and the CW
  valve faults at the pump's start (`ref/vectors/plant3d-v1.json`, `forks`).

| # | System (codes §1) | What the trainee does | Faked behaviour (values, lags) | What it teaches |
|---|---|---|---|---|
| 1 | Instrument air | start a compressor | header pressure ramps 0 → 7 bar in ~60 s; pneumatic valves refuse to move below 4 bar (permissive) | air-operated valves need air first |
| 2 | Closed cooling water | start a CCW pump, open the cooler | flow lag τ 5 s; lube oil temperatures stay cool only with CCW | why the auxiliaries start first |
| 3 | Cooling tower basin | check level, open makeup if needed | basin level integrates makeup − evaporation − blowdown | the source of all CW |
| 4 | CW pump A | set its discharge valve to the start position (~15 %), start the pump, open the valve | motor current: inrush 6× for 4 s then a table of flow; discharge pressure surge if started with the valve open on an empty pipe (a spike alarm and a heavy thud); valve travel 60 s | starting large pumps against a nearly closed valve; filling a pipe slowly |
| 5 | Condenser water boxes | open the vents until water shows, then close | water box "full" after a time ∝ flow; CW flow and condenser ΔT appear | air in the water boxes |
| 6 | Hotwell, condensate | check hotwell level (demin makeup), start a condensate extraction pump on minimum flow recirculation | hotwell level integrates makeup + condensed steam − CEP flow; the pump trips on hotwell level low-low | minimum flow protection |
| 7 | ST lube oil, jacking oil, turning gear | start the AC lube oil pump, then jacking oil, then the turning gear | oil pressure lag τ 3 s; the turning gear needs oil and jacking pressure (permissives); rotor eccentricity falls with time on turning gear (table; ~20 min of model time, compressed from hours) | a hot or bent rotor; the order of the oil systems |
| 8 | GT lube oil, turning gear | the same for GT1 | as 7 | |
| 9 | Auxiliary steam | start the auxiliary boiler | aux steam pressure ramp to 12 bar in ~10 min of model time (compressed: a real cold auxiliary boiler takes longer) | where the first steam comes from |
| 10 | Gland steam | admit sealing steam to the ST glands | **refused unless the turning gear runs** (steam on a stopped rotor bows it) | an interlock with a reason |
| 11 | Vacuum | start both vacuum pumps (hogging) | condenser pressure lag from 101 kPa: to ~30 kPa without gland steam (air leaks in at the glands), to ~8 kPa with it (limited by the cold water temperature); one pump kept for holding | why gland steam comes before vacuum |
| 12 | HRSG | check drum levels, open the superheater drains and start-up vents, start a feedwater pump | drum level integrates feed − steam − blowdown; drain and vent positions; feedwater pump minimum flow | draining condensate from cold superheaters |
| 13 | GT1 start | check the start permissives on the screen, then Start | machine: crank by the SFC to ~25 % speed, **HRSG purge** (5 volume changes, ~8 min model time), coast to ~15 %, ignition, flame detected, acceleration, SFC off at ~70 %, full speed no load; exhaust temperature table of speed and fuel; GT sound rises in pitch with speed | the purge; the start sequence stages |
| 14 | GT1 generator | excitation on, synchronise (synchroscope: frequency and phase), close the breaker, take minimum load | voltage lag τ 2 s; synchroscope phase = integral of the frequency difference; the sync-check relay refuses a close outside ±10° phase, ±0.1 Hz and ±5 % voltage (permissive, with the reason shown) | synchronising |
| 15 | HRSG warm-up | hold the GT at minimum load; close drains and vents as pressure rises; watch drum level | drum pressure lags toward a target set by exhaust heat (τ minutes); **swell**: drum level rises when boiling starts (a lag difference of heat input) — a trainee who drains it then gets low level when it settles | drum level swell and shrink |
| 16 | Turbine bypass | put HP and LP bypass in automatic | bypass opens to hold pressure; **blocked unless condenser pressure < 25 kPa and CW flow is on** (interlock); spray water keeps bypass steam temperature down | the bypass needs the condenser |
| 17 | Cooling tower fans | start fans as CW return temperature rises | CW cold-water temperature: a table of heat load, fans running and the wet-bulb temperature; each fan's sound and its fan stack's spray | matching cooling to load |
| 18 | ST roll | when steam has ≥ 50 K superheat and is matched to the HP casing temperature: reset, open stop valves, roll | speed ramps: hold at ~800 rpm for warming, then through the critical speed band (~1,600–1,900 rpm) to 3,000 rpm; **bearing vibration rises in the band** (table) and trips if the trainee holds there | critical speeds; steam/metal matching |
| 19 | ST generator | synchronise as 14, load | as 14 | |
| 20 | Loading | raise GT load; bypass valves close as the ST takes the steam; start CW pump B when the condenser pressure rises | sliding pressure; condenser pressure a table of heat load, CW flow and cold-water temperature, lag τ 60 s | the plant as one system |

**Interlocks and trips of the first train** (each a model trip or interlock with its code, §5):
GT: lube oil pressure low-low; flame failure; exhaust temperature high-high; exhaust temperature spread high;
overspeed; HRSG drum level high-high or low-low (HRSG protection trips the GT); compressor surge (fast pressure
drop). ST: lube oil pressure low-low; condenser pressure high-high; overspeed; axial displacement; bearing vibration
high-high; HP steam temperature low (wet steam). CW pump: motor overload; basin level low-low; discharge valve not
open after 120 s. CEP: hotwell level low-low. Cooling tower fan: vibration high-high.

## 5. Alarms

Each alarm names its measurement's KKS code (or the equipment's own code for a drive's trip or state alarm); a
range "001–003" stands for one alarm per code and the ISA-5.1 letters on its bubble (P pressure, T temperature, L level,
F flow, S speed, V vibration, Z position, B burner flame; A alarm, H/L high/low, HH/LL the trip levels). Limits are
round and invented; priority 1 is the most urgent (PLANT3D.md §7.6). Trip-level entries (HH/LL) are also trips (§4).

| Code | ISA | Alarm | Limit | Prio |
|---|---|---|---|---|
| 00QFB10CP001 | PAL | Instrument air header pressure low | < 5.0 bar | 1 |
| 00PGC10AP001–002 | — | Closed cooling water pump tripped | motor trip | 2 |
| 10MBV10CP001–003 | PAL / PALL | GT lube oil pressure low / low-low (trip) | < 1.8 / < 1.2 bar | 2 / 1 |
| 10MBK10AE001 | — | GT turning gear not running with the rotor hot | stopped, wheel space > 150 °C | 2 |
| 10MBP10CP001 | PAL | Fuel gas pressure low (start blocked) | < 25 bar | 2 |
| 10MBM10CB001–002 | BAL | GT flame failure (trip) | flame lost after ignition | 1 |
| 10MBR10CT001–012 | TAH / TAHH | GT exhaust temperature high / high-high (trip) | > 620 / > 640 °C | 2 / 1 |
| 10MBR10CT001–012 | TDAH | GT exhaust temperature spread high (as built: that thermocouple more than 30 K from the mean) | > 30 K | 2 |
| 10MBY10CS001–003 | SAHH | GT overspeed (trip) | > 110 % | 1 |
| 10MBD10CY001–004 | VAH / VAHH | GT bearing vibration high / high-high (trip) | > 12 / > 25 mm/s | 2 / 1 |
| 10MKA10CT001–006 | TAH | Generator 1 stator winding temperature high | > 120 °C | 2 |
| 10BAC10 | — | Generator 1 breaker tripped by protection | breaker trip | 1 |
| 10HAD30CL001–003 | LAH / LAHH | HP drum level high / high-high (GT trip) | > +150 / > +250 mm | 2 / 1 |
| 10HAD30CL001–003 | LAL / LALL | HP drum level low / low-low (GT trip) | < −150 / < −300 mm | 2 / 1 |
| 10HAD10CL001 | LAL | LP drum level low | < −200 mm | 2 |
| 10HAD30CP001 | — | HP drum warming too fast (saturation temperature from the drum pressure) | > 4 K/min | 3 |
| 10LAC10CF001–002 | FAL | Feedwater pump flow below minimum (recirculation not open) | < 15 % for 10 s | 2 |
| 10LBA30CT001 | TAH | HP steam temperature high | > 575 °C | 2 |
| 30MAG10CP001–003 | PAH / PAHH | Condenser pressure high / high-high (ST trip, bypass blocked) | > 15 / > 25 kPa(a) | 2 / 1 |
| 30MAG10CL001 | LAH / LAL / LALL | Hotwell level high / low / low-low (CEP trip) | +200 / −200 / −400 mm | 2 / 2 / 1 |
| 30MAV10CP001–003 | PAL / PALL | ST lube oil pressure low / low-low (trip) | < 1.8 / < 1.2 bar | 2 / 1 |
| 30MAK10AE001 | — | ST turning gear stopped with gland steam on | stopped and 30MAW10AA001 open | 1 |
| 30MAD10CY001–008 | VAH / VAHH | ST bearing vibration high / high-high (trip) | > 125 / > 250 µm (shaft, peak to peak) | 2 / 1 |
| 30MAY10CS001–003 | SAHH | ST overspeed (trip) | > 110 % | 1 |
| 30MAA10CT001 | TAL | HP steam superheat too low to roll | < 50 K | 3 |
| 30MAN10AA001 | ZAH | HP bypass wide open for over 30 min | > 90 % | 3 |
| 30LCB10AP001–002 | — | Condensate pump on minimum flow too long (overheating) | > 30 min | 3 |
| 30PAC10AP001–003 | — | CW pump tripped (overcurrent, basin level low-low) | motor trip | 1 |
| 30PAC10AA101–103 | ZAL | CW pump discharge valve not open 120 s after start (pump trip) | < 95 % | 1 |
| 30PAB10CF001 | FAL | CW flow low | < 10,000 m³/h with the ST running | 1 |
| 30PAD10CL001 | LAL / LALL | Cooling tower basin level low / low-low | −0.3 / −0.6 m | 2 / 1 |
| 30PAD10CY001–010 | VAHH | Cooling tower fan vibration high-high (fan trip) | > 10 mm/s | 2 |
| 30PAB20BR010 | TAH | CW return temperature high | > 48 °C | 2 |

## 6. Sounds

| Source | What is heard | Made from |
|---|---|---|
| Gas turbine | compressor whine (blade-pass tone ∝ speed), combustion roar ∝ fuel, exhaust rumble at the HRSG inlet | synth layers (tone + band noise) |
| SFC, excitation | high-pitched electronic whine in the SFC room | synth |
| Generators | 100 Hz magnetic hum and its harmonics; fan noise ∝ speed | synth |
| Steam turbine | steam rush ∝ flow, rotor hum ∝ speed; turning gear clicks | synth + one recorded mechanical loop |
| Pumps and motors | motor hum (50/100 Hz) and fan noise ∝ speed; CW pumps louder and lower | synth + recorded motor loops |
| Vacuum pumps (liquid ring) | churning water, a gurgle | recorded loop |
| Cooling tower | falling water (broadband "rain", loud under the tower), fans | synth noise + recorded water loop |
| Vents, drains, bypass | hiss to roar ∝ flow, silencer muffled | synth noise |
| Breakers, valves | clunk of a breaker; motor operator whirr while a valve travels | recorded one-shots |
| Alarms | control room horn per priority; field beacons' sounders | synth tones |
| People cues | footsteps on concrete, grating and steel stairs; doors | recorded one-shots |
| Ambience | wind, distant plant hum (level from how much runs) | synth + recorded wind loop |

Recorded clips: CC0 only (0054), each with its source and licence in the sound library. The plant gets loud where a
real plant is (the GT hall at full speed); the app caps its output level and shows a hearing-protection sign at the
doors, as on site.
