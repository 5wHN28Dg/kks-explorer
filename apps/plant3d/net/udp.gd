## A UDP socket of the session (docs/plant3d/MULTIPLAYER.md §9.2, §9.3). Every socket the app opens is opened here,
## and counted: outside a session the app opens none (§8.5, §12: tests/test_net_no_network.gd).
extends RefCounted

static var opened := 0          # sockets opened in this process
static var open_now := 0        # sockets open now

var sock: PacketPeerUDP
var port := 0
var sent := 0                   # packets and bytes, both ways (the measurements)
var sent_bytes := 0
var got := 0
var got_bytes := 0


## Binds to `port` (0: any free one) on `address` ("*": dual-stack, every interface; "0.0.0.0": IPv4 only, which the
## LAN query's broadcasts need).
func open(p: int, address := "*", broadcast := false) -> Error:
	sock = PacketPeerUDP.new()
	if broadcast:
		sock.set_broadcast_enabled(true)
	var err := sock.bind(p, address)
	if err != OK:
		sock = null
		return err
	opened += 1
	open_now += 1
	port = sock.get_local_port()
	return OK


func is_open() -> bool:
	return sock != null


func send(ip: String, p: int, bytes: PackedByteArray) -> void:
	if sock == null or ip == "" or p <= 0:
		return
	sock.set_dest_address(ip, p)
	if sock.put_packet(bytes) == OK:
		sent += 1
		sent_bytes += bytes.size()


## The packets waiting: [[bytes, ip, port], …] (at most `limit`, so that a flood can't hold a frame).
func poll(limit := 512) -> Array:
	var out := []
	if sock == null:
		return out
	while sock.get_available_packet_count() > 0 and out.size() < limit:
		var b := sock.get_packet()
		var ip := sock.get_packet_ip()
		var p := sock.get_packet_port()
		if sock.get_packet_error() != OK:
			continue
		got += 1
		got_bytes += b.size()
		out.append([b, ip, p])
	return out


func close() -> void:
	if sock != null:
		sock.close()
		sock = null
		open_now -= 1
