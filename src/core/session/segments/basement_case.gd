class_name BasementCase
extends RefCounted
## THE BASEMENT — evidence dealing + theory scoring (CP7; docs/04 §7). Pure logic so every case can
## be validated for 2–8 players automatically.
##
## Dealing rules:
##  * every KEY clue is dealt, spread across as many different players as possible (sharing matters);
##  * then support / unreliable clues, then at most one red herring per player;
##  * every player gets at least one card; with 2 players each holds several (2-player multi-clue);
##  * the holder is never told a card is unreliable; "sensitive" cards are marked privately.
## Scoring: per question, the chosen option's credit (partial credit allowed) × points.

var case: Dictionary
var n := 2
var hands: Array = []          # player index -> [evidence dicts]


static func deal(p_case: Dictionary, players: int, rng: RandomNumberGenerator) -> BasementCase:
	var b := BasementCase.new()
	b.case = p_case
	b.n = players
	b._deal(rng)
	return b


func _deal(rng: RandomNumberGenerator) -> void:
	hands = []
	for i in n:
		hands.append([])
	var ev: Array = case.get("evidence", [])
	var keys: Array = ev.filter(func(e): return e.kind == "key")
	var mid: Array = ev.filter(func(e): return e.kind in ["support", "unreliable"])
	var herrings: Array = ev.filter(func(e): return e.kind == "red_herring")
	_shuffle(keys, rng)
	_shuffle(mid, rng)
	_shuffle(herrings, rng)
	var off := rng.randi_range(0, n - 1)
	var i := 0
	for e in keys:
		hands[(off + i) % n].append(e)
		i += 1
	# per-player target so hands stay roughly even; 2 players hold more cards each
	var per := maxi(2, int(ceil(float(ev.size()) / n))) if n <= 3 else maxi(1, int(ceil(float(keys.size() + mid.size()) / n)))
	for e in mid:
		var best := _smallest()
		if hands[best].size() >= per and n > 3:
			continue   # large groups: not every support card needs dealing
		hands[best].append(e)
	for e in herrings:
		var best2 := _smallest()
		if hands[best2].any(func(x): return x.kind == "red_herring"):
			continue
		hands[best2].append(e)
	for h in hands:
		_shuffle(h, rng)


func _smallest() -> int:
	var b := 0
	for p in n:
		if hands[p].size() < hands[b].size():
			b = p
	return b


func hand_for(p: int) -> Array:
	return hands[p].map(func(e): return {"id": e.id, "text": e.text, "sensitive": bool(e.get("sensitive", false))})


func dealt_ids() -> Array:
	var out: Array = []
	for h in hands:
		for e in h:
			out.append(e.id)
	return out


## Credit (0..1) for one player's answers {question_id: option_index}.
func score(answers: Dictionary) -> Dictionary:
	var per := {}
	var total := 0.0
	for qd in case.get("questions", []):
		var c := 0.0
		if answers.has(qd.id):
			var k := int(answers[qd.id])
			var credits: Array = qd.get("credit", [])
			if k >= 0 and k < credits.size():
				c = float(credits[k])
		per[qd.id] = c
		total += c
	var qn := maxi(1, (case.get("questions", []) as Array).size())
	return {"per": per, "fraction": total / qn}


## Best-supported option per question (index of the highest credit).
func best_answers() -> Dictionary:
	var out := {}
	for qd in case.get("questions", []):
		var credits: Array = qd.get("credit", [])
		var best := 0
		for k in credits.size():
			if float(credits[k]) > float(credits[best]):
				best = k
		out[qd.id] = best
	return out


## Automated validation for a player count (docs/11 CP7 gate). Empty = valid.
func validate() -> Array:
	var errs: Array = []
	for p in n:
		if hands[p].is_empty():
			errs.append("player %d has no evidence" % p)
	var dealt := dealt_ids()
	var keys: Array = (case.get("evidence", []) as Array).filter(func(e): return e.kind == "key")
	for k in keys:
		if not dealt.has(k.id):
			errs.append("key clue %s not dealt" % k.id)
	if keys.size() >= n:
		for p in n:
			if not hands[p].any(func(e): return e.kind == "key"):
				errs.append("player %d holds no key clue although there are enough" % p)
	# every question's best answer must be supported by at least one dealt key clue (no missing path)
	for qd in case.get("questions", []):
		var supported := false
		for h in hands:
			for e in h:
				if e.kind == "key" and (e.get("supports", []) as Array).has(qd.id):
					supported = true
		if not supported:
			errs.append("question %s has no dealt key clue supporting it" % qd.id)
	for p in n:
		if hands[p].filter(func(e): return e.kind == "red_herring").size() > 1:
			errs.append("player %d holds more than one red herring" % p)
	return errs


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
