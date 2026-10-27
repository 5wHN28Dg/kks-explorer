## Android's side of a LAN session (docs/plant3d/MULTIPLAYER.md §9.3, §7.5): Android filters the Wi-Fi's broadcasts
## unless the app holds a WifiManager.MulticastLock (the CHANGE_WIFI_MULTICAST_STATE permission, normal, granted at
## install), taken while the app hosts or plays a session and released when it ends; reached through Godot's
## AndroidRuntime plugin and its JavaClassWrapper proxies, as ui/links_in.gd reads the Intent. Nothing elsewhere.
extends RefCounted

static var _lock = null
static var held := false


## Takes (on) or releases (off) the multicast lock; "" or why not.
static func multicast(on: bool) -> String:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return ""
	var rt = Engine.get_singleton("AndroidRuntime")
	if on:
		if _lock == null:
			var ctx = rt.getApplicationContext()
			if ctx == null:
				return "no application context"
			var wifi = ctx.getSystemService("wifi")
			if wifi == null:
				return "no Wi-Fi service"
			_lock = wifi.createMulticastLock("walkdown-plant")
			if _lock == null:
				return "no multicast lock"
			_lock.setReferenceCounted(false)
		_lock.acquire()
		held = bool(_lock.isHeld())
		return "" if held else "the multicast lock was not taken"
	if _lock != null:
		_lock.release()
		held = bool(_lock.isHeld())
	return ""
