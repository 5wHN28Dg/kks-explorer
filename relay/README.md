# KKS Explorer internet relay (M5)

Lets the plant's devices sync when they are not on one network (a phone on mobile data, a laptop at HQ). Protocol:
`docs/PROTOCOL.md` §18 (v1 apps: Ed25519 hellos) and `docs/PROTOCOL-v2.md` §18 (v2 apps: P-256 hellos); one Worker
serves both. It is a Cloudflare Worker with one Durable Object per plant ("room").

What it does: devices announce themselves in the plant's room (each proves it holds its device key), swap addresses
so they can connect to each other directly (UDP hole punching), and if that fails, it passes their sync bytes between
them. Those bytes are encrypted end to end (the same sync as on the Wi-Fi: Noise in v1, TLS in v2), so the relay never sees plant data,
photos or passwords. It stores nothing except pipe bytes waiting up to 30 s for the other side.

What it can't do: check that a device belongs to the plant (it doesn't have the log). Someone who knows the plant's
root ID can see which device IDs are online. They still get nothing: the devices refuse a sync with any device that
isn't certified in the plant's log.

## Deploy (once, on your own Cloudflare account)

Needs Node.js 18+ and a free Cloudflare account.

```sh
cd relay
npx wrangler login          # opens the browser
npx wrangler deploy         # prints https://kks-relay.<your-subdomain>.workers.dev
```

Then, as the manager: Manage → Devices → Internet in the web pages (v2 apps: Manage → Account → Internet relay) →
relay address `wss://kks-relay.<your-subdomain>.workers.dev`
→ Save. The setting goes into the plant's log, and every device picks it up at its next sync. An empty address turns
internet sync off.

Cost: Durable Objects with SQLite storage are part of the Workers Free plan. Idle devices cost almost nothing, because
the WebSocket Hibernation API answers keep-alive pings without waking the object. Each sync that falls back to the
pipe counts its messages as requests. Check Cloudflare's current free-plan limits against the plant's device count
before relying on it.

Before going live, get the same written IT/security approval as for remote access (`https://github.com/5wHN28Dg/kks-explorer/wiki/Remote-access`). The
devices only make outgoing connections (HTTPS/WebSocket to Cloudflare, UDP to STUN servers and to each other), but it
is still plant equipment talking to the internet.

## Test locally

```sh
cd relay && npx wrangler dev --port 8787            # the real Worker code in workerd
KKS_RELAY_URL=ws://127.0.0.1:8787 .venv/bin/python -m unittest tests.test_internet   # v1 (from the repo root)
KKS_RELAY_URL=ws://127.0.0.1:8787 /tmp/kkslinux/test_internet                          # v2 (platform/linux tests)
```

Without `KKS_RELAY_URL`, the tests use `peer/relay_server.py`, the Python twin of this Worker (same protocol). You
can also self-host that one: `python3 -m peer.relay_server 8787`, behind a TLS proxy for `wss://`.
