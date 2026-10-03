class_name DnpPuzzle
extends RefCounted
## DO NOT PRESS THAT puzzle generator + rules (CP6; docs/04 §6). Pure logic, no session access, so
## every template × player count × seed can be validated automatically (role-allocation tests).
##
## A puzzle = TV display (lamps / gauge / card) + k controls (switch, dial 1-9, press button) whose
## correct final values are only knowable from instructions held by *other* players, some of which
## refer to the TV, some to other controls ("copy"), plus an optional ORDER rule, a NEVER control and
## an irrelevant DO-NOT-PRESS decoy. Controls and instructions are dealt so that nobody holds the
## instruction for a control they operate, and every player has something to do.

const COLOURS := ["RED", "GREEN", "BLUE", "AMBER"]
const NAMED_COLOURS := ["RED", "GREEN", "BLUE", "AMBER", "WHITE", "PINK", "VIOLET", "GREY"]
const DIAL_MAX := 9

var tpl: Dictionary
var n := 2
var display := {}            # {kind, lamps:[{label, colour, lit}], gauge, card:{item: count}}
var controls: Array = []     # [{id, type, label, max, value, target, rule, owner, decoy, never, ref}]
var instructions: Array = [] # [{text, holder, about:[ids], kind}]
var _used_items: Array = []  # card items already used by a rule (variety)
var order: Array = []        # [a_id, b_id]: a must be correct before b is touched


static func generate(p_tpl: Dictionary, players: int, rng: RandomNumberGenerator, decoy_owner: int = -1) -> DnpPuzzle:
	var p := DnpPuzzle.new()
	p.tpl = p_tpl
	p.n = players
	p._build(rng, decoy_owner)
	return p


func _build(rng: RandomNumberGenerator, decoy_owner: int) -> void:
	var k := clampi(n, 3, 6)
	var ctype := str(tpl.get("controls", "switch"))
	var labels: Array = (tpl.get("labels", []) as Array).duplicate()
	_shuffle(labels, rng)
	labels = labels.slice(0, k)
	# --- TV display -----------------------------------------------------------------------
	var dk := str(tpl.get("display", "lamps"))
	display = {"kind": dk}
	match dk:
		"lamps":
			var lamps: Array = []
			if ctype == "switch":
				for l in labels:
					# a lamp labelled with a colour is that colour (no "WHITE lamp glowing blue")
					var col: String = l if NAMED_COLOURS.has(l) else COLOURS[rng.randi_range(0, 3)]
					lamps.append({"label": l, "colour": col, "lit": rng.randf() < 0.5})
			for i in 6 - lamps.size() if lamps.size() < 6 else 0:
				lamps.append({"label": "", "colour": COLOURS[rng.randi_range(0, 3)], "lit": rng.randf() < 0.55})
			if lamps.filter(func(x): return x.lit).is_empty():
				lamps[rng.randi_range(0, lamps.size() - 1)].lit = true
			display["lamps"] = lamps
		"gauge":
			display["gauge"] = rng.randi_range(3, 8)
		"card":
			var items: Array = (tpl.get("card_items", ["EGGS", "PIES", "HAMS"]) as Array).duplicate()
			_shuffle(items, rng)
			var card := {}
			for it in items.slice(0, 3):
				card[it] = rng.randi_range(1, 4)
			display["card"] = card
	# --- Controls + per-control rules --------------------------------------------------------
	var rules: Array = tpl.get("rules", [])
	var never_used := false
	for i in k:
		var c := {"id": "c%d" % i, "type": ctype, "label": labels[i], "max": DIAL_MAX if ctype == "dial" else (1 if ctype == "switch" else 9),
			"value": 0, "target": 0, "rule": "", "owner": -1, "decoy": false, "never": false, "ref": ""}
		var choices: Array = rules.filter(func(r): return _rule_ok(r, ctype, i, never_used))
		var rule: String = choices[rng.randi_range(0, choices.size() - 1)] if not choices.is_empty() else _fallback(ctype)
		if rule == "never":
			never_used = true
		var made := _apply_rule(c, rule, i, rng)
		if not made:
			_apply_rule(c, _fallback(ctype), i, rng)
		controls.append(c)
	# start states: switches off, dials somewhere wrong, buttons at zero presses
	for c in controls:
		if c.type == "dial":
			var v: int = rng.randi_range(1, DIAL_MAX)
			while v == int(c.target):
				v = rng.randi_range(1, DIAL_MAX)
			c.value = v
	# make sure it isn't already solved (e.g. all switches should stay off)
	if is_solved():
		for c in controls:
			if c.type == "switch" and not c.never:
				c.target = 1
				c.rule = "plain_on"
				c.text = "%s must be switched ON." % c.label
				break
	# ORDER rule
	if bool(tpl.get("order", false)):
		var cand: Array = controls.filter(func(c): return not c.never and int(c.target) != int(c.value))
		if cand.size() >= 2:
			_shuffle(cand, rng)
			order = [cand[0].id, cand[1].id]
	# decoy: an irrelevant control nobody should touch
	var decoy := {"id": "x", "type": "button", "label": str(tpl.get("decoy", "DO NOT PRESS")), "max": 1, "value": 0, "target": 0,
		"rule": "decoy", "owner": -1, "decoy": true, "never": false, "ref": ""}
	controls.append(decoy)
	_allocate(rng, decoy_owner)


func _fallback(ctype: String) -> String:
	return {"switch": "plain_on", "dial": "plain_dial", "button": "plain_press"}.get(ctype, "plain_on")


func _rule_ok(rule: String, ctype: String, i: int, never_used: bool) -> bool:
	var dk := str(display.kind)
	match rule:
		"lamp", "lamp_off":
			return ctype == "switch" and dk == "lamps"
		"never":
			return ctype == "switch" and not never_used and i > 0
		"card_switch", "lamp_card":
			return ctype == "switch" and dk == "card"
		"gauge_switch":
			return ctype == "switch" and dk == "gauge"
		"card", "card_plus":
			return ctype in ["dial", "button"] and dk == "card"
		"gauge", "gauge_minus", "gauge_plus":
			return ctype == "dial" and dk == "gauge"
		"count", "count_plus", "press_lamp":
			return ctype in ["dial", "button"] and dk == "lamps"
		"copy":
			return ctype == "dial" and i > 0
	return false


func _lit(colour: String = "") -> int:
	var n_lit := 0
	for l in display.get("lamps", []):
		if l.lit and (colour == "" or l.colour == colour):
			n_lit += 1
	return n_lit


func _apply_rule(c: Dictionary, rule: String, i: int, rng: RandomNumberGenerator) -> bool:
	var L: String = c.label
	c.rule = rule
	match rule:
		"lamp":
			var lamp: Dictionary = display.lamps.filter(func(l): return l.label == L)[0]
			c.target = 1 if lamp.lit else 0
			c.text = "%s must be ON if the %s lamp on the television is lit, and OFF if it's dark." % [L, L]
		"lamp_off":
			var lamp2: Dictionary = display.lamps.filter(func(l): return l.label == L)[0]
			c.target = 0 if lamp2.lit else 1
			c.text = "%s is wired backwards: ON if the %s lamp is dark, OFF if it's lit." % [L, L]
		"never":
			c.target = 0
			c.never = true
			c.text = "Never switch on %s. Don't even say its name." % L
		"card_switch", "lamp_card":
			var keys: Array = display.card.keys().filter(func(x): return not _used_items.has(x))
			if keys.is_empty():
				keys = display.card.keys()
			var it: String = keys[rng.randi_range(0, keys.size() - 1)]
			_used_items.append(it)
			c.target = 1 if int(display.card[it]) >= 2 else 0
			c.text = "%s must be ON if the card shows two or more %s. Otherwise OFF." % [L, it]
		"gauge_switch":
			var th := rng.randi_range(4, 7)
			c.target = 1 if int(display.gauge) > th else 0
			c.text = "%s must be ON only if the gauge reads more than %d." % [L, th]
		"card":
			var keys2: Array = display.card.keys()
			var it2: String = keys2[rng.randi_range(0, keys2.size() - 1)]
			c.target = int(display.card[it2])
			c.text = ("Set %s to the number of %s on the card." if c.type == "dial" else "Press %s once for every %s on the card. Exactly.") % [L, it2]
		"card_plus":
			var keys3: Array = display.card.keys()
			var t := int(display.card[keys3[0]]) + int(display.card[keys3[1]])
			if t > 9:
				return false
			c.target = t
			c.text = "Set %s to the number of %s plus the number of %s." % [L, keys3[0], keys3[1]]
		"gauge":
			c.target = int(display.gauge)
			c.text = "Set %s to whatever the gauge on the television reads." % L
		"gauge_minus":
			var d := rng.randi_range(1, 2)
			if int(display.gauge) - d < 1:
				return false
			c.target = int(display.gauge) - d
			c.text = "Set %s to the gauge reading minus %d." % [L, d]
		"gauge_plus":
			var d2 := rng.randi_range(1, 2)
			if int(display.gauge) + d2 > DIAL_MAX:
				return false
			c.target = int(display.gauge) + d2
			c.text = "Set %s to the gauge reading plus %d." % [L, d2]
		"count", "press_lamp":
			if rule == "press_lamp" or (c.type == "dial" and rng.randf() < 0.5):
				var col: String = COLOURS[rng.randi_range(0, 3)]
				if _lit(col) == 0:
					return false
				c.target = _lit(col)
				c.text = ("Set %s to the number of %s lamps that are lit." if c.type == "dial" else "Press %s once for each lit %s lamp. No more.") % [L, col]
			else:
				c.target = maxi(1, _lit())
				c.text = ("Set %s to the number of lamps lit on the television." if c.type == "dial" else "Press %s once for every lit lamp on the television. No more.") % L
		"count_plus":
			if _lit() + 1 > DIAL_MAX:
				return false
			c.target = _lit() + 1
			c.text = "Set %s to one more than the number of lit lamps." % L
		"copy":
			var prev: Array = controls.filter(func(x): return x.type == "dial" and not x.decoy)
			if prev.is_empty():
				return false
			var src: Dictionary = prev[rng.randi_range(0, prev.size() - 1)]
			var d3 := rng.randi_range(-1, 2)
			var t3 := int(src.target) + d3
			if t3 < 1 or t3 > DIAL_MAX:
				d3 = 0
				t3 = int(src.target)
			c.target = t3
			c.ref = src.id
			var how := "the same as" if d3 == 0 else ("%d more than" % d3 if d3 > 0 else "%d less than" % -d3)
			c.text = "%s must end up %s %s. Ask whoever has %s." % [L, how, src.label, src.label]
		"plain_on":
			c.target = 1
			c.text = "%s must be switched ON." % L
		"plain_dial":
			c.target = rng.randi_range(2, DIAL_MAX)
			c.text = "Set %s to %d." % [L, c.target]
		"plain_press":
			c.target = rng.randi_range(1, 3)
			c.text = "Press %s exactly %d times." % [L, c.target]
		_:
			return false
	return true


## Deals controls and instructions (see class doc). decoy_owner: the previous culprit (punishment hook).
func _allocate(rng: RandomNumberGenerator, decoy_owner: int) -> void:
	var load := []
	load.resize(n)
	load.fill(0)
	var off := rng.randi_range(0, n - 1)
	var real: Array = controls.filter(func(c): return not c.decoy)
	for i in real.size():
		real[i].owner = (off + i) % n
		load[real[i].owner] += 1
	var ins_count := []
	ins_count.resize(n)
	ins_count.fill(0)
	for c in real:
		var best := -1
		for j in n:
			var p := (int(c.owner) + 1 + j) % n
			if p == int(c.owner):
				continue
			if best < 0 or load[p] < load[best]:
				best = p
		instructions.append({"text": c.text, "holder": best, "about": [c.id], "kind": c.rule})
		load[best] += 1
	if order.size() == 2:
		var a := _ctl(order[0])
		var b := _ctl(order[1])
		var best2 := -1
		for p in n:
			if p == int(a.owner) or p == int(b.owner):
				continue
			if best2 < 0 or load[p] < load[best2]:
				best2 = p
		if best2 < 0:
			best2 = int(a.owner)
		instructions.append({"text": "%s must be set correctly BEFORE anybody touches %s." % [a.label, b.label], "holder": best2, "about": order.duplicate(), "kind": "order"})
		load[best2] += 1
	var dec := _ctl("x")
	if decoy_owner >= 0 and decoy_owner < n:
		dec.owner = decoy_owner
	else:
		var lo := 0
		for p in n:
			if load[p] < load[lo]:
				lo = p
		dec.owner = lo
	load[dec.owner] += 1


func _ctl(id: String) -> Dictionary:
	for c in controls:
		if c.id == id:
			return c
	return {}


func is_correct(c: Dictionary) -> bool:
	return c.decoy or int(c.value) == int(c.target)


func is_solved() -> bool:
	for c in controls:
		if not is_correct(c):
			return false
	return true


func solved_count() -> int:
	return controls.filter(func(c): return not c.decoy and is_correct(c)).size()


## Applies one action. Returns {ok, mistake:"" | "decoy" | "never" | "order" | "overpress", value}.
## Buttons: press_seq is the press count the phone believes it has reached (1-based), so duplicated
## or re-sent presses are ignored instead of over-pressing.
func act(id: String, value: int, press_seq: int = -1) -> Dictionary:
	var c := _ctl(id)
	if c.is_empty():
		return {"ok": false}
	if c.decoy:
		c.value = 1
		return {"ok": true, "mistake": "decoy", "value": 1}
	if order.size() == 2 and id == order[1] and not is_correct(_ctl(order[0])):
		return {"ok": true, "mistake": "order", "value": c.value}
	match str(c.type):
		"switch":
			c.value = clampi(value, 0, 1)
			if c.never and c.value == 1:
				return {"ok": true, "mistake": "never", "value": c.value}
		"dial":
			c.value = clampi(value, 1, DIAL_MAX)
		"button":
			if press_seq >= 0 and press_seq <= int(c.value):
				return {"ok": true, "mistake": "", "value": c.value, "dup": true}   # duplicate/late press (latency tolerance)
			c.value = int(c.value) + 1
			if int(c.value) > int(c.target):
				c.value = 0
				return {"ok": true, "mistake": "overpress", "value": 0}
	return {"ok": true, "mistake": "", "value": c.value}


## Automated role-allocation validation (docs/11 CP6 gate). Empty = valid.
func validate() -> Array:
	var errs: Array = []
	var has := []
	has.resize(n)
	has.fill(false)
	for c in controls:
		if int(c.owner) < 0 or int(c.owner) >= n:
			errs.append("control %s unowned" % c.id)
			continue
		has[int(c.owner)] = true
		if not c.decoy and (int(c.target) < (1 if c.type == "dial" else 0) or int(c.target) > int(c.max)):
			errs.append("control %s target %s out of range" % [c.id, c.target])
	for ins in instructions:
		has[int(ins.holder)] = true
		if ins.kind != "order":
			var c2 := _ctl(ins.about[0])
			if int(c2.owner) == int(ins.holder):
				errs.append("player %d holds the instruction for their own control %s" % [ins.holder, c2.id])
	for p in n:
		if not has[p]:
			errs.append("player %d has nothing to do" % p)
	for c in controls:
		if not c.decoy and not instructions.any(func(i): return (i.about as Array).has(c.id) and i.kind != "order"):
			errs.append("control %s has no instruction" % c.id)
	if is_solved():
		errs.append("puzzle starts solved")
	# solvability: apply targets in a safe order
	var sim := DnpPuzzle.new()
	sim.n = n
	sim.order = order.duplicate()
	sim.controls = controls.map(func(c): return c.duplicate())
	var seq: Array = sim.controls.filter(func(c): return not c.decoy)
	if order.size() == 2:
		seq.sort_custom(func(a, b): return a.id == order[0] and b.id != order[0])
	for c in seq:
		if c.type == "button":
			for k in int(c.target):
				var r := sim.act(c.id, 0, k + 1)
				if r.mistake != "":
					errs.append("solving %s caused %s" % [c.id, r.mistake])
		elif int(c.value) != int(c.target):
			var r2 := sim.act(c.id, int(c.target))
			if r2.mistake != "":
				errs.append("solving %s caused %s" % [c.id, r2.mistake])
	if not sim.is_solved():
		errs.append("not solvable by following the instructions")
	return errs


## What one phone sees: its own controls (with live values) and its own instructions.
func panel_for(p: int) -> Dictionary:
	var ctls: Array = []
	for c in controls:
		if int(c.owner) == p:
			ctls.append({"id": c.id, "type": c.type, "label": c.label, "value": c.value, "max": c.max, "decoy": c.decoy})
	var ins: Array = instructions.filter(func(i): return int(i.holder) == p).map(func(i): return i.text)
	return {"controls": ctls, "instructions": ins}


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
