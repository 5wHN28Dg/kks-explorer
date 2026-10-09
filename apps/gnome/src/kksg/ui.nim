## Small helpers for building screens with GTK/libadwaita (decision 0031).

import std/strutils
import gtk

proc vbox*(spacing = 6): W = gtk_box_new(GTK_ORIENTATION_VERTICAL, cint(spacing))
proc hbox*(spacing = 6): W = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, cint(spacing))
proc add*(box: W, ws: varargs[W]) =
  for w in ws: gtk_box_append(box, w)
proc clear*(box: W) =
  var c = gtk_widget_get_first_child(box)
  while c != nil:
    let n = gtk_widget_get_next_sibling(c)
    gtk_box_remove(box, c)
    c = n

proc label*(text: string, css = "", wrap = true, xalign = 0.0, selectable = false): W =
  result = gtk_label_new(text.cstring)
  gtk_label_set_xalign(result, cfloat(xalign))
  if wrap:
    gtk_label_set_wrap(result, 1)
    gtk_label_set_wrap_mode(result, PANGO_WRAP_WORD_CHAR)
  if selectable: gtk_label_set_selectable(result, 1)
  for c in css.splitWhitespace: gtk_widget_add_css_class(result, c.cstring)

proc onClick*(b: W, fn: proc ()) =
  ## Button handlers run from an idle callback: widgets built while GTK handles an accessibility action (a screen
  ## reader's or AT-SPI's "click") were missing from the accessibility tree (GTK 4.22, found 2026-10-01).
  b.on("clicked", proc () = idle(fn))

proc button*(text: string, css = "", fn: proc () = nil): W =
  result = gtk_button_new_with_label(text.cstring)
  for c in css.splitWhitespace: gtk_widget_add_css_class(result, c.cstring)
  if fn != nil: result.onClick(fn)

proc iconButton*(icon, tooltip: string, fn: proc () = nil): W =
  result = gtk_button_new_from_icon_name(icon.cstring)
  gtk_widget_set_tooltip_text(result, tooltip.cstring)
  setAccessibleLabel(result, tooltip)
  if fn != nil: result.onClick(fn)

proc margins*(w: W, m: int): W {.discardable.} =
  gtk_widget_set_margin_top(w, cint(m))
  gtk_widget_set_margin_bottom(w, cint(m))
  gtk_widget_set_margin_start(w, cint(m))
  gtk_widget_set_margin_end(w, cint(m))
  w

proc scrolled*(child: W): W =
  result = gtk_scrolled_window_new()
  gtk_scrolled_window_set_policy(result, GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
  gtk_scrolled_window_set_child(result, child)
  gtk_widget_set_vexpand(result, 1)

proc group*(title: string, description = ""): W =
  result = adw_preferences_group_new()
  if title.len > 0: adw_preferences_group_set_title(result, title.cstring)
  if description.len > 0: adw_preferences_group_set_description(result, description.cstring)

proc row*(title, subtitle: string, selectable = false): W =
  ## an AdwActionRow; markup off (user text is never markup)
  result = adw_action_row_new()
  adw_preferences_row_set_use_markup(result, 0)
  adw_preferences_row_set_title(result, title.cstring)
  if subtitle.len > 0: adw_action_row_set_subtitle(result, subtitle.cstring)
  if selectable: adw_action_row_set_subtitle_selectable(result, 1)

proc entryRow*(title, value: string): W =
  result = adw_entry_row_new()
  adw_preferences_row_set_use_markup(result, 0)
  adw_preferences_row_set_title(result, title.cstring)
  gtk_editable_set_text(result, value.cstring)

proc passwordRow*(title: string): W =
  result = adw_password_entry_row_new()
  adw_preferences_row_set_title(result, title.cstring)

proc esc*(s: string): string =
  ## Pango markup escaping, for the few labels built with markup
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#39;"
    else: result.add c

proc toast*(overlay: W, msg: string) =
  if overlay == nil: return
  # a toast's title is Pango markup: the text is escaped (codes, typed values and plant data go into toasts)
  let t = adw_toast_new(esc(msg).cstring)
  adw_toast_set_timeout(t, 4)
  adw_toast_overlay_add_toast(overlay, t)

proc present*(d, parent: W) =
  ## (see onClick: never inside an accessibility action)
  idle(proc () = adw_dialog_present(d, parent))

proc confirm*(parent: W, heading, body, yes: string, destructive: bool, fn: proc ()) =
  let d = adw_alert_dialog_new(heading.cstring, body.cstring)
  adw_alert_dialog_add_response(d, "cancel", "Cancel")
  adw_alert_dialog_add_response(d, "yes", yes.cstring)
  adw_alert_dialog_set_response_appearance(d, "yes", if destructive: ADW_RESPONSE_DESTRUCTIVE else: ADW_RESPONSE_SUGGESTED)
  adw_alert_dialog_set_default_response(d, "cancel")
  adw_alert_dialog_set_close_response(d, "cancel")
  d.onResponse(proc (id: string) =
    if id == "yes": fn())
  present(d, parent)

proc page*(child: W, title: string): W = adw_navigation_page_new(child, title.cstring)

proc toolbarView*(header, content: W): W =
  result = adw_toolbar_view_new()
  adw_toolbar_view_add_top_bar(result, header)
  adw_toolbar_view_set_content(result, content)

proc headerBar*(title: W = nil): W =
  result = adw_header_bar_new()
  if title != nil: adw_header_bar_set_title_widget(result, title)

proc navRow*(title, subtitle, actionLabel: string, fn: proc ()): W =
  ## a row that opens something: the whole row activates its "go" button, which carries an accessible name
  ## ("Open LP system"), so keyboard, screen reader and AT-SPI users get a real action
  result = row(title, subtitle)
  let b = gtk_button_new_from_icon_name("go-next-symbolic")
  gtk_widget_add_css_class(b, "flat")
  gtk_widget_set_valign(b, GTK_ALIGN_CENTER)
  setAccessibleLabel(b, actionLabel)
  gtk_widget_set_tooltip_text(b, actionLabel.cstring)
  b.onClick(fn)
  adw_action_row_add_suffix(result, b)
  adw_action_row_set_activatable_widget(result, b)
