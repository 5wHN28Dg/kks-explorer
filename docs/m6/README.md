# M6: re-deriving KKS Explorer from scratch under the evidence-first policy

Started 2026-09-30. The policies: docs/evidence-first-platform-engineering.md, docs/evidence-first-web-engineering.md.
The architecture must come out of the investigation; nothing in the current code is assumed. The current code is
only compared at the end.

## Scope (user decisions, 2026-09-30)

- **Whole product:** desktop, Android, server / remote access, web UI, sync, drawing importer, internet relay.
- **Targets:**
  - Windows desktop (10/11);
  - Linux desktop, **GNOME/GTK** named as the Linux platform stack;
  - Android;
  - iOS through the browser (Safari), per https://github.com/5wHN28Dg/kks-explorer/wiki/iOS-research.
- **Protocol is open:** the data model and sync protocol may change if the decisions call for it. Existing plant data
  (signed logs on the server, laptops, phones) must then be migrated once, without loss.
- **No code changes** until the decisions are agreed. That includes the approved actions of the dependency audit
  (docs/decisions/README.md).

## Steps

1. [REQUIREMENTS.md](REQUIREMENTS.md): what the product must do, with no technology named. **Approved 2026-09-30.**
2. [CAPABILITIES.md](CAPABILITIES.md): each requirement × each target platform: what the platform provides (with
   sources), what is optional, what is missing. **Draft 2026-09-30.** It lists 10 gaps and 2 measurements still
   needed.
3. Decision records `docs/decisions/0014`–`0027`: one per gap or cross-cutting choice. **All decided 2026-09-30.**
4. [COMPARISON.md](COMPARISON.md): the result against today's code: what survives, what changes, what is
   rewritten, and the order of work. **Approved by the user 2026-09-30.** Then code. All decisions settled 2026-09-30.

## Progress

- Phase 1 (2026-09-30): docs/PROTOCOL-v2.md, the test-only reference in `ref/`, and the vectors in
  `ref/vectors/` (tests/test_protocol_v2.py, 16 tests). Still to do: the path store and course format
  specifications.
