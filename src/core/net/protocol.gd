class_name Protocol
extends RefCounted
## Mildew controller protocol (phone <-> host). JSON objects over WebSocket text frames.
## Every message has "t" (type). Server never trusts client-supplied score/role/Director values.
## Bump VERSION on any breaking change; controller and host must agree.

const VERSION := 1

# --- Controller -> Server -------------------------------------------------
const C_HELLO := "hello"                    # {v, room?|key?, resume?}
const C_CHECK_NAME := "check_name"          # {name}
const C_SAY_NAME := "say_name"              # {speech}  (TV speaks it for pronunciation check)
const C_CREATE_PROFILE := "create_profile"  # {name, speech, avatar, claim_existing?}
const C_SELECT_PROFILE := "select_profile"  # {profile_id}
const C_START_SHOW := "start_show"          # {} (floor captain only)
const C_ANSWER := "answer"                  # {q, c}
const C_READY := "ready"                    # {}
const C_PLAY_AGAIN := "play_again"          # {} (floor captain only)
const C_LEAVE := "leave"                    # {}
const C_PING := "ping"                      # {id, rtt?}

# --- Server -> Controller -------------------------------------------------
const S_WELCOME := "welcome"        # {v, conn, profiles:[...], room_ok}
const S_ERROR := "error"            # {code, detail?, ref?}
const S_NAME_RESULT := "name_result"  # {ok, code?, match_profile?}
const S_JOINED := "joined"          # {player_id, resume, name, avatar}
const S_SCREEN := "screen"          # {screen, data, seq}
const S_STATUS := "status"          # {paused, reason, detail}
const S_PONG := "pong"              # {id, st}
const S_KICKED := "kicked"          # {reason}

const CLIENT_TYPES := [C_HELLO, C_CHECK_NAME, C_SAY_NAME, C_CREATE_PROFILE, C_SELECT_PROFILE,
	C_START_SHOW, C_ANSWER, C_READY, C_PLAY_AGAIN, C_LEAVE, C_PING]

# Error codes (stable strings; the controller maps them to on-brand copy).
const E_BAD_JSON := "bad_json"
const E_TOO_LARGE := "too_large"
const E_UNKNOWN_TYPE := "unknown_type"
const E_BAD_VERSION := "bad_version"
const E_BAD_ROOM := "bad_room"
const E_NOT_HELLO := "hello_required"
const E_INVALID_STATE := "invalid_state"
const E_BAD_PAYLOAD := "bad_payload"
const E_NAME_TAKEN := "name_taken"
const E_NAME_INVALID := "name_invalid"
const E_PROFILE_UNAVAILABLE := "profile_unavailable"
const E_ROOM_FULL := "room_full"
const E_NOT_CAPTAIN := "not_captain"
const E_NOT_ENOUGH_PLAYERS := "not_enough_players"
const E_ALREADY_ANSWERED := "already_answered"
const E_NOT_PARTICIPANT := "not_participant"
const E_STALE := "stale_question"
const E_RATE_LIMIT := "rate_limited"


## Parse a raw text frame. Returns {ok, msg?, code?}.
static func parse(raw: String, max_bytes: int) -> Dictionary:
	if raw.to_utf8_buffer().size() > max_bytes:
		return {"ok": false, "code": E_TOO_LARGE}
	var json := JSON.new()  # silent on malformed input (parse_string logs engine errors)
	if json.parse(raw) != OK:
		return {"ok": false, "code": E_BAD_JSON}
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "code": E_BAD_JSON}
	var t = parsed.get("t")
	if typeof(t) != TYPE_STRING or not CLIENT_TYPES.has(t):
		return {"ok": false, "code": E_UNKNOWN_TYPE}
	return {"ok": true, "msg": parsed}


static func get_str(msg: Dictionary, key: String, max_len: int = 256) -> Variant:
	var v = msg.get(key)
	if typeof(v) != TYPE_STRING:
		return null
	if v.length() > max_len:
		return null
	return v


static func get_int(msg: Dictionary, key: String) -> Variant:
	var v = msg.get(key)
	# JSON numbers arrive as float; accept integral floats only.
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v) and absf(v) < 1.0e9:
		return int(v)
	return null
