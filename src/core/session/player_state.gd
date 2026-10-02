class_name PlayerState
extends RefCounted
## Session-scope player record (session memory, docs/09). Authoritative; never client-supplied.

enum Status { ACTIVE, WAITING, LEFT, DROPPED }

var player_id := ""
var profile_id := ""
var display_name := ""
var speech_name := ""
var avatar: Dictionary = {}
var number := 0                 # podium number (1..8), stable for the session
var conn_id := -1
var connected := false
var status: Status = Status.ACTIVE
var resume_token := ""
var is_fake := false
var returning := false          # profile existed before this session
var score := 0
var rot := 0                    # Tonight's Rot; never decreases during a session
var joined_at := 0.0
var lost_at := -1.0             # session time the connection dropped (reconnect window)
var mid_call_done := false
var screen_seq := 0
var last_rtt_ms := -1
var history: Array = []         # per-question records (session only)


func is_active() -> bool:
	return status == Status.ACTIVE


func is_present() -> bool:
	return status == Status.ACTIVE or status == Status.WAITING


func status_name() -> String:
	return ["active", "waiting", "left", "dropped"][status]


func add_rot(amount: int) -> void:
	if amount > 0:
		rot += amount  # Rot cannot decrease during a session (docs/05)


func public_info() -> Dictionary:
	return {
		"pid": player_id,
		"name": display_name,
		"avatar": avatar,
		"number": number,
		"score": score,
		"rot": rot,
		"status": status_name(),
		"connected": connected,
		"fake": is_fake,
		"returning": returning,
	}
