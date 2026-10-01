# kks: libjxl and zxing-cpp in WebAssembly (our own build)

Built by `platform/web/build-wasm.sh` (decision 0037) with Emscripten 6.0.10 (pinned emsdk) from the same pinned,
SHA-256-checked sources as the native apps:
- libjxl v0.12.0 with highway, brotli and skcms at the commits it names (BSD-3-Clause, MIT; Apache-2.0 for highway);
- zxing-cpp v3.1.1 (Apache-2.0).

Files (`SHA256SUMS` lists them; the build is reproducible: a rebuild gives the same bytes):
- `kks-simd.{js,wasm}`, `kks.{js,wasm}`: everything (JPEG XL decode and encode, QR read and write); WebAssembly SIMD and
  scalar variants.
- `kks-simd-dec.{js,wasm}`, `kks-dec.{js,wasm}`: JPEG XL decoding only, for browsers that can't show it.

The `.js` files are Emscripten's generated loaders. The pages use them through `/kks-wasm.js`, which picks the variant
(SIMD where `WebAssembly.validate` accepts a v128 instruction). The C API is `platform/web/kks_wasm.cpp`.
