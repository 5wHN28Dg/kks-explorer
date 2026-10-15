## About Walkdown: libadwaita's AdwAboutDialog, filled from the shared About content (data/about.json, compiled in by
## kksl/buildinfo) and from what this build knows about itself (version, commit, local changes, source).
## The legal page carries every third-party part the Linux app is built with or uses (about.json `platforms.gnome`),
## each with its copyright and the licence or notice text it asks to be shipped with; the course photos' credits are
## an acknowledgement section, with their licences linked.
##
## What AdwAboutDialog does with the strings (libadwaita 1.9, checked 2026-10-15): the app's copyright, a legal
## section's copyright and licence, an acknowledgement section's name and a link's title are Pango markup; a legal
## section's title is plain text; a person in an acknowledgement section is plain text, cut at its first "http" (the
## link) or "<" (an e-mail address), so credits carry no other URL or "<".

import std/[os, strutils]
import kks/json
import kksl/buildinfo
import gtk, ui

type
  Legal* = object
    title*: string       ## plain text
    copyright*: string   ## markup: the part's copyright line, then what it is for and where this app's copy comes from
    license*: string     ## markup: the licence's name with links, then the licence or notice text
  About* = object
    name*, summary*, developer*, copyright*, version*: string
    website*, issues*, help*: string
    sourceTitle*, sourceUrl*: string     ## the link to this build's source (sourceTitle is markup)
    legal*: seq[Legal]                   ## the first one says what the parts are (platforms.gnome.note)
    photos*: seq[string]                 ## acknowledgement entries: "credit https://page"
    photoLicences*: seq[string]          ## acknowledgement entries: "CC BY-SA 4.0 https://creativecommons.org/…"

const
  PhotosTitle* = "Course photos"
  PhotoLicencesTitle* = "Licences of the course photos"

proc str(n: JNode, key: string): string =
  let v = n.get(key)
  if v.isStr: v.s else: ""

proc attr(s: string): string = esc(s)   ## (esc escapes quotes too: safe inside href="…")

proc plainCredit(s: string): string =
  ## a credit as AdwAboutDialog's person rows can show it: no URL scheme inside (the row would end there, and link to
  ## the rest), no "<" or ">" (read as an e-mail address)
  s.multiReplace(("https://", ""), ("http://", ""), ("<", "‹"), (">", "›")).strip

proc isCommitHash(v: string): bool = v.len == 40 and v.allCharsInSet(HexDigits)

proc legalOf(c, licences: JNode): Legal =
  let how = c["platforms"].str("gnome")
  result.title = c.str("name")
  let ver = c.str("version")
  if how == "bundled" and ver.len > 0:            # (a system part's version is whatever the system has)
    result.title.add(if isCommitHash(ver): " (commit " & ver[0 ..< 12] & ")" else: " " & ver)
  let notice = c.str("notice").strip(leading = false)
  # a notice of one short paragraph is a copyright line (the fonts'); a longer one is the licence file itself
  let isCopyright = notice.len > 0 and notice.len <= 300 and "\n\n" notin notice
  var use = c.str("use")
  if use.len > 0: use[0] = use[0].toUpperAscii
  let origin = if how == "bundled": "Comes with Walkdown."
               else: "Walkdown uses the system's copy (in the Flatpak, the GNOME runtime's)."
  result.copyright = (if isCopyright: esc(notice) & "\n" else: "") & esc(use & (if use.len > 0: ". " else: "") & origin)
  var links: seq[string]
  var texts: seq[string]
  if notice.len > 0 and not isCopyright: texts.add notice
  if c.get("license_ids") != nil:
    for id in c["license_ids"].elems:
      let l = licences.get(id.s)
      if l == nil:
        links.add esc(id.s)
        continue
      links.add "<a href=\"" & attr(l.str("url")) & "\">" & esc(id.s) & "</a>"
      let t = l.str("text").strip(leading = false)
      if t.len > 0 and t notin notice: texts.add t
  result.license = "Licence: " & esc(c.str("license_name")) & (if links.len > 0: " (" & links.join(", ") & ")" else: "")
  if texts.len > 0: result.license.add "\n\n" & esc(texts.join("\n\n"))

proc aboutFrom*(text: string): About =
  ## the dialog's content from about.json's text
  let d = parseStrict(text)
  let links = d["links"]
  result.name = d.str("name")
  result.summary = d.str("summary")
  result.developer = d.str("developer")
  result.copyright = "© " & esc(result.developer)
  result.version = versionLine("").strip           # "0.10.3 (commit 0123456789ab, with local changes)"
  result.website = links.str("homepage")
  result.issues = links.str("issues")
  result.help = links.str("help")
  result.sourceUrl = SourceUrl
  result.sourceTitle = if Commit.len == 0: "Source code"
                       elif Modified: "Source of this version (without its local changes)"
                       else: "Source of this version"
  let gnome = d["platforms"].get("gnome")
  if gnome != nil:
    result.legal.add Legal(title: "Third-party parts", copyright: esc(gnome.str("note")))
  let licences = d["licenses"]
  for c in d["components"].elems:
    if c["platforms"].str("gnome").len > 0: result.legal.add legalOf(c, licences)
  var seen: seq[string]
  for p in d["photos"].elems:
    var page = ""
    for l in p["links"].elems:
      let u = l.str("url")
      if "creativecommons.org" in u:
        let key = u.strip(leading = false, chars = {'/'})     # (the same licence, written with and without a /)
        if key notin seen:
          seen.add key
          result.photoLicences.add plainCredit(l.str("text")) & " " & u
      else: page = u
    result.photos.add plainCredit(p.str("text")) & (if page.len > 0: " " & page else: "")

var cached: About
var parsed = false
proc about*(): About =
  ## parsed once, the first time the dialog opens
  if not parsed:
    cached = aboutFrom(AboutJson)
    parsed = true
  cached

# ---------------------------------------------------------------- the dialog

proc gObjectTypeName(o: W): cstring {.importc: "G_OBJECT_TYPE_NAME", header: "<glib-object.h>".}
proc gtk_native_get_surface(n: W): W {.importc, header: "<gtk/gtk.h>".}
proc gdk_surface_get_scale(s: W): cdouble {.importc, header: "<gtk/gtk.h>".}
var GTK_LICENSE_UNKNOWN {.importc, header: "<gtk/gtk.h>", nodecl.}: cint

proc osName(): string =
  ## the machine's system (inside the Flatpak sandbox, the host's: /run/host/os-release)
  for f in ["/run/host/os-release", "/etc/os-release", "/usr/lib/os-release"]:
    try:
      for line in readFile(f).splitLines:
        if line.startsWith("PRETTY_NAME="): return line[12 .. ^1].strip(chars = {'"', '\''})
    except IOError, OSError: discard
  "unknown"

proc debugInfo*(parent: W): string =
  ## what support needs to know about this copy and this machine (Troubleshooting → Debugging Information)
  result = versionLine("Walkdown") & "\n"
  result.add "Commit: " & (if Commit.len > 0: Commit else: "unknown") & "\n"
  result.add "Local changes: " & (if Modified: "yes" else: "no") & "\n"
  result.add sourceLine() & "\n"
  result.add "Package: " & (when defined(flatpak): "Flatpak" else: "not packaged") & "\n"
  result.add "GTK: " & $gtk_get_major_version() & "." & $gtk_get_minor_version() & "." & $gtk_get_micro_version() &
             " (built with " & $GTK_MAJOR_VERSION & "." & $GTK_MINOR_VERSION & "." & $GTK_MICRO_VERSION & ")\n"
  result.add "libadwaita: " & $adw_get_major_version() & "." & $adw_get_minor_version() & "." & $adw_get_micro_version() &
             " (built with " & $ADW_MAJOR_VERSION & "." & $ADW_MINOR_VERSION & "." & $ADW_MICRO_VERSION & ")\n"
  let disp = gdk_display_get_default()
  result.add "Display: " & (if disp != nil: $gObjectTypeName(disp) else: "none")
  if parent != nil:
    let s = gtk_native_get_surface(parent)
    result.add ", scale " & $gtk_widget_get_scale_factor(parent) &
               (if s != nil: " (" & formatFloat(gdk_surface_get_scale(s), ffDecimal, 2) & ")" else: "")
  result.add "\nSystem: " & osName() & "\n"

const IconDir = currentSourcePath().parentDir.parentDir.parentDir / "icons"   ## apps/gnome/icons: a build run from
                                                                              ## the repository has no installed icon

proc ensureIcon(appId: string) =
  let d = gdk_display_get_default()
  if d == nil: return
  let theme = gtk_icon_theme_get_for_display(d)
  if gtk_icon_theme_has_icon(theme, appId.cstring) == 0 and dirExists(IconDir):
    gtk_icon_theme_add_search_path(theme, IconDir.cstring)

proc aboutDialog*(parent: W, appId: string): W =
  let a = about()
  ensureIcon(appId)
  let d = adw_about_dialog_new()
  adw_about_dialog_set_application_name(d, a.name.cstring)
  adw_about_dialog_set_application_icon(d, appId.cstring)
  adw_about_dialog_set_version(d, a.version.cstring)
  adw_about_dialog_set_developer_name(d, a.developer.cstring)
  adw_about_dialog_set_comments(d, esc(a.summary).cstring)     # (markup)
  adw_about_dialog_set_copyright(d, a.copyright.cstring)
  adw_about_dialog_set_license_type(d, GTK_LICENSE_AGPL_3_0)       # (or later)
  adw_about_dialog_set_website(d, a.website.cstring)
  adw_about_dialog_set_issue_url(d, a.issues.cstring)
  adw_about_dialog_set_support_url(d, a.help.cstring)
  adw_about_dialog_add_link(d, a.sourceTitle.cstring, a.sourceUrl.cstring)
  for i, l in a.legal:
    adw_about_dialog_add_legal_section(d, l.title.cstring, l.copyright.cstring,
      if l.license.len > 0: GTK_LICENSE_CUSTOM else: GTK_LICENSE_UNKNOWN,
      if l.license.len > 0: l.license.cstring else: nil)
  for (title, people) in [(PhotosTitle, a.photos), (PhotoLicencesTitle, a.photoLicences)]:
    if people.len > 0:
      let arr = allocCStringArray(people)
      adw_about_dialog_add_acknowledgement_section(d, esc(title).cstring, arr)
      deallocCStringArray(arr)
  adw_about_dialog_set_debug_info(d, debugInfo(parent).cstring)
  adw_about_dialog_set_debug_info_filename(d, "walkdown-debug-info.txt")
  d

var aboutShown = false
var shownDialog: W          ## the open About dialog (nil once it has closed)
proc showAbout*(parent: W, appId: string) =
  ## Built and shown from idle (the menu's item can be pressed through an accessibility action, and a dialog built
  ## inside one has no accessible contents); one at a time.
  if parent == nil or aboutShown: return
  aboutShown = true
  idle(proc () =
    try:
      let d = aboutDialog(parent, appId)
      d.on("closed", proc () =
        aboutShown = false
        shownDialog = nil)
      shownDialog = d
      adw_dialog_present(d, parent)
    except CatchableError, Defect:
      aboutShown = false
      raise)

# tests: the dialog's pages. Its rows (Legal, Acknowledgements …) have no accessibility action to press, and the
# headless test session has no pointer or keyboard: the e2e opens them through the dialog's own navigation view.
proc adw_navigation_view_get_visible_page(v: W): W {.importc, header: "<adwaita.h>".}
proc adw_navigation_page_get_tag(p: W): cstring {.importc, header: "<adwaita.h>".}

proc navigationOf(w: W): W =
  if $gObjectTypeName(w) == "AdwNavigationView": return w
  var c = gtk_widget_get_first_child(w)
  while c != nil:
    result = navigationOf(c)
    if result != nil: return
    c = gtk_widget_get_next_sibling(c)

proc aboutPage*(): string =
  ## the tag of the open About dialog's visible page ("legal" …, "main" for the first); "" when it is not open
  if shownDialog == nil: return ""
  let nav = navigationOf(shownDialog)
  if nav == nil: return "?"
  let p = adw_navigation_view_get_visible_page(nav)
  if p == nil: "?"
  elif adw_navigation_page_get_tag(p) == nil: "main"      # (the first page has no tag)
  else: $adw_navigation_page_get_tag(p)

proc aboutGo*(tag: string) =
  ## shows the open About dialog's page of this tag; "back" goes back one page
  if shownDialog == nil: return
  let nav = navigationOf(shownDialog)
  if nav == nil: return
  if tag == "back": adw_navigation_view_pop(nav)
  elif adw_navigation_view_find_page(nav, tag.cstring) != nil: adw_navigation_view_push_by_tag(nav, tag.cstring)
  else: stderr.writeLine "About: no page " & tag

proc primaryMenu*(): W =
  ## the header bar's main menu (GNOME's primary menu): About Walkdown (app.about)
  let m = g_menu_new()
  g_menu_append(m, "About Walkdown", "app.about")
  result = gtk_menu_button_new()
  gtk_menu_button_set_icon_name(result, "open-menu-symbolic")
  gtk_menu_button_set_menu_model(result, m)
  g_object_unref(m)
  gtk_menu_button_set_primary(result, 1)
  gtk_widget_set_tooltip_text(result, "Main Menu")
  setAccessibleLabel(result, "Main menu")
