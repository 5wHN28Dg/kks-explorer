# 0057 Walkdown takes walkdown:// links from other apps

Date 2026-10-16 · Scope: Walkdown's Android, GNOME and Windows apps, the core (the link's reader), Walkdown Plant's
links out (`apps/plant3d/ui/links_in.gd`) · Status: **decided by the user** ("Add it", 2026-10-16) · Follows 0054 §3

**Question:** Walkdown Plant opens Walkdown at a piece of equipment or a course page (`walkdown://…`, PLANT3D.md §6).
How does each Walkdown app register the scheme and receive the link, and what may a link do?

## Findings

[D] platform documentation, [V] verified here.

| Target | Registering | Receiving, cold and while running |
|---|---|---|
| Android | An intent filter (`VIEW`, `BROWSABLE`, `DEFAULT`, `<data android:scheme>`) on an exported activity; the scheme is matched case-sensitively, so lowercase only [D: developer.android.com/guide/components/intents-filters, …/training/app-links/deep-linking] | A VIEW Intent from another app starts the activity **in the caller's task** unless it sets `FLAG_ACTIVITY_NEW_TASK` (Godot's `OS.shell_open` doesn't), a second MainActivity next to the first. `launchMode="singleTask"` on the launcher activity would avoid that, but it also clears the activities above it when the person comes back through the launcher icon: the camera taking a photo for Walkdown is one of them. `FLAG_ACTIVITY_NEW_TASK \| CLEAR_TOP \| SINGLE_TOP` from a small exported activity brings Walkdown's own task forward and calls the existing MainActivity's `onNewIntent` [D: developer.android.com/guide/components/activities/tasks-and-back-stack, Intent flag reference] |
| GNOME (and its Flatpak) | `MimeType=x-scheme-handler/walkdown;` and `Exec=walkdown %u` in the `.desktop` file; Flatpak exports the file with the app and its MimeType [D: specifications.freedesktop.org desktop-entry-spec "exec-variables"; docs.flatpak.org "Desktop integration"] | `G_APPLICATION_HANDLES_OPEN`: the URIs come to the "open" signal as GFiles of the primary instance (a second start passes them over D-Bus); a scheme GVfs doesn't know gives a GDummyFile, whose `get_uri` is the text as given [D: docs.gtk.org/gio/class.Application.html; GIO's gdummyfile.c] |
| Windows (MSIX) | `uap3:Extension Category="windows.protocol"` with `uap3:Protocol Name="walkdown" Parameters="…%1…"`: a full-trust desktop app is started with the URI on its command line, Windows 10 1607+ [D: learn.microsoft.com/uwp/schemas/appxpackage/uapmanifestschema/element-uap3-protocol] | Each activation starts a new process. The app is not single-instance (one store, one sync port): the new process hands the link to the running window with `WM_COPYDATA` and quits [D: learn.microsoft.com/windows/win32/dataxchg/wm-copydata]; a sender at a lower integrity level can't send it (UIPI) [D] |
| Web | Custom schemes in a browser need `registerProtocolHandler` with a `web+` prefix, not in Safari [D: MDN] | — (0054 §3: an https URL instead; not now) |

## Choice

- **Two link kinds**, as PLANT3D.md §6 writes them: `walkdown://kks/<code>` (code `[0-9A-Z]{4,24}`, as course links)
  opens the tag with that code on its drawing, as a course's code link does; `walkdown://course/<course>[/<page>]`
  (identifiers as in COURSES.md) opens that course, at that page. Nothing else: a link never signs in, joins,
  sends, deletes, imports or fetches anything; anything else (another path, a query, a fragment, percent signs,
  a malformed code, over 128 characters) is ignored, with nothing done. A device that hasn't joined does nothing.
- **One reader, in the core** (`core/src/kks/applink.nim`, unit tests with hostile input): the desktop apps call it
  directly, Android through the existing native call (`/native/link`), which also finds the tag.
- **Android:** the filter is on `kks.explorer.LinkActivity` (exported, no window), which hands the link to
  MainActivity with `NEW_TASK | CLEAR_TOP | SINGLE_TOP` and finishes: no second MainActivity, and the launcher keeps
  its usual behaviour. MainActivity reads the link in `onCreate` (not when recreated, nor reopened from Recents) and
  in `onNewIntent`.
- **GNOME:** `HANDLES_OPEN`; the `.desktop` file (repository and Flatpak) registers the scheme.
- **Windows:** `uap3:Protocol` with `Parameters="&quot;%1&quot;"`; a link on the command line goes to a running
  Walkdown window through `WM_COPYDATA` (at most 128 bytes, read by the same reader), else the app starts with it.
- Walkdown Plant's `WALKDOWN_TAKES` lists `kks` and `course`.

**Verified** (2026-10-16): Android on the emulator (a cold start and a running app, one MainActivity, a link before
joining dropped; `test_app_links` in test_app2.py); GNOME headless (cold starts with good and hostile links;
test_gnome.py); Windows 11 in the VM, the plain exe and the installed test-signed MSIX through the shell (a cold start,
second starts handing over and ending, hostile links; test_windows.py). Not tried: a running GNOME app receiving a
link over D-Bus (the tests run each app with its own non-unique ID), real phones.

**When to revisit:** when the web client should take links (an https path on the server instead of a scheme); when
another kind is needed (a procedure: PLANT3D.md §6 first).
