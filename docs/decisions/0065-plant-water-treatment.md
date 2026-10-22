# 0065 Walkdown Plant's water treatment: clarifiers, media filters, one-pass RO, degasser and mixed beds

Date 2026-10-22 · Scope: docs/plant3d/WATER-TREATMENT.md, the `wtp` and `intake` areas, their model · Status:
**proposed**, before any content (the user's decision of 2026-10-22: a generic river-water-to-demin plant, walkable
and operable) · Extends 0054; no new dependency

**Question:** which treatment train does the generic plant have? The user named the usual options: RO in two passes,
or RO with mixed beds or EDI, ultrafiltration optional. The plant must teach (procedures named by the user: start-up,
RO CIP, mixed-bed regeneration, filter backwash), stay plausible, and add as little drawing and model cost as it can.

## Findings

| Option | What it gives | Source |
|---|---|---|
| Media filters before RO | SDI < 5 on surface water with conventional pretreatment: an RO designed at 12–16 gfd (20–27 L/m²h) | [FT] DuPont FilmTec manual, table 22, p. 91 |
| Ultrafiltration before RO | SDI < 2.5, higher flux (16–20 gfd); its own backwash every 15–60 min and chemical cleans | [FT] table 22; US EPA Membrane Filtration Guidance Manual p. 238–241 |
| Mixed bed after RO | makeup < 0.1 µS/cm, silica < 10 µg/kg; run ≥ 24 h, a ~4-hour regeneration with acid and caustic | DuPont Tech Fact 45-D01127-en; IAPWS TGD3-10 §6.8 |
| EDI after RO | the same quality without regenerant chemicals, continuously; 90–95 % recovery; sensitive to CO₂ and hardness | vendor manuals (E-Cell), secondary |
| Second RO pass | lowers permeate to a few µS/cm; still needs a polisher for HRSG makeup | [FT] p. 97 |

The user asked for a mixed-bed regeneration procedure: only a mixed bed has one. EDI and a second pass add equipment
without a procedure the trainee works through. UF adds a second backwashing filter system the media filters already
teach.

## Choice

Intake → pre-chlorination → coagulation and flocculation → two solids-contact clarifiers → six gravity media filters →
filtered water tank (cooling tower makeup, service water, RO feed) → SBS, antiscalant, 5 µm cartridges → two RO trains
(2:1, 75 % recovery) → forced-draft degasser → two mixed beds → two demin tanks → transfer to the plant's demin tank;
neutralisation pit and sludge thickener with a filter press. **Not built:** UF, EDI, a second RO pass (named as
alternatives in WATER-TREATMENT.md §9). Numbers and sources: WATER-TREATMENT.md §2–§3.

**When to revisit:** if trainees need an EDI or UF plant (a second WTP variant, as format 1 §13 plans alternative
cooling ends); if the model's cost on the Note 9 (its step with the WTP added) lowers the fast-forward cap below 12×.
