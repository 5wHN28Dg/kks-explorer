# Walkdown Plant: the staff (content plan)

**Status: DRAFT 2026-10-22**, before any code. Format: docs/PLANT3D.md format 2 (§14–§19). Decisions: 0062
(the staff model), 0063 (characters), 0064 (budgets). Everything here is invented and generic (R1): roles as most
combined-cycle plants have them, no plant's organisation chart, no names (people have call signs).

The user's decision (2026-10-22): "full roles to play". Staff follow shift rosters and daily routines, their work
changes the plant (isolations, permits, repairs, calibrations), the trainee can play any role with that role's own
task list, and NPCs fill the others.

## 1. Roles and how many

Per crew (four crews, A–D, on a rotation of two days, two nights, four off: 12-hour shifts 06:00–18:00 and
18:00–06:00) and on days (07:00–16:00, six days a week). Counts give a plant of about 2 trains at full build; the
first train's content uses the same numbers (people have work enough with the WTP and the BOP).

| Role (`id`) | Roster | Per crew / on days | Authorities (PLANT3D.md §16.3) | Plays | What they do |
|---|---|---|---|---|---|
| Shift supervisor (`shift_sup`) | shift | 1 | operate_screen, request, approve, issue, lock_process | yes | handover, approves and issues permits, answers trips, morning meeting, shift log |
| Control room operator (`ccr_op`) | shift | 2 | operate_screen, request, lock_process | yes | runs the plant from the screens, answers alarms, logs |
| Field operator (`field_op`) | shift | 3 (GT/HRSG, ST/BOP, CW/CT) | operate_local, request, lock_mechanical, lock_process | yes | rounds with readings, local operations, mechanical and process isolations |
| Electrical authorised person (`elec_ap`) | shift | 1 | operate_local, request, lock_electrical | yes | electrical isolations (rack out, lock, prove dead), switching |
| WTP operator (`wtp_op`) | shift | 1 | operate_local, operate_screen (the WTP's local panel), request, lock_mechanical, lock_process, sample | yes | the water treatment plant: rounds, backwash, regeneration, CIP |
| Shift chemist (`shift_chem`) | shift | 1 | sample, request | yes | cycle chemistry samples, WTP lab checks, dosing |
| Security guard (`guard`) | shift | 2 (plant gate, camp gate) | — | no | gates, patrol |
| I&C technician (`ic_tech`) | days | 4 | operate_local, accept, lock_instrument | yes | calibrations, transmitter faults, loop checks |
| I&C engineer (`ic_eng`) | days | 1 | request, accept | yes | plans I&C work, approves calibration results, meetings |
| Mechanical technician (`mech_tech`) | days | 6 | accept | yes | pump, valve and fan jobs; preventive maintenance |
| Mechanical engineer (`mech_eng`) | days | 1 | request, accept | yes | |
| Electrical technician (`elec_tech`) | days | 4 | accept, lock_electrical | yes | motors, breakers, lighting |
| Electrical engineer (`elec_eng`) | days | 1 | request, accept, lock_electrical | yes | |
| Maintenance supervisor (`maint_sup`) | days | 3 (mech, elec, I&C) | request, accept | yes | daily work list, assigns jobs, checks permits are in place |
| Chemist (`chemist`) | days | 2 | sample, request | yes | lab, WTP performance, chemical stock |
| HSE officer (`hse_officer`) | days | 2 | stop_work | yes | safety walks, permit audits, toolbox talks |
| Plant manager (`plant_mgr`) | days | 1 | — | yes | morning meeting, walk-round, reports |
| Operations manager (`ops_mgr`), maintenance manager (`maint_mgr`) | days | 1 each | approve | yes | meetings, planning, permits for major work |
| Contractor supervisor (`contractor_sup`) | days | 1 | request, accept | yes | the contractors' permits and their toolbox talk |
| Contractor (`contractor`) | days | 8 (two teams) | — | yes | scaffolding, insulation, painting, civil jobs under their supervisor's permit; the shortcuts the safety walk finds |
| Storekeeper (`store`) | days | 1 | — | no | tool and spares issue |
| Driver (`driver`) | shift | 1 | drive | yes | the bus runs of the shift (the shift changes and the day workers' times, PLANT3D.md §16.8); a pickup for jobs between them |
| Camp staff: cook, cleaner, laundry (`camp`) | days | 6 | — | no | mess hall, rooms, laundry |

12 people per crew (48 on the rotation, 12 on duty at a time) and 43 on days: 91 people, under the 200 limit; in
the plant at 10:00 on a weekday about 50, at night 12 (and the camp staff in the camp).

Role disciplines (PLANT3D.md §16.3): operators, the supervisor and the electrical authorised person `ops`; I&C
`inst`; mechanical `mech`; electrical technicians and engineer `elec`; chemists and the WTP operator `chem`;
contractors `civil`; HSE `hse`; managers `mgmt`; guards `security`; drivers `transport`; camp staff `camp`. A work's
permit is accepted by its discipline's `accept` holders (the contractor supervisor for `civil`).

## 2. A day

Clock (PLANT3D.md §16.1): `day_scale` 6. A 12-hour shift is 2 hours of model time; played at 1× with fast-forward in
the quiet stretches (the Note 9's cap, about 15× with the staff step, PLANT3D.md §18.4) a shift takes 40–90 minutes of the trainee's time,
depending on how much of it is theirs to do. Walking is not compressed: a 300 m walk takes 4 minutes, which the clock
shows as 23. Tasks' clock minutes are set so a round of 12 readings takes about 45 clock minutes, as on site.

| Clock | Shift crew | Day workers | Camp |
|---|---|---|---|
| 05:15–05:45 | night crew on duty; day crew wakes, breakfast | | mess open |
| 05:40 | bus from the camp gate | | |
| 05:45–06:00 | handover at each post (slots at `start-0:15`): the control room desk, the field office, the WTP panel (shift log, open permits, alarms, running equipment); the night crew goes off duty at 06:00 | | |
| 06:30 | | buses at 06:30 and 06:45 | |
| 07:00–07:20 | | toolbox talk per discipline (HSE officer visits one); the maintenance supervisors' daily work list | |
| 07:30 | supervisor at the morning meeting (control building) | managers, maintenance supervisors, HSE, chemist | |
| 08:00– | rounds every 2 hours; permit requests come in; supervisor approves, operators isolate | jobs start as their permits are issued | |
| 10:00, 14:00 | | safety walks (HSE officer; the plant manager on Mondays of the week list) | |
| 12:00–13:00 | breaks in turn (meal brought to the control room for the operators) | lunch at the mess (bus) | mess open |
| 15:00–16:00 | permits returned, isolations removed, equipment back in service | | |
| 16:15 | | bus to the camp | |
| 17:45–18:00 | handover to the night crew | | |
| evening | | | dinner, gym, laundry, prayer room, recreation, rooms |
| 22:30 | | | lights out in the blocks |

## 3. Tasks that change the plant

Each is a task (PLANT3D.md §16.6) with its steps and, for work on equipment, a work (§15.2) with its permit.

| Task | Who | Steps that touch the model | What the trainee sees on the other side |
|---|---|---|---|
| Field round | field op | `read` of every local gauge on the route; a finding when a value is outside its range | the CCR operator gets the round's findings by radio |
| Start or stop on instruction | field op ← CCR op (`call`) | the `local` op (a CW pump discharge valve to its start position, the condenser vents) | the CCR operator waits for the field's "done" before the next step of a procedure |
| Corrective job on a pump | mech tech, maint sup, shift sup, field op, elec AP | `permit` request → approve → `lock` the breaker (elec AP) and the valve (field op) → issue → accept → `work` (bearing, coupling) → `done` repairs the fault → return → `unlock` → close; then the operator starts the pump again | on the screens: CW pump B locked out (padlock, PTW number), its start refused with the failed value `iso_cw_b_locked`; its standby auto-start skipped. In the field: a chain, padlock and danger tag on the valve's handwheel, a padlock and tag on the breaker |
| Isolating a transmitter | I&C tech, CCR op | the CCR op shelves nothing: the isolation's point (kind `instrument`) suppresses its alarms; the reading holds (`hold` node) and is marked isolated; the 2-out-of-3 condenser pressure trip runs 2 out of 2 on the others | the condenser pressure 30MAG10CP002 shows "isolated, PTW-0007" and a held value on the operator's screen |
| Calibration | I&C tech | the work's `set` puts the transmitter's drift (a fault the scenario sets slowly) back to 0 | the reading jumps back into line with its two partners when the permit is returned |
| Preventive maintenance | mech or elec tech, by the week list | a work without a fault (greasing a fan motor: the fan locked out for 20 clock minutes) | a cooling tower fan out of service: the cold water a little warmer at high load |
| Filter backwash, MB regeneration, RO CIP | WTP op (WATER-TREATMENT.md §6) | the WTP's machine commands, with permits only where hands go into the equipment | the demin tank level falls while a train is out |
| Samples | shift chemist, chemist | `read` of analysers and sample points; a finding goes to the CCR | |
| Safety walk | HSE officer | none; finds unsafe acts (`seen`) and stops work | the trainee's own unsafe acts are found the same way |
| Answer an alarm | CCR op (priority 1 alarms) → field op (`call`) | acknowledge; the field op goes to the alarm's `where` and reports | |
| Trip response | shift sup | radio, then a meeting at the control room desk | |

**What an NPC does with a refusal:** the same as a trainee should: an op refused for a permissive or a lock goes to
the task's `else` (report to the supervisor, wait, try again once), never round the rule.

## 4. Unsafe acts and the safety walk

Zones carry the PPE of the place (the halls with machines of 85 dB(A) and over: hearing protection, as the signs;
everywhere outside the buildings: helmet, boots, glasses; the chemical area of the WTP: face shield and apron when
handling acids). A contractor's task may `choose` a shortcut (weight 1 in 12: working at height without the harness
clipped, skipping the face shield) and is an unsafe act until found. The HSE officer's walk passes through the zones
where work is going on; an unsafe act in the officer's zone is seen and stopped, and recorded. The trainee is held to
the same rules.

## 5. Off duty and the camp

Off-duty routines (SITE.md, camp): meals at the mess at fixed times (05:15–06:15, 11:30–13:30 for the day staff,
17:30–19:30), then `choose` among the gym, laundry, prayer room, recreation room and the own room, by weights per
role; sleep from 22:30 to the roster's wake-up. Night crews sleep by day. The buses run at the shift changes and the
day workers' times; anyone may walk (the camp gate is 130 m from the plant gate, SITE.md).


A trainee who plays a role through the end of its shift may follow the evening in the camp or sleep to the next
shift (a jump, PLANT3D.md §17.6), which is allowed when the plant is quiet: the night passes without a change to the
plant, and the debrief lists the night crew's slots as done by the other crew.

## 6. What the first content holds

M2–M4 (MILESTONES.md) build this in steps: first the operators and the permit flow on the first train, then the
maintenance disciplines with their jobs, then the WTP's people, then the camp and the full day. Scenario seeds pick a
day; trainer faults (format 1) make the corrective jobs, so a trainer chooses the day's work.
