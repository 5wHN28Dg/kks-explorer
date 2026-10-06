# Dependency record: Emscripten 6.0.10 (emsdk)

Added: 2026-10-01 (decision 0037)   Pull request: https://github.com/5wHN28Dg/kks-explorer/pull/23 (record written for an existing dependency)   Recorded by: Claude for Hashim, 2026-10-05
Kind: build-time, with runtime parts (Emscripten's generated loader `.js` and the C/C++ runtime libraries it compiles
into the `.wasm` ship in `vendor/kks/`)
Packages covered: emsdk at tag 6.0.10 (pinned by full commit in `platform/web/build-wasm.sh`) and the SDK release it
installs: Emscripten, LLVM/clang, Binaryen, Node.js 24.19.0

## Purpose
Compiles libjxl and zxing-cpp to WebAssembly for the browser client (JPEG XL decoding where the browser can't, JPEG
XL encoding of photos, QR reading and writing), from the same pinned sources as the native apps (0037).

## Platform alternative checked
Browsers run WebAssembly but provide no compiler; the C/C++ → WebAssembly route is a toolchain on the developer's
machine. What the browser itself provides for the purpose is covered in [libjxl.md](libjxl.md) and
[zxing-cpp.md](zxing-cpp.md) (native JXL decoding in some engines, `BarcodeDetector` in some). Plain clang can target
`wasm32` but brings no libc, C++ runtime or JavaScript loader for browsers (0037).

## Custom implementation considered
Building with plain clang plus WASI libc and hand-written loader glue: we would own the memory-growth, module
instantiation and libc++ setup that Emscripten maintains. Or a JavaScript port of the codecs, which is the custom
codec 0018 already rejected.

## Transitive dependencies
Count: 4 toolchain components and 5 runtime libraries   How counted: what `emsdk install 6.0.10` puts in
`~/.local/kksdev/emsdk` (Emscripten, LLVM/clang, Binaryen, Node.js), and what the link step compiles into each
`.wasm` from Emscripten's `system/lib` (musl libc, libc++, libc++abi, compiler-rt, dlmalloc). The emsdk repository is
pinned by full commit; emsdk then downloads the SDK release that tag names.

## License
Emscripten: MIT OR NCSA (University of Illinois); musl: MIT; libc++, libc++abi, compiler-rt: Apache-2.0 WITH
LLVM-exception; dlmalloc: CC0 (public domain); Binaryen: Apache-2.0; Node.js (build-time only): MIT. Compatible with
AGPL-3.0.

## Maintenance signals
- Recent releases: 6.0.10 on 2026-09-21 (our pin); 6.0.11 since; 6.0.3 to 6.0.10 between July and September 2026
  ([releases](https://github.com/emscripten-core/emscripten/releases), [emsdk tags](https://github.com/emscripten-core/emsdk/tags)).
- Security response: [SECURITY.md](https://github.com/emscripten-core/emscripten/blob/main/SECURITY.md) routes reports
  to the Chromium security tracker; no GitHub advisories published.
- Active maintainers: 52 commit authors in the last 12 months; sbc100 (1,033 commits), juj, aheejin, kleisauke,
  brendandahl and others, part of Google's WebAssembly tooling team (GitHub contributor statistics, 2026-10-05).
- Age across major versions: repository since 2011; major versions 2.0.0 through 6.0.0
  ([tags](https://github.com/emscripten-core/emscripten/tags)), with `emcc`/`emcmake` stable across them (0037).

## Size impact
The generated loaders are 7–12 KB each (`vendor/kks/kks*.js`). The runtime libraries are inside the `.wasm` modules
(3.58 MB full, 0.74 MB decode-only; see [libjxl.md](libjxl.md)); their share was not separated. The build is
reproducible: a rebuild gives the same bytes (`vendor/kks/SHA256SUMS`).

## Replacement cost
Medium. One build script (`platform/web/build-wasm.sh`) and the loader interface used by `kks-wasm.js` and
`kks-wasm-worker.js` (`MODULARIZE`, `EXPORT_ES6`, `HEAPU8`). Another toolchain would need a new loader; the C API in
`platform/web/kks_wasm.cpp` would stay.

## Decision
Keep. It is the maintained C/C++ → browser toolchain, with a large team and a security route, and it lets the web
client use the same pinned libjxl and zxing-cpp as every other target instead of separately maintained ports (which is
what replaced the single-maintainer `@jsquash/jxl`, jsQR and qrcodegen). Revisit with 0037's triggers: every engine
decodes JPEG XL and has `BarcodeDetector`, or libjxl publishes its own WebAssembly build.
