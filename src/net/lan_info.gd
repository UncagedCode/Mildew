class_name LanInfo
extends RefCounted
## Picks the host's most plausible home-LAN IPv4 address for the join URL / QR code.


static func candidates() -> Array:
	var out: Array = []
	for iface in IP.get_local_interfaces():
		var name := str(iface.get("name", "")).to_lower()
		for addr in iface.get("addresses", []):
			var a := str(addr)
			if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254.") or a == "0.0.0.0":
				continue
			out.append({"addr": a, "iface": name, "score": _score(a, name)})
	if out.is_empty():
		for a in IP.get_local_addresses():
			if not a.contains(":") and not a.begins_with("127.") and not a.begins_with("169.254."):
				out.append({"addr": a, "iface": "?", "score": _score(a, "")})
	out.sort_custom(func(x, y): return x.score > y.score)
	return out


static func best_ipv4() -> String:
	var c := candidates()
	return c[0].addr if not c.is_empty() else ""


static func _score(a: String, iface: String) -> int:
	var s := 0
	if a.begins_with("192.168."):
		s += 30
	elif a.begins_with("10."):
		s += 20
	elif a.begins_with("172."):
		var second := int(a.split(".")[1])
		s += 20 if second >= 16 and second <= 31 else 0
	if iface.begins_with("wlan") or iface.begins_with("eth") or iface.begins_with("en") or iface.begins_with("wl"):
		s += 10
	for bad in ["docker", "veth", "br-", "tun", "tap", "rmnet", "p2p", "virbr", "lo"]:
		if iface.begins_with(bad):
			s -= 25
	return s
