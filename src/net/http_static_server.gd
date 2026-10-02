class_name HttpStaticServer
extends RefCounted
## Tiny HTTP/1.1 static file server for the phone controller bundle (GET/HEAD only,
## Connection: close). Pure GDScript over TCPServer so it runs on any Godot host
## (Android TV now; other hosts later) with no platform code.
## Security: LAN-only party use; path traversal rejected; request size/time limited.

const MIME := {
	"html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8",
	"json": "application/json; charset=utf-8", "png": "image/png", "svg": "image/svg+xml", "ico": "image/x-icon",
	"ttf": "font/ttf", "otf": "font/otf", "woff2": "font/woff2", "txt": "text/plain; charset=utf-8", "webmanifest": "application/manifest+json",
}

var root := "res://controller"
var port := 0
var max_request_bytes := 8192
var request_timeout_ms := 10000
var dynamic_routes := {}         # "/path" -> Callable() -> {status:int, type:String, body:PackedByteArray}
var requests_served := 0
var requests_rejected := 0
var last_error := ""

var _server := TCPServer.new()
var _clients: Array = []
var _cache := {}


func start(first_port: int, span: int, bind_address: String = "*") -> bool:
	for p in range(first_port, first_port + maxi(1, span)):
		if _server.listen(p, bind_address) == OK:
			port = p
			return true
	last_error = "could not bind HTTP ports %d-%d" % [first_port, first_port + span - 1]
	return false


func stop() -> void:
	for c in _clients:
		c.peer.disconnect_from_host()
	_clients.clear()
	_server.stop()
	port = 0


func is_listening() -> bool:
	return _server.is_listening()


func poll() -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			break
		peer.set_no_delay(true)
		_clients.append({"peer": peer, "buf": PackedByteArray(), "t0": Time.get_ticks_msec(), "out": PackedByteArray(), "sent": 0, "responded": false})
	var keep: Array = []
	for c in _clients:
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		var st := peer.get_status()
		if st != StreamPeerTCP.STATUS_CONNECTED:
			continue
		if not c.responded:
			var avail := peer.get_available_bytes()
			if avail > 0:
				var res := peer.get_partial_data(avail)
				if res[0] == OK:
					c.buf.append_array(res[1])
			if c.buf.size() > max_request_bytes:
				_respond(c, 413, "text/plain", "Request too large".to_utf8_buffer())
			else:
				var text: String = c.buf.get_string_from_ascii()
				if text.contains("\r\n\r\n"):
					_handle(c, text)
				elif Time.get_ticks_msec() - int(c.t0) > request_timeout_ms:
					peer.disconnect_from_host()
					continue
		if c.responded:
			if c.sent < c.out.size():
				var chunk: PackedByteArray = c.out.slice(c.sent, mini(c.sent + 16384, c.out.size()))
				var wr := peer.put_partial_data(chunk)
				if wr[0] == OK:
					c.sent += int(wr[1])
			if c.sent >= c.out.size():
				peer.disconnect_from_host()
				continue
			if Time.get_ticks_msec() - int(c.t0) > request_timeout_ms * 3:
				peer.disconnect_from_host()
				continue
		keep.append(c)
	_clients = keep


func _handle(c: Dictionary, text: String) -> void:
	var first := text.split("\r\n", false, 1)[0] if text.length() > 0 else ""
	var parts := first.split(" ")
	if parts.size() < 3:
		_respond(c, 400, "text/plain", "Bad request".to_utf8_buffer())
		return
	var method := parts[0]
	if method != "GET" and method != "HEAD":
		_respond(c, 405, "text/plain", "Method not allowed".to_utf8_buffer())
		return
	var path := parts[1].split("?", true, 1)[0].uri_decode()
	if path == "" or path == "/":
		path = "/index.html"
	if path.contains("..") or path.contains("\\") or not path.begins_with("/"):
		requests_rejected += 1
		_respond(c, 400, "text/plain", "Bad path".to_utf8_buffer())
		return
	if dynamic_routes.has(path):
		var r: Dictionary = dynamic_routes[path].call()
		_respond(c, int(r.get("status", 200)), str(r.get("type", "application/json")), r.get("body", PackedByteArray()), method == "HEAD")
		return
	var body := _load(path)
	if body.is_empty():
		_respond(c, 404, "text/plain", "Not found".to_utf8_buffer(), method == "HEAD")
		return
	var ext := path.get_extension().to_lower()
	_respond(c, 200, MIME.get(ext, "application/octet-stream"), body, method == "HEAD")


func _load(path: String) -> PackedByteArray:
	if _cache.has(path):
		return _cache[path]
	var full := root + path
	if not FileAccess.file_exists(full):
		return PackedByteArray()
	var data := FileAccess.get_file_as_bytes(full)
	_cache[path] = data
	return data


func _respond(c: Dictionary, status: int, type: String, body: PackedByteArray, head_only: bool = false) -> void:
	var reason: String = {200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"}.get(status, "OK")
	var headers := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-cache\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n" % [status, reason, type, body.size()]
	var out := headers.to_utf8_buffer()
	if not head_only:
		out.append_array(body)
	c.out = out
	c.sent = 0
	c.responded = true
	requests_served += 1
