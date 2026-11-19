# Adoption check, 2026-11-19 (UI/UX policy v4.13, phase 1)

Both products checked against the rules that can never be waived (S1 to S3, S8, A10, T0, T1, T9, Z1) and against
U1, A1 and A5, as the rulebook's adoption phase 1 asks. Done by reading the code on main at ae3440d8 and the existing
evidence: the 2026-11 full audit ([2026-11.md](2026-11.md)) and the audits posted on later PRs. No new screenshots,
builds or runs were made for this check. Every fail is tracked; fails found while adopting count as pre-existing once
tracked (rulebook 9.2).

| Rule | Walkdown | Walkdown Plant | Evidence |
|---|---|---|---|
| S1 Losing data is undoable or confirmed | **Fail**: the photo editor's Cancel drops marks on the web and GNOME; Clear removed without a count or Undo (web, Windows, Android); refusing a join request doesn't ask (web, GNOME, Windows) | **Fail**: the instructor's "Restart in it" drops the running scenario without asking | #414, #415, #416, #417; #437 |
| S2 Confirmations are safe | **Fail** where the S1 follow-ups add questions; elsewhere fixed by #409 (#365) | **Fail**: "Lock it anyway" has no destructive style; Plant has none | #414–#417; #437 |
| S3 Work is never lost silently | **Fail**: Escape, Close or leaving drops typed text (web, GNOME, Windows); Android's description and reading-correction Cancel | Pass from the code (typed text survives closing panels; the app being stopped not checked: GM5.2 at the full audit) | #366, #429, #430, #431, #436; 2026-11 audit D3 |
| S8 Live systems stay reachable | N/A for the four clients (they change no network, firewall or service). The server's update scripts keep the previous build and print the rollback, never touch SSH, but don't check health or report PASS or FAIL: **Fail** | N/A (no live system) | #441; `deploy/install-server-user.sh` |
| A10 No seizures | Pass: no flashing content in the clients (code reading) | **Fail (likely; to confirm with IRIS)**: lightning brightens the whole scene for 0.15 s; at 1× at most once in 2 s, but its slots follow model time, so in fast-forward (up to 60×) it averages 2.4 flashes a second, more than 3 in about one second in five; no flash analysis has been run. The alarm flashing is within the limit (the screens' banner toggles every 0.25 s: 2 flashes a second on small areas), but GM8.3 then asks for a photosensitivity warning before play | #443; `app/weather_view.gd`, `ui/mimic.gd` |
| T0 The law's interface duties | **Open, owner item**: the owner's checklist doesn't exist yet | **Open, owner item** | #442 |
| T1 No dark patterns | Pass: no nagging, pre-ticked consent, fake urgency or de-emphasised No found; the background-sync notice offers the settings "if you want"; updates install only when the person agrees (REQUIREMENTS R24) | Pass: no rewards, streaks or nagging | code reading |
| T9 Children | N/A (profile: adult plant staff; no tracking, ads or contact with strangers anyway) | N/A (profile) | profiles' applicability lists |
| Z1 Synthetic data | Pass for the evidence in the repository (2026-11 audit, synthetic fixtures, one shot removed for addresses); the runs are isolated (temporary servers, the emulator only, the VMs, GNOME's private session) | **Fail** (process): the Plant evidence runs use the real Godot user folder | #438 |
| U1 Every main task can be done | **Fail**: keyboard and tap alternatives (drag, pinch, the photo editor's boxes); the web's file pickers can't be reached from the keyboard; Back and Escape; Windows' Alt keys and scaling; the install warnings aren't explained beforehand | **Fail**: keyboard and gamepad in the Workshop's Info and the Settings panel; dragging on Android; no install steps | #375, #403, #366, #377; #418, #381, #425; #439 |
| A1 Text contrast | **Fail**: under 4.5:1, and under the profile's 7:1 for codes, values and body text on phones | **Fail**: the manual reader's buttons at 3.7:1; HUD text's backing | #368; #422, #412 |
| A5 Colour is never the only signal | **Fail**: tag states, photo coverage and course readings by colour only | Pass (alarm priorities carry their number; normally-closed valves a filled shape) | #370; 2026-11 audit K4 |

Also seen, outside phase 1's set: there is no accessibility statement in the README or the About screens (T11, #440),
which gates the next release of each product.
