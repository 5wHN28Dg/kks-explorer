# 0067 Walkdown Plant multiplayer: deterministic lockstep with the host as sequencer, no rollback

Date 2026-10-26 · Scope: docs/plant3d/MULTIPLAYER.md §3–§7; `apps/plant3d/sim` (several trainees), `ref/plant3d.py`,
`ref/plant3d_staff.py`, the vectors; the app's session layer · Status: **proposed**, written before any code under
the user's decision of 2026-10-26 ("deterministic lockstep … only players' inputs travel, a host orders the inputs,
each player takes a role, and NPCs fill the rest") · Extends 0054, 0062; no new dependency

**Question:** how do up to 8 players on Android, Linux and Windows share one run of the plant, staff included, so
that everyone sees the same plant, a player can join late or come back, and the session survives its host, within
the Note 9's frame rules and over mobile networks?

## Findings

| | Finding | Source |
|---|---|---|
| The engine | a fixed 0.1 s step; inputs queued for step 1; every value an IEEE double in the reference's order; bit for bit with the Python reference on glibc and on the Note 9's bionic; not yet run on Windows (a lag's factor calls the C library's `exp`) | apps/plant3d/sim/README.md, CAPABILITIES.md §8 [V] |
| Its cost | 0.77–0.81 ms a step on the Note 9 (release build with the WTP, the generated program, 2026-10-23); fast-forward capped at 31–33× there (a quarter of a core) | sim/README.md "Faster, the same bits" [V] |
| The state | thousands of values, machine and alarm states, permits, the staff's queues and per-person random streams; the save holds it all (37 KB at the end of the cold start before staff) and restores a run bit for bit | ui/run_save.gd, apps/plant3d/README.md [V] |
| The NPCs | already a pure function of the seed and the inputs (0062): nothing to send for them | PLANT3D.md §17 |
| What must feel instant | walking, looking, the panels: all local, outside the engine | the app |
| Classic lockstep | Age of Empires: commands scheduled two 200 ms turns ahead; playable at 250–500 ms latency on 28.8k modems; the turn length adapted to the slowest machine and the round trip | Bettner and Terrano, "1500 Archers on a 28.8: Network Programming in Age of Empires and Beyond", GDC 2001 |
| Mobile latency | median about 45–50 ms (Ookla, US carriers: 46 ms H2 2025, 49 ms H2 2024); 18 ms in the best countries (Speedtest Global Index, Qatar, June 2025); tails longer | Ookla reports via rcrwireless.com and 5gstore.com; Speedtest Global Index via meatechwatch.com (secondary reports of other regions: MP4's measurement on the Note 9 on mobile data is the evidence for the users' own networks) |
| Godot's multiplayer | `MultiplayerAPI`/`MultiplayerPeer` (RPCs, replication of node properties) with ENet, WebSocket and WebRTC peers | [S] 4.7-stable modules/multiplayer, enet, websocket, webrtc |

## Alternatives

1. **Lockstep, host as sequencer** (the user's choice): only inputs travel; a turn of 2 steps; inputs take effect
   at the turn after they reach the host. Cost: 0.3–0.8 s from press to effect on mobile data. Desyncs must be
   detected (hashes) and repaired (snapshots).
2. **Lockstep with rollback** (GGPO style): each player predicts and re-runs on late inputs. Saves the delay, but
   every step's state must be copied (the save's copy is 0.75 ms on the Note 9), late inputs re-run the steps since
   (about 8 ms for 10) and with them the staff's placement after a jump (≤ 50 ms). The plant reacts in seconds; the
   delay doesn't matter.
3. **The host simulates and streams state** (Godot's replication): the clients run no engine. The state is
   thousands of values plus the staff, and the engine has no delta encoding; the bandwidth and the host's upload
   would grow with the plant, and it breaks "the same simulation everywhere" (the debrief, saved runs and continue
   alone need the full engine on each player).
4. **Godot's high-level multiplayer for the lockstep itself:** RPCs are bound to nodes and scene paths, its
   authentication hook doesn't encrypt end to end through a relay, and its peers don't run over our relay protocol;
   we would use only its packet transport, which `PacketPeerUDP` and `WebSocketPeer` give directly.

## Choice

- **(1)**, as MULTIPLAYER.md §3 specifies: commits of turns (2 steps at 1×, more in fast-forward), inputs scheduled at
  the turn's first step in the host's order, an adaptive jitter buffer of 1–5 turns, catch-up up to the device's
  fast-forward cap, never a dropped committed step. Positions travel beside it, unreliable, at 5 Hz.
- **Several trainees in the engine** (§3.3): `players`, the slot on every trainee input, per-slot task state,
  `release`/reclaim made by the host; reference, GDScript and vectors in one milestone (MP1).
- **Digests every 50 steps** (a stride in fast-forward) of the saved state without its logs, packed arrays hashed
  directly, ≤ 1 ms each on the Note 9 (§4); a mismatch resyncs that player from the host's
  snapshot and writes a desync report; the host is the reference.
- **Late join and rejoin by the save's snapshot** (§5); **host migration** to the lowest connected slot with the
  highest committed step among the players (§5.3).
- **Fast-forward** at the slowest player's cap when every player is ready; **pause** by anyone; **instructor** inputs
  from the host or a named seat; the host's save is the session's; players keep a copy and may continue alone (§7).
- The Windows `exp` check comes first (MP1): if it differs, the build stores the factors.

## When to revisit

- if the measured press-to-effect on mobile data misses 1 s at the 95th percentile (MP4): a 1-step turn, or a
  region-pinned relay;
- if desyncs appear in practice that the digests can't explain (a Godot upgrade changing `var_to_bytes` or float
  printing; the digest covers the state, not the logs);
- if a future content needs real-time action (a fast-twitch task), where rollback would matter.

Sources: https://www.gamedeveloper.com/programming/1500-archers-on-a-28-8-network-programming-in-age-of-empires-and-beyond ·
https://www.rcrwireless.com/?p=428028 · https://5gstore.com/blog/2025/02/14/ookla-report-mobile-connectivity-2h24/ ·
https://meatechwatch.com/?p=29896 · https://github.com/godotengine/godot/tree/4.7-stable/modules/multiplayer ·
apps/plant3d/sim/README.md, ui/run_save.gd, docs/PLANT3D.md §7.10, §17, §18.4.
