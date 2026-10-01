# 0031 The GNOME app: bindings, event loop, drawing, keys, camera

Date 2026-10-01 · Scope: phase 5 (R1–R20 on GNOME, N1a, N2, N6) · Status: **decided by Claude under the user's
standing instruction to continue** ("don't stop between phases unless something needs my input"); the user can
revisit.

**Question:**
- How the GNOME app (0014: GTK 4 + libadwaita, Nim per 0027) calls GTK.
- How the node's network I/O shares the GTK main thread.
- How the viewer draws (0016).
- Where the storage key lives (0020).
- How a QR code is scanned without a webcam API in GTK.

## Findings

[V] = checked on this machine 2026-10-01 (Ubuntu 26.04.1 LTS, GNOME Shell 50.1, Wayland). [D] = vendor
documentation.

| Need | What the platform provides | Gap / choice |
|---|---|---|
| Toolkit | GTK 4.22.4 and libadwaita 1.9.1 installed [V]. Headers not installed: `apt-get download` of the -dev packages into a local prefix; a test program compiled and ran [V]. | none |
| Nim bindings | **owlkettle** 3.1.0: 5 commits from 4 people in the year to 2026-10-01; one release since 2024-03; MIT [V, GitHub API]. **futhark** (0027's plan): 13 commits/year, 6 people, but it needs libclang at build time and would generate tens of thousands of lines for GTK. | **Hand-written `importc` bindings for the subset used, with the `header` pragma**, as 0029 did for GnuTLS: the C compiler checks every signature against the real headers. owlkettle fails the maintenance test (one active maintainer, rare releases). GTK's C API is the platform itself and stable within GTK 4. Revisit futhark if the surface grows past a few hundred functions. |
| Event loop | GTK owns the main thread (GLib main loop) [D]. The node's sync code uses Nim's asyncdispatch (`platform/linux/net.nim`). | One thread owns the node (0030): GLib watches asyncdispatch's epoll fd (`g_unix_fd_add`), plus a 100 ms timer for asyncdispatch's timers; both run `poll(0)`. No second thread touches the node. |
| Drawing (0016) | GtkSnapshot + GdkTexture are composited by GSK on the GPU [D]. Cairo image surfaces for CPU tiles [V, measured in 0016]. | A small GtkWidget subclass in C (`kks_view.c`, a snapshot vfunc calling Nim), so cached tiles go to the GPU as textures, as 0016 decided. Tiles are drawn with Cairo from the `.kkp` grid; overview levels come from the JXL pyramid. |
| JPEG XL (0018) | libjxl 0.11.1 installed [V] | the same C shim as the importer (`kks_jxl.c`) |
| Storage key (0020) | libsecret 0.21 → Secret Service (gnome-keyring) [V]; inside Flatpak through the Secret portal (`org.freedesktop.portal.Secret` present [V]) | libsecret: one 32-byte key per device, stored as a secret with the attributes `app=kks-explorer`, `kind=storage-key`. Limits (N1a): any program running as the user can ask the keyring while it is unlocked; the app says so. |
| Files (photos, bundles, join files) | GtkFileDialog, which goes through the FileChooser portal [D, portal present V] | none |
| QR scan (0019) | No camera API in GTK. Camera portal present [V]; PipeWire + GStreamer installed [V]; zxing-cpp 2.3 runtime installed, headers not [V]. | Phase 5 first ships "paste the code" and "open an image of the QR" (zxing on a still image). The webcam path (Camera portal → PipeWire → GStreamer appsink → zxing) is a later step with its own check on a real webcam. |
| QR show | none in GTK | the core's own encoder (decision 0010's qrcodegen algorithm, ported), drawn by Cairo |
| Accessibility (N2) | GTK 4 widgets implement GtkAccessible (AT-SPI) [D] | The viewer is custom-drawn, so every tag on the visible sheet is also listed in an accessible list (search results / "tags on this sheet"), reachable by keyboard. |
| Packaging (0022) | Flatpak + Flathub, GNOME runtime 50 [D] | manifest later in phase 5; development builds run from the tree |

## Choice

- **Code layout:** `apps/gnome/`:
  - `src/kksg/gtk.nim`: the bindings;
  - `kks_view.c`: the viewer widget;
  - Nim modules per screen.
  - Business logic stays in `core/` (the node and the local API routes), and `platform/linux/` (store, TLS, net,
    mDNS) is shared with the server.
- **Screens call the core's local API** (`api.nim`, the port of LocalApi) with the same routes and JSON as the web
  pages. One behaviour, tested once.

**When to revisit:**
- if the binding surface passes about 400 functions (then generate it);
- if GTK 5 changes the C API;
- once the webcam path is built and tested on a real camera.

## Found while building (2026-10-01)

- **Accessibility:** a dialog built during an accessibility action (AT-SPI or screen reader "click") had no contents
  in the accessibility tree (GTK 4.22.4, libadwaita 1.9.1).
  - Handlers and dialog presentation now run from an idle callback.
  - Verified through AT-SPI: the invite dialog's labels and buttons are present.
- **Closures in loops (Nim):** closures made in a `for` body share its variables, and loop variables are `lent`.
  Lists of rows are built with `closureScope` over indexed copies.
- **Application ID:** `io.github._5wHN28Dg.kks_explorer`. The GitHub user starts with a digit, which a D-Bus name
  segment can't, so the Flathub convention prefixes an underscore. A custom data folder gets its own ID.
- **A removed device wipes itself (§15), added 2026-10-01:**
  - The core's `Hooks.wipe(by)` empties the store and keeps a note naming who removed the device.
  - The app then re-executes itself: a new device key, and the setup screen shows the note.
  - In the e2e test: the manager removes the second device under Manage → Devices; at its next sync it wipes itself.
- **Open Manage pages follow the data** (Approvals, My proposals, History, Devices): they rebuild on a change while
  shown. Pushing a page whose tag is already in the navigation stack now pops back to it (Adwaita refuses duplicate tags).
- **A covered window draws nothing:** an alert dialog in it has no accessible children until it draws (it lays out
  lazily). That's a test artifact, since a person acting in a window has it in front. The e2e test closes the second
  app before using a dialog in the first.
