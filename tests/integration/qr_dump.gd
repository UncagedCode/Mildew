extends SceneTree
## Dumps QrEncoder matrices for cross-checking against an independent encoder.
func _initialize() -> void:
	var cases := ["http://192.168.1.23:8080/?k=0123456789abcdef", "http://10.0.0.5:8080/", "HELLO",
		"http://192.168.100.200:8088/?k=ffffffffffffffff&room=ABCD", "http://172.16.254.254:8089/?k=0a1b2c3d4e5f6071&x=" + "y".repeat(60)]
	var out := []
	for text in cases:
		for ecl in [QrEncoder.ECL_M, QrEncoder.ECL_L]:
			for m in 8:
				var q := QrEncoder.encode(text, ecl, m)
				out.append({"text": text, "ecl": ecl, "mask": m, "version": q.version, "rows": Array(q.to_strings())})
			var auto := QrEncoder.encode(text, ecl)
			out.append({"text": text, "ecl": ecl, "mask": auto.mask, "version": auto.version, "rows": Array(auto.to_strings()), "auto": true})
	var f := FileAccess.open("res://tests/output/qr_dump.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	print("dumped ", out.size())
	quit()
