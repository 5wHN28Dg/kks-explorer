# Walkdown Plant relay

Walkdown Plant's multiplayer relay: online sessions whose players can't reach the host over a LAN or by direct UDP pass
their packets through it. Its spec is `docs/plant3d/MULTIPLAYER.md` §9.1 (decision 0068). It is a Cloudflare Worker
with one Durable Object per session room, separate from Walkdown's relay (`relay/`): its own code, Worker name and
deployment.

What it does:
- It opens a room when its host creates one, and admits only clients that hold the room's `admit` token.
- It passes their packets between at most 12 sockets (8 players, and rejoins overlapping during a host change).
- The packets are end-to-end encrypted under keys derived from the invite code. The relay never sees K, P, the code,
  inputs, names or voice. It stores one row per room: SHA-256(admit), the creation time, the relay IDs handed out, and
  when the room went empty.

`src/index.js` is the Worker. `twin.py` is its Python twin (the same protocol and limits), used by the tests and the
app's session harness.

## Protocol

- `GET /v1/room/<room>` (32 lowercase hex characters) upgrades to a WebSocket.
- The first message is text: `{"t":"hello","admit":<32 bytes, base64url without padding>,"create":true|false}`.
  - `create: true`: the room must not exist yet. The socket becomes relay ID 1 and the room's host.
  - `create: false`: the room must exist, and SHA-256(admit) must match. The socket gets the next relay ID: 16 bits,
    from 1, never reused within the room.
  - The answer is `{"t":"welcome","id","peers":[ids],"host":id|null}`, or `{"t":"error","why"}` followed by a close.
    `why` is one of:
    - `exists`, `no such session`, `bad admit`, `full`, `limit`;
    - `bad hello` (not the hello above);
    - `no hello` (none within 10 s).
- A client waits for its `welcome` before sending anything else: what arrives while its hello is being checked is
  dropped.
- Members hear `{"t":"joined","id"}`, `{"t":"left","id"}` and `{"t":"host","id"}`. A member's text `{"t":"host"}`
  makes it the host, for routing only (the relay can't check the claim).
- Binary messages, at most 64 KiB, are framed like this:
  - `to`: 2 bytes, big-endian: a relay ID, or 0 for every other member;
  - then one or more packets, each a 2-byte big-endian length (at least 1) and that many bytes.

  The relay checks the framing, replaces `to` with the sender's relay ID, and passes the message on unread. A
  message that doesn't frame, or that is addressed to its sender or to nobody, is dropped.
- The text `{"t":"ping"}` is answered `{"t":"pong"}` by the runtime without waking the room, so a paused room
  hibernates.
- When a room is closed, every socket gets `{"t":"error","why":"idle"}` or `{"t":"error","why":"expired"}`.

## Limits

Each limit follows MULTIPLAYER.md §9.1. The counters live in memory, never in storage, so a room evicted from memory
starts its counters again.

- **A socket's messages:** 60 a second with a burst of 200 (the host 120 and 400), and 256 KiB a second with a burst
  of 1 MiB. A message over a limit, or over 64 KiB, is dropped, and the sender gets `{"t":"slow"}` (at most once a
  second).
- **Closing a socket:** at three times a rate, counted over 10 s, the socket is closed with `limit` (a busy host is
  slowed, not cut off).
- **Text messages:** at most 512 bytes. A longer one is ignored.
- **Hellos:** 12 sockets may wait for their hello at once (a 13th gets HTTP 429). A socket has 10 s to say hello; a
  silent one is closed by the room's next connection or its alarm (no timer per socket, which would keep the room
  awake).
- **Failed hellos:** 30 a minute per room (bad admit, bad hello). After that, every hello to the room is refused with
  `limit` until the minute is over. `no such session` is not counted: players retry a new room after a removal (§2.4).
- **Joins:** at most 60 successful hellos a minute per room.
- **Room lifetime:** a room lives at most 24 h. It is closed and deleted after 10 minutes with no binary message (pings
  don't count), or 10 minutes empty.
- **Room creation:** at most 200 rooms a UTC day, counted by the `Daily` Durable Object. At most 10 a minute per
  client address (an IPv6 address by its /64), through the Workers rate limiting binding (`CREATE_LIMIT`, per Cloudflare location, approximate).
  The binding is only asked when a room is created. Cloudflare's page doesn't say whether the free plan has it. If a
  deploy says it doesn't, remove the `[[ratelimits]]` block: the Worker runs without it.

## Deploy

**Free plan only:** a paid account would be billed past the free allowance. `deploy.py` reads the account's
subscriptions through Cloudflare's API. It stops if any of them could be billed: a price other than 0, a Workers plan
other than the free one, or anything it doesn't understand. Workers Paid is an account subscription, so a Free
account has none of these. If the subscriptions can't be read, it deploys nothing.

You need:
- Node.js 22 or newer;
- a Cloudflare account on the Workers Free plan;
- an API token with only the permission **Account › Billing › Read**, for the plan check. wrangler's own login can't
  read subscriptions.

wrangler is pinned in `package.json` and `package-lock.json`, with every package's integrity hash. `npm ci` installs
exactly that version, and `npx` runs the installed copy.

```sh
cd relay-plant
npm ci --ignore-scripts     # the pinned wrangler, into relay-plant/node_modules
npx wrangler login          # opens the browser
PLANT_RELAY_BILLING_TOKEN=<the billing-read token> python3 deploy.py --url-file ~/private/plant-relay-url.txt
```

`deploy.py` does these steps:
1. It refuses a `wrangler.toml` that sets variables.
2. It checks the login and the plan.
3. It runs `wrangler deploy`.
4. It writes the `wss://` address to the `--url-file`, which must be outside the repository.
5. It smoke-tests the deployed relay: two clients join a room and exchange packets, and a wrong admit is refused.

It never prints the address. The address never goes into tracked files, the wiki or a pull request. It is kept in
`CLAUDE.local.md` and in the app's build configuration file, which git ignores. Builds without that file offer only
This Wi-Fi sessions.

To smoke-test again later: `python3 deploy.py --smoke --url-file ~/private/plant-relay-url.txt`.

To move wrangler:
1. Change its version in `package.json`.
2. Run `npm install --package-lock-only --ignore-scripts`.
3. Commit both files. The dependency check in CI scans the lockfile; `osv-scanner.toml` here explains its entries.

The `overrides` in `package.json` force versions of wrangler's own dependencies, as in `relay/`:
- `sharp`, for its licence (see `osv-scanner.toml`);
- `undici` 7.30.1: miniflare pins 7.29.1, which has three advisories. When you move wrangler, check with
  `npm ls undici` whether miniflare still needs the override, and drop it once miniflare asks for 7.30.1 or newer.

**Cost:** MULTIPLAYER.md §9.1 has the estimate, about 8–14 hours of 8-player relay play a day within the free plan.
Past the free limits, requests fail until 00:00 UTC; nothing is billed on the free plan. Anyone who extracts the
address from a build can use up the day's allowance (an accepted risk, §9.1). The limits above make that take effort.

## Test locally

```sh
.venv/bin/python -m unittest tests.test_plant_relay                     # against twin.py
cd relay-plant && npm ci --ignore-scripts && cd ..
KKS_PLANT_RELAY_WORKERD=1 .venv/bin/python -m unittest tests.test_plant_relay   # and the Worker in workerd
```

The tests start `wrangler dev` themselves, with shorter timings passed in `RELAY_LIMITS` (`--var`). Only the idle,
empty, maximum age and hello timings, the day's room count and the joins a minute can be changed that way. CI's
`plant-relay` job runs the workerd part.

For a twin of your own: `python3 relay-plant/twin.py 8787` (behind a TLS proxy for `wss://`).
