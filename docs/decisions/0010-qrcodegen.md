# 0010 qrcodegen.js (drawing the invite QR)

Date 2026-09-30 · Scope: admin.html Devices → "Add a device with a QR code" · Status: keep

**Needed for:** turning the invite text into a QR matrix, drawn on a canvas.

**Platform:** no browser API encodes QR codes (`BarcodeDetector` only decodes). Android and desktop OSes have no
system QR encoder either.

**Dependency check:**

| Criterion | Evidence |
|---|---|
| Releases | 1.8.0 on 2022-04-17; last push 2026-08-31 |
| Maintainers | 1 (Nayuki) |
| Security policy | none |
| License | MIT |

Fails the more-than-one-maintainer criterion. But it is a small, complete implementation of a frozen standard
(ISO/IEC 18004), with no transitive dependencies, compiled once from TypeScript and vendored. It is effectively
finished code.

**Decision:** keep. Writing our own encoder would be more code to own for the same result.

**Revisit:** only if a browser QR encoder appears.

Sources: https://github.com/nayuki/QR-Code-generator · https://www.nayuki.io/page/qr-code-generator-library
