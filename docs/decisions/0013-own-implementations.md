# 0013 Things we implemented ourselves

Date 2026-09-30 · Status: keep; the reliable UDP is re-evaluated in M6

The policy asks the reverse question too: did we write something a platform or a well-maintained library already
provides?

| What | Where | Platform / library alternative | Why ours |
|---|---|---|---|
| Noise_XX handshake + transport | `peer/noise.py`, `Noise.kt` | No OS provides Noise. Libraries exist (e.g. `noiseprotocol` for Python) | Small (one pattern, one cipher suite). Checked against the published cacophony vector and our frozen vectors in two languages. Keeps the protocol identical in Python and Kotlin. |
| Reliable UDP (SACK, RFC 6298 RTO) | `peer/rudp.py`, `Rudp.kt` | QUIC: Python `aioquic`; Android Cronet (through Play services, optional) | Needed for hole-punched paths. QUIC would bring its own TLS layer on top of Noise and bigger dependencies. **Weakest case:** congestion and loss handling is subtle. Tests cover 2–20 % loss, but real NATs are unverified. |
| WebSocket client | `peer/ws.py`, `WsClient.kt` | Python stdlib: none (`websockets` library exists); Android: no framework WebSocket client (OkHttp is a library) | Client-only, one use (relay pipe), about 150 lines each. |
| JSON parser/encoder | `android/core` Json.kt | Android framework `org.json` | The signed log needs canonical encoding byte-identical to Python (key order, number forms, `bad_encoding` for numbers the protocol can't carry). `org.json` doesn't guarantee these and isn't in a plain JVM library. The frozen vectors check it. |
| Canonical encoding, replay, merge | `peer/`, `android/core` | none | This is the product's protocol. |

**Decision:** keep all. For M6, decide the reliable UDP question explicitly: our rudp vs a maintained QUIC library in
the chosen language, weighing QUIC's size against owning a transport.

Sources: docs/PROTOCOL.md §15, §18 · https://github.com/aiortc/aioquic · https://developer.android.com/reference/org/json/JSONObject
