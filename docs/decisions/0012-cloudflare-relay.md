# 0012 Internet relay on Cloudflare Workers

Date 2026-09-30 · Scope: internet sync (M5, `relay/`) · Status: keep

**Needed for:**
- presence and connection setup between devices that are not on the same Wi-Fi;
- a WebSocket pipe when UDP hole punching fails.

**Platform:** no OS or browser provides a rendezvous server. This is hosting, not a library.

Lock-in check:
- The relay speaks our own documented protocol (PROTOCOL.md §18).
- `peer/relay_server.py` is a working twin used in tests, so the host can change.
- The clients don't depend on Cloudflare APIs, only on WebSocket and UDP (the policy's "protocol ecosystem" shape).

**Decision:** keep. It is not deployed yet: that needs the user's Cloudflare account and IT approval, the same as
remote access.

**Revisit:** at deployment. Measure costs and limits on the free plan then.

Sources: `relay/README.md`, docs/PROTOCOL.md §18
