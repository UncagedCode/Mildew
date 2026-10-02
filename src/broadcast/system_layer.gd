class_name SystemLayer
extends Control
## Screen-space (1920x1080) layer OUTSIDE the fictional 4:3 programme.
## Everything real lives here: join instructions/QR, genuine connection holds, pause menu.
## Fictional effects never draw on this layer, so real status can never be disguised
## (docs/01 #88-89, docs/13 networking boundaries).

const SW := 1920.0
const SH := 1080.0

var f_sans: Font
var f_mono: Font
var f_display: Font
var _t := 0.0

var join_visible := 0.0
var join_target := 0.0
var qr_tex: Texture2D
var short_url := ""
var room_code := ""
var dev_hint := ""          # debug builds only: phone dev panel address + PIN
var contestants := 0
var min_players := 2
var max_players := 8
var network_ok := true
var network_error := ""
var late_hint := false

var hold_reason := ""
var hold_detail: Dictionary = {}
var hold_since := 0.0

var pause_items: Array = []        # [{label, value?, desc?}]
var pause_selected := 0
var pause_title := "TRANSMISSION PAUSED"
var toast_text := ""
var _toast_until := 0.0


func _ready() -> void:
	f_sans = load("res://assets/fonts/LiberationSans-Bold.ttf")
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	f_display = load("res://assets/fonts/InterDisplay-BlackItalic.otf")
	size = Vector2(SW, SH)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_join(url_for_qr: String, p_short_url: String, code: String) -> void:
	short_url = p_short_url
	room_code = code
	var q := QrEncoder.encode(url_for_qr, QrEncoder.ECL_M)
	if q.is_valid():
		qr_tex = ImageTexture.create_from_image(q.to_image(10))


func toast(text: String, seconds: float = 4.0) -> void:
	toast_text = text
	_toast_until = _t + seconds


func _process(delta: float) -> void:
	_t += delta
	join_visible = move_toward(join_visible, join_target, delta * 2.5)
	queue_redraw()


func _draw() -> void:
	_draw_pillars()
	if join_visible > 0.0:
		_draw_join(join_visible)
	elif late_hint and room_code != "":
		_draw_late_hint()
	if hold_reason != "":
		_draw_hold()
	if not network_ok:
		_draw_banner("THIS TELEVISION CANNOT HOST CONTROLLERS", network_error + "  Check Wi-Fi, then restart the transmission.", Color(0.55, 0.0, 0.0))
	if not pause_items.is_empty():
		_draw_pause()
	if _t < _toast_until and toast_text != "":
		var tw := f_sans.get_string_size(toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var r := Rect2((SW - tw) * 0.5 - 24, SH - 120, tw + 48, 60)
		draw_rect(r, Color(0, 0, 0, 0.85))
		draw_string(f_sans, Vector2(r.position.x + 24, r.position.y + 41), toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)


func _draw_pillars() -> void:
	# Restrained receiver surround; faint metadata only.
	for x in [0.0, SW - 240.0]:
		draw_rect(Rect2(x, 0, 240, SH), Color(0.03, 0.025, 0.04))
	draw_string(f_mono, Vector2(20, SH - 24), "SALLOW ENTERTAINMENT LTD", HORIZONTAL_ALIGNMENT_LEFT, 220, 12, Color(1, 1, 1, 0.12))


func _draw_join(vis: float) -> void:
	var x0 := 1140.0 + (1.0 - vis) * 300.0
	var a := vis
	var panel := Rect2(x0, 80, 720, 930)
	draw_rect(panel, Color(0, 0, 0, 0.92 * a))
	# Teletext-style header bar
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 64)), Color(0.0, 0.0, 0.75, a))
	draw_string(f_mono, panel.position + Vector2(20, 44), "P888  MILDEW  CONTESTANT ENTRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 0, a))
	draw_string(f_mono, panel.position + Vector2(36, 120), "SCAN TO TAKE PART:", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0, 1, 1, a))
	if qr_tex:
		var qs := 400.0
		var qr_r := Rect2(panel.position + Vector2((panel.size.x - qs) * 0.5, 150), Vector2(qs, qs))
		draw_texture_rect(qr_tex, qr_r, false, Color(1, 1, 1, a))
	var y := panel.position.y + 610
	draw_string(f_mono, Vector2(panel.position.x + 36, y), "OR VISIT ON YOUR PHONE:", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0, 1, 1, a))
	draw_string(f_mono, Vector2(panel.position.x + 36, y + 52), short_url.replace("http://", ""), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 60, 42, Color(1, 1, 1, a))
	draw_string(f_mono, Vector2(panel.position.x + 36, y + 112), "BROADCAST CODE:", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0, 1, 1, a))
	draw_string(f_mono, Vector2(panel.position.x + 330, y + 118), room_code, HORIZONTAL_ALIGNMENT_LEFT, -1, 72, Color(1, 1, 0, a))
	var count_col := Color(0.3, 1, 0.3, a) if contestants >= min_players else Color(1, 0.6, 0.2, a)
	draw_string(f_mono, Vector2(panel.position.x + 36, y + 184), "CONTESTANTS: %d/%d   MINIMUM %d" % [contestants, max_players, min_players], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, count_col)
	draw_string(f_mono, Vector2(panel.position.x + 36, y + 228), "SAME WI-FI AS THIS TV · NO INTERNET NEEDED", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.8, 0.8, 0.8, a))
	if contestants >= min_players:
		var blink := 0.6 + 0.4 * sin(_t * 5.0)
		var hint_col := Color(1, 1, 0, a * blink)
		draw_string(f_mono, Vector2(panel.position.x + 36, y + 266), "FLOOR CAPTAIN: PRESS BEGIN ON YOUR PHONE", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 60, 20, hint_col)
		draw_string(f_mono, Vector2(panel.position.x + 36, y + 292), "(OR OK ON THE REMOTE)", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 60, 20, hint_col)
	if dev_hint != "":
		draw_rect(Rect2(panel.position.x, panel.end.y + 12, panel.size.x, 40), Color(0.35, 0.12, 0.0, 0.9 * a))
		draw_string(f_mono, Vector2(panel.position.x + 16, panel.end.y + 40), dev_hint, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 24, 22, Color(1, 0.75, 0.3, a))


func _draw_late_hint() -> void:
	draw_string(f_mono, Vector2(SW - 232, 40), "JOIN: " + room_code, HORIZONTAL_ALIGNMENT_LEFT, 220, 22, Color(1, 1, 1, 0.45))
	draw_string(f_mono, Vector2(SW - 232, 66), short_url.replace("http://", ""), HORIZONTAL_ALIGNMENT_LEFT, 224, 14, Color(1, 1, 1, 0.35))
	if dev_hint != "":
		draw_string(f_mono, Vector2(SW - 232, 88), "DEV PIN " + dev_hint.get_slice("PIN ", 1), HORIZONTAL_ALIGNMENT_LEFT, 224, 14, Color(1, 0.7, 0.3, 0.35))


func _draw_hold() -> void:
	match hold_reason:
		"reconnect":
			var names: Array = []
			var remaining := 0.0
			for l in hold_detail.get("lost", []):
				names.append(str(l.get("name", "?")))
				remaining = maxf(remaining, float(l.get("remaining", 0)) - (_t - hold_since))
			_draw_banner("WAITING FOR %s TO RECONNECT" % ", ".join(names).to_upper(),
				"Connection lost (real).  Up to %d s, then the programme continues without them." % int(ceil(maxf(0.0, remaining))), Color(0.6, 0.05, 0.05))
		"players":
			_draw_banner("WAITING FOR CONTESTANTS", "At least two are needed. Join with the code " + room_code + " · " + short_url.replace("http://", ""), Color(0.08, 0.08, 0.1))
		"manual":
			pass  # the pause menu itself is shown


func _draw_banner(title: String, detail: String, col: Color) -> void:
	var r := Rect2(0, 0, SW, 104)
	draw_rect(r, Color(col, 0.96))
	draw_string(f_sans, Vector2(0, 50), title, HORIZONTAL_ALIGNMENT_CENTER, SW, 40, Color.WHITE)
	draw_string(f_sans, Vector2(0, 88), detail, HORIZONTAL_ALIGNMENT_CENTER, SW, 24, Color(1, 1, 1, 0.9))


func _draw_pause() -> void:
	draw_rect(Rect2(0, 0, SW, SH), Color(0, 0, 0, 0.72))
	draw_string(f_display, Vector2(0, 250), pause_title, HORIZONTAL_ALIGNMENT_CENTER, SW, 80, Color.WHITE)
	for i in pause_items.size():
		var it: Dictionary = pause_items[i]
		var sel := i == pause_selected
		var r := Rect2(SW * 0.5 - 380, 330 + i * 86, 760, 70)
		draw_rect(r, Color(1, 1, 1, 0.95) if sel else Color(0.15, 0.15, 0.18, 0.95))
		var label := str(it.get("label", ""))
		if it.has("value"):
			label += ":  " + str(it.value)
		draw_string(f_sans, Vector2(r.position.x, r.position.y + 47), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 34, Color.BLACK if sel else Color.WHITE)
	if pause_selected < pause_items.size():
		var desc := str(pause_items[pause_selected].get("desc", ""))
		var y := 330 + pause_items.size() * 86 + 30
		for line in GraphicsLayer._wrap(desc, 80):
			draw_string(f_sans, Vector2(0, y), line, HORIZONTAL_ALIGNMENT_CENTER, SW, 24, Color(0.85, 0.85, 0.85))
			y += 32
	draw_string(f_sans, Vector2(0, SH - 50), "Remote: ▲▼ select · OK confirm · BACK resume", HORIZONTAL_ALIGNMENT_CENTER, SW, 22, Color(0.7, 0.7, 0.7))
