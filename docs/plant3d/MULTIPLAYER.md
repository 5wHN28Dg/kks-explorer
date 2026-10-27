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
  the first 15 characters)), so that a typo is caught before anything is sent (all but one in 32 random typos);
  typing is forgiving as Crockford's decoding is (I and L read as 1, O as 0, lower case as upper case, dashes and
  spaces ignored);
- the **link** `walkdown-plant://join/<code>` and its **QR code** on the host's screen. A phone's own camera app opens
  the link, and the app's existing link path (decision 0056) starts the join, so the plant app needs **no camera
  permission and no QR reader**. The QR code is drawn by a small GDScript encoder of our own (byte mode, error
  correction M; Godot has no QR class [S 4.7 doc/classes]). `join` is a new link kind (PLANT3D.md §6 and
  `sim/links.gd` gain it in MP2). Not every camera app offers to open a scheme other than http(s) from a QR code:
  MP2 tries the Note 9's camera app and Google Lens, and the code under the QR code is always there to type. On a
  desktop a link starts a second instance of the app, which joins on its own (the running instance keeps its run;
  `autosave.gd`'s claim keeps the two from saving over each other).

The code is the session's only secret: whoever holds it may join (§1.3 explains why that is enough here). It is shown
to the room as Walkdown shows an invite, and it is gone when the session ends.

### 1.2 Join

**As built (MP2):** §14 says where the build differs from what follows.

The joiner types the code, follows the link, or scans the QR code with the camera app. The app then:
1. looks for the session on the LAN for 2 s (§9.3: a broadcast query with the room ID derived from the code);
2. if none answers and the code's session is online, enters the relay room (§9.1);
3. sends `hello` (§2.2) to the host, with its **display name** (1–24 characters, typed once and kept in the app's
   settings) and its **RSA public key** (§1.3);
4. gets `welcome` (its slot, the roster, the session's settings, the epoch, its P encrypted to its RSA key) and the
   snapshot (§5.1), then plays from the next commit.

A `join` link opened on a cold start skips the saved-run offer (`autosave.gd`); the single-player save stays as it is
and is offered at the next solo start.

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
  - `room` = 16 bytes, info `"room"`: the relay room (32 hex characters) and the LAN query's ID (§9.3);
  - `admit` = 32 bytes, info `"admit"`: the relay's admission token (the relay keeps only its SHA-256);
  - **K** = 32 bytes, info `"group"`: the session key for messages to everyone.
- **P**: 32 random bytes the host makes for each player and sends it in `welcome`, encrypted to the player's RSA
  public key (`Crypto.encrypt`, RSA-2048 with mbedTLS's PKCS#1 v1.5 padding; the plaintext of 32 bytes fits). Each
  app instance makes its RSA key once per process (`Crypto.generate_rsa(2048)`, on a worker thread when the join or
  host screen opens; MP2 measures its time on the Note 9) and sends the public key in `hello` (under K). Messages
  between that player and the host are under P, so another player can't make an input that the host takes as
  someone else's, and capturing traffic (a shared-key Wi-Fi) or the relay's routing doesn't reveal P. Only an
  **active** attacker who holds K and stands in for the host at the moment of a join (spoofing the host's address on
  a LAN, or claiming the relay's host routing, §9.1) can give that joiner a P of its own; it then faces a session
  only it can see (its commits must match the real host's for the joiner's digests and roster to make sense), and the
  roster on the real host's screen shows the joiner missing. A new P is made for each player at every rekey (§2.4)
  and host change (§5.3), the same way.
- **Encryption:** AEAD_AES_128_CBC_HMAC_SHA_256 of RFC 7518 §5.2.3 (the JOSE "A128CBC-HS256"): the 32-byte key's
  first half is the MAC key and its second half the AES key, a random 16-byte IV per message, PKCS#7 padding, the
  tag the first 16 bytes of HMAC-SHA-256 over (AAD ‖ IV ‖ ciphertext ‖ AAD length in bits as a 64-bit big-endian
  number). Every piece is a Godot primitive (`AESContext` CBC, `HMACContext` SHA-256, `Crypto.generate_random_bytes`,
  `Crypto.constant_time_compare`), and RFC 7518 Appendix B.1 gives the test vector. The AAD is the packet header
  (§2.1), so a header can't be moved onto another body.
- **Replay:** every packet carries the sender's incarnation and packet number (§2.1); a receiver drops a number it
  has seen or one more than 256 below the highest seen from that (sender, incarnation, key). Before it has a slot, a
  joiner's packets are told apart by their incarnation alone.
- **Other uses get their own keys:** the LAN answer's MAC key is HKDF(K, info `"lan"`) and a punch's is HKDF(P, info
  `"punch"`), so the AEAD keys are used for nothing else.

**What this does not give, and why that is accepted:** players are trusted classmates. One who holds K can read
the session's broadcasts and could forge a broadcast as the host on a path that doesn't say who sent it: the relay
tags every message with its sender's socket (§9.1), so only a LAN (where an IP address can be spoofed) is open to it.
Such a forgery desyncs the others, who are then resynced from the host under their P (§4). The active attack on a
join (above) would need a key the joiner can check against the code, which a typed code of 16 characters can't
carry (decision 0068, "When to revisit"). A player can always disrupt a session by playing it badly; the host can remove them (§2.4), which moves the
session to new keys. Whoever reads the code over a shoulder can join: the host sees every join in the roster and
removes strangers.

## 2. Messages

### 2.1 Packets

**As built (MP2):** §14 says where the build differs from what follows.

Every transport (LAN UDP, direct UDP, the relay) carries the same packets:

| Field | Size | Meaning |
|---|---|---|
| version | 1 | 1 |
| key | 1 | 0: K; 1: P of the player in `from` or `to` (whichever is not the host); 2: none (only `punch`, §9.2) |
| from | 1 | the slot that made the packet; 255 before it has one (its `hello`) |
| to | 1 | a slot, or 255 for everyone |
| epoch | 2 | the host epoch (§5.3); packets of an older epoch are dropped, except `last`, `hello`, `welcome` and `refuse` (a joiner learns the epoch from `welcome` or the LAN answer) |
| incarnation | 4 | random, made once per app process: a player whose app was killed and rejoins sends under a new one, so its fresh numbers aren't taken for replays |
| number | 4 | the packet number of (`from`, incarnation) under this key, from 1: the replay counter (§1.3) |
| body | | IV, ciphertext and tag (§1.3) of one or more messages |

A packet is at most 1,200 bytes on UDP (one datagram without fragmentation on any common path) and at most 64 KiB
through the relay (65,000 bytes, so that a relay message's framing fits, §9.1). The header is 14 bytes; encryption
adds 16 (IV) + 1–16 (padding) + 16 (tag). A packet carries
messages of one key only (the key byte says which). A host forwarding a packet (§9.4) passes it on unchanged: its
`from`, number and tag stay the original sender's.

### 2.2 Message kinds

Each message inside a body is a kind (1 byte), a length (2 bytes), for a reliable message its stream sequence
(4 bytes, §2.3), and its fields. Inputs are the trace format of
PLANT3D.md §12 and §17.6, as strict JSON text (read with `sim/json_strict.gd`, at most 512 bytes each): the same
form the vectors, the save and the debrief already use.

| Kind | Channel | From → to | Key | Fields |
|---|---|---|---|---|
| `hello` | reliable | joiner → host | K | display name, RSA public key, the app version (`RunSave.app_version()`), the content hash, a rejoin token or none (§5.2) |
| `welcome` | reliable | host → joiner | K (P inside it RSA-encrypted) | slot, epoch, P encrypted to the joiner's RSA key, roster, settings (nothing in them is secret from the other players), the next input number for the slot, the host broadcast stream's next sequence; from then on host and joiner use P |
| `refuse` | reliable | host → joiner | K | a reason (`full`, `version`, `content`, `removed`, `closed`) |
| `key` | reliable | host → one player | K, RSA-encrypted | a new P after a rekey or host change (§2.4, §5.3) |
| `roster` | reliable | host → all | K | every slot: name, role (a person or none), connected, path, LAN address, ready flags, SHA-256 of its rejoin token |
| `input` | reliable | player → host | P | the player's input number (from 1), the input |
| `commit` | reliable | host → all | K | epoch, first and last step of the turn, the digest stride (§4), the inputs scheduled in it as `[step, slot, input number, input]` |
| `hash` | reliable | everyone → host | P | step, the state digest (§4) |
| `snap` | reliable | host → one player | P | the snapshot (§5.1), in fragments |
| `control` | reliable | player → host / host → all | P / K | pause, run, fast-forward votes and caps, the jump vote, instructor mode (§7) |
| `pos` | unreliable | player → all | K | the player's position, heading, pitch, gait, at 5 Hz (§6.3) |
| `voice` | unreliable | player → all | K | channel, talk-spurt number, frame number, Opus frames (§8) |
| `talk` | reliable | player → host / host → all | P / K | ask for, grant, refuse and end a channel's floor (§8.4) |
| `ping` / `pong` | unreliable | any (paused: never through the relay, §3.1) | P with the host, else K | a time stamp, for round-trip times |
| `ack` | unreliable | any | the acknowledged stream's | stream, the highest sequence received in order, a 32-bit mask of those after it (§2.3) |
| `frag` | as its message | any | its message's | message ID (2 bytes), index (2 bytes), count (2 bytes), a piece of a reliable message too long for one UDP packet (§2.3); each piece is its own stream message with its own sequence |
| `last` | reliable | player → candidate | K | committed step, digest, uncommitted inputs, RSA public key (§5.3) |
| `newhost` | reliable | new host → all | K | (§5.3) |
| `remove` / `rekey` | reliable | host → one / each other player | P | (§2.4) |
| `bye` | reliable | any | P with the host, else K | leaving |

### 2.3 Reliability

**As built (MP2):** §14 says where the build differs from what follows.

- **Streams.** Reliable messages travel in streams, each with its own sequence numbers from 1 (not the packet
  numbers, which count every packet for replay protection): one per player and direction between that player and
  the host (under P), and the host's broadcast stream (under K, every reliable host → all message), plus the
  migration streams of §5.3 (each player's to the candidate). A stream is identified by its two ends and the
  epoch: a new host's streams start at 1; `welcome` (and the snapshot) give a joiner the broadcast stream's next
  sequence, and commits are applied by their step numbers, never by sequence alone. Every addressee acknowledges
  each stream with `ack` (cumulative sequence and a mask), in its next packet back or at the latest with its next
  0.2 s send (§9.1), so acks cost no extra relay messages; for the broadcast stream every player acknowledges on its
  own and the host keeps each player's position.
- **Window and pacing:** at most 32 unacknowledged messages per stream (the ack mask's width), growing from 8 as
  acks come and halved once per window on a loss, fast retransmit after 3 later messages acknowledged (Walkdown's
  rudp rules, PROTOCOL-v2 §18, capped by our mask). The snapshot has its own stream, sent only when the commit and
  input streams have nothing waiting, and through the relay at most 128 KiB a second.
- **Delivery:** in order per stream; a message is sent again after an RTO computed as in RFC 6298 (400 ms, above the
  ack delay, to 4 s),
  as Walkdown's reliable UDP does (PROTOCOL-v2 §18), to those that haven't acknowledged it (a broadcast message
  resent to one player goes to that player alone). Unreliable messages never ride in a packet with reliable ones
  and are never sent again.
- **Long messages:** on UDP a reliable message longer than fits in one packet (a commit with many inputs, `welcome`,
  a full `roster`, the snapshot) is cut into `frag` pieces with one message ID; the receiver reassembles at most
  64 KiB per message (the snapshot: its own limit, §5.1) and 256 KiB in all per sender, and drops pieces beyond that.
  Through the relay the whole message goes in one relay message (≤ 64 KiB) or, for the snapshot, in 60 KiB pieces.
- **Through the relay** (a WebSocket over TCP) nothing is lost, but the same sequences and acks are kept, so that a
  player can move between the relay and UDP (§9) without losing or repeating a message.

### 2.4 Leaving and removing

`bye`, or no packet for 10 s, marks a player disconnected in the roster. Their person goes to the NPCs (§6.2) after
60 s unless they rejoin. The host may **remove** a player: it sends `remove`, then a new code's keys (a new room,
admit and K, made by the host from 75 new random bits) to each remaining player under their P in `rekey`; the host
creates the new relay room first, the others enter it (retrying `no such session` every second for 10 s) and send a
new `hello` with their rejoin token, the host answers each with a new P (`welcome`), and the LAN query (§9.3) uses the
new room ID. The removed player still knows the old code, which now opens nothing. The host's
screen shows the new code for anyone who should join later.

## 3. Lockstep (decision 0067)

### 3.1 The rule

**As built (MP2):** §14 says where the build differs from what follows.

Every player runs the whole engine (`sim/engine.gd`), from the same start, with the same inputs at the same steps, so
every player has the same plant bit for bit, as the vectors already require between the reference and the app on
every platform. Only inputs travel. The host is the **sequencer**: it alone says which inputs take effect at which
step.

- The host keeps the **committed step** C. Every turn it closes the steps (C, C + T] with a `commit` that lists the
  inputs that take effect in them, each at the turn's first step C + 1, in the order the host received them (its own
  included, through the same path as anyone's). No player, the host included, runs a step that isn't committed.
- **T, the turn:** 2 steps (0.2 s) at 1×. In fast-forward the host closes more steps per 0.2 s of real time (§7.2).
  A turn with no inputs is a commit with an empty list (about 70 bytes with header and encryption); a paused session
  sends none. Paused, the host sends a `ping` every second to the players it reaches over the LAN or direct UDP, but
  nothing through the relay except the relay's own text ping every 25 s (§9.1), which keeps the room open and asleep.
- **The host runs before it commits:** it runs each step of the turn on its own engine, then sends the commit. In
  fast-forward it ends the turn early at the step after which the engine no longer offers fast-forward (§7.2), so no
  player runs past that point at the fast rate; the next turns are at 1×. The host runs without a jitter buffer; its
  committed step is always the step its own engine has reached.
- **Inputs:** a player's UI no longer queues an input in the engine: it hands it to the session (`input`), shows it
  as sent (the op's button as pressed, "sending…"), and the input takes effect in every engine when its commit
  arrives. The player keeps each input until a commit lists its number, sends it again after a host change (§5.3),
  and the host ignores an input number it has committed already. **As built (MP1):** every input the app makes goes
  through one path, `apps/plant3d/ui/inputs.gd` (`send([kind, …])`, the trace form without step or slot); alone it
  queues the input in the run's engine at once, as before, and a session (MP2) sets its `sink` to take it instead.
  `tests/test_plant3d_inputs.py` checks that nothing else in the app makes an input.
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
and re-running states: a copy of the whole state every step (the save's copy takes about 0.75 ms on the Note 9,
apps/plant3d/README.md), and on a late input the steps since re-run (0.77–0.81 ms each there, sim/README.md "Faster,
the same bits"; 10 steps are about 8 ms, a quarter of a frame) with the staff's jump placement (≤ 50 ms, §18.4)
whenever a jump falls inside. None of that buys anything for a plant that answers in seconds. Streaming the state
from the host would need the
state in every message (thousands of values and the staff) or a delta scheme the engine doesn't have, and it would
end "the same simulation everywhere" (decision 0067 compares the three).

**Latency to expect:** mobile networks' median latency is about 45–50 ms (Ookla's US reports: T-Mobile 46 ms in
H2 2025, 49 ms in H2 2024) to under 20 ms in the best (Qatar, 18 ms, Speedtest Global Index June 2025), with longer
tails and worse on congested cells. These are secondary reports of US and Gulf networks, not of the users' own; MP4's
measurement on the Note 9 is the evidence that counts. Through the relay a message goes player → the nearest
Cloudflare location → the data centre where the room's Durable Object lives → host. A Durable Object is created near
its first request, but Durable Objects don't run in the Middle East, Africa or South America: rooms made there land
in a nearby region, which adds that hop's round trip [D durable-objects/reference/data-location]. An input then takes
effect after its trip to the host (≈ 50–200 ms), the wait for the next commit (0–200 ms), the commit's trip back
(≈ 50–200 ms) and the jitter buffer (200 ms): about 0.3–0.8 s on mobile data, 0.25–0.45 s on a Wi-Fi. MP4 records
where the room landed. MP2 and MP4 measure it on the Note 9 (§13) against a budget of **0.5 s median, 1 s at the 95th percentile**
on mobile data, input made to effect seen.

### 3.3 Several trainees in one engine

**As built (MP1, 2026-10-26): PLANT3D.md §17.13** is the engine's rule, in the reference, the GDScript and the vectors
(§19, "Added for milestone MP1"); where it differs from the plan below, it wins. What it settles: a slot that plays
nobody is exactly a single-player run's free mode (its format 2 inputs naming no person pass, as there); the events
of a session's `role`, `release` and `task_ack` end with the slot (`[n, "role", person, "done" | "refused", slot]`,
`[n, "release", person, "done" | "refused", slot]`, `[n, "task_ack", slot]`); a claim or a release pauses the person's
task as a pre-emption does and their next turn takes it up (a person walking a way when claimed is between places; one
between places when released goes back to the place they left); an input without a valid slot does nothing. The
engine is made as a session run (`new(model, scenario, true)`, `Engine(b, scenario, session=True)`), which its save
and its digest record.

The plan, as written before the code:

Today the staff step has one trainee (`st_trainee`, PLANT3D.md §17.4). A session has up to 8, so the engine changes
(milestone MP1, reference, GDScript and vectors together, as every engine change):
- **`players`:** the trainee becomes a list of persons, one per player with a role. The role input becomes
  `[n, "role", person, slot]`, accepted at any step in a run with players (today's step-1-only rule stays for the
  single-player run): refused, with its event, when the person is another player's, absent, not a `play` role, or
  that slot already has a person. A scenario that names its trainee (`_fixed_trainee`) gives that person to the
  host's slot in a session. The single-player run is the case of one slot 0.
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
- **Instructor inputs** (`fault`, `repair` and removals by authority as the trainer) carry no authority in the
  engine: the host takes them only from the host's and instructor slots (§7.3) and drops them from anyone else.
- The vectors (`plant3d-v2.json`'s staff `runs` and `day` forks) gain runs with two and three players, a release and
  a reclaim mid-task, refusals for another slot's person, and fast-forward held by one player's unseen task.

## 4. State hashes and desyncs

**The digest (as built in MP1): PLANT3D.md §17.14**, in both engines (`engine.gd digest()`, `ref/plant3d.py
Engine.digest()`), with vectors: SHA-256 over a tag, the values' doubles and the Godot Variant encoding of a *digest
tree* that holds every part of the state the next steps read (machines, trips, alarms and their counters, shelves,
faults, permits, locks, the timers' counts; the staff's people, duties, places, ways, task instances, queues, held
jobs, reservations, reaction sources, kept offers, random streams, PPE, unsafe acts, the players' slots and counts, the
NPCs' inputs for the next step), each in a fixed order and form. It differs from the plan below, which hashed the
save's fields as GDScript keeps them: the reference could not make that (its state is kept in other forms), so the
tree is a form of its own that both make, and it leaves out what an implementation may keep its own way (a task step's
own progress: the app counts an NPC's work when they wake, the reference every step), with what the logs only record
and what is derived (§17.14 says what and why). A difference hidden in a task step's progress shows by the step after
that step ends, which for a long `work` (an hour's job) can be thousands of steps later: accepted, because what could
make two players' progress differ (a float, an input missed or applied twice) changes the values, events or task
steps the digest does cover at once; a difference confined to a step's own counter would need an engine bug that the
vectors (both engines, every step's events) are there to catch. Godot's `var_to_bytes` is the encoding (a future Godot that changes it is a "When to revisit" of 0067:
the vectors' digests would fail first).

**Its cost** (`apps/plant3d/sim/tests/bench_digest.gd`; on a phone the app's `digest=bench`, app/digest_bench.gd): the
first train with its staff (shift_cold, 66 people, about 40 task instances, 38 KB hashed) at five points of the shift:
laptop 0.24 ms median, 0.30 ms
at the 95th percentile, 0.39 ms the longest; **Note 9 (release build, 2026-10-26): 0.55 ms median, 0.66 ms at the
95th percentile, 0.86 ms the longest** (0.42–0.64 ms by point, the most when the most tasks are given), of which the
tree built and encoded is 0.36 ms (the rest SHA-256). Within the budget of 1 ms on the main thread: no worker thread
is needed. At most about 2 digests a second (below), it is about 0.1 % of a core there.

The plan, as written before the code: SHA-256 over the engine's state as the save keeps it (`RunSave.engine_fields`: every script variable
but the compiled program), **without** `events`, `inputs` and the debrief's logs (they only grow, and what they record
is in the state too), field by field in sorted name order: a packed array's bytes go straight into the
`HashingContext` (`cur`, `prev`, `mem` and the other `Packed…Array`s, by far the largest part: no encoding), the
small Arrays and Dictionaries through `var_to_bytes`. Same Godot release, same field order, doubles as their bits:
the same state gives the same bytes on every platform, which MP1 checks (the digest of every vector run's every
50th step equal on Linux, Android and Windows). The save's whole cost (copy 0.75 ms, then encoding and writing,
about 4.5 ms on the Note 9 by apps/plant3d/README.md's estimate) is not the digest's: it encodes the logs and
everything as Variants. **Budget: ≤ 1 ms per digest on the Note 9** for the first train with staff; MP1 measures it,
and if it misses, the digest's state is copied on the main thread and hashed on a worker thread.

**When:** every player sends `hash` for every step that is a multiple of **50 × the digest stride**. The stride is in
every commit (so every player hashes the same steps): 1 at 1× (every 5 s of model time); in fast-forward the host
sets it to the session's rate divided by 10, rounded up (at 30× every 150 steps, every 0.5 s of real time). So a
player makes at most about 2 digests a second, 2 ms a second of the Note 9's main thread. The host keeps its own
digests of the last 20 such steps.

**On a mismatch** with the host's digest: the host marks the player desynced in the roster and sends it a snapshot
(§5.1's form) at its current committed step; the player throws its engine away, loads the snapshot and plays on from
the next commit (the plant may jump on its screen; a banner says "Resynchronised with the host"). Before loading, the
player writes a **desync report** to `user://desync/` (both digests, the step, its own state and the snapshot), and
the host notes it in the session log, so that the cause is found (a platform's `exp`, an engine bug). A player that
desyncs twice within 10 minutes is told its device can't follow this session and stays as an observer (it sees the
host's snapshots every 30 s and makes no inputs) until the host's next decision. The host is the reference by
definition, except when most players' digests agree with each other against the host's at the same step: then the
host's device is the odd one out (a platform difference), and the session stops with a "the host's device differs"
report rather than demoting everyone; the players may start again with another host. The host keeps its digests for
3 minutes of real time; a hash for a step older than that is ignored.

**Checked in MP1 (2026-10-26):** the Windows 11 VM ran every vector with Godot 4.7.2's Windows build: all passed, and every run's value digests and state digests were Linux's (`tools/plant3d/vectors_windows.sh`), so no stored factors are needed. The Note 9 ran the digest bench only (above); bionic's `exp` was checked on every vector run on 2026-10-16. **The risk as it was written:** the engine is bit for bit with the reference on glibc and bionic but not yet run on
Windows, whose C library's `exp` makes a lag's factor (sim/README.md, CAPABILITIES.md §8). MP1 runs the vectors on
Windows; if any digest differs, the build computes the factors on Linux and stores them in the compiled model, as the
README already plans.

## 5. Late join, rejoin and host changes

### 5.1 The snapshot

**As built (MP2):** §14 says where the build differs from what follows.

The host takes the snapshot at a committed step C. It is its own Dictionary, not a run save (the save's `decode`
and `autosave.check` require the UI, player and tracker parts and refuse other keys): `{"app", "content",
"scenario", "engine", "session"}`, where `engine` is exactly the save's engine part (with `events` and `inputs`, so
that the joiner's debrief and alarm list are whole) and `session` the roster, roles, settings and C. It is encoded as
the save is (`var_to_bytes`, no objects) and compressed with zstd (`PackedByteArray.compress(FileAccess
.COMPRESSION_ZSTD)`). The first piece says the uncompressed length; the joiner refuses one over the save's
`MAX_BYTES` (64 MiB), decompresses with `decompress(length, FileAccess.COMPRESSION_ZSTD)` (`decompress_dynamic`
doesn't take zstd [S 4.7 PackedByteArray.xml]), and refuses a result of any other length. It is sent under the
joiner's P (UDP `frag` pieces or 60 KiB relay pieces), at most 16 MiB compressed. The joiner checks `app`,
`content` and `scenario` as the save does, and `engine` with the save's own engine check (`RunSave.check` and
`autosave.gd`'s engine contents: the fields and their types must be this engine's), and refuses anything else.

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

1. **Noticing:** no packet from the host for 5 s (a host sends a commit or, paused, a `ping` at least every second;
   a host gone to the background sends `away` first, §7.5, and is waited for 30 s), the relay's `left` for the host's
   relay ID, or the host's `bye`. The 5 s rule doesn't apply to a paused host reached only through the relay, which
   sends no packets there (§3.1): its loss is noticed by its `bye`, or by the relay's `left` when its socket closes or
   when the relay closes it for silence (no message and no ping for 2 minutes, checked at the room's alarm, so within
   about 12 minutes of the device vanishing).
2. **The candidate** is the connected player with the lowest slot. Every player stops at the last commit it has and
   sends the candidate `last`: its committed step, its digest at its last hashed step, the numbers of its
   uncommitted inputs, and its RSA public key. `last` goes under K, addressed to the candidate alone. A player whose
   candidate sends no `newhost` within 8 s sends a new `last` to the next candidate (the next lowest connected slot),
   and so on.
3. **A quorum:** the candidate takes over only when more than half of the last roster's connected players (itself
   counted, the old host not) have sent `last`; with two players left (the old host gone and one other), the relay's
   `left` for the host or the host's `bye` is enough, and on a LAN alone the survivor waits 30 s. A candidate without
   a quorum after 8 s goes back to being a player and keeps listening for the old host. It waits at least 3 s, and
   6 s after its own noticing when any player is on UDP (they notice later). Its own state must not be desynced or an
   observer's, and its digest must agree with the majority of the digests reported for the same step; otherwise it
   passes to the next slot (sending its own `last` there).
4. The candidate takes the highest committed step among the `last`s and fetches the commits it lacks from the player
   who has them (everyone keeps the last 600 commits, two minutes at 1×). The old host's commits are taken as they
   are: they were already committed, and some players may have run them.
5. It sends `newhost` to everyone: epoch + 1, its slot, its relay ID and LAN address, and the committed step; then
   to each player a `key` with its new P (encrypted to the RSA key in its `last`) and the commits it lacks, as
   ordinary `commit` messages. A player accepts `newhost` only after it has itself found the host gone (step 1) or
   within 10 s of having sent its latest `last`, only for the next epoch, and only from the candidate it sent that
   `last` to (by its relay ID through the relay, its roster address on UDP). A player that can't accept it yet
   doesn't acknowledge it, so it is sent again until it can. Everyone runs to that step and follows the new host from
   the next turn; inputs that weren't committed are sent to it again (§3.1). Its first digest exchange confirms that
   everyone agrees.
6. **Late and ahead:** the new host takes a `last` that comes after `newhost` at any time and answers it with
   `newhost` and a `key`. A player whose committed step is above the new host's (its `last` came too late to count)
   marks itself desynced and gets a snapshot (§4): the steps it ran past are replaced, not run twice.

The new host takes over the LAN query's answers (§9.3), saving (§7.4), the talk floors (every floor is ended) and the
roster; its roster carries a SHA-256 of each player's rejoin token, so it can take rejoins it never gave out. **A host
that receives any valid packet of a higher epoch** stops committing at once, keeps its state for a desync report, and
rejoins as a player with its token; so does a host that comes back from a gap and finds itself replaced. The quorum
makes two hosts unlikely; if a split still gives two (each side with a quorum of a roster that changed meanwhile),
the side with more players wins when they meet again (then the higher epoch, then the lower host slot), and the other
side's players rejoin and are resynced from the winner's snapshot, losing their turns since the split. The relay
room, the code and K don't change.

## 6. Roles, NPCs and other players

### 6.1 Claiming roles

The session starts in a **lobby** (the host's chosen scenario at step 0, nothing committed): the roster with each
player's name and the scenario's `play` roles with their people on duty (the Crew panel's start list, §18.7). A
player claims a role (or free mode); in the lobby the host settles claims as session state, first come first served,
and shows them in `roster`. When everyone is ready the host starts the run: the first commit puts every claim's
`role` input at step 1. A player who joins later claims from what is left; that claim is an ordinary input, settled
by commit order (the first `done`, a second for the same person `refused`, the same on every screen). The host may set a role as reserved for a named slot (an instructor assigning
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

**Procedure holds:** a player's procedure tracker is local, so its "pause when a step is done" (sim_clock.gd's
`hold`) can't stop the session. In a session it becomes a notice on that player's screen and, if the player chose
it, a pause request to the host (§7.1).

### 7.3 Instructor mode

The trainer's inputs (faults, repairs, removing a lock by authority, PLANT3D.md §15.5) are open to the **host** and to
any player the host names **instructor** in the session settings (a seat with no person; an instructor may also hold a
role). The host drops trainer inputs from other slots (§3.3). Every such input carries the `instructor` event as
today, so every player's debrief shows them. Other players don't see the instructor panel.

### 7.4 Saved runs

**As built (MP2):** §14 says where the build differs from what follows.

- **The host saves the session** as a single player saves a run (every 5 s while it changes, on going to the
  background), to `user://mp-host.save`, never over the single-player `user://run.save`. It is a file of its own
  format (magic `"WDPMSAV\n"`, otherwise run_save.gd's container: length, SHA-256, `var_to_bytes`), whose payload is
  the snapshot's Dictionary (§5.1) plus the host's own `ui`, `player` and `tracker` parts as the run save has them;
  its loader reuses the save's checks part by part. `run.save`'s format doesn't change.
- **Continue a session:** the host opens a saved session as a new session (a new code). The players who join claim
  their roles again (the lobby offers each the role of the same display name in the save); unclaimed roles stay
  NPCs.
- **Players keep a copy** of the shared run (`user://mp-last.save`, written when they leave or the session ends) for
  their debrief, which shows every player's actions by name and their own tasks (§18.7's Your tasks for their slot).
  From that copy a player may **continue alone**: the other players' persons are released to NPCs and the run goes on
  as a single-player run.

### 7.5 Android's lifecycle

A phone that turns its screen off or goes to the background stops Godot's main loop, and with it the session
(`NOTIFICATION_APPLICATION_PAUSED`, which autosave.gd already handles). So:
- while a session is open the app keeps the screen on (`DisplayServer.screen_set_keep_on(true)`);
- a player that goes to the background sends `away` (`control`); the host keeps it connected, with its person, for
  120 s, then treats it as disconnected (§2.4);
- a host that goes to the background sends `away` and the session pauses for everyone (§7.1); the players wait 30 s
  before a host change (§5.3). A laptop is the better host: the roster suggests it when a phone hosts with a laptop
  in the session.

## 8. Voice (decision 0069)

### 8.1 What Godot 4.7 has

- **No Opus.** Godot 4.7's `thirdparty/` has libogg, libvorbis and libtheora but no libopus, and no Opus class [S
  4.7-stable thirdparty/, doc/classes/].
- **Microphone:** `audio/driver/enable_input` (default off) [D], then either `AudioStreamMicrophone` played on a muted
  bus with `AudioEffectCapture` reading its frames, or the experimental `AudioServer.set_input_device_active`
  with `get_input_frames(n)` and `get_input_frames_available()` (float stereo frames at `get_input_mix_rate()`) [S
  4.7 doc/classes/AudioServer.xml]. We use the latter: no bus and no stream player.
- **Android:** Godot's OpenSL ES driver asks for `RECORD_AUDIO` when input starts (`request_permission`, which is
  asynchronous: the first start fails while the dialog is up) and records 44.1 kHz mono in buffers of 2,048 frames
  (about 46 ms, counted in the mouth-to-ear budget) with the default preset, so the platform's echo canceller and
  noise suppressor are **not** applied [S 4.7 platform/android/audio_driver_opensl.cpp]. So the app asks with
  `OS.request_permission("android.permission.RECORD_AUDIO")` when voice is turned on, waits for
  `on_request_permissions_result`, and only then starts input. The export needs the `RECORD_AUDIO` permission
  ticked.
- **Playback:** `AudioStreamGenerator` with `push_buffer`, one call per decoded 20 ms frame [D].

### 8.2 The codec and library

**Opus** (RFC 6716), through a small GDExtension of our own, **`wdp_voice`** (C++ against godot-cpp 10.0.0 with
Godot 4.7's API, MIT; built as `apps/plant3d/voice/`, decision 0069 "As built"), built
from pinned sources: **libopus 1.5.2** (BSD-3-Clause) and **SpeexDSP 1.2.1**'s resampler (BSD-3-Clause), for Android
arm64-v8a (the NDK, as `libkks.so`), Linux x86-64 (built in the Flatpak's own SDK, matching
`org.godotengine.godot.BaseApp//4.7`'s runtime, so that its glibc is the one it runs on) and Windows x86-64 and
ARM64 (the two MSIX packages; llvm-mingw, decisions 0047, 0053). Its interface: an encoder (`encode(PackedVector2Array frames) -> PackedByteArray`, taking the mix rate's
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
**Measured (MP5):** at 16 kbit/s, libopus 1.5.2 codes no in-band FEC at any expected loss. It needs about
20 kbit/s with 10 % or more expected loss (decision 0069, "As built"). Until MP2 sets the bitrate, a lost frame is
concealed, not rebuilt.
Two frames per `voice` message (40 ms): about 80 bytes of Opus, 12 of fields, 14 of header and 33–48 of encryption,
so about 150 bytes per 40 ms, **30 kbit/s** per talker (plus UDP/IP or WebSocket framing). The receiver keeps a
jitter buffer of 60–200 ms (adaptive), decodes a lost frame by FEC or concealment, and plays it on the radio's bus
(with two frames per message, in-band FEC rebuilds only the second frame of a lost message from the next one; above
5 % measured loss a sender on UDP sends one frame per message, and the host bundles what it forwards to the relay
per 40 ms, §9.4):
a band-pass of 300–3,000 Hz and light distortion (Godot's `AudioEffectBandPassFilter` and `AudioEffectDistortion`),
the squelch clicks at the start and end of a talk spurt as CC0 clips (0054 §7).

### 8.4 Push-to-talk and channels

- **Channels:** the radio panel's (operations, maintenance, HSE: §18.7). A player hears the channels their role's
  radio carries (all three in free mode and as instructor) and talks on the one selected.
- **Push-to-talk:** a held key (`V`), a gamepad button, or a held on-screen button on a phone. The microphone's input
  is started at the first press (`set_input_device_active(true)`), sent only while the button is held, and stopped
  10 s after the last release, so a quick exchange doesn't pay the start-up each time; Android 12 and later show
  their microphone indicator for exactly that time, and the app shows its own mark while sending.
- **One talker per channel**, as on a real radio, so voices never overlap: pressing asks the host for the channel's
  floor (`talk`); the frames captured meanwhile are kept, and sent once granted (dropped, with a busy tone, when
  refused). The floor ends when the button is released or after 30 s.
- **Half duplex:** while a player talks, their own playback of that channel is muted. So a phone's speaker never
  feeds its own microphone; all voice playback is muted while push-to-talk is held (also the channels a free-mode
  player or instructor hears).
- **Players in one room:** a phone's speaker playing A's voice next to A comes back into A's microphone at the next
  press, and everyone in the room hears each voice twice. So voice from players reached over the LAN is not played
  by default (they are in earshot; a setting turns it on, for headsets or separate rooms). Headsets are recommended
  where players share a room and use the relay. No echo canceller; noise suppression is left to Opus's VOIP mode
  (RNNoise, BSD-3, can be added to `wdp_voice` later if trainees' rooms prove too loud).
- NPCs' radio messages stay text in the radio log (§18.7), and players' voice is not recorded or saved anywhere.

### 8.5 Permissions per platform

| | Android | Linux (Flatpak) | Windows (MSIX) |
|---|---|---|---|
| Network | `INTERNET` (and `CHANGE_WIFI_MULTICAST_STATE` for the LAN query, §9.3); normal permissions, granted at install | `--share=network` | `internetClient`, `privateNetworkClientServer` (the LAN) |
| Microphone | `RECORD_AUDIO`, asked at run time when voice is first turned on in a session | `--socket=pulseaudio` (the microphone through PipeWire's Pulse server) | `microphone` device capability; Windows' privacy setting must allow desktop apps |

**Android's network permission can't be switched on and off:** `INTERNET` is granted at install for as long as the app
is installed. "The network only while a session is open" is therefore the app's behaviour, not the system's: no socket
is opened outside a session, and a test checks it (§12). The same holds for Flatpak's and MSIX's static permissions.
0054 §8's `permissions/internet=false` changes, and that record gains a note. Android 17's local network permission (`ACCESS_LOCAL_NETWORK`) binds apps that target SDK 37; Godot 4.7's
template targets 36, whose apps get it implicitly with `INTERNET` [D developer.android.com local-network-permission;
S 4.7 platform/android/java/app/config.gradle]. A move to target 37 must add the runtime request.

## 9. Transport (decision 0068)

Three paths carry the packets of §2; a session may use all three at once, chosen per player (who forwards: §9.4):

### 9.1 The relay

A new Cloudflare Worker with one Durable Object per room, built like Walkdown's (`relay/src/index.js`: hibernating
WebSockets, `setWebSocketAutoResponse` for pings) but its own code, repository folder `relay-plant/` (Worker, pinned
wrangler, twin, tests), its own Worker name and its own deployment. Its URL is in `CLAUDE.local.md` and the app's
build configuration file (ignored by git), never in tracked files; the app reads it from the build. Builds without it (CI's exports, a
clone) offer This Wi-Fi only.

- `GET /v1/room/<room>` (32 hex characters) upgrades to a WebSocket. The first message is text:
  `{"t": "hello", "admit": <32 bytes, base64url>, "create": true | false}`.
  - `create: true`: the room must not exist; the relay stores SHA-256(admit) and the creation time (SQLite storage:
    one row per room), and the socket becomes relay ID 1 and the room's host.
  - `create: false`: the room must exist and SHA-256(admit) match; the socket gets the next relay ID (16 bits, from
    1, never reused within the room).
  - The answer: `{"t": "welcome", "id", "peers": [ids], "host": id or null}`, or `{"t": "error", "why"}` and close
    (`exists`, `no such session`, `bad admit`, `full`, `limit`). Members hear `{"t": "joined", "id"}`,
    `{"t": "left", "id"}` and `{"t": "host", "id"}`.
  - `{"t": "host"}` from a member makes it the room's host (after a migration, §5.3) and tells everyone. The relay
    can't check the claim (it holds no key); it is routing only: players accept host packets by the rules of §5.3,
    and a joiner sends its `hello` to the relay's host (a false claim can at most stand in for the host at a join,
    §1.3).
- Then binary messages of at most 64 KiB: the sender writes `to` (2 bytes: a relay ID, 0 for every other member)
  before one or more packets, each with a 2-byte length; the relay replaces `to` with `from` (the sender's relay ID) and passes the
  packets on unread. It never sees K, P or the code: it holds a hash of `admit`, and `admit` and `room` are HKDF
  outputs that don't reveal the code.
- The roster maps relay IDs to slots, so a player accepts a host packet only from the host's relay ID, and a
  forwarded packet (§9.4) only from the host's.
- **Limits:** 12 sockets per room (8 players and rejoins overlapping during a host change); a message ≤ 64 KiB; per
  socket 60 messages a second averaged over 10 s (burst 200) and 256 KiB/s, the room's host 120 a second (it
  forwards, §9.4). Over a limit the relay drops the messages and sends `{"t": "slow"}`; only at three times the limit
  for 10 s does it close the socket with `limit` (a busy host is slowed, not cut off, which would force a host
  change). A room lives at most 24 h; a room in which no member sent anything, not even a ping, for 10
  minutes, or empty for 10 minutes, is closed and deleted; a member that sent nothing, not even a ping, for 2 minutes
  while others did is closed (`quiet`), and the others hear `left`; failed hellos (bad admit, bad hello; not
  `no such session`, which players retry after a removal, §2.4) at most 30 a minute per room. The counters live in
  the Durable Object's memory, never its storage (the free plan allows 100,000 rows written a day); a room evicted
  from memory starts its counters again. **Keep-alive:** a paused session sends nothing through the relay but the
  text `{"t":"ping"}` every 25 s, which the relay answers by `setWebSocketAutoResponse` without waking the object
  (as Walkdown's), so a paused room hibernates and costs no duration. The relay reads each socket's last ping time
  (`getWebSocketAutoResponseTimestamp`) when the room's alarm runs, so the pings count as activity: a paused room
  stays open, up to its 24 h, for one alarm (one request, and perhaps one row written) every 10 minutes. A paused host's every-second `ping`
  (§3.1, §5.3) does not go through the relay: each binary message would wake the room and keep it from hibernating
  (450 GB-s an hour, below).
- **Room creation:** one more Durable Object counts the rooms created per UTC day and refuses `create` beyond 200
  (one request per room created); and the Workers rate limiting binding (10 or 60 s periods, per Cloudflare
  location, approximate [D workers/runtime-apis/bindings/rate-limit]) at 10 rooms a minute per IP address, if MP4
  finds it available on the free plan.
- **Known denial of service, accepted:** the relay's URL is in every build, so anyone who extracts it can open rooms
  and send messages until the day's free allowance is used, and every online session fails until 00:00 UTC (LAN
  sessions are unaffected). The limits above make that take some effort; it costs nothing, because the free plan
  can't be billed.
- **Cost on the free plan** [D durable-objects/platform/pricing]: Durable Objects 100,000 requests and 13,000 GB-s a
  day; a WebSocket's incoming messages count 20 to a request, outgoing messages and protocol pings nothing; past a
  limit, operations fail until 00:00 UTC (no charge on the free plan). A room with steady traffic never hibernates,
  so it is billed its wall time at 128 MB: 450 GB-s an hour, **≈ 28 room-hours a day**. Incoming messages with
  8 players all on the relay: each player sends one relay message every 0.2 s carrying its packets of that time
  (positions under K; inputs, hashes and acks under P, acks waiting for that send, §2.3; the host's commit), so
  8 × 5 = 40 a second (a snapshot adds its pieces), and while someone
  talks 25 a second from the talker (a `voice` packet is sent once with `to` = 0 and fanned out by the relay); a host
  forwarding for players on UDP adds at most its own 5 a second and the forwarded voice. About 40 messages a second
  idle and 65 while someone talks: ≈ 7,000–12,000 requests an hour, **≈ 8–14 hours of 8-player relay play a day**; a session of 2 costs about
  a fifth. Players on the LAN or on direct UDP cost nothing beyond their hello. MP4 measures the real counts in
  Cloudflare's analytics and writes them here.
- **Deploying:** only on an account on the **Workers Free plan** (a paid account would be billed past the free
  allowance). The deploy step checks the account's plan through the Cloudflare API first and stops if it is not the
  free plan.
- **As built** (MP4's server side, 2026-10-26; details and deploy steps in `relay-plant/README.md`):
  - every 2-byte number in the binary framing is big-endian, and a message that doesn't frame is dropped;
  - besides the errors above, a hello can get `bad hello` (not the hello above) or `no hello` (none within 10 s);
    a room that is closed tells its sockets `idle` or `expired`, and a member closed for silence gets `quiet`;
  - at most 12 sockets may wait for their hello at once, and 60 hellos a minute may succeed in a room;
  - the host's burst is 400 messages, a player's 200; the byte rate has a burst of 1 MiB;
  - `relay-plant/deploy.py` reads the account's subscriptions with an API token that has Billing Read (wrangler's own
    login can't), deploys nothing if it can't, and writes the address only to a file outside the repository.

### 9.2 Direct UDP

As Walkdown's direct path (PROTOCOL-v2 §18, `kksl/udp.nim`), between each player and the host only:
- each side's UDP socket (`PacketPeerUDP`) asks STUN (RFC 5389 binding request, written in GDScript; the servers
  Walkdown uses: `stun.cloudflare.com:3478`, `stun.l.google.com:19302`) for its public address;
- the two exchange candidates (the public address, their own IPv4 addresses and their global IPv6 addresses, at most
  8; the socket bound dual-stack, as Walkdown's listeners are) as a reliable message through the relay, under P.
  Many mobile carriers give phones a global IPv6 address with no NAT, where punching through the phone's stateful
  firewall usually works;
- both send `punch` packets (key 2: a counter and the address it is sent to, with an HMAC under the punch key
  (§1.3), so a stranger's packets are dropped and a captured punch can't be replayed from another address) to every
  candidate every 100 ms for 3 s; the first answered address becomes that player's path, and the relay stays as the
  fallback;
- a path silent for 3 s (no packet; a keep-alive every 1 s) falls back to the relay; the punch is tried again after
  60 s. A carrier NAT that maps per destination can't be punched (the lesson in CLAUDE.md), so phones on mobile data
  without IPv6 will often stay on the relay.

### 9.3 The LAN

**As built (MP2):** §14 says where the build differs from what follows.

- **Query and answer**, not beacons: the host (and every player, so that a new host after §5.3 answers at once)
  listens on the **discovery port** 47820; its session traffic uses another port, any free one. A joiner sends,
  from an ephemeral port, a query every 250 ms for 2 s to 255.255.255.255 and each IPv4 interface's broadcast address
  on the discovery port: `"WDPQ"`, version, the first 8 bytes of `room`, 8 random bytes. A host whose room matches
  answers to the query's address: `"WDPA"`, version, the joiner's random bytes, the session port, the epoch, and 16
  bytes of HMAC under the LAN key (§1.3) over them, so only the code's holder can make a valid answer and a stranger learns only that someone
  answered. Only one process per machine can hold the discovery port: a second host on one machine (the harness, two
  windows) is found by typing its address, shown on its screen; the harness gives each instance its own ports on
  the command line. The discovery query and answer use their own IPv4 socket bound to 0.0.0.0 (a dual-stack socket
  may not send IPv4 broadcasts on every platform), checked in the VM in MP2.
- Android filters broadcasts unless the app holds a `WifiManager.MulticastLock` (the `CHANGE_WIFI_MULTICAST_STATE`
  permission), taken while the app hosts or plays a session, through Godot's `JavaClassWrapper` and the
  AndroidRuntime plugin (as 0056 reads the Intent) [D JavaClassWrapper; to verify in MP2]. If no host answers (client
  isolation on the Wi-Fi), the joiner can type the host's address shown on its screen.
- Windows asks the firewall question the first time a desktop app listens; MP2 checks what the MSIX's
  `privateNetworkClientServer` capability does there in the VM.

### 9.4 Who forwards what

The session is a star around the host. Each player sends everything on its one path: to the host (LAN or direct
UDP), or through the relay. The relay fans out a packet sent to 0; UDP paths reach only the host. So:
- a broadcast (`pos`, `voice`, under K) from a player on UDP goes to the host, which forwards it unchanged to every
  other player on UDP and, once, to the relay with `to` = 0 if any player is on the relay;
- a broadcast that the host receives through the relay is forwarded to every player on UDP;
- the host's own broadcasts (commits, `roster`, its `pos`) go to every UDP player and once to the relay;
- a receiver takes a broadcast whose `from` is not the packet's transport sender only when the transport sender is
  the host (its address or relay ID); packets keep their original `from`, number and tag, so the replay window is
  per original sender;
- the host bundles what it forwards into its own relay messages (several packets per message, §9.1), at most 5 a
  second plus forwarded voice, within its 120 a second.

## 10. Security and privacy

**The relay and the network** see packet sizes, times and which relay IDs talk; never inputs, names, voice or the
code. A stranger without the code can't enter a relay room (no admit), can't make a valid LAN answer, and can't make
a packet any player accepts.

**A malicious player** (holding K and their own P):
| They can | The effect | What limits it |
|---|---|---|
| Make wild inputs as themselves | the engine refuses what the rules refuse, the same on every player; what it allows is "playing badly" | the host removes them (§2.4); the debrief shows who did what |
| Make inputs as another player | no: inputs are taken only under the sender's P, which travelled encrypted to that player's RSA key, and the commit names the slot; only by standing in for the host at that player's join (spoofing it on a LAN or claiming the relay's host routing, §1.3) | the real host's roster shows the joiner missing; the host removes them |
| Forge a LAN answer or `newhost` | an answer needs K (a player has it): a joiner could be led to them instead of the host; a `newhost` is accepted only from the expected candidate after the host is found gone (§5.3) | through the relay, sender tags; on a LAN, the joiner's hello then fails (no session state), and digests catch the rest |
| Flood inputs or voice | | the host takes at most 20 inputs per player per turn and 1 KiB of them, and at most one `talk` request a second; beyond that it drops and warns; the relay's per-socket limits |
| Send wrong hashes | they are resynced; they can't make the host resync others | only the host's digest counts |
| Forge a host broadcast (commit) on a LAN by spoofing the host's address | the others desync, are detected within N steps and resynced under their P | the relay path is not open to it (sender tags) |
| As host: send a crafted snapshot | the joiner decodes it with `bytes_to_var` (no objects) and the save's strict checks | the host is trusted by every player of its session; snapshots are accepted only from the host under P |
| Keep the old code after removal | nothing: the session has moved to new keys, sent to each remaining player under their P, and every player gets a new P (§2.4) | |
| Hear voice | only the session's players hear it, and only on their role's channels | |

**Parsing:** every field is read with bounds (lengths, counts, the 512-byte input, the 16 MiB snapshot); inputs with
the strict JSON reader; nothing from the network is ever loaded as a resource or run. 0054 and PLANT3D.md §13 keep
outside content out because of the engine's security response (0041); session packets are data in our own formats,
read by our own code, and snapshots come only from the session's host.

**Privacy:** display names are what the player types; no account, no device identity, nothing kept after the session
but the saves of §7.4 and desync reports (§4), all on the device. Online sessions also ask Cloudflare's and Google's
STUN servers (§9.2) for the device's public address, which tells them that address and the time. The microphone's input runs only from a
push-to-talk press to 10 s after the last release, in a session (§8.4), and is sent only while it is held.

## 11. Performance budgets on the Note 9

The frame rules don't change (MILESTONES.md: ≥ 95 % of frames at ≥ 30 fps in the 10-minute walk, none over 100 ms
that the app causes, peak PSS ≤ 1.5 GB, first walkable frame ≤ 15 s). Multiplayer gets this share of the main thread:

| | Budget | Notes |
|---|---|---|
| Session layer per frame (receive, decrypt, parse, send) | ≤ 0.5 ms mean, ≤ 2 ms max | about 40 packets a second in with 7 others at 1× (35 positions, 5 commits), about 30 more per talker; `AESContext` and `HMACContext` are native |
| Model steps | as alone (≤ 2.1 ms a step, §18.4) | lockstep runs the same steps a single player would; catching up is capped by `cpu_share` like fast-forward |
| State digest | ≤ 1 ms each, at most about 2 a second | §4 |
| Snapshot (host) | ≤ 1 ms on the main thread; encoding on a worker thread | §5.1 |
| Snapshot load (joiner) | off the frame except the final swap (≤ 5 ms), under a "Joining…" screen | |
| Other players drawn | within §18.4's skinned budget (12) | §6.3 |
| Voice encode | ≤ 1 ms per 20 ms frame on a worker thread (WorkerThreadPool), never the main thread | measured in MP5: 0.20 ms on the Note 9 (median, 48 kHz in; p95 0.22); libopus at complexity 5, 16 kHz mono |
| Voice decode | ≤ 0.3 ms per 20 ms frame per talker, on the same worker | one talker per channel, at most 3 channels; measured in MP5: 0.13 ms on the Note 9 (median, to 44.1 kHz; p95 0.14) |
| Memory | ≤ 30 MB PSS for the session, buffers and voice | |
| Network | idle, per player: up ≈ 4 kbit/s (positions, acks), down ≈ 25 kbit/s with 7 others (35 positions and 5 commits a second at about 70–90 bytes each); ≈ 30 kbit/s per talker to each listener; a host forwarding for players on UDP sends each forwarded packet to each of them (voice to 6 players ≈ 180 kbit/s up) | plus UDP/IP or WebSocket framing |

MP2, MP5 and MP6 measure these on the Note 9 with the walk among other players (§13); a milestone that misses a
budget isn't done.

## 12. Tests

- **The engine (MP1):** the multi-trainee vectors (§3.3) on the reference and GDScript; the digest's equality across
  Linux, Android (the Note 9) and Windows (the VM) for every vector run every 50 steps. As built: the staff runs, the
  day and its forks carry their digests (`digests`), which `run_vectors.gd` checks on every platform it runs on; every
  other run's digests are in its `--digests` output (`state`), which `tests/test_plant3d_sim.py` compares with the
  reference's, and a run on another platform with Linux's. Checked on Linux and Windows; **not yet on Android**: the
  Note 9 ran the digest's timing only (`digest=bench`), so `run_vectors.gd --digests` on the Note 9, compared with
  Linux's, is the first thing MP2 does before two devices compare digests in a session.
- **Settled in MP2 (§14):** inputs from the network are checked in the session layer, so the engines never see a
  malformed one; any slot may play nobody; the trainer's inputs come from the host and the instructor seats. As
  planned:
- **Before MP2 takes inputs from other devices:** a committed input whose kind is not a text, or whose length is not
  its kind's, must do nothing in both engines (the GDScript stops with a script error on a kind that is not a text,
  halfway through a step; MP1's inputs come from the app alone, which makes none such), and a slot that plays nobody
  has free mode's powers (PLANT3D.md §17.13): MP2 settles which slots may play nobody (the instructor's seat only, or
  any) and what the host does with the others' inputs.
- **The crypto:** RFC 5869's HKDF test cases and RFC 7518 Appendix B.1's AEAD vector through our GDScript code; the
  code's check character; replay windows.
- **The multi-instance harness** (`apps/plant3d/net/tests/`): N headless Godot processes (`--headless`, the engine and
  the session layer without rendering; the synthetic plant for most tests, the first train for one) driven by a
  Python runner that scripts each player's inputs and reads each one's digests, each instance on its own ports. How
  many fit is measured in MP2 (each instance's PSS with the synthetic plant and with the first train), and the
  runs are made under a memory-capped scope (`MemoryMax`, never `MemoryHigh`); CI runs them in the `plant3d` job.
  - 2, 3 and 8 players for 10 model minutes with inputs from all: every digest equal at every 50th step, and every
    player's event log equal to a single engine fed the same commits;
  - late join at minute 5 and rejoin after a kill (a new incarnation: its `pos` and inputs work afterwards); two
    joins at once; claims of one person by two players (one refused everywhere), in the lobby and later;
  - host killed mid-turn (some players have its last commit, some don't): a new host within 10 s, no step lost or run
    twice, uncommitted inputs resent and committed once; the host and then the first candidate killed; a candidate
    cut off for 6 s (no quorum: it takes nothing over); the host back after a 6 s gap (it steps down on the higher
    epoch); a `last` that comes after `newhost`; a host gone to the background (`away`: paused, no host change);
  - a desync injected (one instance's value changed): found within 50 steps, resynced, the report written;
  - fast-forward with mixed `ff_cap`s; pause by a non-host; the jump vote; removal and rekey (the removed instance's
    packets are dropped afterwards);
  - limits: input floods, oversized and malformed packets, packets with another session's keys, replays.
- **Network simulation:** a Python UDP and WebSocket proxy between the instances (`apps/plant3d/net/tests/netsim.py`)
  with latency, jitter, loss, duplication, reordering and outages per link, deterministic from a seed; the runs above
  at 150 ms ± 50 ms with 5 % loss and at 400 ms with 15 % loss must still agree, and the harness reports the
  input-to-effect delay.
- **The relay:** `relay-plant/twin.py`, the Python twin of the Worker (as `relay/twin.py` is of Walkdown's), used by
  the harness; the same protocol tests (`tests/test_plant_relay.py`) run against the real Worker in workerd
  (`npx wrangler dev`) on the laptop before each deploy, and in CI's `plant-relay` job. Tests of the limits, admit, create races, the 13th socket, host claims, the empty-room
  deletion, relay IDs past 255.
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
| MP1 | **Lockstep-ready engine:** several trainees (§3.3) in the reference, the GDScript and the vectors; `release` and reclaim; the state digest (§4); the vectors on Windows (the factors stored if `exp` differs); one input path in the app (every UI input through `ui/inputs.gd`, which a single-player run feeds straight to the engine) | M | S3 | single-player unchanged; vectors for 1–3 players | digest cost on the Note 9 ≤ 1 ms; digests equal on three platforms |
| MP2 | **LAN sessions:** the code and link (`join` in PLANT3D.md §6 and `sim/links.gd`; the Note 9's camera app tried), keys and AEAD (§1.3) with their vectors, packets, streams, fragments and reliability (§2), the LAN query and join, forwarding (§9.4), the RSA key per process (its time on the Note 9), the lobby and role claims, commits and the jitter buffer, Android's lifecycle (§7.5), hashes and resync, late join and rejoin, pause and the ready-for-fast vote, instructor seat, other players' avatars and `pos`, host and player saves; the harness and netsim; Android `INTERNET` and the multicast lock; the Flatpak's and MSIX's network permissions | L | MP1 | 2–8 players on one Wi-Fi | harness: 8 instances agree; the Note 9 + laptop + Windows VM in one session; input-to-effect ≤ 0.5 s median on the Wi-Fi; the Note 9 walk with 2 players within the frame rules; session layer ≤ 0.5 ms a frame |
| MP3 | **Host migration and removal:** §5.3's election with its quorum, `last`/`newhost`/`key`, next candidates, stepping down on a higher epoch, inputs resent, removal and rekey; the host-kill, partition and removal harness runs | M | MP2 | a session that survives its host | harness: new host within 10 s at 150 ms and at 400 ms with loss, no step lost or run twice, no two hosts |
| MP4 | **Online:** `relay-plant/` (Worker, twin, tests, pinned wrangler, its README), deployed after the twin and workerd tests pass, on a free-plan account (§9.1); the relay path in the app; direct UDP (STUN, candidates, punch, fallback) | L | MP2 | play from anywhere | the Note 9 on mobile data + laptop: RTT, input-to-effect ≤ 0.5 s median and ≤ 1 s p95; requests per session-hour from Cloudflare's analytics and where the room's Durable Object landed, written into §9.1 |
| MP5 | **Voice:** decision 0069's `wdp_voice` built from pinned sources for the four packages' targets (its licence notices in About), capture with `get_input_frames`, push-to-talk, channels and floor, jitter buffer, radio bus; `RECORD_AUDIO` and the desktop permissions | L | MP2 | push-to-talk on the radio | encode ≤ 1 ms / decode ≤ 0.3 ms per frame on the Note 9; mouth-to-ear ≤ 400 ms on the Wi-Fi; the frame rules with one talker; the APK still ≤ 150 MB |
| MP6 | **A full session measured:** 8 players (the Note 9, the laptop, the VM and harness bots) through a shift with fast-forward and a jump, voice on; the Note 9's 10-minute walk among 7 players | M | MP3, MP4, MP5 | the whole feature, measured | the frame rules on the Note 9 with 7 others drawn and one talker; no desync in 60 minutes |

**MP2 built 2026-10-27** (§14): everything in its row but MP3's host changes; its measurements are in §14.

**Order:** MP1 → MP2, then MP3, MP4 and MP5 in any order (each needs only MP2), then MP6.

**When to stop and ask the user:** the Cloudflare account isn't on the free plan (§9.1); the APK would pass 150 MB
with `wdp_voice` (it adds about 1 MB); a platform can't build `wdp_voice` (voice dropped there?); the measured
input-to-effect on mobile data misses 1 s at the 95th percentile (a turn of 1 step, or a regional relay, is then a
choice); Windows' `exp` differs and the stored factors change the vectors.

## 14. MP2 as built (2026-10-27): LAN sessions

The session layer is `apps/plant3d/net/` (its files' headers say what each does): `crypto.gd` (HKDF, the AEAD, big-endian
numbers), `code.gd` (the code and its keys), `wire.gd` (packets, messages, the replay window), `stream.gd` (reliable
streams and fragments), `input_check.gd`, `snapshot.gd`, `udp.gd`, `qr.gd`, `session.gd` (everything else),
`others_view.gd`, `android_net.gd`; the app's side is `ui/session_panel.gd` ("Together" on the bar) and
`ui/plant_ui.gd`. Where this differs from §1–§12, this section says how it was built and why.

**The code and its keys (§1.1, §1.3).** S is the 15 characters' 5-bit values one after another, most significant bit
first, padded with 5 zero bits to 10 bytes. The LAN key is HKDF(K, info `"lan"`) with the session's salt. RFC 5869's
three SHA-256 cases, RFC 7518 B.1 and an independent Python computation of a code's keys are
`tests/test_net_crypto.gd`. The `join` link is in `sim/links.gd`, `ref/plant3d.py` (`join_code`) and the vectors'
`links`; a code with a wrong check character opens the app at its start.

**The QR code (§1.1).** `net/qr.gd`: byte mode, level M, versions 1–10, the mask with the lowest penalty (the link is
version 3). Its matrices equal those of the Python package qrcode 8.2 for the same text, version and mask
(`tests/test_net_qr.gd`, four cases with one to four blocks and version bits); zxing-cpp 2.3 reads the invite's code.
(segno 1.6.6 adds a zero codeword when byte mode's bit stream already ends on a codeword boundary, which ISO/IEC 18004
7.4.10 doesn't ask for: its matrices differ in the data, so it is not the reference.) On the Note 9 a `walkdown-plant://join/<code>` Intent (what a camera app sends when its link is tapped), with the code
in lower case and dashes, started a join with the code read right; after "no session answered", the code stays in
Together to try again with an address. Whether the Note 9's camera app and Google Lens offer to open the scheme from
the QR code needs a person to point the phone: not tried yet.

**Joining (§1.2, §9.3).** The LAN query goes to 255.255.255.255 and, for each IPv4 address of the device, its /24's
broadcast address: Godot gives no netmask, a Wi-Fi's /24 is the common case, and a typed address covers the rest (the
host's IP, or IP:port when its discovery port is not 47820: the harness, or a second host on one machine). A second
host on a machine whose discovery port is taken says so and is joined by its address. The RSA key is made on a worker
thread when the join starts (307 ms on the Note 9 from a cool start, 967 ms when it was hot).

**Messages (§2.1–§2.3).**
- A reliable message carries a stream byte after its kind and length (0: the player's stream with the host, or the
  host's broadcast stream; 1: the snapshot's), so the two streams under P are told apart.
- `hello`, `welcome` and `refuse` ride no stream: a joiner has no slot and so no stream before its `welcome`. The
  joiner sends `hello` every 0.5 s until it is answered, and the host answers each `hello` of an incarnation it knows
  with the same `welcome` (the same slot, the same P).
- `ack` carries the acknowledged stream's key byte and stream byte; a player sends all its acks (the broadcast
  stream's included) to the host under its P, and acks ride in packets with reliable messages.
- The fields: `input`, `commit`, `hash`, `pos`, `ack`, `ping` and the snapshot's header are binary (big-endian);
  `hello`, `welcome`, `refuse`, `roster` and `control` are strict JSON. `pos` is §6.3's 24 bytes, its gait byte the
  walker's speed in tenths of a metre a second (what the avatars' clips follow).
- The broadcast stream has one numbering; the host keeps a sender per player (its window, timeouts and acks), and a
  joiner's starts at the `welcome`'s sequence.
- A reliable message is sent in the frame it was made (inputs and commits); acknowledgements and timeouts at least
  every 50 ms.
- Both ends ping every second (the round trip; the player's step for the host; a paused host's sign of life).
- The host forwards at most 40 broadcasts a second from each player (a burst of 80), and drops the rest (§10).

**Lockstep (§3.1).**
- **At 1× the host commits each turn ahead:** when its engine reaches the last commit it commits the next 2 steps with
  the inputs received since, then runs them at the clock's pace. The inputs of a turn are known at its start, and a
  turn at 1× is never cut short (a pause takes effect after the turn committed). Committing after running, as planned,
  added a whole turn to every input's delay. **In fast-forward** the host runs a turn's steps, then commits them, as
  §3.1 says: the engine may stop offering fast-forward within a turn.
- A turn is 2 steps at 1× and the rate × 2 in fast-forward, so commits go out about 5 times a second at any rate. (The
  harness runs the model faster than real time, Engine.time_scale; a turn is that many times longer there.)
- **The jitter buffer:** a player plays at the session's rate, `buffer` turns behind the last commit. When it runs dry
  it waits until that much is committed again, and the buffer grows by a turn (at most 5). More than a turn behind it,
  it catches up faster (never dropping a committed step). After 30 s without running dry the buffer shrinks.
- **Inputs from the network (§12):** checked in the session layer, not the engines (`net/input_check.gd`). An input is
  strict JSON of at most 512 bytes, with a kind the app makes, that kind's length and the types `ui/inputs.gd` makes.
  The host drops anything else before a commit, and every player skips an input in a commit that fails the check, so
  the engines never see a kind that is not a text. **Which slots may play nobody:** any (free mode, §6.1). The
  trainer's inputs (a fault, a repair without a permit, a lock removed by authority naming no person) are taken from
  the host's slot and the instructor seats only; `release` and `jump` from the host alone (the jump is voted). The
  engine's own rules (§17.13) decide the rest.

**Digests and resync (§4):** as planned, the host's digest of each step a multiple of 50 × the stride kept for 3
minutes; a player whose digest differs is sent a snapshot, and its desync report (both digests, its state and the
snapshot, `var_to_bytes` compressed with zstd) is written to `user://desync/` on a worker thread. Twice within 10
minutes, and it watches. Most players agreeing against the host ends the session ("the host's device differs").

**The snapshot (§5.1).** The joiner decodes, checks and builds the engine on a worker thread; the main thread only
installs it (on the Note 9 a late join's whole load took 197–251 ms off the frame; the swap 0.1 ms). The host copies the state on its main thread (0.5 ms on the laptop for the
day shift at minute 6) and encodes it on a worker. The host's snapshot is at a commit's end (its engine runs the
steps already committed first).

**Rejoin (§5.2):** the token is kept in memory and in `user://mp-session.json`; a player that comes back gets its
slot, its inputs' numbering from the last one committed, and its person when it is still free.

**Saved sessions (§7.4).** The host writes `user://mp-host.save` every 5 s while the run changes, on a worker thread.
In MP2 it holds the snapshot's parts (`net/snapshot.gd`: the container of `run_save.gd` with the magic
`"WDPMSAV\n"`); the host's own place and procedure are not in it yet. "Continue the saved session" hosts it with a
new code. In its lobby a player joining under a name of the save is offered that person again. At its start every
old player's person is released, then the claims are committed. A player writes `user://mp-last.save` when its session ends,
and "Continue alone" goes on from it as a single-player run (the others' people released).

**Android (§7.5, §9.3).** The screen is kept on while a session is open. Going to the background sends `away` (a host
pauses the session; a player keeps its person for 120 s). The multicast lock is taken through the AndroidRuntime
plugin while a session is open (`net/android_net.gd`). On the Note 9 (Android 10) the lock is taken and the broadcast LAN query found the laptop's session on the Wi-Fi, with no address typed. The packages: Android `INTERNET` and
`CHANGE_WIFI_MULTICAST_STATE`, Flatpak `--share=network`, MSIX `internetClient` and `privateNetworkClientServer`
(tests/test_plant3d_links.py). No socket is opened outside a session (`tests/test_net_no_network.gd`: the session
layer's count and the process's sockets in /proc). In the Windows 11 VM (on a Private network), installing the MSIX adds an inbound Allow rule for the package (Domain and Private profiles, from `privateNetworkClientServer`); the app, bound on every interface, joined the laptop's session, and no firewall prompt was on the screen at 25 s or 45 s (screenshots). On a Public network that rule doesn't apply: the session's traffic is then only the answers to the app's own packets, which the firewall lets through (not tried).

**Other players (§6.3):** drawn by `net/others_view.gd` at their `pos`, 200 ms behind and interpolated, with their
names within 15 m. Their avatars are their people's roles' looks, added to the people on screen as someone the trainee
works with (skinned first). A player's person standing at their place is also drawn there by the staff's view, which
shows every person but the trainee's own: this view then draws only the name, until they walk away from it. MP6
measures the crowd with 7 others.

**From the two reviews (blind and adversarial; tests/test_net_attacks.gd and harness runs for each):**
- **The rejoin token** travels with P inside the RSA encryption (`welcome`'s `p` is P ‖ token) and is new at every
  welcome. A hello again for an incarnation the host knows is answered only for the RSA key it first came with, since
  every packet's header shows its incarnation. A token whose player is still heard takes nothing over. Without this,
  a player holding the code could fetch another's welcome, read the token and take their slot, or a replayed old hello
  could move a slot.
- **Replay windows** are kept only for known senders (a player's slot and incarnation, the host's address) and are
  dropped with an incarnation, at most 256. A player's K packets are taken only from the address its P packets come
  from, and hashes only for steps the host digested.
- **A step's digests are judged together:** once every player has reported, or 3 s after the host's digest.
  Judged one by one, "most players against the host" never fired.
- **The host's silence** is noticed in the lobby and while a snapshot loads too. When the host is in the background,
  its players wait up to 120 s. The last packets before the background (away, the pause, a bye) go three times, as
  nothing is sent again while Android has the app stopped.
- **Slots** of hellos never followed by their player's packets (15 s) are given again. A player that leaves keeps its
  token and comes back to its slot. An input the host won't take is told to its player, and a snapshot says which
  inputs it holds, so no input is left "sending…".
- **A procedure's "pause when a step is done"** stops the frame's steps first; in fast-forward a turn had been left
  open.
- **After a session** the app goes back to the player's own run (saved before the session, or the scenario afresh,
  saved from then on). "Continue alone" moves the player's person to slot 0, the single-player run's.

**Not in MP2:** host migration and removal (MP3; a player whose host is silent for 10 s ends its session), the relay
and direct UDP (MP4), voice (MP5).

**The harness (§12).** `apps/plant3d/net/tests/`:
- `instance.gd`: a headless player driven by a plan of actions;
- `replay.gd`: one engine fed the host's commits;
- `netsim.py`: a UDP proxy per link, with latency, jitter, loss, duplication and outages, from a seed;
- `harness.py` and `test_harness.py`: the runs, in CI's `multiplayer` job;
- `vm_session.py`: the Windows VM's check.

The runs, each player's digests at every 50th step and events checked against every other player's and against the
replay:
- 2, 3 and 8 players for 10 model minutes (at 20× real time) with inputs from all;
- a late join at minute 5, and a rejoin after a kill;
- two joins at once, and one person claimed twice (in the lobby and later);
- the jump vote, a pause by a player, the host away;
- an injected desync, resynced within 150 steps;
- fast-forward at the slowest player's cap;
- an input flood, junk and replays at the host's ports, another session's code;
- 150 ms ± 50 ms with 5 % loss and 400 ms with 15 % loss through the network simulator.

Each instance of the first train is 98–174 MB of PSS (8 at once, measured by the instances), so CI's runner takes 8.
Input to effect through the simulator (two players, median and 95th percentile): 0.64 s and 0.75 s at 150 ms ± 50 ms
with 5 % loss; 1.48 s and 2.42 s at 400 ms with 15 % loss (MP4 measures mobile data on the Note 9).

**Measured on the devices (2026-10-27).** Test-signed release builds of this branch (the APK 142.8 MB), the Note 9
on the Wi-Fi (5 GHz), the laptop as the host (`instance.gd`, headless, bound to every interface), the frames walk
joined as it starts (`mp=`, an input every 3 s):
- **The engine's vectors on the Note 9** (`tools/plant3d/vectors_android.sh`): 245 passed. Every run's value digests
  and its 32,217 state digests equal Linux's. (This is §12's first step: two devices then compare digests in a
  session.)
- **The LAN query on the Note 9** found the laptop's session by broadcast with no address typed: the multicast lock
  works.
- **Laptop, Note 9 and the Windows 11 VM in one session**, with inputs committed from all three and no desync. The VM
  renders without a GPU, at 0.5 s a frame, and still keeps up.

The Note 9 against §11's budgets:

| | Budget | Measured |
|---|---|---|
| Session layer a frame | ≤ 0.5 ms mean, ≤ 2 ms max | 0.29 ms mean. Before P's decryption moved off the frame, the join's worst was 12.4 ms. Since: 2.57 ms, with 4 of 22,134 frames over 2 ms, none of them a join, a snapshot or a roster. **The maximum misses its budget**, cause not found yet |
| Input to effect on the Wi-Fi | ≤ 0.5 s median | 317 ms median, 521 ms p95, 637 ms at most (201 inputs); 334 ms median in the first, short walk |
| RSA key | (measured) | 307 ms from a cool start, 997 ms in a warm phone, on a worker thread |
| Snapshot load (late join) | off the frame but the swap ≤ 5 ms | 167–251 ms in all, the swap 0.1 ms |
| Network | idle ≈ 4 kbit/s up, the rest ≈ 25 kbit/s down with 7 others | with one other player and an input every 3 s: 6.3 kbit/s up, 7.6 kbit/s down |
| State digests | ≤ 1 ms, about 2 a second | no desync in any device session |

**The frame rules with two players** (cool start, 30.0 °C, `SAMPLE=1`, `probe=1`):
- 98.25 % of frames at ≥ 30 fps;
- first walkable frame 12.6 s.

One frame of 173 ms at 566 s counts as the app's. It was GPU time: 166 ms on the GPU, 4.3 ms of scripts, 822 draws, at
a place 330 m from the other player. The walk had reclaim in 5.95 % of its samples, so the rule says walk again. **Not yet walked again:** the phone, on its charger at 100 %, did not cool back to
30.0 °C within two hours. So MP2's frame-rule walk with two players is still to be judged.

Peak PSS was not read: `phone/frames.sh` read `dumpsys meminfo` by the package's name, which matches no process when
Walkdown is installed too. It now reads it by the pid. The session's ≤ 30 MB is therefore still to be measured.
