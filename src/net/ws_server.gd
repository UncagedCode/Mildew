class_name WsServer
extends RefCounted
## WebSocket server for phone controllers (pure GDScript: TCPServer + WebSocketPeer).

signal client_connected(ws_id: int, addr: String)
signal client_text(ws_id: int, text: String)
signal client_disconnected(ws_id: int, code: int, reason: String)

var port := 0
var handshake_timeout_ms := 5000
var last_error := ""

var _tcp := TCPServer.new()
var _pending: Array = []
var _peers := {}          # ws_id -> {ws: WebSocketPeer, addr}
var _next_id := 1


func start(first_port: int, span: int, bind_address: String = "*") -> bool:
	for p in range(first_port, first_port + maxi(1, span)):
		if _tcp.listen(p, bind_address) == OK:
			port = p
			return true
	last_error = "could not bind WebSocket ports %d-%d" % [first_port, first_port + span - 1]
	return false


func stop() -> void:
	for id in _peers.keys():
		_peers[id].ws.close(1001, "host stopped")
	_peers.clear()
	_pending.clear()
	_tcp.stop()
	port = 0


func peer_count() -> int:
	return _peers.size()


func poll() -> void:
	if not _tcp.is_listening():
		return
	while _tcp.is_connection_available():
		var conn := _tcp.take_connection()
		if conn == null:
			break
		conn.set_no_delay(true)
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 65536
		ws.outbound_buffer_size = 262144
		ws.max_queued_packets = 1024
		var addr := conn.get_connected_host()
		if ws.accept_stream(conn) == OK:
			_pending.append({"ws": ws, "addr": addr, "t0": Time.get_ticks_msec()})
	var still: Array = []
	for p in _pending:
		p.ws.poll()
		var st: int = p.ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			var id := _next_id
			_next_id += 1
			_peers[id] = {"ws": p.ws, "addr": p.addr}
			client_connected.emit(id, p.addr)
		elif st == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() - int(p.t0) < handshake_timeout_ms:
			still.append(p)
	_pending = still
	for id in _peers.keys():
		var entry: Dictionary = _peers[id]
		var ws: WebSocketPeer = entry.ws
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if ws.was_string_packet():
				client_text.emit(id, pkt.get_string_from_utf8())
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_peers.erase(id)
			client_disconnected.emit(id, ws.get_close_code(), ws.get_close_reason())


func send_text(ws_id: int, text: String) -> void:
	var entry = _peers.get(ws_id)
	if entry != null and entry.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		entry.ws.send_text(text)


func close(ws_id: int, code: int = 1000, reason: String = "") -> void:
	var entry = _peers.get(ws_id)
	if entry != null:
		entry.ws.close(code, reason)
