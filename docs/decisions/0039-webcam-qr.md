# 0039 Scanning an invite QR with the webcam in the GNOME and Windows apps

Date 2026-10-03 · Scope: R13 (joining by invite), decisions 0019 (QR codes), 0031 (GNOME), 0033 (Windows) · Status:
**asked for by the user 2026-10-02 ("I want webcam scanning on both"); choices by Claude**, the user can revisit.

**Question:** the desktop apps can paste an invite's text (and GNOME can open a picture of the QR), but they can't
read the code from the webcam the way the phones and the browser do. What does each platform give an app to get
camera frames, and what does a sandboxed or restricted install need?

## Findings

| | GNOME (this laptop: Ubuntu, GStreamer 1.28.2, PipeWire, xdg-desktop-portal) | Windows 10 / 11 |
|---|---|---|
| Permission | **Camera portal** `org.freedesktop.portal.Camera`: `AccessCamera` asks the person, `OpenPipeWireRemote` returns a PipeWire fd that only shows the camera nodes [D]. Here: version 1, `IsCameraPresent` = true [V] | Settings → Privacy → Camera → "Let desktop apps access your camera"; denied = `E_ACCESSDENIED` when the source starts [D] |
| Frames | PipeWire stream from that fd. GStreamer's `pipewiresrc fd=… path=…` + `videoconvert` + `appsink` does the format negotiation for us [D]; installed here with the PipeWire plugin 1.6.2 [V] | **Media Foundation**: `MFEnumDeviceSources` (video capture) + `IMFSourceReader` with video processing on, asking for RGB32 [D] |
| Present where | GStreamer and PipeWire are part of the GNOME platform and of the GNOME Flatpak runtime [K]; the portal needs xdg-desktop-portal-gnome (any current GNOME) | In every Windows 10/11 edition except **N/KN** (Media Feature Pack needed) [D] |
| Without the portal | `/dev/video*` through V4L2 (`v4l2src`): works for an unsandboxed app with the seat's ACL (here `crw-rw----+`) [V], not inside Flatpak without `--device=all` | — |
| Decoding | zxing-cpp, already linked (0019; the GNOME app reads a QR from a picture with it) | zxing-cpp, already linked (writer today); the static library has the reader built (`ZXING_READERS=ON`) |

Sources: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Camera.html ·
https://gstreamer.freedesktop.org/documentation/app/appsink.html ·
https://docs.pipewire.org/page_portal.html ·
https://learn.microsoft.com/windows/win32/medfound/source-reader ·
https://learn.microsoft.com/windows/win32/api/mfidl/nf-mfidl-mfenumdevicesources ·
https://support.microsoft.com/windows/media-feature-pack-for-windows-10-11-n-september-2022 ·
https://support.microsoft.com/windows/manage-app-permissions-for-your-camera-in-windows ([V] = ran here).

## Choice

- **GNOME:** the camera portal first (the sandbox-correct way, and the only one that works in Flatpak without
  extra device rights), then `v4l2src` when no portal answers (an unsandboxed install on a desktop without it).
  Frames come through a GStreamer pipeline into an `appsink` as 8-bit grey, go to zxing-cpp, and are shown as the
  preview. GStreamer is a platform library here, not bundled: no new dependency. Its headers come in for building
  the same way as GTK's (`apt-get download` into `~/.local/kksdev/root`).
- **Windows:** Media Foundation's Source Reader from the first video capture device, RGB32 frames → grey →
  zxing-cpp, preview drawn in the scan window. A denied permission or an N edition gets a message that says what to
  do; pasting the text stays available.
- **Both:** a "Scan with the camera" button next to the pasted invite text; a decoded invite fills the field and
  joins as if pasted. For tests, an environment variable feeds a video file through the same pipeline
  (`KKS_CAMERA_FILE`): the VMs have no camera, and a QR in front of a real webcam needs a person.

**When to revisit:** if the portal gains a frame API that needs no PipeWire, or Windows apps move to MSIX with the
WinRT `MediaCapture` API (its permission model is the same).
