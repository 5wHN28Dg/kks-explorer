# 0016 Viewer rendering: CPU-drawn cached tiles, composited by the platform

Date 2026-09-30 · Scope: R1, N3 · Status: **accepted by the user 2026-09-30** (from measurements)

**Question (the user):** does drawing the grid-indexed paths (0015) on the GPU beat the CPU, on the phone and on the
laptop?

**Setup:** same sheets and path data as 0015; off-screen frames; median of 5 after 2 warm-up frames.
- Laptop: i7-12700H with Iris Xe, GTK 4.22 (GSK OpenGL, Vulkan and Cairo renderers), `tools/m6/gsk_bench.py`.
- Phone: Galaxy Note 9, Android 10; `HardwareRenderer` + `RenderNode` vs a software Canvas on a Bitmap,
  `tools/m6/android-bench`.

The GPU times include finishing the frame and reading it back. On a screen there is no read-back, but the frame
still has to finish. On the laptop, "record" (building the node tree) runs in Python and would be faster in compiled
code. The phone records in the framework, so its numbers are real.

**512 px tile:**

| | 1× | 4× | 16× |
|---|---|---|---|
| Phone, CPU Canvas | 7.6–12 ms | 1.3–2.1 ms | 0.5–0.7 ms |
| Phone, GPU | 16–48 ms | 3.3–10 ms | 2.0–3.6 ms |
| Laptop, Cairo (CPU) | 7.8–12 ms | 0.6–1.3 ms | 0.1–0.2 ms |
| Laptop, GSK OpenGL / Vulkan | 10–13 ms | 5.6–7.5 ms | 2.9–7.4 ms |

**Screen-sized frame** (phone 1440², laptop 1536²; at 1× nearly the whole sheet is visible, 25k–112k paths):

| | 1× | 4× | 16× |
|---|---|---|---|
| Phone, CPU Canvas | 48–169 ms | 10–19 ms | 3.1–4.2 ms |
| Phone, GPU | 171–491 ms | 36–54 ms | 4.6–6.9 ms |
| Phone, PdfRenderer (for reference) | 412–929 ms | 22–64 ms | 3.2–5.4 ms |
| Laptop, Cairo | 68–209 ms | 9–16 ms | 1.3–2.7 ms |
| Laptop, GSK OpenGL | 73–121 ms | 21–44 ms | 25–29 ms |

GPU pictures match (phone GPU vs PdfRenderer at 4×: 0.06–0.13 % of pixels differ).

**Findings:**
- For this content (tens of thousands of thin, short strokes), **CPU rasterization is as fast as the GPU or faster**,
  except for the busiest full-sheet laptop frame (GSK 81 ms vs Cairo 209 ms on FW).
- The GPU pays a fixed cost per frame (about 2–7 ms for a tile, 20–30 ms for a screen) plus a cost per path.
- **Redrawing all vectors every frame is too slow at the overview on both devices** (50–490 ms against 16 ms for
  60 fps), GPU or CPU.
- Zoomed in, one screen costs 3–19 ms on the phone's CPU.

**Proposed pipeline:**
1. **Tiles, drawn on the CPU on background threads:**
   - Cairo image surfaces on GNOME, a software Canvas on a Bitmap on Android, and on Windows Direct2D/WIC
     (unmeasured, no Windows machine).
   - Several tiles render in parallel (the phone has 8 cores, the laptop 20 threads).
   - Tiles are cached by zoom level.
2. **The GPU only composites cached tile bitmaps while panning and zooming**, through each platform's normal image
   drawing: GTK textures, hardware-accelerated `drawBitmap`, Direct2D bitmaps. That is cheap and keeps 60 fps. Sharp
   tiles for the new zoom level replace the stretched ones when they are ready (today's app does the same with its
   canvas).
3. **Overview levels (below about 2×) are pre-rendered at import** as a small image pyramid in the plant data. The
   overview is the most expensive frame (up to 169 ms on the phone's CPU), and it is also the sheet thumbnail.
4. Vector tiles from about 2× up, drawn from the grid store (0015).

**Revisit:**
- if a platform's GPU path renderer changes a lot (e.g. GSK's path rendering matures);
- on Windows once it can be measured;
- if devices change: re-run `tools/m6` on the new ones.

Sources: tools/m6/gsk_bench.py, tools/m6/grid_bench.py (`TILE=` sets the frame size), tools/m6/android-bench
(`adb shell am start -n kks.bench/.Bench --ei tile 1440`); docs/decisions/0015-drawing-format.md
