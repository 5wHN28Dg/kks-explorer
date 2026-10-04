## mDNS on Linux through Avahi's D-Bus API, using GIO's GDBus (decisions 0002, 0030): announce `_kks._tcp` with its
## TXT record (PROTOCOL-v2 §16) and browse for other devices. GLib's main context is pumped from the asyncdispatch loop
## (`pump`), so callbacks run on the loop's thread like everything else. Nothing here may block that thread: a found
## service is resolved asynchronously (until 2026-10-04 it was a synchronous call, and each device that didn't answer
## held the GNOME app's window back by Avahi's 5 s timeout: 20-40 s on a network with a few of them).

{.passC: gorge("pkg-config --cflags gio-2.0").}
{.passL: gorge("pkg-config --libs gio-2.0").}

const HG = "<gio/gio.h>"

type
  GDBusConnection {.importc, header: HG, incompleteStruct.} = object
  GVariant {.importc, header: HG, incompleteStruct.} = object
  GVariantType {.importc, header: HG, incompleteStruct.} = object
  GVariantBuilder {.importc, header: HG, incompleteStruct.} = object
  GError {.importc, header: HG.} = object
    message {.importc.}: cstring
  GSignalCb {.importc: "GDBusSignalCallback", header: HG.} = pointer

var
  G_BUS_TYPE_SYSTEM {.importc, header: HG, nodecl.}: cint
  G_DBUS_CALL_FLAGS_NONE {.importc, header: HG, nodecl.}: cint
  G_DBUS_SIGNAL_FLAGS_NONE {.importc, header: HG, nodecl.}: cint

proc g_bus_get_sync(t: cint, cancel: pointer, err: ptr ptr GError): ptr GDBusConnection {.importc, header: HG.}
proc g_dbus_connection_call_sync(c: ptr GDBusConnection, name, path, iface, meth: cstring, params: ptr GVariant,
                                 replyType: ptr GVariantType, flags: cint, timeout: cint, cancel: pointer,
                                 err: ptr ptr GError): ptr GVariant {.importc, header: HG.}
proc g_dbus_connection_call(c: ptr GDBusConnection, name, path, iface, meth: cstring, params: ptr GVariant,
                            replyType: ptr GVariantType, flags: cint, timeout: cint, cancel: pointer,
                            cb: pointer, data: pointer) {.importc, header: HG.}
proc g_dbus_connection_call_finish(c: ptr GDBusConnection, res: pointer, err: ptr ptr GError): ptr GVariant {.importc, header: HG.}
proc g_dbus_connection_signal_subscribe(c: ptr GDBusConnection, sender, iface, member, path, arg0: cstring, flags: cint,
                                        cb: GSignalCb, data: pointer, free: pointer): cuint {.importc, header: HG.}
proc g_main_context_iteration(ctx: pointer, mayBlock: cint): cint {.importc, header: HG.}
proc g_error_free(e: ptr GError) {.importc, header: HG.}
proc g_variant_new_int32(v: int32): ptr GVariant {.importc, header: HG.}
proc g_variant_new_uint32(v: uint32): ptr GVariant {.importc, header: HG.}
proc g_variant_new_uint16(v: uint16): ptr GVariant {.importc, header: HG.}
proc g_variant_new_string(v: cstring): ptr GVariant {.importc, header: HG.}
proc g_variant_new_tuple(items: ptr ptr GVariant, n: csize_t): ptr GVariant {.importc, header: HG.}
proc g_variant_new_fixed_array(t: ptr GVariantType, data: pointer, n: csize_t, size: csize_t): ptr GVariant {.importc, header: HG.}
proc g_variant_type_new(s: cstring): ptr GVariantType {.importc, header: HG.}
proc g_variant_builder_new(t: ptr GVariantType): ptr GVariantBuilder {.importc, header: HG.}
proc g_variant_builder_add_value(b: ptr GVariantBuilder, v: ptr GVariant) {.importc, header: HG.}
proc g_variant_builder_end(b: ptr GVariantBuilder): ptr GVariant {.importc, header: HG.}
proc g_variant_builder_unref(b: ptr GVariantBuilder) {.importc, header: HG.}
proc g_variant_get_child_value(v: ptr GVariant, i: csize_t): ptr GVariant {.importc, header: HG.}
proc g_variant_n_children(v: ptr GVariant): csize_t {.importc, header: HG.}
proc g_variant_get_string(v: ptr GVariant, n: pointer): cstring {.importc, header: HG.}
proc g_variant_get_int32(v: ptr GVariant): int32 {.importc, header: HG.}
proc g_variant_get_uint16(v: ptr GVariant): uint16 {.importc, header: HG.}
proc g_variant_get_fixed_array(v: ptr GVariant, n: ptr csize_t, size: csize_t): pointer {.importc, header: HG.}
proc g_variant_unref(v: ptr GVariant) {.importc, header: HG.}

const
  Avahi = "org.freedesktop.Avahi"
  Unspec = -1'i32
  ServiceType* = "_kks._tcp"

type
  Found* = object
    name*, host*, address*: string
    port*: int
    txt*: seq[(string, string)]

  MdnsError* = object of CatchableError

  Mdns* = ref object
    bus: ptr GDBusConnection
    group: string               ## our entry group's object path
    onFound*: proc (f: Found)
    onGone*: proc (name: string)
    found*: seq[Found]

proc check(err: ptr GError, what: string) =
  if err != nil:
    let m = $err.message
    g_error_free(err)
    raise newException(MdnsError, what & ": " & m)

proc call(m: Mdns, path, iface, meth: string, args: seq[ptr GVariant]): ptr GVariant =
  var err: ptr GError
  var a = args
  let params = g_variant_new_tuple(if a.len > 0: addr a[0] else: nil, csize_t(a.len))
  result = g_dbus_connection_call_sync(m.bus, Avahi, path.cstring, iface.cstring, meth.cstring, params, nil,
                                       G_DBUS_CALL_FLAGS_NONE, 10000, nil, addr err)
  check(err, meth)

proc str(v: ptr GVariant, i: int): string =
  let c = g_variant_get_child_value(v, csize_t(i))
  result = $g_variant_get_string(c, nil)
  g_variant_unref(c)

proc newMdns*(): Mdns =
  var err: ptr GError
  result = Mdns(bus: g_bus_get_sync(G_BUS_TYPE_SYSTEM, nil, addr err))
  check(err, "system bus")

proc txtArray(txt: seq[(string, string)]): ptr GVariant =
  let b = g_variant_builder_new(g_variant_type_new("aay"))
  for (k, v) in txt:
    var item = k & "=" & v
    g_variant_builder_add_value(b, g_variant_new_fixed_array(g_variant_type_new("y"), addr item[0], csize_t(item.len), 1))
  result = g_variant_builder_end(b)
  g_variant_builder_unref(b)

proc announce*(m: Mdns, name: string, port: int, txt: seq[(string, string)]) =
  ## Publish (or re-publish with new TXT) this device's service.
  if m.group.len == 0:
    let r = m.call("/", "org.freedesktop.Avahi.Server", "EntryGroupNew", @[])
    m.group = r.str(0)
    g_variant_unref(r)
  else:
    discard m.call(m.group, "org.freedesktop.Avahi.EntryGroup", "Reset", @[])
  discard m.call(m.group, "org.freedesktop.Avahi.EntryGroup", "AddService", @[
    g_variant_new_int32(Unspec), g_variant_new_int32(Unspec), g_variant_new_uint32(0), g_variant_new_string(name.cstring),
    g_variant_new_string(ServiceType), g_variant_new_string(""), g_variant_new_string(""), g_variant_new_uint16(uint16(port)),
    txtArray(txt)])
  discard m.call(m.group, "org.freedesktop.Avahi.EntryGroup", "Commit", @[])

proc resolved(r: ptr GVariant): Found =
  ## Avahi's ResolveService answer (iface, proto, name, type, domain, host, aproto, address, port, txt, flags)
  result = Found(name: r.str(2), host: r.str(5), address: r.str(7))
  let pv = g_variant_get_child_value(r, 8)
  result.port = int(g_variant_get_uint16(pv))
  g_variant_unref(pv)
  let tv = g_variant_get_child_value(r, 9)
  for i in 0 ..< int(g_variant_n_children(tv)):
    let item = g_variant_get_child_value(tv, csize_t(i))
    var n: csize_t
    let data = cast[ptr UncheckedArray[char]](g_variant_get_fixed_array(item, addr n, 1))
    var s = newString(int(n))
    for k in 0 ..< int(n): s[k] = data[k]
    let eq = s.find('=')
    if eq > 0: result.txt.add((s[0 ..< eq], s[eq + 1 .. ^1]))
    g_variant_unref(item)
  g_variant_unref(tv)

proc onResolved(src: pointer, res: pointer, data: pointer) {.cdecl.} =
  let m = cast[Mdns](data)
  var err: ptr GError
  let r = g_dbus_connection_call_finish(m.bus, res, addr err)
  if err != nil:
    g_error_free(err)          # gone again, or it didn't answer in time
    return
  try:
    let f = resolved(r)
    var known = false
    for x in m.found:
      if x.name == f.name: known = true
    if not known:
      m.found.add f
      if m.onFound != nil: m.onFound(f)
  except CatchableError: discard    # never unwind through GLib
  finally: g_variant_unref(r)

proc resolve(m: Mdns, iface, proto: int32, name, typ, domain: string) =
  ## ask Avahi for the service's address, port and TXT; the answer comes to onResolved
  var a = @[g_variant_new_int32(iface), g_variant_new_int32(proto), g_variant_new_string(name.cstring),
            g_variant_new_string(typ.cstring), g_variant_new_string(domain.cstring), g_variant_new_int32(0),   # IPv4
            g_variant_new_uint32(0)]
  let params = g_variant_new_tuple(addr a[0], csize_t(a.len))
  g_dbus_connection_call(m.bus, Avahi, "/", "org.freedesktop.Avahi.Server", "ResolveService", params, nil,
                         G_DBUS_CALL_FLAGS_NONE, 10000, nil, cast[pointer](onResolved), cast[pointer](m))

proc onSignal(c: ptr GDBusConnection, sender, path, iface, signal: cstring, params: ptr GVariant, data: pointer) {.cdecl.} =
  let m = cast[Mdns](data)
  let name = params.str(2)
  if $signal == "ItemNew":
    var known = false
    for x in m.found:
      if x.name == name: known = true
    if known: return             # the same device again on another interface or protocol
    let i0 = g_variant_get_child_value(params, 0)
    let i1 = g_variant_get_child_value(params, 1)
    let iface = g_variant_get_int32(i0)
    let proto = g_variant_get_int32(i1)
    g_variant_unref(i0)
    g_variant_unref(i1)
    m.resolve(iface, proto, name, params.str(3), params.str(4))
  elif $signal == "ItemRemove":
    var kept: seq[Found]
    for x in m.found:
      if x.name != name: kept.add x
    m.found = kept
    if m.onGone != nil: m.onGone(name)

proc browse*(m: Mdns) =
  ## Start finding `_kks._tcp` services. Subscribe first, then create the browser (Avahi may signal at once).
  GC_ref(m)
  for sig in ["ItemNew", "ItemRemove"]:
    discard g_dbus_connection_signal_subscribe(m.bus, Avahi, "org.freedesktop.Avahi.ServiceBrowser", sig.cstring, nil, nil,
                                               G_DBUS_SIGNAL_FLAGS_NONE, cast[GSignalCb](onSignal), cast[pointer](m), nil)
  let r = m.call("/", "org.freedesktop.Avahi.Server", "ServiceBrowserNew", @[
    g_variant_new_int32(Unspec), g_variant_new_int32(Unspec), g_variant_new_string(ServiceType), g_variant_new_string(""),
    g_variant_new_uint32(0)])
  g_variant_unref(r)

proc pump*(m: Mdns) =
  ## Run GLib's pending events (signals) without blocking.
  while g_main_context_iteration(nil, 0) != 0: discard
