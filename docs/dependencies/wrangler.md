# Dependency record: wrangler (Cloudflare Workers CLI), unpinned

Added: 2026-09-28 (the internet relay, M5; decision 0012)   Pull request: https://github.com/5wHN28Dg/kks-explorer/pull/23 (record written for an existing dependency)   Recorded by: Claude for Hashim, 2026-10-05
Kind: dev-only (a deploy and local-test tool; nothing of it ships: the relay is `relay/src/index.js`, our code, with no
npm dependencies)
Packages covered: `wrangler` from npm, run as `npx wrangler login|deploy|dev` (`relay/README.md`). No version is
pinned and the repository has no `package.json`: `npx` fetches the latest release at each use (4.147.0 on 2026-10-02
when this record was written).

## Purpose
Deploys the relay Worker and its Durable Object to the maintainer's Cloudflare account, and runs the Worker locally in
`workerd` for the relay tests (`wrangler dev`, used against `platform/linux/tests/test_internet.nim`).

## Platform alternative checked
The relay's platform is Cloudflare Workers (platform-provided as the external service's documented API, see the
index). Cloudflare documents two ways to deploy: wrangler and the REST API
([Workers API](https://developers.cloudflare.com/api/resources/workers/)); a dashboard upload is a third, manual one.
For local runs the alternative is `relay/twin.py`, our own Python twin, which the tests already use by default.

## Custom implementation considered
A deploy script against the REST API (upload the script with its Durable Object binding and migration metadata, with
an API token): about 50 lines of our own, but we would track Cloudflare's upload format ourselves. The local test
runtime (`workerd`) can't reasonably be replaced; the twin covers the protocol, not Cloudflare's runtime.

## Transitive dependencies
Count: 39 packages on Linux x86_64   How counted: `npm install --ignore-scripts wrangler@4.147.0` in an empty folder
(2026-10-05) installed 40 packages including wrangler; the resulting `package-lock.json` lists 91 entries, the rest
being optional platform binaries for other systems (esbuild, workerd, sharp). The tree includes `workerd` (Cloudflare's
runtime, a native binary), `miniflare`, `esbuild`, and `sharp`'s libvips binaries. 239 MB installed.

## License
MIT OR Apache-2.0 (wrangler, `npm view wrangler license`). Its installed tree (each `package.json`, 2026-10-05) is MIT,
Apache-2.0, ISC, 0BSD and CC0-1.0, except `sharp`'s libvips binaries (`@img/sharp-libvips-*`), LGPL-3.0-or-later.
Nothing ships, so none of these licenses reach the product.

## Maintenance signals
- Recent releases: 25 releases in the 30 days before 2026-10-05 (`npm view wrangler time`; 4.147.0 on 2026-10-02, from the
  [workers-sdk](https://github.com/cloudflare/workers-sdk/releases) monorepo).
- Security response: [SECURITY.md](https://github.com/cloudflare/workers-sdk/blob/main/SECURITY.md) (Cloudflare's
  `security.txt` reporting route) and published advisories, e.g. CVE-2026-0933 (command injection in `wrangler pages deploy`, fixed
  in 4.59.1; we don't use Pages) and CVE-2023-7078/7079/7080 ([advisories](https://github.com/cloudflare/workers-sdk/security/advisories)).
- Active maintainers: 69 commit authors in the last 12 months, Cloudflare's Workers developer-platform team (GitHub
  contributor statistics, 2026-10-05).
- Age across major versions: since 2019 (the Rust wrangler 1.x), rewritten in JavaScript as 2.x (2022), now 4.x.

## Size impact
None in the product (dev-only). 239 MB in `node_modules` when installed.

## Replacement cost
Low. It touches only `relay/wrangler.toml` (the Worker's name, the Durable Object binding and its migration tag) and two
commands in `relay/README.md`. The relay code doesn't import anything from it.

## Decision
Keep as the deploy tool: it is Cloudflare's own CLI for its platform, maintained by a large team with a security
process, and deploys are rare (once, then on relay changes). The weak point is ours: it runs unpinned through `npx`,
so each deploy uses whatever version npm serves that day, with a 39-package tree that is neither locked nor scanned.
Action for the owner: add `relay/package.json` with wrangler as an exact dev dependency and commit its
`package-lock.json` (the policy's lockfile rule then applies and the CI scan reads it), and run `npx wrangler` from
that folder only.
