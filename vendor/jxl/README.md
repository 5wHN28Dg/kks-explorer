# JPEG XL decoder for browsers without native JXL (vendored)

libjxl's decoder compiled to WebAssembly, from the npm package `@jsquash/jxl` 1.3.0 (Apache-2.0, see LICENSE;
https://github.com/jamsinclair/jSquash, built from Google's Squoosh codec). Only the decoder is copied:
`decode.js`, `utils.js`, `codec/dec/jxl_dec.{js,wasm}`, unchanged (`SHA256SUMS`). common.js loads it only when the
browser can't show JXL itself; the Android app decodes with its own libjxl instead.
