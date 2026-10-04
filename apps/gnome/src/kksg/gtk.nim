## Hand-written bindings to the parts of GLib/GObject, GTK 4, libadwaita and Cairo the app uses (decision 0031).
## Every function is declared with the `header` pragma, so the C compiler checks it against the installed headers.
## Objects are plain pointers (`W`); GTK checks instance types at run time (g_return_if_fail criticals).

{.passC: "-DGDK_DISABLE_DEPRECATION_WARNINGS".}
const
  HA = "<adwaita.h>"
  HC = "<cairo.h>"

type
  W* = pointer                                ## any GObject / GtkWidget / AdwWidget
  GCallback* = pointer
  GError* {.importc, header: HA.} = object
    message*: cstring
  GraphRect* {.importc: "graphene_rect_t", header: HA, bycopy.} = object
  Cairo* = pointer                            ## cairo_t*
  Surface* = pointer                          ## cairo_surface_t*

# ---------------------------------------------------------------- GLib / GObject

proc g_signal_connect_data(inst: W, sig: cstring, cb: GCallback, data: pointer, destroy: pointer, flags: cint): culong {.importc, header: HA.}
proc g_signal_handler_disconnect*(inst: W, id: culong) {.importc, header: HA.}
proc g_object_ref*(o: W): W {.importc, header: HA, discardable.}
proc g_object_unref*(o: W) {.importc, header: HA.}
proc g_object_ref_sink*(o: W): W {.importc, header: HA, discardable.}
proc g_timeout_add(ms: cuint, fn: pointer, data: pointer): cuint {.importc, header: HA.}
proc g_idle_add(fn: pointer, data: pointer): cuint {.importc, header: HA.}
proc g_source_remove*(id: cuint): cint {.importc, header: HA, discardable.}
proc g_unix_fd_add(fd: cint, cond: cint, fn: pointer, data: pointer): cuint {.importc, header: "<glib-unix.h>".}
proc g_error_free*(e: ptr GError) {.importc, header: HA.}
proc g_free*(p: pointer) {.importc, header: HA.}
proc g_bytes_new*(data: pointer, size: csize_t): W {.importc, header: HA.}
proc g_bytes_unref*(b: W) {.importc, header: HA.}
proc g_application_run*(app: W, argc: cint, argv: cstringArray): cint {.importc, header: HA.}
proc g_application_quit*(app: W) {.importc, header: HA.}
proc g_get_user_data_dir*(): cstring {.importc, header: HA.}
proc g_main_context_iteration*(ctx: pointer, mayBlock: cint): cint {.importc, header: HA, discardable.}
var G_IO_IN* {.importc, header: HA, nodecl.}: cint

# ---------------------------------------------------------------- closures behind signals

type Env = ref object
  fn0: proc ()
  fnI: proc (i: int)
  fnP: proc (p: W)
  fnDD: proc (a, b: float)
  fnKey: proc (keyval: cuint, state: cuint): bool
  fnB: proc (): bool
  fnS: proc (s: Surface, w, h: int)

proc envDestroy(data: pointer, closure: pointer) {.cdecl.} = GC_unref(cast[Env](data))

var errorHook*: proc (text: string)   ## the app's diagnostics (decision 0040): every caught error, with its trace

proc report(e: ref Exception) =
  ## an exception must never unwind through GLib's C frames: log it and carry on
  stderr.writeLine "error in a UI callback: " & e.msg & "\n" & e.getStackTrace()
  if errorHook != nil:
    try: errorHook($e.name & ": " & e.msg & "\n" & e.getStackTrace()) except CatchableError: discard

template guard(body: untyped) =
  try: body
  except CatchableError as e: report(e)
  except Defect as e: report(e)

proc keep(e: Env): pointer =
  GC_ref(e)
  cast[pointer](e)

proc tramp0(inst: W, data: pointer) {.cdecl.} = guard: cast[Env](data).fn0()
proc trampP(inst: W, p: W, data: pointer) {.cdecl.} = guard: cast[Env](data).fnP(p)
proc trampDD(inst: W, a, b: cdouble, data: pointer) {.cdecl.} = guard: cast[Env](data).fnDD(float(a), float(b))
proc trampScroll(inst: W, a, b: cdouble, data: pointer): cint {.cdecl.} =
  guard: cast[Env](data).fnDD(float(a), float(b))
  1
proc trampPressed(inst: W, n: cint, x, y: cdouble, data: pointer) {.cdecl.} =
  guard:
    let e = cast[Env](data)
    e.fnI(int(n))
    e.fnDD(float(x), float(y))
proc trampKey(inst: W, keyval, keycode, state: cuint, data: pointer): cint {.cdecl.} =
  result = 0
  guard: result = cint(cast[Env](data).fnKey(keyval, state))
proc trampScale(inst: W, scale: cdouble, data: pointer) {.cdecl.} = guard: cast[Env](data).fnDD(float(scale), 0)
proc trampBoolSrc(data: pointer): cint {.cdecl.} =
  ## timers keep running after an error (fnB returns false to stop on purpose)
  result = 1
  guard: result = cint(cast[Env](data).fnB())

proc connect(inst: W, sig: string, cb: pointer, e: Env): culong {.discardable.} =
  g_signal_connect_data(inst, sig.cstring, cast[GCallback](cb), keep(e), cast[pointer](envDestroy), 0)

proc on*(inst: W, sig: string, fn: proc ()): culong {.discardable.} =
  ## signals with no arguments: clicked, activate, changed, search-changed, close-request (returns FALSE), …
  connect(inst, sig, cast[pointer](tramp0), Env(fn0: fn))
proc onPtr*(inst: W, sig: string, fn: proc (p: W)): culong {.discardable.} =
  ## signals with one object argument: row-activated (row), notify (pspec), …
  connect(inst, sig, cast[pointer](trampP), Env(fnP: fn))
proc onXY*(inst: W, sig: string, fn: proc (a, b: float)): culong {.discardable.} =
  ## drag-begin/update/end (offset), motion (x, y)
  connect(inst, sig, cast[pointer](trampDD), Env(fnDD: fn))
proc onScroll*(inst: W, fn: proc (dx, dy: float)): culong {.discardable.} =
  connect(inst, "scroll", cast[pointer](trampScroll), Env(fnDD: fn))
proc onPressed*(inst: W, sig: string, fn: proc (n: int, x, y: float)): culong {.discardable.} =
  ## GtkGestureClick pressed/released: (n_press, x, y)
  var nn = 0
  connect(inst, sig, cast[pointer](trampPressed), Env(fnI: proc (i: int) = nn = i, fnDD: proc (x, y: float) = fn(nn, x, y)))
proc onKey*(inst: W, fn: proc (keyval, state: cuint): bool): culong {.discardable.} =
  connect(inst, "key-pressed", cast[pointer](trampKey), Env(fnKey: fn))
proc onScale*(inst: W, fn: proc (scale: float)): culong {.discardable.} =
  connect(inst, "scale-changed", cast[pointer](trampScale), Env(fnDD: proc (a, b: float) = fn(a)))

proc timeout*(ms: int, fn: proc (): bool): cuint {.discardable.} =
  ## fn returns true to keep running
  let e = Env(fnB: fn)
  GC_ref(e)
  g_timeout_add(cuint(ms), cast[pointer](trampBoolSrc), cast[pointer](e))
proc idle*(fn: proc ()): cuint {.discardable.} =
  let e = Env(fnB: proc (): bool =
    try: fn()
    except CatchableError as e: report(e)
    false)
  GC_ref(e)
  g_idle_add(cast[pointer](trampBoolSrc), cast[pointer](e))
proc trampFd(fd: cint, cond: cint, data: pointer): cint {.cdecl.} =
  result = 1
  guard: result = cint(cast[Env](data).fnB())
proc watchFd*(fd: int, fn: proc (): bool): cuint {.discardable.} =
  let e = Env(fnB: fn)
  GC_ref(e)
  g_unix_fd_add(cint(fd), G_IO_IN, cast[pointer](trampFd), cast[pointer](e))

# ---------------------------------------------------------------- libadwaita

proc adw_application_new*(id: cstring, flags: cint): W {.importc, header: HA.}
proc adw_application_window_new*(app: W): W {.importc, header: HA.}
proc adw_application_window_set_content*(w, content: W) {.importc, header: HA.}
proc adw_toolbar_view_new*(): W {.importc, header: HA.}
proc adw_toolbar_view_add_top_bar*(v, w: W) {.importc, header: HA.}
proc adw_toolbar_view_add_bottom_bar*(v, w: W) {.importc, header: HA.}
proc adw_toolbar_view_set_content*(v, w: W) {.importc, header: HA.}
proc adw_header_bar_new*(): W {.importc, header: HA.}
proc adw_header_bar_pack_start*(h, w: W) {.importc, header: HA.}
proc adw_header_bar_pack_end*(h, w: W) {.importc, header: HA.}
proc adw_header_bar_set_title_widget*(h, w: W) {.importc, header: HA.}
proc adw_header_bar_set_show_end_title_buttons*(h: W, v: cint) {.importc, header: HA.}
proc adw_window_title_new*(title, subtitle: cstring): W {.importc, header: HA.}
proc adw_window_title_set_title*(t: W, s: cstring) {.importc, header: HA.}
proc adw_window_title_set_subtitle*(t: W, s: cstring) {.importc, header: HA.}
proc adw_navigation_split_view_new*(): W {.importc, header: HA.}
proc adw_navigation_split_view_set_sidebar*(v, page: W) {.importc, header: HA.}
proc adw_navigation_split_view_set_content*(v, page: W) {.importc, header: HA.}
proc adw_navigation_split_view_set_show_content*(v: W, s: cint) {.importc, header: HA.}
proc adw_navigation_split_view_set_collapsed*(v: W, s: cint) {.importc, header: HA.}
proc adw_navigation_split_view_set_min_sidebar_width*(v: W, w: cdouble) {.importc, header: HA.}
proc adw_navigation_split_view_set_max_sidebar_width*(v: W, w: cdouble) {.importc, header: HA.}
proc adw_overlay_split_view_new*(): W {.importc, header: HA.}
proc adw_overlay_split_view_set_sidebar*(v, w: W) {.importc, header: HA.}
proc adw_overlay_split_view_set_content*(v, w: W) {.importc, header: HA.}
proc adw_overlay_split_view_set_show_sidebar*(v: W, s: cint) {.importc, header: HA.}
proc adw_overlay_split_view_get_show_sidebar*(v: W): cint {.importc, header: HA.}
proc adw_overlay_split_view_set_sidebar_position*(v: W, p: cint) {.importc, header: HA.}
proc adw_overlay_split_view_set_min_sidebar_width*(v: W, w: cdouble) {.importc, header: HA.}
proc adw_overlay_split_view_set_max_sidebar_width*(v: W, w: cdouble) {.importc, header: HA.}
proc adw_navigation_page_new*(child: W, title: cstring): W {.importc, header: HA.}
proc adw_navigation_page_set_title*(p: W, t: cstring) {.importc, header: HA.}
proc adw_navigation_view_new*(): W {.importc, header: HA.}
proc adw_navigation_view_push*(v, page: W) {.importc, header: HA.}
proc adw_navigation_view_find_page*(v: W, tag: cstring): W {.importc, header: HA.}
proc adw_navigation_view_pop_to_page*(v, page: W): cint {.importc, header: HA, discardable.}
proc adw_navigation_view_pop*(v: W): cint {.importc, header: HA, discardable.}
proc adw_navigation_view_replace*(v: W, pages: ptr W, n: cint) {.importc, header: HA.}
proc adw_status_page_new*(): W {.importc, header: HA.}
proc adw_status_page_set_title*(p: W, t: cstring) {.importc, header: HA.}
proc adw_status_page_set_description*(p: W, t: cstring) {.importc, header: HA.}
proc adw_status_page_set_icon_name*(p: W, t: cstring) {.importc, header: HA.}
proc adw_status_page_set_child*(p, c: W) {.importc, header: HA.}
proc adw_toast_overlay_new*(): W {.importc, header: HA.}
proc adw_toast_overlay_set_child*(o, c: W) {.importc, header: HA.}
proc adw_toast_overlay_add_toast*(o, t: W) {.importc, header: HA.}
proc adw_toast_new*(title: cstring): W {.importc, header: HA.}
proc adw_toast_set_timeout*(t: W, s: cuint) {.importc, header: HA.}
proc adw_preferences_group_new*(): W {.importc, header: HA.}
proc adw_preferences_group_set_title*(g: W, t: cstring) {.importc, header: HA.}
proc adw_preferences_group_set_description*(g: W, t: cstring) {.importc, header: HA.}
proc adw_preferences_group_add*(g, w: W) {.importc, header: HA.}
proc adw_preferences_group_set_header_suffix*(g, w: W) {.importc, header: HA.}
proc adw_preferences_page_new*(): W {.importc, header: HA.}
proc adw_preferences_page_add*(p, g: W) {.importc, header: HA.}
proc adw_action_row_new*(): W {.importc, header: HA.}
proc adw_action_row_add_suffix*(r, w: W) {.importc, header: HA.}
proc adw_action_row_add_prefix*(r, w: W) {.importc, header: HA.}
proc adw_action_row_set_subtitle*(r: W, s: cstring) {.importc, header: HA.}
proc adw_action_row_set_activatable_widget*(r, w: W) {.importc, header: HA.}
proc adw_action_row_set_subtitle_selectable*(r: W, s: cint) {.importc, header: HA.}
proc adw_preferences_row_set_title*(r: W, t: cstring) {.importc, header: HA.}
proc adw_preferences_row_set_use_markup*(r: W, v: cint) {.importc, header: HA.}
proc adw_entry_row_new*(): W {.importc, header: HA.}
proc adw_entry_row_set_show_apply_button*(r: W, v: cint) {.importc, header: HA.}
proc adw_password_entry_row_new*(): W {.importc, header: HA.}
proc adw_switch_row_new*(): W {.importc, header: HA.}
proc adw_switch_row_get_active*(r: W): cint {.importc, header: HA.}
proc adw_switch_row_set_active*(r: W, v: cint) {.importc, header: HA.}
proc adw_combo_row_new*(): W {.importc, header: HA.}
proc adw_combo_row_set_model*(r, m: W) {.importc, header: HA.}
proc adw_combo_row_get_selected*(r: W): cuint {.importc, header: HA.}
proc adw_combo_row_set_selected*(r: W, i: cuint) {.importc, header: HA.}
proc adw_expander_row_new*(): W {.importc, header: HA.}
proc adw_expander_row_add_row*(r, child: W) {.importc, header: HA.}
proc adw_expander_row_set_subtitle*(r: W, s: cstring) {.importc, header: HA.}
proc adw_alert_dialog_new*(heading, body: cstring): W {.importc, header: HA.}
proc adw_alert_dialog_add_response*(d: W, id, label: cstring) {.importc, header: HA.}
proc adw_alert_dialog_set_response_appearance*(d: W, id: cstring, a: cint) {.importc, header: HA.}
proc adw_alert_dialog_set_default_response*(d: W, id: cstring) {.importc, header: HA.}
proc adw_alert_dialog_set_close_response*(d: W, id: cstring) {.importc, header: HA.}
proc adw_alert_dialog_set_extra_child*(d, w: W) {.importc, header: HA.}
proc adw_dialog_present*(d, parent: W) {.importc, header: HA.}
proc adw_dialog_close*(d: W): cint {.importc, header: HA, discardable.}
proc adw_dialog_new*(): W {.importc, header: HA.}
proc adw_dialog_set_child*(d, w: W) {.importc, header: HA.}
proc adw_dialog_set_title*(d: W, t: cstring) {.importc, header: HA.}
proc adw_dialog_set_content_width*(d: W, w: cint) {.importc, header: HA.}
proc adw_dialog_set_content_height*(d: W, h: cint) {.importc, header: HA.}
proc adw_view_stack_new*(): W {.importc, header: HA.}
proc adw_view_stack_add_titled_with_icon*(s, child: W, name, title, icon: cstring): W {.importc, header: HA, discardable.}
proc adw_view_stack_set_visible_child_name*(s: W, n: cstring) {.importc, header: HA.}
proc adw_view_stack_get_visible_child_name*(s: W): cstring {.importc, header: HA.}
proc adw_view_switcher_new*(): W {.importc, header: HA.}
proc adw_view_switcher_set_stack*(sw, st: W) {.importc, header: HA.}
proc adw_view_switcher_set_policy*(sw: W, p: cint) {.importc, header: HA.}
proc adw_spinner_new*(): W {.importc, header: HA.}
proc adw_wrap_box_new*(): W {.importc, header: HA.}
proc adw_wrap_box_append*(b, w: W) {.importc, header: HA.}
proc adw_wrap_box_set_child_spacing*(b: W, s: cint) {.importc, header: HA.}
proc adw_wrap_box_set_line_spacing*(b: W, s: cint) {.importc, header: HA.}
proc adw_style_manager_get_default*(): W {.importc, header: HA.}
proc adw_style_manager_get_dark*(m: W): cint {.importc, header: HA.}
var
  ADW_RESPONSE_DESTRUCTIVE* {.importc, header: HA, nodecl.}: cint
  ADW_RESPONSE_SUGGESTED* {.importc, header: HA, nodecl.}: cint
  ADW_VIEW_SWITCHER_POLICY_WIDE* {.importc, header: HA, nodecl.}: cint
  GTK_PACK_END* {.importc, header: HA, nodecl.}: cint
proc trampResponse(d: W, resp: cstring, data: pointer) {.cdecl.} =
  guard: cast[Env](data).fnP(cast[W](resp))
proc onResponse*(d: W, fn: proc (id: string)): culong {.discardable.} =
  connect(d, "response", cast[pointer](trampResponse), Env(fnP: proc (p: W) = fn($cast[cstring](p))))

# ---------------------------------------------------------------- GTK widgets

proc gtk_window_present*(w: W) {.importc, header: HA.}
proc gtk_window_set_title*(w: W, t: cstring) {.importc, header: HA.}
proc gtk_window_set_default_size*(w: W, a, b: cint) {.importc, header: HA.}
proc gtk_window_close*(w: W) {.importc, header: HA.}
proc gtk_window_maximize*(w: W) {.importc, header: HA.}
proc gtk_widget_set_visible*(w: W, v: cint) {.importc, header: HA.}
proc gtk_widget_get_visible*(w: W): cint {.importc, header: HA.}
proc gtk_widget_set_sensitive*(w: W, v: cint) {.importc, header: HA.}
proc gtk_widget_set_hexpand*(w: W, v: cint) {.importc, header: HA.}
proc gtk_widget_set_vexpand*(w: W, v: cint) {.importc, header: HA.}
proc gtk_widget_set_halign*(w: W, a: cint) {.importc, header: HA.}
proc gtk_widget_set_valign*(w: W, a: cint) {.importc, header: HA.}
proc gtk_widget_set_margin_top*(w: W, m: cint) {.importc, header: HA.}
proc gtk_widget_set_margin_bottom*(w: W, m: cint) {.importc, header: HA.}
proc gtk_widget_set_margin_start*(w: W, m: cint) {.importc, header: HA.}
proc gtk_widget_set_margin_end*(w: W, m: cint) {.importc, header: HA.}
proc gtk_widget_set_size_request*(w: W, a, b: cint) {.importc, header: HA.}
proc gtk_widget_add_css_class*(w: W, c: cstring) {.importc, header: HA.}
proc gtk_widget_remove_css_class*(w: W, c: cstring) {.importc, header: HA.}
proc gtk_widget_add_controller*(w, c: W) {.importc, header: HA.}
proc gtk_widget_queue_draw*(w: W) {.importc, header: HA.}
proc gtk_widget_grab_focus*(w: W): cint {.importc, header: HA, discardable.}
proc gtk_widget_set_focusable*(w: W, v: cint) {.importc, header: HA.}
proc gtk_widget_set_can_focus*(w: W, v: cint) {.importc, header: HA.}
proc gtk_widget_get_width*(w: W): cint {.importc, header: HA.}
proc gtk_widget_get_height*(w: W): cint {.importc, header: HA.}
proc gtk_widget_get_root*(w: W): W {.importc, header: HA.}
proc gtk_widget_get_mapped*(w: W): cint {.importc, header: HA.}
proc gtk_widget_set_tooltip_text*(w: W, t: cstring) {.importc, header: HA.}
proc gtk_widget_set_cursor_from_name*(w: W, n: cstring) {.importc, header: HA.}
proc gtk_widget_get_scale_factor*(w: W): cint {.importc, header: HA.}
proc gtk_widget_get_first_child*(w: W): W {.importc, header: HA.}
proc gtk_widget_get_next_sibling*(w: W): W {.importc, header: HA.}
proc gtk_widget_unparent*(w: W) {.importc, header: HA.}
proc gtk_accessible_update_property_label(a: W, prop: cint, label: cstring, last: cint) {.importc: "gtk_accessible_update_property", header: HA, varargs.}
var GTK_ACCESSIBLE_PROPERTY_LABEL {.importc, header: HA, nodecl.}: cint
proc setAccessibleLabel*(w: W, label: string) =
  gtk_accessible_update_property_label(w, GTK_ACCESSIBLE_PROPERTY_LABEL, label.cstring, -1)
var
  GTK_ALIGN_START* {.importc, header: HA, nodecl.}: cint
  GTK_ALIGN_END* {.importc, header: HA, nodecl.}: cint
  GTK_ALIGN_CENTER* {.importc, header: HA, nodecl.}: cint
  GTK_ALIGN_FILL* {.importc, header: HA, nodecl.}: cint
  GTK_ORIENTATION_HORIZONTAL* {.importc, header: HA, nodecl.}: cint
  GTK_ORIENTATION_VERTICAL* {.importc, header: HA, nodecl.}: cint
  GTK_POLICY_NEVER* {.importc, header: HA, nodecl.}: cint
  GTK_POLICY_AUTOMATIC* {.importc, header: HA, nodecl.}: cint
  GTK_SELECTION_NONE* {.importc, header: HA, nodecl.}: cint
  GTK_SELECTION_SINGLE* {.importc, header: HA, nodecl.}: cint
  GTK_WRAP_WORD_CHAR* {.importc, header: HA, nodecl.}: cint
  PANGO_WRAP_WORD_CHAR* {.importc, header: HA, nodecl.}: cint
  PANGO_ELLIPSIZE_END* {.importc, header: HA, nodecl.}: cint

proc gtk_box_new*(o: cint, spacing: cint): W {.importc, header: HA.}
proc gtk_box_append*(b, w: W) {.importc, header: HA.}
proc gtk_box_remove*(b, w: W) {.importc, header: HA.}
proc gtk_box_prepend*(b, w: W) {.importc, header: HA.}
proc gtk_label_new*(s: cstring): W {.importc, header: HA.}
proc gtk_label_set_text*(l: W, s: cstring) {.importc, header: HA.}
proc gtk_label_set_markup*(l: W, s: cstring) {.importc, header: HA.}
proc gtk_label_set_wrap*(l: W, v: cint) {.importc, header: HA.}
proc gtk_label_set_wrap_mode*(l: W, m: cint) {.importc, header: HA.}
proc gtk_label_set_xalign*(l: W, x: cfloat) {.importc, header: HA.}
proc gtk_label_set_selectable*(l: W, v: cint) {.importc, header: HA.}
proc gtk_label_set_ellipsize*(l: W, m: cint) {.importc, header: HA.}
proc gtk_label_set_max_width_chars*(l: W, n: cint) {.importc, header: HA.}
proc gtk_label_set_mnemonic_widget*(l, w: W) {.importc, header: HA.}
proc gtk_button_new_with_label*(s: cstring): W {.importc, header: HA.}
proc gtk_button_new_with_mnemonic*(s: cstring): W {.importc, header: HA.}
proc gtk_button_new_from_icon_name*(s: cstring): W {.importc, header: HA.}
proc gtk_button_set_label*(b: W, s: cstring) {.importc, header: HA.}
proc gtk_button_set_icon_name*(b: W, s: cstring) {.importc, header: HA.}
proc gtk_toggle_button_new_with_label*(s: cstring): W {.importc, header: HA.}
proc gtk_toggle_button_get_active*(b: W): cint {.importc, header: HA.}
proc gtk_toggle_button_set_active*(b: W, v: cint) {.importc, header: HA.}
proc gtk_check_button_new_with_label*(s: cstring): W {.importc, header: HA.}
proc gtk_check_button_get_active*(b: W): cint {.importc, header: HA.}
proc gtk_check_button_set_active*(b: W, v: cint) {.importc, header: HA.}
proc gtk_entry_new*(): W {.importc, header: HA.}
proc gtk_entry_set_placeholder_text*(e: W, s: cstring) {.importc, header: HA.}
proc gtk_password_entry_new*(): W {.importc, header: HA.}
proc gtk_search_entry_new*(): W {.importc, header: HA.}
proc gtk_search_entry_set_placeholder_text*(e: W, s: cstring) {.importc, header: HA.}
proc gtk_editable_get_text*(e: W): cstring {.importc, header: HA.}
proc gtk_editable_set_text*(e: W, s: cstring) {.importc, header: HA.}
proc gtk_editable_set_editable*(e: W, v: cint) {.importc, header: HA.}
proc gtk_scrolled_window_new*(): W {.importc, header: HA.}
proc gtk_scrolled_window_set_child*(s, c: W) {.importc, header: HA.}
proc gtk_scrolled_window_set_policy*(s: W, h, v: cint) {.importc, header: HA.}
proc gtk_scrolled_window_set_propagate_natural_height*(s: W, v: cint) {.importc, header: HA.}
proc gtk_list_box_new*(): W {.importc, header: HA.}
proc gtk_list_box_append*(l, w: W) {.importc, header: HA.}
proc gtk_list_box_remove_all*(l: W) {.importc, header: HA.}
proc gtk_list_box_set_selection_mode*(l: W, m: cint) {.importc, header: HA.}
proc gtk_list_box_row_new*(): W {.importc, header: HA.}
proc gtk_list_box_row_set_child*(r, c: W) {.importc, header: HA.}
proc gtk_list_box_row_get_index*(r: W): cint {.importc, header: HA.}
proc gtk_list_box_get_row_at_index*(l: W, i: cint): W {.importc, header: HA.}
proc gtk_list_box_select_row*(l, r: W) {.importc, header: HA.}
proc gtk_list_box_set_placeholder*(l, w: W) {.importc, header: HA.}
proc gtk_separator_new*(o: cint): W {.importc, header: HA.}
proc gtk_text_view_new*(): W {.importc, header: HA.}
proc gtk_text_view_get_buffer*(t: W): W {.importc, header: HA.}
proc gtk_text_view_set_wrap_mode*(t: W, m: cint) {.importc, header: HA.}
proc gtk_text_view_set_editable*(t: W, v: cint) {.importc, header: HA.}
proc gtk_text_buffer_set_text*(b: W, s: cstring, n: cint) {.importc, header: HA.}
type TextIter* {.importc: "GtkTextIter", header: HA, bycopy.} = object
proc gtk_text_buffer_get_start_iter*(b: W, i: ptr TextIter) {.importc, header: HA.}
proc gtk_text_buffer_get_end_iter*(b: W, i: ptr TextIter) {.importc, header: HA.}
proc gtk_text_buffer_get_text*(b: W, s, e: ptr TextIter, hidden: cint): cstring {.importc, header: HA.}
proc gtk_overlay_new*(): W {.importc, header: HA.}
proc gtk_overlay_set_child*(o, c: W) {.importc, header: HA.}
proc gtk_overlay_add_overlay*(o, c: W) {.importc, header: HA.}
proc gtk_stack_new*(): W {.importc, header: HA.}
proc gtk_stack_add_named*(s, c: W, n: cstring): W {.importc, header: HA, discardable.}
proc gtk_stack_set_visible_child_name*(s: W, n: cstring) {.importc, header: HA.}
proc gtk_menu_button_new*(): W {.importc, header: HA.}
proc gtk_menu_button_set_icon_name*(b: W, n: cstring) {.importc, header: HA.}
proc gtk_menu_button_set_popover*(b, p: W) {.importc, header: HA.}
proc gtk_popover_new*(): W {.importc, header: HA.}
proc gtk_popover_set_child*(p, c: W) {.importc, header: HA.}
proc gtk_popover_popdown*(p: W) {.importc, header: HA.}
proc gtk_string_list_new_c(items: pointer): W {.importc: "gtk_string_list_new", header: HA.}
proc gtk_string_list_new*(items: cstringArray): W = gtk_string_list_new_c(cast[pointer](items))
proc gtk_string_list_append*(l: W, s: cstring) {.importc, header: HA.}

proc gtk_drop_down_get_selected*(d: W): cuint {.importc, header: HA.}
proc gtk_drop_down_set_selected*(d: W, i: cuint) {.importc, header: HA.}
proc gtk_picture_new_for_paintable*(p: W): W {.importc, header: HA.}
proc gtk_picture_set_content_fit*(p: W, f: cint) {.importc, header: HA.}
proc gtk_image_new_from_icon_name*(n: cstring): W {.importc, header: HA.}
proc gtk_spin_button_new_with_range*(a, b, s: cdouble): W {.importc, header: HA.}
proc gtk_spin_button_get_value*(s: W): cdouble {.importc, header: HA.}
proc gtk_spin_button_set_value*(s: W, v: cdouble) {.importc, header: HA.}
proc gtk_progress_bar_new*(): W {.importc, header: HA.}
proc gtk_progress_bar_set_fraction*(p: W, f: cdouble) {.importc, header: HA.}
proc gtk_flow_box_new*(): W {.importc, header: HA.}
proc gtk_flow_box_append*(f, w: W) {.importc, header: HA.}
var GTK_CONTENT_FIT_CONTAIN* {.importc, header: HA, nodecl.}: cint
proc gtk_css_provider_new*(): W {.importc, header: HA.}
proc gtk_css_provider_load_from_string*(p: W, s: cstring) {.importc, header: HA.}
proc gtk_style_context_add_provider_for_display*(d, p: W, prio: cuint) {.importc, header: HA.}
proc gdk_display_get_default*(): W {.importc, header: HA.}

# event controllers
proc gtk_gesture_drag_new*(): W {.importc, header: HA.}
proc gtk_gesture_click_new*(): W {.importc, header: HA.}
proc gtk_gesture_zoom_new*(): W {.importc, header: HA.}
proc gtk_gesture_single_set_button*(g: W, b: cuint) {.importc, header: HA.}
proc gtk_gesture_single_get_current_button*(g: W): cuint {.importc, header: HA.}
proc gtk_event_controller_scroll_new*(flags: cint): W {.importc, header: HA.}
proc gtk_event_controller_motion_new*(): W {.importc, header: HA.}
proc gtk_event_controller_key_new*(): W {.importc, header: HA.}
proc gtk_event_controller_get_current_event_state*(c: W): cuint {.importc, header: HA.}
proc gtk_gesture_zoom_get_scale_delta*(g: W): cdouble {.importc, header: HA.}
proc gtk_gesture_get_bounding_box_center*(g: W, x, y: ptr cdouble): cint {.importc, header: HA.}
proc gtk_event_controller_scroll_get_unit*(c: W): cint {.importc, header: HA.}
proc gtk_event_controller_get_current_event_device*(c: W): pointer {.importc, header: HA.}
proc gdk_device_get_source*(d: pointer): cint {.importc, header: HA.}
var
  GDK_SOURCE_TOUCHSCREEN* {.importc, header: HA, nodecl.}: cint
  GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES* {.importc, header: HA, nodecl.}: cint
  GDK_CONTROL_MASK* {.importc, header: HA, nodecl.}: cuint
  GDK_SHIFT_MASK* {.importc, header: HA, nodecl.}: cuint
  GDK_SCROLL_UNIT_WHEEL* {.importc, header: HA, nodecl.}: cint

# file dialogs (portal-backed)
proc gtk_file_dialog_new*(): W {.importc, header: HA.}
proc gtk_file_dialog_set_title*(d: W, t: cstring) {.importc, header: HA.}
proc gtk_file_dialog_set_initial_name*(d: W, n: cstring) {.importc, header: HA.}
proc gtk_file_dialog_open(d, parent, cancel: W, cb: pointer, data: pointer) {.importc, header: HA.}
proc gtk_file_dialog_open_finish(d, res: W, err: ptr ptr GError): W {.importc, header: HA.}
proc gtk_file_dialog_save(d, parent, cancel: W, cb: pointer, data: pointer) {.importc, header: HA.}
proc gtk_file_dialog_save_finish(d, res: W, err: ptr ptr GError): W {.importc, header: HA.}
proc g_file_get_path*(f: W): cstring {.importc, header: HA.}
proc trampOpen(src, res: W, data: pointer) {.cdecl.} =
  let e = cast[Env](data)
  var err: ptr GError
  let f = gtk_file_dialog_open_finish(src, res, addr err)
  if err != nil: g_error_free(err)
  guard: e.fnP(f)
  if f != nil: g_object_unref(f)
  GC_unref(e)
proc trampSave(src, res: W, data: pointer) {.cdecl.} =
  let e = cast[Env](data)
  var err: ptr GError
  let f = gtk_file_dialog_save_finish(src, res, addr err)
  if err != nil: g_error_free(err)
  guard: e.fnP(f)
  if f != nil: g_object_unref(f)
  GC_unref(e)
proc filePath(f: W): string =
  if f == nil: return ""
  let p = g_file_get_path(f)
  result = $p
  g_free(p)
proc openFile*(parent: W, title: string, fn: proc (path: string)) =
  ## The portal file chooser; fn("") when cancelled.
  let d = gtk_file_dialog_new()
  gtk_file_dialog_set_title(d, title.cstring)
  let e = Env(fnP: proc (f: W) = fn(filePath(f)))
  GC_ref(e)
  gtk_file_dialog_open(d, parent, nil, cast[pointer](trampOpen), cast[pointer](e))
proc saveFile*(parent: W, title, name: string, fn: proc (path: string)) =
  let d = gtk_file_dialog_new()
  gtk_file_dialog_set_title(d, title.cstring)
  gtk_file_dialog_set_initial_name(d, name.cstring)
  let e = Env(fnP: proc (f: W) = fn(filePath(f)))
  GC_ref(e)
  gtk_file_dialog_save(d, parent, nil, cast[pointer](trampSave), cast[pointer](e))

# clipboard
proc gtk_widget_get_clipboard*(w: W): W {.importc, header: HA.}
proc gdk_clipboard_set_text*(c: W, s: cstring) {.importc, header: HA.}

# textures and snapshots
proc gdk_memory_texture_new*(w, h: cint, fmt: cint, bytes: W, stride: csize_t): W {.importc, header: HA.}
proc gdk_texture_get_width*(t: W): cint {.importc, header: HA.}
proc gdk_texture_get_height*(t: W): cint {.importc, header: HA.}
var
  GDK_MEMORY_B8G8R8A8_PREMULTIPLIED* {.importc, header: HA, nodecl.}: cint
  GDK_MEMORY_R8G8B8* {.importc, header: HA, nodecl.}: cint
  GDK_MEMORY_R8G8B8A8* {.importc, header: HA, nodecl.}: cint
  GSK_SCALING_FILTER_LINEAR* {.importc, header: HA, nodecl.}: cint
  GSK_SCALING_FILTER_TRILINEAR* {.importc, header: HA, nodecl.}: cint
  GSK_SCALING_FILTER_NEAREST* {.importc, header: HA, nodecl.}: cint
proc graphene_rect_init*(r: ptr GraphRect, x, y, w, h: cfloat): ptr GraphRect {.importc, header: HA, discardable.}
proc gtk_snapshot_append_texture*(s, tex: W, r: ptr GraphRect) {.importc, header: HA.}
proc gtk_snapshot_append_scaled_texture*(s, tex: W, filter: cint, r: ptr GraphRect) {.importc, header: HA.}
proc gtk_snapshot_append_cairo*(s: W, r: ptr GraphRect): Cairo {.importc, header: HA.}
proc gtk_snapshot_push_clip*(s: W, r: ptr GraphRect) {.importc, header: HA.}
proc gtk_snapshot_pop*(s: W) {.importc, header: HA.}

proc textureFromRgb*(data: openArray[byte], w, h: int, alpha = false): W =
  ## a GdkMemoryTexture from RGB(A) rows
  let n = if alpha: 4 else: 3
  let b = g_bytes_new(unsafeAddr data[0], csize_t(w * h * n))
  result = gdk_memory_texture_new(cint(w), cint(h), if alpha: GDK_MEMORY_R8G8B8A8 else: GDK_MEMORY_R8G8B8, b, csize_t(w * n))
  g_bytes_unref(b)

# ---------------------------------------------------------------- Cairo

proc cairo_image_surface_create*(fmt: cint, w, h: cint): Surface {.importc, header: HC.}
proc cairo_image_surface_get_data*(s: Surface): ptr UncheckedArray[byte] {.importc, header: HC.}
proc cairo_image_surface_get_stride*(s: Surface): cint {.importc, header: HC.}
proc cairo_image_surface_get_width*(s: Surface): cint {.importc, header: HC.}
proc cairo_image_surface_get_height*(s: Surface): cint {.importc, header: HC.}
proc cairo_image_surface_create_for_data*(data: pointer, fmt, w, h, stride: cint): Surface {.importc, header: HC.}
proc cairo_surface_flush*(s: Surface) {.importc, header: HC.}
proc cairo_surface_mark_dirty*(s: Surface) {.importc, header: HC.}
proc cairo_surface_destroy*(s: Surface) {.importc, header: HC.}
proc cairo_create*(s: Surface): Cairo {.importc, header: HC.}
proc cairo_destroy*(c: Cairo) {.importc, header: HC.}
proc cairo_save*(c: Cairo) {.importc, header: HC.}
proc cairo_restore*(c: Cairo) {.importc, header: HC.}
proc cairo_scale*(c: Cairo, x, y: cdouble) {.importc, header: HC.}
proc cairo_translate*(c: Cairo, x, y: cdouble) {.importc, header: HC.}
proc cairo_set_source_rgb*(c: Cairo, r, g, b: cdouble) {.importc, header: HC.}
proc cairo_set_source_rgba*(c: Cairo, r, g, b, a: cdouble) {.importc, header: HC.}
proc cairo_set_source_surface*(c: Cairo, s: Surface, x, y: cdouble) {.importc, header: HC.}
proc cairo_paint*(c: Cairo) {.importc, header: HC.}
proc cairo_move_to*(c: Cairo, x, y: cdouble) {.importc, header: HC.}
proc cairo_line_to*(c: Cairo, x, y: cdouble) {.importc, header: HC.}
proc cairo_curve_to*(c: Cairo, a, b, cc, d, e, f: cdouble) {.importc, header: HC.}
proc cairo_close_path*(c: Cairo) {.importc, header: HC.}
proc cairo_new_path*(c: Cairo) {.importc, header: HC.}
proc cairo_rectangle*(c: Cairo, x, y, w, h: cdouble) {.importc, header: HC.}
proc cairo_arc*(c: Cairo, xc, yc, r, a1, a2: cdouble) {.importc, header: HC.}
proc cairo_stroke*(c: Cairo) {.importc, header: HC.}
proc cairo_stroke_preserve*(c: Cairo) {.importc, header: HC.}
proc cairo_fill*(c: Cairo) {.importc, header: HC.}
proc cairo_fill_preserve*(c: Cairo) {.importc, header: HC.}
proc cairo_clip*(c: Cairo) {.importc, header: HC.}
proc cairo_set_line_width*(c: Cairo, w: cdouble) {.importc, header: HC.}
proc cairo_set_line_cap*(c: Cairo, v: cint) {.importc, header: HC.}
proc cairo_set_line_join*(c: Cairo, v: cint) {.importc, header: HC.}
proc cairo_set_miter_limit*(c: Cairo, v: cdouble) {.importc, header: HC.}
proc cairo_set_fill_rule*(c: Cairo, v: cint) {.importc, header: HC.}
proc cairo_set_antialias*(c: Cairo, v: cint) {.importc, header: HC.}
proc cairo_set_dash*(c: Cairo, d: ptr cdouble, n: cint, off: cdouble) {.importc, header: HC.}
proc cairo_device_to_user_distance*(c: Cairo, x, y: ptr cdouble) {.importc, header: HC.}
proc cairo_identity_matrix*(c: Cairo) {.importc, header: HC.}
proc cairo_select_font_face*(c: Cairo, f: cstring, s, w: cint) {.importc, header: HC.}
proc cairo_set_font_size*(c: Cairo, s: cdouble) {.importc, header: HC.}
proc cairo_show_text*(c: Cairo, s: cstring) {.importc, header: HC.}
var
  CAIRO_FORMAT_ARGB32* {.importc, header: HC, nodecl.}: cint
  CAIRO_FORMAT_RGB24* {.importc, header: HC, nodecl.}: cint
  CAIRO_FILL_RULE_EVEN_ODD* {.importc, header: HC, nodecl.}: cint
  CAIRO_FILL_RULE_WINDING* {.importc, header: HC, nodecl.}: cint
  CAIRO_ANTIALIAS_DEFAULT* {.importc, header: HC, nodecl.}: cint

proc str*(c: cstring): string = (if c == nil: "" else: $c)
proc text*(e: W): string = str(gtk_editable_get_text(e))
proc textOf*(view: W): string =
  let b = gtk_text_view_get_buffer(view)
  var s, e: TextIter
  gtk_text_buffer_get_start_iter(b, addr s)
  gtk_text_buffer_get_end_iter(b, addr e)
  let p = gtk_text_buffer_get_text(b, addr s, addr e, 0)
  result = str(p)
  g_free(p)

# ---------------------------------------------------------------- screenshots of our own window (tests, docs)
proc gtk_widget_paintable_new(w: W): W {.importc, header: HA.}
proc gtk_snapshot_new(): W {.importc, header: HA.}
proc gdk_paintable_snapshot(p, s: W, w, h: cdouble) {.importc, header: HA.}
proc gtk_snapshot_free_to_node(s: W): W {.importc, header: HA.}
proc gtk_native_get_renderer(w: W): W {.importc, header: HA.}
proc gsk_renderer_render_texture(r, node: W, viewport: pointer): W {.importc, header: HA.}
proc gdk_texture_save_to_png(t: W, path: cstring): cint {.importc, header: HA.}
proc gsk_render_node_unref(n: W) {.importc, header: HA.}
proc saveScreenshot*(window: W, path: string): bool =
  ## the window as GTK draws it, through its own renderer (works on Wayland without a portal)
  let p = gtk_widget_paintable_new(window)
  let s = gtk_snapshot_new()
  gdk_paintable_snapshot(p, s, cdouble(gtk_widget_get_width(window)), cdouble(gtk_widget_get_height(window)))
  let node = gtk_snapshot_free_to_node(s)
  g_object_unref(p)
  if node == nil:
    stderr.writeLine "screenshot: the window drew nothing (" & $gtk_widget_get_width(window) & "×" & $gtk_widget_get_height(window) & ")"
    return false
  let tex = gsk_renderer_render_texture(gtk_native_get_renderer(window), node, nil)
  gsk_render_node_unref(node)
  if tex == nil:
    stderr.writeLine "screenshot: the renderer made no texture"
    return false
  result = gdk_texture_save_to_png(tex, path.cstring) != 0
  if not result: stderr.writeLine "screenshot: could not write " & path
  g_object_unref(tex)

# drawing areas (the photo annotation editor)
proc gtk_drawing_area_new*(): W {.importc, header: HA.}
proc gtk_drawing_area_set_content_width*(a: W, w: cint) {.importc, header: HA.}
proc gtk_drawing_area_set_content_height*(a: W, h: cint) {.importc, header: HA.}
proc gtk_drawing_area_set_draw_func(a: W, fn: pointer, data: pointer, destroy: pointer) {.importc, header: HA.}
proc trampDraw(area: W, c: Cairo, w, h: cint, data: pointer) {.cdecl.} = guard: cast[Env](data).fnS(cast[Surface](c), int(w), int(h))
proc onDraw*(area: W, fn: proc (c: Cairo, w, h: int)) =
  let e = Env(fnS: proc (s: Surface, w, h: int) = fn(cast[Cairo](s), w, h))
  gtk_drawing_area_set_draw_func(area, cast[pointer](trampDraw), keep(e), cast[pointer](envDestroy))

# images from files (GdkTexture loaders: PNG, JPEG, WebP, … through glycin)
proc gdk_texture_new_from_filename(path: cstring, err: ptr ptr GError): W {.importc, header: HA.}
proc gdk_texture_download(t: W, data: pointer, stride: csize_t) {.importc, header: HA.}
proc loadImage*(path: string): (int, int, seq[byte]) =
  ## a picture file → (w, h, RGBA bytes, straight alpha); w = 0 when it can't be read
  var err: ptr GError
  let t = gdk_texture_new_from_filename(path.cstring, addr err)
  if err != nil:
    g_error_free(err)
    return (0, 0, @[])
  let w = int(gdk_texture_get_width(t))
  let h = int(gdk_texture_get_height(t))
  var buf = newSeq[byte](w * h * 4)
  gdk_texture_download(t, addr buf[0], csize_t(w * 4))   # CAIRO_FORMAT_ARGB32 layout: premultiplied B, G, R, A
  g_object_unref(t)
  var rgba = newSeq[byte](w * h * 4)
  for i in 0 ..< w * h:
    let a = int(buf[i * 4 + 3])
    template un(v: byte): byte = (if a == 0: 0'u8 else: byte(min(255, (int(v) * 255 + a div 2) div a)))
    rgba[i * 4] = un(buf[i * 4 + 2])
    rgba[i * 4 + 1] = un(buf[i * 4 + 1])
    rgba[i * 4 + 2] = un(buf[i * 4])
    rgba[i * 4 + 3] = byte(a)
  (w, h, rgba)
proc gtk_picture_new*(): W {.importc, header: HA.}
proc gtk_picture_set_paintable*(p, t: W) {.importc, header: HA.}
proc gtk_picture_set_can_shrink*(p: W, v: cint) {.importc, header: HA.}
proc gtk_widget_set_overflow*(w: W, o: cint) {.importc, header: HA.}
var GTK_OVERFLOW_HIDDEN* {.importc, header: HA, nodecl.}: cint
proc gtk_button_new*(): W {.importc, header: HA.}
proc gtk_button_set_child*(b, c: W) {.importc, header: HA.}
proc adw_banner_new*(title: cstring): W {.importc, header: HA.}
proc adw_banner_set_title*(b: W, t: cstring) {.importc, header: HA.}
proc adw_banner_set_button_label*(b: W, t: cstring) {.importc, header: HA.}
proc adw_banner_set_revealed*(b: W, v: cint) {.importc, header: HA.}
proc adw_navigation_view_push_by_tag*(v: W, tag: cstring) {.importc, header: HA.}
proc adw_navigation_view_pop_to_tag*(v: W, tag: cstring): cint {.importc, header: HA, discardable.}
proc adw_navigation_view_add*(v, page: W) {.importc, header: HA.}
proc adw_navigation_page_set_tag*(p: W, t: cstring) {.importc, header: HA.}
proc adw_navigation_page_new_with_tag*(child: W, title, tag: cstring): W {.importc, header: HA.}
proc gtk_widget_get_parent*(w: W): W {.importc, header: HA.}
proc gtk_widget_set_parent*(w, p: W) {.importc, header: HA.}

# ---------------------------------------------------------------- courses (decision 0036)
const
  HP = "<pango/pangocairo.h>"
  HF = "<fontconfig/fontconfig.h>"
{.passL: "-lfontconfig".}
var
  PANGO_SCALE* {.importc, header: HP, nodecl.}: cint
  GTK_ACCESSIBLE_PROPERTY_DESCRIPTION* {.importc, header: HA, nodecl.}: cint
  GTK_ACCESSIBLE_ROLE_IMG* {.importc, header: HA, nodecl.}: cint
proc pango_cairo_create_layout*(c: Cairo): W {.importc, header: HP.}
proc pango_layout_set_text*(l: W, t: cstring, n: cint) {.importc, header: HP.}
proc pango_font_description_from_string*(s: cstring): pointer {.importc, header: HP.}
proc pango_font_description_set_absolute_size*(d: pointer, size: cdouble) {.importc, header: HP.}
proc pango_layout_set_font_description*(l: W, d: pointer) {.importc, header: HP.}
proc pango_font_description_free*(d: pointer) {.importc, header: HP.}
proc pango_layout_get_baseline*(l: W): cint {.importc, header: HP.}
proc pango_layout_get_size*(l: W, w, h: ptr cint) {.importc, header: HP.}
proc pango_cairo_show_layout*(c: Cairo, l: W) {.importc, header: HP.}
proc cairo_rotate*(c: Cairo, a: cdouble) {.importc, header: HC.}
proc cairo_push_group*(c: Cairo) {.importc, header: HC.}
proc cairo_pop_group_to_source*(c: Cairo) {.importc, header: HC.}
proc cairo_paint_with_alpha*(c: Cairo, a: cdouble) {.importc, header: HC.}
proc cairo_pattern_create_radial*(cx0, cy0, r0, cx1, cy1, r1: cdouble): pointer {.importc, header: HC.}
proc cairo_pattern_add_color_stop_rgba*(p: pointer, off, r, g, b, a: cdouble) {.importc, header: HC.}
proc cairo_set_source*(c: Cairo, p: pointer) {.importc, header: HC.}
proc cairo_pattern_destroy*(p: pointer) {.importc, header: HC.}
var
  CAIRO_LINE_CAP_BUTT* {.importc, header: HC, nodecl.}: cint
  CAIRO_LINE_CAP_ROUND* {.importc, header: HC, nodecl.}: cint
  CAIRO_LINE_CAP_SQUARE* {.importc, header: HC, nodecl.}: cint
  CAIRO_LINE_JOIN_MITER* {.importc, header: HC, nodecl.}: cint
  CAIRO_LINE_JOIN_ROUND* {.importc, header: HC, nodecl.}: cint
  CAIRO_LINE_JOIN_BEVEL* {.importc, header: HC, nodecl.}: cint
proc FcConfigGetCurrent(): pointer {.importc, header: HF.}
proc FcConfigAppFontAddFile(c: pointer, f: cstring): cint {.importc, header: HF.}
proc addAppFont*(path: string): bool = FcConfigAppFontAddFile(FcConfigGetCurrent(), path.cstring) != 0

proc setAccessibleDescription*(w: W, text: string) =
  gtk_accessible_update_property_label(w, GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, text.cstring, -1)

# frame clock ticks
proc gtk_widget_add_tick_callback(w: W, fn: pointer, data: pointer, destroy: pointer): cuint {.importc, header: HA.}
proc gtk_widget_remove_tick_callback*(w: W, id: cuint) {.importc, header: HA.}
proc gdk_frame_clock_get_frame_time(c: W): int64 {.importc, header: HA.}
type TickEnv = ref object
  fn: proc (us: int64): bool
proc tickDestroy(data: pointer) {.cdecl.} = GC_unref(cast[TickEnv](data))
proc trampTick(w: W, clock: W, data: pointer): cint {.cdecl.} =
  result = 1
  guard: result = cint(cast[TickEnv](data).fn(gdk_frame_clock_get_frame_time(clock)))
proc onTick*(w: W, fn: proc (us: int64): bool): cuint {.discardable.} =
  ## every frame while `w` is mapped; fn gets the frame time (µs) and returns false to stop
  let e = TickEnv(fn: fn)
  GC_ref(e)
  gtk_widget_add_tick_callback(w, cast[pointer](trampTick), cast[pointer](e), cast[pointer](tickDestroy))

# sliders, radio groups, grids
proc gtk_scale_new_with_range*(o: cint, lo, hi, step: cdouble): W {.importc, header: HA.}
proc gtk_scale_set_draw_value*(s: W, v: cint) {.importc, header: HA.}
proc gtk_range_get_value*(r: W): cdouble {.importc, header: HA.}
proc gtk_range_set_value*(r: W, v: cdouble) {.importc, header: HA.}
proc gtk_check_button_set_group*(b, g: W) {.importc, header: HA.}
proc gtk_grid_new*(): W {.importc, header: HA.}
proc gtk_grid_attach*(g, child: W, col, row, w, h: cint) {.importc, header: HA.}
proc gtk_grid_set_row_spacing*(g: W, s: cuint) {.importc, header: HA.}
proc gtk_grid_set_column_spacing*(g: W, s: cuint) {.importc, header: HA.}
proc gtk_scrolled_window_get_vadjustment*(s: W): W {.importc, header: HA.}
proc gtk_adjustment_set_value*(a: W, v: cdouble) {.importc, header: HA.}
proc gtk_adjustment_get_value*(a: W): cdouble {.importc, header: HA.}
proc gtk_adjustment_get_page_size*(a: W): cdouble {.importc, header: HA.}
proc gtk_widget_compute_point(w, target: W, p, out1: pointer): cint {.importc, header: HA.}
proc yIn*(w, target: W): float =
  ## w's top edge in target's coordinates (NaN when they share no ancestor)
  var p: array[2, cfloat]
  var o: array[2, cfloat]
  if gtk_widget_compute_point(w, target, addr p, addr o) == 0: return NaN
  float(o[1])
proc gtk_label_set_use_markup*(l: W, v: cint) {.importc, header: HA.}
type LinkEnv = ref object
  fn: proc (uri: string): bool
proc linkDestroy(data: pointer, closure: pointer) {.cdecl.} = GC_unref(cast[LinkEnv](data))
proc trampLink2(l: W, uri: cstring, data: pointer): cint {.cdecl.} =
  result = 0
  guard: result = cint(cast[LinkEnv](data).fn($uri))
proc onLink*(label: W, fn: proc (uri: string): bool) =
  ## a markup link was activated; fn returns true when it handled the link (else GTK opens the URI)
  let e = LinkEnv(fn: fn)
  GC_ref(e)
  discard g_signal_connect_data(label, "activate-link", cast[GCallback](trampLink2), cast[pointer](e), cast[pointer](linkDestroy), 0)
proc gtk_settings_get_default*(): W {.importc, header: HA.}
proc g_object_get*(o: W, name: cstring) {.importc, header: HA, varargs.}
proc animationsEnabled*(): bool =
  var v: cint = 1
  g_object_get(gtk_settings_get_default(), "gtk-enable-animations", addr v, nil)
  v != 0
proc gtk_window_get_application*(w: W): W {.importc, header: HA.}
proc gtk_window_destroy*(w: W) {.importc, header: HA.}
proc g_object_new(t: uint, first: cstring): W {.importc, header: HA, varargs.}
proc gtk_label_get_type(): uint {.importc, header: HA.}
proc gtk_drawing_area_get_type(): uint {.importc, header: HA.}
var
  GTK_ACCESSIBLE_ROLE_HEADING* {.importc, header: HA, nodecl.}: cint
  GTK_ACCESSIBLE_PROPERTY_LEVEL* {.importc, header: HA, nodecl.}: cint
proc gtk_accessible_update_property_int(a: W, prop: cint, v: cint, last: cint) {.importc: "gtk_accessible_update_property", header: HA, varargs.}
proc headingLabel*(level: int): W =
  ## a GtkLabel that assistive technology reads as a heading of `level`
  result = g_object_new(gtk_label_get_type(), "accessible-role", GTK_ACCESSIBLE_ROLE_HEADING, nil)
  gtk_accessible_update_property_int(result, GTK_ACCESSIBLE_PROPERTY_LEVEL, cint(level), -1)
proc imageArea*(): W =
  ## a GtkDrawingArea exposed as an image (a course figure)
  g_object_new(gtk_drawing_area_get_type(), "accessible-role", GTK_ACCESSIBLE_ROLE_IMG, nil)
proc adw_clamp_new*(): W {.importc, header: HA.}
proc adw_clamp_set_maximum_size*(c: W, s: cint) {.importc, header: HA.}
proc adw_clamp_set_child*(c, w: W) {.importc, header: HA.}
proc cairo_new_sub_path*(c: Cairo) {.importc, header: HC.}
