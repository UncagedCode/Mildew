class_name PodiumScreen
extends Control
## The little CRT built into each contestant podium (rendered in its own SubViewport).
## Shows avatar, name, score, answer lamp. Connection state shown here is REAL.

var info: Dictionary = {}
var lit := 0.0
var flash := 0.0
var show_score := false
var delta_text := ""
var _t := 0.0
var _font: Font
var _mono: Font


func _ready() -> void:
	_font = load("res://assets/fonts/LiberationSans-Bold.ttf")
	_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")


func set_info(d: Dictionary) -> void:
	info = d
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	flash = maxf(0.0, flash - delta * 1.5)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("#0b0f26"))
	var connected: bool = info.get("connected", true)
	var avatar_rect := Rect2(Vector2(10, 10), Vector2(size.y - 60, size.y - 60))
	if connected:
		AvatarPainter.draw(self, avatar_rect, info.get("avatar", {}))
	else:
		# Real disconnection: plain, unambiguous.
		draw_rect(avatar_rect, Color(0.1, 0.1, 0.1))
		draw_string(_mono, avatar_rect.position + Vector2(8, avatar_rect.size.y * 0.55), "NO LINK", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.35, 0.3))
	var x := avatar_rect.end.x + 12
	draw_string(_mono, Vector2(x, 40), "No.%d" % int(info.get("number", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#7fe0d8"))
	var score := int(info.get("score", 0))
	draw_string(_mono, Vector2(x, 84), _fmt(score), HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 6, 34, Color("#ffcc33"))
	if delta_text != "" and flash > 0.0:
		draw_string(_mono, Vector2(x, 124), delta_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 6, 28, Color(0.6, 1, 0.5, minf(1.0, flash * 2.0)))
	# name strip
	var strip := Rect2(Vector2(0, size.y - 46), Vector2(size.x, 46))
	draw_rect(strip, Color("#6b1f2e"))
	draw_rect(Rect2(strip.position, Vector2(size.x, 3)), Color("#d9b24c"))
	draw_string(_font, Vector2(10, size.y - 12), str(info.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x - 20, 32, Color.WHITE)
	if lit > 0.0:
		draw_rect(r, Color(1, 0.9, 0.4, 0.18 * lit), false, 8.0)
	if flash > 0.0:
		draw_rect(r, Color(1, 1, 1, 0.25 * flash))
	for yy in range(0, int(size.y), 3):
		draw_line(Vector2(0, yy), Vector2(size.x, yy), Color(0, 0, 0, 0.18))


static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
