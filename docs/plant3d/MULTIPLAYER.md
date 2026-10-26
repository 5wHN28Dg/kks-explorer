# Walkdown Plant: multiplayer

**Status: DRAFT 2026-10-26**, written before any code. Decisions 0067 (lockstep), 0068 (sessions, transport and the
relay), 0069 (voice). The engine: docs/PLANT3D.md (§7.9–§7.10 the step, §12 the trace format, §17 the staff step);
saved runs: apps/plant3d/README.md "Saved runs" (`ui/run_save.gd`). Milestones MP1–MP6: §13.

**The user's decisions (2026-10-26):**
- local and online multiplayer, serverless like Walkdown;
- the same simulation everywhere: deterministic lockstep, only the players' inputs travel, a host orders them, each
  player takes a role, NPCs fill the rest;
- online through a new Cloudflare Worker relay (the free plan only, separate from Walkdown's; its URL never in
  tracked files), with direct UDP when the network allows; Claude may deploy it once its tests pass against a local
  twin;
- the network is used only while a session is open; local play uses the LAN;
- up to 8 players, with push-to-talk voice over the in-game radio (the microphone permission);
- no releases until the project is complete.

**Words used here.** A **session** is one shared run. Its **players** are 1 to 8 app instances; one of them is the
**host**, which orders the inputs. A **slot** is a player's number in the session (0 to 7, given by the host in join
order and never reused within a session). A **turn** is the range of model steps one commit closes. **K**, **P**
and the code are the keys of §1.3.

## 1. Sessions: create, join, identity

### 1.1 Create

The host picks a scenario, or a saved run (§7.4), and **Online** or **This Wi-Fi only**, and gets an **invite**:
- a **code** of 16 characters from Crockford's base32 alphabet (no I, L, O or U), shown in four groups
  (`K3QX-9F2M-HT4C-7PWD`): 75 random bits and a 5-bit check (the first 5 bits of SHA-256(`"wdp-code-v1\n"` +
  the first 15 characters)), so that a typo is caught before anything is sent;
- the **link** `walkdown-plant://join/<code>` and its **QR code** on the host's screen. A phone's own camera app opens
  the link, and the app's existing link path (decision 0056) starts the join, so the plant app needs **no camera
  permission and no QR reader**. The QR code is drawn by a small GDScript encoder of our own (byte mode, error
  correction M; Godot has no QR class [S 4.7 doc/classes]).

The code is the session's only secret: whoever holds it may join (§1.3 explains why that is enough here). It is shown
to the room as Walkdown shows an invite, and it is gone when the session ends.

### 1.2 Join

The joiner types the code, follows the link, or scans the QR code with the camera app. The app then:
1. looks for the session on the LAN for 2 s (§9.3: beacons carry the room ID derived from the code);
2. if none answers and the code's session is online, enters the relay room (§9.1);
3. sends `hello` (§2.2) to the host, with its **display name** (1–24 characters, typed once and kept in the app's
   settings) and a fresh random **P**;
4. gets `welcome` (its slot, the roster, the session's settings) and the snapshot (§5.1), then plays from the next
   commit.

A **This Wi-Fi only** session never touches the relay; an online session also answers on the LAN, so players in
one room play over the Wi-Fi and the others through the relay or direct UDP.

### 1.3 Identity and keys

Walkdown's identity (device keys, root-signed certificates, the log, TLS with peer-ID pinning; PROTOCOL-v2 §2, §15,
§16) is **not reused**. Here there are no plant data, no accounts and nothing that outlives the session: trainees
share one invented plant for an hour. What a session needs is (a) that only the people in the room can join, (b)
that nobody else can read or change what travels, the relay included, (c) that each player's inputs are theirs. And
Godot gives GDScript no ECDH, no Ed25519 and no AEAD: `Crypto` has RSA, HMAC-SHA-256, random bytes and signatures
with an RSA or EC key loaded from PEM; `AESContext` has ECB and CBC only [S 4.7 doc/classes Crypto.xml,
CryptoKey.xml, AESContext.xml]. Walkdown's approach would need the Nim core in the plant app, which 0054 §2 rules
out (four native builds per release for this alone). So (decision 0068):

- **From the code** (its 75 random bits as the input key material, `S`), with HKDF-SHA-256 (RFC 5869) built on
  `HMACContext`, salt `"walkdown-plant-mp-v1"`:
  - `room` = 16 bytes, info `"room"`: the relay room (32 hex characters) and the LAN beacon's ID;
  - `admit` = 32 bytes, info `"admit"`: the relay's admission token (the relay keeps only its SHA-256);
  - **K** = 32 bytes, info `"group"`: the session key for messages to everyone.
- **P**: 32 random bytes each player makes when it joins and sends to the host in its `hello` (under K). Messages
  between that player and the host are under P, so another player can't make an input that the host takes as
  someone else's.
- **Encryption:** AEAD_AES_128_CBC_HMAC_SHA_256 of RFC 7518 §5.2.3 (the JOSE "A128CBC-HS256"): the 32-byte key's
  first half is the MAC key and its second half the AES key, a random 16-byte IV per message, PKCS#7 padding, the
  tag the first 16 bytes of HMAC-SHA-256 over (AAD ‖ IV ‖ ciphertext ‖ AAD length in bits as a 64-bit big-endian
  number). Every piece is a Godot primitive (`AESContext` CBC, `HMACContext` SHA-256, `Crypto.generate_random_bytes`,
  `Crypto.constant_time_compare`), and RFC 7518 Appendix B.1 gives the test vector. The AAD is the packet header
  (§2.1), so a header can't be moved onto another body.
- **Replay:** every packet carries the sender's packet number (§2.1); a receiver drops a number it has seen or one
  more than 256 below the highest seen from that sender under that key.

**What this does not give, and why that is accepted:** players are trusted classmates. One who holds K can read
the session and could forge a broadcast as the host on a path that doesn't say who sent it: the relay tags every
message with its sender's socket (§9.1), so only a direct UDP path between players on one LAN (where an IP address
can be spoofed) is open to it. Such a forgery desyncs the others, who are then resynced from the host under their P
(§4). A player can always disrupt a session by playing it badly; the host can remove them (§2.4), which moves the
session to new keys. Whoever reads the code over a shoulder can join: the host sees every join in the roster and
removes strangers.

## 2. Messages

### 2.1 Packets

Every transport (LAN UDP, direct UDP, the relay) carries the same packets:

| Field | Size | Meaning |
|---|---|---|
| version | 1 | 1 |
| key | 1 | 0: K; 1: P of the player in `from` or `to` (whichever is not the host); 2: none (only `punch`, §9.2) |
| from | 1 | the sender's slot; 255 before it has one (its `hello`) |
| to | 1 | a slot, or 255 for everyone |
| epoch | 2 | the host epoch (§5.3); packets of an older epoch are dropped, except `last` |
| number | 4 | the sender's packet number, from 1, per key |
| ack, ack mask | 4 + 4 | the highest reliable packet number received from the addressee and the 32 before it (§2.3) |
| body | | IV, ciphertext and tag (§1.3) of one or more messages |

A packet is at most 1,200 bytes on UDP (one datagram without fragmentation on any common path) and at most 64 KiB
through the relay. The header is 18 bytes; encryption adds 16 (IV) + 1–16 (padding) + 16 (tag).

### 2.2 Message kinds

Each message inside a body is a kind (1 byte), a length (2 bytes) and its fields. Inputs are the trace format of
PLANT3D.md §12 and §17.6, as strict JSON text (read with `sim/json_strict.gd`, at most 512 bytes each): the same
form the vectors, the save and the debrief already use.

| Kind | Channel | From → to | Fields |
|---|---|---|---|
| `hello` | reliable | joiner → host | display name, P, the app version (`RunSave.app_version()`), the content hash, a rejoin token or none (§5.2) |
| `welcome` / `refuse` | reliable | host → joiner | slot, roster, settings / a reason (`full`, `version`, `content`, `removed`, `closed`) |
| `roster` | reliable | host → all | every slot: name, role (a person or none), connected, transport, ready flags |
| `input` | reliable | player → host | the player's input number (from 1), the input |
| `commit` | reliable | host → all | epoch, first and last step of the turn, the inputs scheduled in it as `[step, slot, input number, input]` |
| `hash` | reliable | everyone → host | step, the state digest (§4) |
| `snap` | reliable | host → one player | snapshot chunks (§3) |
| `control` | reliable | player → host, host → all | pause, run, fast-forward votes, the jump vote, instructor mode (§7) |
| `pos` | unreliable | player → all | the player's position, heading, pitch, gait, at 5 Hz (§6.3) |
| `voice` | unreliable | player → all | channel, talk-spurt number, Opus frames (§8) |
| `talk` | reliable | player → host, host → all | ask for, grant, refuse and end a channel's floor (§8.4) |
| `ping` / `pong` | unreliable | any | a time stamp, for round-trip times |
| `last` / `newhost` | reliable | players → candidate / new host → all | (§5.3) |
| `remove` / `rekey` | reliable | host → one / each other player | (§2.4) |
| `bye` | reliable | any | leaving |

### 2.3 Reliability

Reliable messages ride in packets that the addressee acknowledges (the header's ack and mask, sent in the next
packet back, or alone after 50 ms); an unacknowledged packet is sent again after an RTO computed as in RFC 6298
(200 ms to 4 s), as Walkdown's reliable UDP does (PROTOCOL-v2 §18). Reliable messages are delivered in order per
sender. Through the relay (a WebSocket over TCP) nothing is lost, but the same numbers and acks are kept so that a
player can move between the relay and UDP (§9) without losing or repeating a message. Unreliable messages are never
sent again.

### 2.4 Leaving and removing

`bye`, or no packet for 10 s, marks a player disconnected in the roster. Their person goes to the NPCs (§6.2) after
60 s unless they rejoin. The host may **remove** a player: it sends `remove`, then a new code's keys (a new room,
admit and K, made by the host from 75 new random bits) to each remaining player under their P in `rekey`; everyone
moves to the new room and LAN ID. The removed player still knows the old code, which now opens nothing. The host's
screen shows the new code for anyone who should join later.

## 3. Lockstep (decision 0067)

### 3.1 The rule

Every player runs the whole engine (`sim/engine.gd`), from the same start, with the same inputs at the same steps, so
every player has the same plant bit for bit, as the vectors already require between the reference and the app on
every platform. Only inputs travel. The host is the **sequencer**: it alone says which inputs take effect at which
step.

- The host keeps the **committed step** C. Every turn it closes the steps (C, C + T] with a `commit` that lists the
  inputs that take effect in them, each at the turn's first step C + 1, in the order the host received them (its own
  included, through the same path as anyone's). No player, the host included, runs a step that isn't committed.
- **T, the turn:** 2 steps (0.2 s) at 1×. In fast-forward the host closes more steps per 0.2 s of real time (§7.2).
  A turn with no inputs is a commit with an empty list (about 40 bytes); a paused session sends none.
- **Inputs:** a player's UI no longer queues an input in the engine: it hands it to the session (`input`), shows it
  as sent (the op's button as pressed, "sending…"), and the input takes effect in every engine when its commit
  arrives. The player keeps each input until a commit lists its number, sends it again after a host change (§5.3),
  and the host ignores an input number it has committed already.
- **Playing a commit:** a player runs the committed steps at the session's rate (1×, or the fast-forward rate). It
  holds a **jitter buffer**: at 1× it runs at most up to C minus the buffer, which starts at one turn (0.2 s) and
  grows by a turn (to at most 5) whenever a commit arrives later than the buffer covered, shrinking again after
  30 s without one. A player that has fallen behind (a hitch, a slow phone) runs faster to catch up, up to its
  `ff_cap` (sim_clock.gd), and never drops a committed step (the solo clock's rule "what the cap leaves out is not
  owed later" does not apply to a session).

### 3.2 Why lockstep and not rollback or state streaming

The plant is a slow process: a valve strokes in seconds, a pump starts in 10 s, a trip waits on a delay. What the
player has to feel at once (walking, looking, the buttons) is local and not in the engine: positions travel beside
the lockstep (§6.3). So an input that takes effect 0.3–0.5 s after the press is acceptable, the way Age of Empires'
commands took effect two turns of 200 ms later and still played over 28.8k modems with 250–500 ms latency
(Bettner and Terrano, "1500 Archers on a 28.8", GDC 2001). Rollback would save that delay at the cost of keeping
and re-running states: a model step is 2.5 ms on the Note 9 (sim/README.md, the release build with the WTP), so
re-running 10 steps after each late input costs 25 ms, a frame. Streaming the state from the host would need the
state in every message (thousands of values and the staff) or a delta scheme the engine doesn't have, and it would
end "the same simulation everywhere" (decision 0067 compares the three).

**Latency to expect:** mobile networks' median latency is about 45–50 ms (Ookla's US reports: T-Mobile 46 ms in
H2 2025, 49 ms in H2 2024) to under 20 ms in the best (Qatar, 18 ms, Speedtest Global Index June 2025), with longer
tails and worse on congested cells. Through the relay a message goes player → Cloudflare → host: two such paths. An
input then takes effect after its trip to the host (≈ 50–150 ms), the wait for the next commit (0–200 ms), the
commit's trip back (≈ 50–150 ms) and the jitter buffer (200 ms): about 0.3–0.7 s on mobile data, 0.25–0.45 s on a
Wi-Fi. MP2 and MP4 measure it on the Note 9 (§13) against a budget of **0.5 s median, 1 s at the 95th percentile**
on mobile data, input made to effect seen.

### 3.3 Several trainees in one engine

Today the staff step has one trainee (`st_trainee`, PLANT3D.md §17.4). A session has up to 8, so the engine changes
(milestone MP1, reference, GDScript and vectors together, as every engine change):
- **`players`:** the trainee becomes a list of persons, one per player with a role. The role input becomes
  `[n, "role", person, slot]`: refused, with its event, when the person is another player's, absent, not a `play`
  role, or that slot already has a person. The single-player run is the case of one slot 0.
- **Inputs carry the slot.** The trainee inputs that name no person today (`arrive`, `leave`, `read`, `ppe`, `zone`,
  `say`, `pick`, `task_ack`) gain the slot as their last element in a run with players; inputs that name a person
  (`permit`, `lock`, `repair`, `stop`, …) are refused when that person is not the slot's (`authority`). Format 1
  inputs (ops, acknowledgements, shelving) carry the slot too and are applied as today: the plant does not care who
  pressed. The commit's slot is authoritative; a slot inside an input that differs from the commit's is refused.
- **Per player:** `st_t_at`, `st_t_in`, `st_unacked`, `st_early` become per slot; fast-forward is offered only when
  no player has unseen tasks (§17.6's rule, for each).
- **Leaving and returning:** `[n, "release", slot]` hands the slot's person to the NPCs: it continues its current
  task from its current step as an NPC would (in the reference's terms: the person leaves `players`, keeps its queue,
  and step 9 runs it from this step). `[n, "role", person, slot]` later takes it back if nobody else did. Both are
  made by the host only (it puts them in a commit), never by a player's own input.
- **Free mode players** (no role) make format 1 inputs only, with their slot.
- The vectors (`plant3d-v2.json`'s staff `runs` and `day` forks) gain runs with two and three players, a release and
  a reclaim mid-task, refusals for another slot's person, and fast-forward held by one player's unseen task.

## 4. State hashes and desyncs

**The digest:** SHA-256 over the engine's state as the save keeps it (`RunSave.engine_fields`: every script variable
but the compiled program), encoded field by field in sorted name order with `var_to_bytes`, **without** `events`,
`inputs` and the debrief's logs (they only grow, and what they record is in the state too). Same Godot release, same
field order, doubles as their bits: the same state gives the same bytes on every platform, which MP1 checks (the
digest of every vector run's every 50th step equal on Linux, Android and Windows). Cost target: ≤ 0.5 ms on the Note
9 for the first train with staff (MP1 measures it with `tests/bench_save.gd`'s method; the save's copy took about
0.75 ms there in all, events included).

**When:** every player sends `hash` for every step that is a multiple of **N = 50** (5 s of model time at 1×; at 10×
every 0.5 s of real time, so at most 1 ms a second of the Note 9's main thread). The host keeps its own digests of the
last 20 such steps.

**On a mismatch** with the host's digest: the host marks the player desynced in the roster and sends it a snapshot
(§5.1's form) at its current committed step; the player throws its engine away, loads the snapshot and plays on from
the next commit (the plant may jump on its screen; a banner says "Resynchronised with the host"). Before loading, the
player writes a **desync report** to `user://desync/` (both digests, the step, its own state and the snapshot), and
the host notes it in the session log, so that the cause is found (a platform's `exp`, an engine bug). A player that
desyncs twice within 10 minutes is told its device can't follow this session and stays as an observer (it sees the
host's snapshots every 30 s and makes no inputs) until the host's next decision. The host is the reference by
definition: in a session of three where two agree against the host, the two are resynced to the host too, and the
reports say who differed.

**Known risk before any session:** the engine is bit for bit with the reference on glibc and bionic but not yet run on
Windows, whose C library's `exp` makes a lag's factor (sim/README.md, CAPABILITIES.md §8). MP1 runs the vectors on
Windows; if any digest differs, the build computes the factors on Linux and stores them in the compiled model, as the
README already plans.

## 5. Late join, rejoin and host changes

### 5.1 The snapshot

The host takes the snapshot at a committed step C: the run save's payload (`ui/run_save.gd`: the engine's state with
`events` and `inputs`, so that the joiner's debrief and alarm list are whole; the scenario; the content hash and app
version) without the host's own UI, tracker and position, plus the session's state (roster, roles, settings, the
committed step). It is encoded as the save is (`var_to_bytes`, no objects), compressed with zstd (Godot's
`PackedByteArray.compress(FileAccess.COMPRESSION_ZSTD)`), and sent under the joiner's P in `snap` messages of 1,100
bytes (UDP) or 60 KiB (relay), at most 16 MiB in all. The joiner checks it with the save's own strict checks (the
fields and their types must be this engine's, `autosave.gd` `check`) and refuses anything else.

The joiner keeps every commit after C that arrives while it loads, then runs from C + 1 to the present at its
catch-up rate. The snapshot's encoding and compression run on a worker thread on the host (as the periodic save's do,
off the frame); the copy on its main thread is the save's (about 0.75 ms on the Note 9). A host takes at most one
snapshot per 2 s and sends a newer one to joiners that ask within that time.

A version or content mismatch (another build, other content) is refused in `welcome`, before any snapshot: lockstep
needs the same code and data on every player (the save already refuses another build's run for the same reason).

### 5.2 Rejoin

`welcome` gives each player a **rejoin token** (16 random bytes), kept in memory with the code while the app runs and
in `user://mp-session.json` while the session is open. A player that comes back with it (the app was killed, the
network dropped) gets its old slot and, if its person is still released and free, its role back (the host puts the
`role` input in a commit), then a snapshot as a joiner. A rejoin after the host has closed the session is refused
with `closed`.

### 5.3 When the host leaves: host migration

Every player has the whole state and the commits, so any of them can go on as host. The session has a **host epoch**
(1 at creation) in every packet.

1. **Noticing:** no packet from the host for 5 s (a host sends a commit or, paused, a `ping` at least every second),
   the relay's `left` for the host's relay ID, or the host's `bye`.
2. **The candidate** is the connected player with the lowest slot. Every player stops at the last commit it has and
   sends the candidate `last`: its committed step, its digest at the last multiple of 50, the numbers of its
   uncommitted inputs, and a fresh P for the new host (the old P was shared with the old host only). `last` goes
   under K, addressed to the candidate alone, as `hello` does.
3. The candidate waits for every connected player's `last`, or 3 s, takes the highest committed step among them and
   fetches the commits it lacks from the player who has them (everyone keeps the last 600 commits, two minutes at
   1×). The old host's commits are taken as they are: they were already committed, and some players may have run
   them.
4. It sends `newhost` to everyone: epoch + 1, its slot, its relay ID and LAN address, the committed step, and the
   commits each player lacks. Everyone runs to that step and follows the new host from the next turn; inputs that
   weren't committed are sent to it again (§3.1). Its first digest exchange at the next multiple of 50 confirms that
   everyone agrees.
5. If the candidate doesn't send `newhost` within 5 s, the next lowest slot takes over (the k-th waits 5 s × k).

The new host takes over beacons (§9.3), saving (§7.4), the talk floors (every floor is ended) and the roster; its
roster carries a SHA-256 of each player's rejoin token, so it can take rejoins it never gave out. The old host, if it
comes back, is an ordinary player rejoining with its token. A network split that elects two hosts gives two epochs:
when the groups meet again, the higher epoch (then the lower host slot) wins and the others are resynced from its
snapshot, losing their own turns since the split. The relay room, the code and K don't change.

## 6. Roles, NPCs and other players

### 6.1 Claiming roles

The session starts in a **lobby** (the host's chosen scenario paused at step 0): the roster with each player's name
and the scenario's `play` roles with their people on duty (the Crew panel's start list, §18.7). A player claims a
role (or free mode); the claim is an input, so two claims of one person are settled by commit order: the first is
`done`, the second `refused`, the same on every screen. The host starts the run when everyone is ready; a player who
joins later claims from what is left. The host may set a role as reserved for a named slot (an instructor assigning
the roles) before the start.

### 6.2 NPCs

Every person not claimed is an NPC, exactly as in a single-player run (§17): the staff step runs them identically on
every player. A released person (§3.3) becomes an NPC at once. With 8 players and the first train's crews, most of
the plant is still NPCs.

### 6.3 Seeing each other

Other players' positions are not in the engine (the walker is the player's own, as in a single-player run). Each
player sends `pos` at 5 Hz (position as three 32-bit floats, heading and pitch as 16-bit angles, gait and a few flags:
24 bytes before encryption) and draws the others 200 ms behind, interpolated. Their avatars are those of their
person's role (0063), and they take the skinned slots before NPCs (PLANT3D.md §18.4: ≤ 12 on the Note 9, so 7 other
players leave 5 for NPCs). Map dots, names over heads within 15 m, and the roster panel name who plays which role. A
player's own `arrive`, `leave` and `zone` inputs still come from their walker (§18.7) and travel as inputs.

## 7. Time, pause, fast-forward, instructor mode and saved runs

### 7.1 Pause

Any player may pause (`control`): the host stops committing at once and everyone shows who paused. Only the host
resumes, or the player who paused. While the session is paused a player can still walk, look and talk.

### 7.2 Fast-forward

Fast-forward is offered when the engine offers it (PLANT3D.md §7.9, §17.6: the same on every player, it is state)
and every connected player has pressed **Ready for fast** (shown in the roster). The host then commits at the
**session's rate**: the lowest of every player's `ff_cap` (each reports its own, from its measured step cost), the
format's 60× and the host's choice. A player more than 2 s of real time behind C lowers the rate until it is back.
The engine stops fast-forward for everyone when it stops being offered; everyone's ready flag is then cleared.

**The jump** ("sleep to the next shift", §17.6) is an input like any other, made by the host when every player with a
role has voted for it; it is refused in the engine as today when not allowed.

### 7.3 Instructor mode

The trainer's inputs (faults, repairs, removing a lock by authority, PLANT3D.md §15.5) are open to the **host** and to
any player the host names **instructor** in the session settings (a seat with no person; an instructor may also hold a
role). Every such input carries the `instructor` event as today, so every player's debrief shows them. Other players
don't see the instructor panel.

### 7.4 Saved runs

- **The host saves the session** as a single player saves a run (every 5 s while it changes, on going to the
  background), to `user://mp-host.save`, never over the single-player `user://run.save`. The save adds the session's
  roster and roles.
- **Continue a session:** the host opens a saved session as a new session (a new code). The players who join claim
  their roles again (the lobby offers each the role of the same display name in the save); unclaimed roles stay
  NPCs.
- **Players keep a copy** of the shared run (`user://mp-last.save`, written when they leave or the session ends) for
  their debrief, which shows every player's actions by name and their own tasks (§18.7's Your tasks for their slot).
  From that copy a player may **continue alone**: the other players' persons are released to NPCs and the run goes on
  as a single-player run.

## 8. Voice (decision 0069)

### 8.1 What Godot 4.7 has

- **No Opus.** Godot 4.7's `thirdparty/` has libogg, libvorbis and libtheora but no libopus, and no Opus class [S
  4.7-stable thirdparty/, doc/classes/].
- **Microphone:** `audio/driver/enable_input` (default off) [D], then either `AudioStreamMicrophone` played on a muted
  bus with `AudioEffectCapture` reading its frames, or the experimental `AudioServer.set_input_device_active`
  with `get_input_frames(n)` and `get_input_frames_available()` (float stereo frames at `get_input_mix_rate()`) [S
  4.7 doc/classes/AudioServer.xml]. We use the latter: no bus and no stream player.
- **Android:** Godot's OpenSL ES driver asks for `RECORD_AUDIO` when input starts (`request_permission`) and records
  with the default preset, so the platform's echo canceller and noise suppressor are **not** applied [S 4.7
  platform/android/audio_driver_opensl.cpp]. The export needs the `RECORD_AUDIO` permission ticked.
- **Playback:** `AudioStreamGenerator` with `push_buffer`, one call per decoded 20 ms frame [D].

### 8.2 The codec and library

**Opus** (RFC 6716), through a small GDExtension of our own, **`wdp_voice`** (C++ against godot-cpp, MIT), built
from pinned sources: **libopus 1.5.2** (BSD-3-Clause) and **SpeexDSP 1.2.1**'s resampler (BSD-3-Clause), for Android
arm64-v8a (the NDK, as `libkks.so`), Linux x86-64 (the Flatpak) and Windows x86-64 and ARM64 (the two MSIX packages) (llvm-mingw, decisions 0047,
0053). Its interface: an encoder (`encode(PackedVector2Array frames) -> PackedByteArray`, taking the mix rate's
frames, down-mixing, resampling and encoding 20 ms at a time) and a decoder (`decode(packet or empty for a lost one)
-> PackedVector2Array` at the output mix rate, with Opus's loss concealment and in-band FEC). TwoVoIP
(github.com/goatchurchprime/two-voip-godot-4, MIT, the same Xiph libraries plus RNNoise, built for every Godot
platform by its CI) was looked at and is kept as the fallback; decision 0069 says why our own binding comes first.
Every licence is permissive and compatible with the repository's AGPL-3.0: **nothing here needs the user**.

0054 kept the app script-only. `wdp_voice` is its first GDExtension: four native builds per release, the
reason 0054 §2 gave against binding the Nim core. It is accepted here because no Godot or platform API encodes Opus,
and voice is the user's requirement; a build without the extension (a platform it fails on) plays multiplayer
without voice and says so.

### 8.3 Settings

Mono, 16 kHz (wideband: a radio's band is narrower), `OPUS_APPLICATION_VOIP`, 20 ms frames, 16 kbit/s, complexity 5,
in-band FEC on with the expected loss set from the measured loss, no DTX (push-to-talk sends only while talking).
Two frames per `voice` message (40 ms): about 80 bytes of Opus, 12 of fields, 18 of header and 33–48 of encryption,
so about 150 bytes per 40 ms, **30 kbit/s** per talker (plus UDP/IP or WebSocket framing). The receiver keeps a
jitter buffer of 60–200 ms (adaptive), decodes a lost frame by FEC or concealment, and plays it on the radio's bus:
a band-pass of 300–3,000 Hz and light distortion (Godot's `AudioEffectBandPassFilter` and `AudioEffectDistortion`),
the squelch clicks at the start and end of a talk spurt as CC0 clips (0054 §7).

### 8.4 Push-to-talk and channels

- **Channels:** the radio panel's (operations, maintenance, HSE: §18.7). A player hears the channels their role's
  radio carries (all three in free mode and as instructor) and talks on the one selected.
- **Push-to-talk:** a held key (`V`), a gamepad button, or a held on-screen button on a phone. The microphone is
  opened only while the session is open and voice is on, and captured only while the button is held; the app shows
  a microphone mark while it is.
- **One talker per channel**, as on a real radio, so voices never overlap: pressing asks the host for the channel's
  floor (`talk`); the frames captured meanwhile are kept, and sent once granted (dropped, with a busy tone, when
  refused). The floor ends when the button is released or after 30 s.
- **Half duplex:** while a player talks, their own playback of that channel is muted. So a phone's speaker never
  feeds its own microphone, and no echo canceller is needed; noise suppression is left to Opus's VOIP mode (RNNoise,
  BSD-3, can be added to `wdp_voice` later if trainees' rooms prove too loud).
- NPCs' radio messages stay text in the radio log (§18.7), and players' voice is not recorded or saved anywhere.

### 8.5 Permissions per platform

| | Android | Linux (Flatpak) | Windows (MSIX) |
|---|---|---|---|
| Network | `INTERNET` (and `CHANGE_WIFI_MULTICAST_STATE` for the LAN beacons, §9.3); normal permissions, granted at install | `--share=network` | `internetClient`, `privateNetworkClientServer` (the LAN) |
| Microphone | `RECORD_AUDIO`, asked at run time when voice is first turned on in a session | `--socket=pulseaudio` (the microphone through PipeWire's Pulse server) | `microphone` device capability; Windows' privacy setting must allow desktop apps |

**Android's network permission can't be switched on and off:** `INTERNET` is granted at install for as long as the app
is installed. "The network only while a session is open" is therefore the app's behaviour, not the system's: no socket
is opened outside a session, and a test checks it (§12). The same holds for Flatpak's and MSIX's static permissions.
0054 §8's `permissions/internet=false` changes, and that record gains a note. Android 17's local network permission (`ACCESS_LOCAL_NETWORK`) binds apps that target SDK 37; Godot 4.7's
template targets 36, whose apps get it implicitly with `INTERNET` [D developer.android.com local-network-permission;
S 4.7 platform/android/java/app/config.gradle]. A move to target 37 must add the runtime request.

## 9. Transport (decision 0068)

Three paths carry the packets of §2; a session may use all three at once, chosen per player:

### 9.1 The relay

A new Cloudflare Worker with one Durable Object per room, built like Walkdown's (`relay/src/index.js`: hibernating
WebSockets, `setWebSocketAutoResponse` for pings) but its own code, repository folder `relay-plant/` (Worker, pinned
wrangler, twin, tests), its own Worker name and its own deployment. Its URL is in `CLAUDE.local.md` and the app's
build configuration file (ignored by git), never in tracked files; the app reads it from the build. Builds without it (CI's exports, a
clone) offer This Wi-Fi only.

- `GET /v1/room/<room>` (32 hex characters) upgrades to a WebSocket. The first message is text:
  `{"t": "hello", "admit": <32 bytes, base64url>, "create": true | false}`.
  - `create: true`: the room must not exist; the relay stores SHA-256(admit) and the creation time (SQLite storage),
    and the socket becomes relay ID 1.
  - `create: false`: the room must exist and SHA-256(admit) match; the socket gets the next relay ID (1–255, never
    reused within the room).
  - The answer: `{"t": "welcome", "id", "peers": [ids]}`, or `{"t": "error", "why"}` and close (`exists`,
    `no such session`, `bad admit`, `full`, `limit`). Members hear `{"t": "joined", "id"}` and `{"t": "left", "id"}`.
- Then binary messages: the sender writes `to` (1 byte: a relay ID, 0 for every other member) before the packet;
  the relay replaces it with `from` (the sender's relay ID) and passes the packet on unread. It never sees K, P or
  the code: it holds a hash of `admit`, and `admit` and `room` are HKDF outputs that don't reveal the code.
- The roster maps relay IDs to slots, so a player accepts a host packet only from the host's relay ID.
- **Limits:** 9 sockets per room (8 players and one rejoin overlapping); a message ≤ 64 KiB; per socket at most 60
  messages a second averaged over 10 s (burst 200) and 256 KiB/s; a room lives at most 24 h; an empty room is deleted
  10 minutes after its last socket closed (rejoin after a short drop); a room's hello attempts at most 10 a minute.
  Anything over a limit closes the socket with `limit`.
- **Room creation per address:** the Workers rate limiting binding (10 or 60 s periods, per Cloudflare location,
  approximate [D workers/runtime-apis/bindings/rate-limit]) at 10 rooms a minute per IP address, if MP4 finds it
  available on the free plan; otherwise no extra limit (the free plan's daily ceiling below still bounds everything,
  and it costs nothing).
- **Cost on the free plan** [D durable-objects/platform/pricing]: Durable Objects 100,000 requests and 13,000 GB-s a
  day; a WebSocket's incoming messages count 20 to a request, outgoing messages and protocol pings nothing; past a
  limit, operations fail until 00:00 UTC (no charge on the free plan). A room with steady traffic never hibernates,
  so it is billed its wall time at 128 MB: 450 GB-s an hour, **≈ 28 room-hours a day**. Incoming messages with
  8 players all on the relay: the host's commit-and-positions bundle 5 a second, each other player's
  positions-and-inputs bundle 5 a second (35), and while someone talks 25 a second from the talker (a `voice` message
  is sent once with `to` = 0 and fanned out by the relay). About 40 messages a second idle and 65 while someone
  talks: ≈ 7,000–12,000 requests an hour, **≈ 8–14 hours of 8-player relay play a day**; a session of 2 costs about
  a fifth. Players on the LAN or on direct UDP cost nothing beyond their hello. MP4 measures the real counts in
  Cloudflare's analytics and writes them here.
- **Deploying:** only on an account on the **Workers Free plan** (a paid account would be billed past the free
  allowance). The deploy step checks the account's plan through the Cloudflare API first and stops if it is not the
  free plan.

### 9.2 Direct UDP

As Walkdown's direct path (PROTOCOL-v2 §18, `kksl/udp.nim`), between each player and the host only:
- each side's UDP socket (`PacketPeerUDP`) asks STUN (RFC 5389 binding request, written in GDScript; the servers
  Walkdown uses: `stun.cloudflare.com:3478`, `stun.l.google.com:19302`) for its public address;
- the two exchange candidates (the public address and their own IPv4 addresses, at most 8) as a reliable message
  through the relay, under P;
- both send `punch` packets (key 2: a fixed body with an HMAC under P, so a stranger's packets are dropped) to every
  candidate every 100 ms for 3 s; the first answered address becomes that player's path, and the relay stays as the
  fallback;
- a path silent for 3 s (no packet; a keep-alive every 1 s) falls back to the relay; the punch is tried again after
  60 s. A carrier NAT that maps per destination can't be punched (the lesson in CLAUDE.md), so phones on mobile data
  will often stay on the relay.

### 9.3 The LAN

- The host listens on a UDP port (47820, or the next free of the following 9) and sends a **beacon** every second to
  255.255.255.255 and to each IPv4 interface's broadcast address on port 47820: `"WDPB"`, version, the first 8 bytes
  of `room`, the host's port, and 8 bytes of HMAC under K over them. A joiner with the code recognises its session;
  anyone else sees only that some session is there.
- Android filters broadcasts unless the app holds a `WifiManager.MulticastLock` (the `CHANGE_WIFI_MULTICAST_STATE`
  permission), taken while a session is being looked for or hosted, through Godot's `JavaClassWrapper` and the
  AndroidRuntime plugin (as 0056 reads the Intent) [D JavaClassWrapper; to verify in MP2]. If a phone still hears no
  beacon (client isolation on the Wi-Fi), the joiner can type the host's address shown on its screen.
- Windows asks the firewall question the first time a desktop app listens; MP2 checks what the MSIX's
  `privateNetworkClientServer` capability does there in the VM.

## 10. Security and privacy

**The relay and the network** see packet sizes, times and which relay IDs talk; never inputs, names, voice or the
code. A stranger without the code can't enter a relay room (no admit), can't decode a beacon, and can't make a packet
any player accepts.

**A malicious player** (holding K and their own P):
| They can | The effect | What limits it |
|---|---|---|
| Make wild inputs as themselves | the engine refuses what the rules refuse, the same on every player; what it allows is "playing badly" | the host removes them (§2.4); the debrief shows who did what |
| Make inputs as another player | not through the host: inputs are taken only under the sender's P, and the commit names the slot | — |
| Flood inputs or voice | | the host takes at most 20 inputs per player per turn and 1 KiB of them, and at most one `talk` request a second; beyond that it drops and warns; the relay's per-socket limits |
| Send wrong hashes | they are resynced; they can't make the host resync others | only the host's digest counts |
| Forge a host broadcast (commit) on a LAN by spoofing the host's address | the others desync, are detected within N steps and resynced under their P | the relay path is not open to it (sender tags) |
| As host: send a crafted snapshot | the joiner decodes it with `bytes_to_var` (no objects) and the save's strict checks | the host is trusted by every player of its session; snapshots are accepted only from the host under P |
| Keep the old code after removal | nothing: the session has moved to new keys (§2.4) | |
| Hear voice | only the session's players hear it, and only on their role's channels | |

**Parsing:** every field is read with bounds (lengths, counts, the 512-byte input, the 16 MiB snapshot); inputs with
the strict JSON reader; nothing from the network is ever loaded as a resource or run. 0054 and PLANT3D.md §13 keep
outside content out because of the engine's security response (0041); session packets are data in our own formats,
read by our own code, and snapshots come only from the session's host.

**Privacy:** display names are what the player types; no account, no device identity, nothing kept after the session
but the saves of §7.4 and desync reports (§4), all on the device. The microphone is open only while push-to-talk is
held in a session.

## 11. Performance budgets on the Note 9

The frame rules don't change (MILESTONES.md: ≥ 95 % of frames at ≥ 30 fps in the 10-minute walk, none over 100 ms
that the app causes, peak PSS ≤ 1.5 GB, first walkable frame ≤ 15 s). Multiplayer gets this share of the main thread:

| | Budget | Notes |
|---|---|---|
| Session layer per frame (receive, decrypt, parse, send) | ≤ 0.5 ms mean, ≤ 2 ms max | about 15 packets a second in, at 1×; `AESContext` and `HMACContext` are native |
| Model steps | as alone (≤ 2.1 ms a step, §18.4) | lockstep runs the same steps a single player would; catching up is capped by `cpu_share` like fast-forward |
| State digest | ≤ 0.5 ms every 50 steps | §4 |
| Snapshot (host) | ≤ 1 ms on the main thread; encoding on a worker thread | §5.1 |
| Snapshot load (joiner) | off the frame except the final swap (≤ 5 ms), under a "Joining…" screen | |
| Other players drawn | within §18.4's skinned budget (12) | §6.3 |
| Voice encode | ≤ 1 ms per 20 ms frame on a worker thread (WorkerThreadPool), never the main thread | measured in MP5; libopus at complexity 5, 16 kHz mono |
| Voice decode | ≤ 0.3 ms per 20 ms frame per talker, on the same worker | one talker per channel, at most 3 channels |
| Memory | ≤ 30 MB PSS for the session, buffers and voice | |
| Network | idle ≈ 3 kbit/s per player in each direction (positions, commits), ≈ 30 kbit/s per talker; through the host on direct paths, voice to 7 players ≈ 210 kbit/s up from the host | |

MP2, MP5 and MP6 measure these on the Note 9 with the walk among other players (§13); a milestone that misses a
budget isn't done.

## 12. Tests

- **The engine (MP1):** the multi-trainee vectors (§3.3) on the reference and GDScript; the digest's equality across
  Linux, Android (the Note 9) and Windows (the VM) for every vector run every 50 steps.
- **The crypto:** RFC 5869's HKDF test cases and RFC 7518 Appendix B.1's AEAD vector through our GDScript code; the
  code's check character; replay windows.
- **The multi-instance harness** (`apps/plant3d/net/tests/`): N headless Godot processes (`--headless`, the engine and
  the session layer without rendering; the synthetic plant for most tests, the first train for one) driven by a
  Python runner that scripts each player's inputs and reads each one's digests. Each instance is light (no scenes),
  so 8 instances fit the 1 GiB this design was written under; CI runs them in the `plant3d` job.
  - 2, 3 and 8 players for 10 model minutes with inputs from all: every digest equal at every 50th step, and every
    player's event log equal to a single engine fed the same commits;
  - late join at minute 5 and rejoin after a kill; claims of one person by two players (one refused everywhere);
  - host killed mid-turn (some players have its last commit, some don't): a new host within 5 s, no step lost or run
    twice, uncommitted inputs resent and committed once;
  - a desync injected (one instance's value changed): found within 50 steps, resynced, the report written;
  - fast-forward with mixed `ff_cap`s; pause by a non-host; the jump vote; removal and rekey (the removed instance's
    packets are dropped afterwards);
  - limits: input floods, oversized and malformed packets, packets with another session's keys, replays.
- **Network simulation:** a Python UDP and WebSocket proxy between the instances (`apps/plant3d/net/tests/netsim.py`)
  with latency, jitter, loss, duplication, reordering and outages per link, deterministic from a seed; the runs above
  at 150 ms ± 50 ms with 5 % loss and at 400 ms with 15 % loss must still agree, and the harness reports the
  input-to-effect delay.
- **The relay:** `relay-plant/twin.py`, the Python twin of the Worker (as `relay/twin.py` is of Walkdown's), used by
  the harness; the same protocol tests run against the real Worker in workerd (`npx wrangler dev`) on the laptop
  before each deploy. Tests of the limits, admit, create races, 9th socket, the empty-room deletion.
- **No network outside a session:** a test starts the app's main scene headless, plays a single-player run and checks
  that no socket was opened (the session layer's own counter, and on Linux `/proc/self/net` sockets of the process).
- **Voice:** `wdp_voice` round trip on a CC0 speech clip (the decoded signal against the original: delay and level),
  loss concealment at 10 % loss, the resampler at 44.1 and 48 kHz; the floor rules in the harness; on the emulator,
  the permission flow (`RECORD_AUDIO` asked when voice is turned on, never before).
- **Devices:** the Note 9 and the laptop over the Wi-Fi (MP2), the Note 9 on mobile data through the relay (MP4), the
  Windows VM in a LAN session with the laptop (MP2). The user's Honor only for the plant app (the memory note), never
  for Walkdown.

## 13. Milestones

Every milestone ends shippable in the sense of MILESTONES.md (every CI run green; a release could be made, though none
is until the project is complete) and keeps the frame rules on the Note 9. Sizes as there: **S** one pull request,
**M** two to four, **L** five to eight.

| # | Milestone | Size | Needs | Ships | Measured |
|---|---|---|---|---|---|
| MP0 | **This design**: MULTIPLAYER.md, decisions 0067–0069, CAPABILITIES.md | S | — | the plan | — |
| MP1 | **Lockstep-ready engine:** several trainees (§3.3) in the reference, the GDScript and the vectors; `release` and reclaim; the state digest (§4); the vectors on Windows (the factors stored if `exp` differs); one input path in the app (every UI input through `ui/inputs.gd`, which a single-player run feeds straight to the engine) | M | S3 | single-player unchanged; vectors for 1–3 players | digest cost on the Note 9 ≤ 0.5 ms; digests equal on three platforms |
| MP2 | **LAN sessions:** the code and link, keys and AEAD (§1.3) with their vectors, packets and reliability (§2), beacons and join, the lobby and role claims, commits and the jitter buffer, hashes and resync, late join and rejoin, pause and the ready-for-fast vote, instructor seat, other players' avatars and `pos`, host and player saves; the harness and netsim; Android `INTERNET` and the multicast lock; the Flatpak's and MSIX's network permissions | L | MP1 | 2–8 players on one Wi-Fi | harness: 8 instances agree; the Note 9 + laptop + Windows VM in one session; input-to-effect ≤ 0.5 s median on the Wi-Fi; the Note 9 walk with 2 players within the frame rules; session layer ≤ 0.5 ms a frame |
| MP3 | **Host migration and removal:** §5.3's election, `last`/`newhost`, inputs resent, removal and rekey; the host-kill and removal harness runs | M | MP2 | a session that survives its host | harness: new host within 5 s at 150 ms and at 400 ms with loss, no step lost |
| MP4 | **Online:** `relay-plant/` (Worker, twin, tests, pinned wrangler, its README), deployed after the twin and workerd tests pass, on a free-plan account (§9.1); the relay path in the app; direct UDP (STUN, candidates, punch, fallback) | L | MP2 | play from anywhere | the Note 9 on mobile data + laptop: RTT, input-to-effect ≤ 0.5 s median and ≤ 1 s p95; requests per session-hour from Cloudflare's analytics written into §9.1 |
| MP5 | **Voice:** decision 0069's `wdp_voice` built from pinned sources for the four packages' targets (its licence notices in About), capture with `get_input_frames`, push-to-talk, channels and floor, jitter buffer, radio bus; `RECORD_AUDIO` and the desktop permissions | L | MP2 | push-to-talk on the radio | encode ≤ 1 ms / decode ≤ 0.3 ms per frame on the Note 9; mouth-to-ear ≤ 400 ms on the Wi-Fi; the frame rules with one talker; the APK still ≤ 150 MB |
| MP6 | **A full session measured:** 8 players (the Note 9, the laptop, the VM and harness bots) through a shift with fast-forward and a jump, voice on; the Note 9's 10-minute walk among 7 players | M | MP3, MP4, MP5 | the whole feature, measured | the frame rules on the Note 9 with 7 others drawn and one talker; no desync in 60 minutes |

**Order:** MP1 → MP2, then MP3, MP4 and MP5 in any order (each needs only MP2), then MP6.

**When to stop and ask the user:** the Cloudflare account isn't on the free plan (§9.1); the APK would pass 150 MB
with `wdp_voice` (it adds about 1 MB); a platform can't build `wdp_voice` (voice dropped there?); the measured
input-to-effect on mobile data misses 1 s at the 95th percentile (a turn of 1 step, or a regional relay, is then a
choice); Windows' `exp` differs and the stored factors change the vectors.
