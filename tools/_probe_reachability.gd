extends SceneTree
## _probe_reachability.gd — PASS 1 of docs/BUG_SWEEP_METHOD_20260829.md (class C1).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_reachability.gd
##
## Content or code that can never run. This class hides because NOTHING ERRORS: a
## dead dispatch arm reads exactly like a live one, and an effect type with no
## handler silently no-ops instead of crashing. The 2026-08-07 pass deleted SIX
## minigames that were dispatched, listed in MODAL_EFFECTS, and emitted by no event
## — 2,257 lines no player could reach, undetected for months.
##
## Both directions are checked, because each is a different bug:
##   PRODUCER with no CONSUMER — content that silently does nothing (a card whose
##     on_enter type has no handler is a card that lies to the player).
##   CONSUMER with no PRODUCER — dead code (the six minigames).
##   DANGLING REFERENCE — an id named by one DB that another does not define.
##
## Handler sets are read from SOURCE, since the arms are `match` cases rather than
## data. Everything below has been triaged once (2026-08-29) and the noise removed,
## so this now FAILS on anything not explicitly waived — the whole point is to catch
## the NEXT dead feature the day it is orphaned rather than months later.
##
## Two false positives from the first run are worth remembering, because both would
## have got live content deleted:
##   * `stranger_hand_pick` looked unreachable because the scan only walked
##     `choices[].effects[]`, and The Wet Cards emits from a top-level `auto_effect`.
##     The walk is recursive now, so a new emission shape cannot slip past.
##   * `structure` looked like dead vocabulary because the scan only read CardDB —
##     every `structure` in the game is stamped on by EncounterDB's `kw` arrays.

## Known orphans, each with the reason it is allowed to stay. An entry here is a
## DEBT, not an absolution — remove it by wiring or deleting the thing.
##
## EMPTY, and it should stay that way. Its one entry was `relic_sacrifice_pick` —
## The Old Forge — a finished feature (picker, decline path, no-target reason,
## `has_nonstarting_relic` gate, and its own painting) that no event emitted, so no
## player could reach any of it. It was WIRED rather than deleted on 2026-08-29:
## unlike the six minigames cut on 2026-08-07 it had no live replacement, and
## deleting a working feature to satisfy a gate is the wrong direction.
const WAIVED_ORPHANS: Dictionary = {}

## Keywords no DB entry prints. Each is named by a resolver and is legitimate.
const WAIVED_KEYWORDS: Dictionary = {
	"adjacent": "prose-glossary word — gilded in rules text, carries the hover hint",
	"slay": "prose-glossary word — 'Slay: draw 1' reads as a clause, not a keyword",
	"sacrifice": "reserved play-cost mechanic; _play_creature already gates on it",
}

var _started := false
var _done := false
var _findings: Array = []
var _fails := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


## Every quoted string that appears as a `match` arm or a dict key in `path`.
## Deliberately generous: we want NO false "unhandled" reports, so anything that
## looks like the token being named anywhere in the file counts as handled.
func _tokens_in(paths: Array) -> Dictionary:
	var out := {}
	for p in paths:
		var f := FileAccess.open(String(p), FileAccess.READ)
		if f == null:
			continue
		var src := f.get_as_text()
		f.close()
		var re := RegEx.create_from_string('"([a-z0-9_]+)"')
		for m in re.search_all(src):
			out[m.get_string(1)] = true
	return out


## `waivers` maps an exact item string to the reason it is allowed. Anything not in
## it is a FAILURE; anything in it prints as accepted debt so it stays visible.
func _report(title: String, missing: Array, note: String = "",
		waivers: Dictionary = {}) -> void:
	var live: Array = []
	var waived: Array = []
	for m in missing:
		if waivers.has(String(m)):
			waived.append(String(m))
		else:
			live.append(String(m))
	live.sort()
	waived.sort()
	if live.is_empty():
		print("  OK    %s — none%s" % [
			title, ("  [%d waived]" % waived.size()) if not waived.is_empty() else ""])
	else:
		_fails += 1
		_findings.append({"title": title, "items": live})
		print("  FAIL  %s — %d unwaived" % [title, live.size()])
		for m in live:
			print("          %s" % m)
		if note != "":
			print("          (%s)" % note)
	for w in waived:
		print("          WAIVED %s" % w)
		print("                 %s" % String(waivers[w]))


func _run() -> void:
	print("[reach] PASS 1 — reachability / orphan sweep\n")
	var CDB := root.get_node_or_null("CardDB")
	var RDB := root.get_node_or_null("RelicDB")
	var KW := root.get_node_or_null("KeywordEffects")
	var HDB := root.get_node_or_null("HeroDB")
	var ENC := root.get_node_or_null("EncounterDB")
	var PDB := root.get_node_or_null("PotionDB")
	# EventDB is NOT an autoload — it is a `class_name` RefCounted that Event.gd
	# preloads (CLAUDE.md's autoload list says otherwise; that is doc drift).
	var EDB = load("res://scripts/data/EventDB.gd")
	if CDB == null or RDB == null or EDB == null or KW == null:
		print("[reach] FATAL: databases missing"); _done = true; quit(1); return

	var kw_src := _tokens_in(["res://scripts/data/KeywordEffects.gd"])
	var combat_src := _tokens_in(["res://scripts/scenes/Combat.gd",
		"res://scripts/net/CombatNet.gd"])
	var event_src := _tokens_in(["res://scripts/scenes/Event.gd"])

	# ── 1. Card effect types → a handler somewhere ────────────────────────
	print("[reach] --- card effect types vs handlers ---")
	var buckets := {
		"on_enter": {}, "on_death": {}, "on_play": {}, "floop": {},
	}
	var passives := {}
	var spell_types := {}
	var spell_ids := {}
	var ctypes := {}
	var kw_used := {}
	for id_v in CDB.CARD_POOL:
		var c: Dictionary = CDB.CARD_POOL[id_v]
		for key in buckets.keys():
			var sub = c.get(key, null)
			if sub is Dictionary and String((sub as Dictionary).get("type", "")) != "":
				buckets[key][String((sub as Dictionary).get("type", ""))] = true
		if String(c.get("passive", "")) != "":
			passives[String(c["passive"])] = true
		if String(c.get("ctype", "")) != "":
			ctypes[String(c["ctype"])] = true
		for k in c.get("keywords", []):
			kw_used[String(k)] = true
		var sp = c.get("spell", null)
		if sp is Dictionary:
			var spd: Dictionary = sp
			if String(spd.get("type", "")) != "":
				spell_types[String(spd["type"])] = true
			if String(spd.get("id", "")) != "":
				spell_ids[String(spd["id"])] = true

	for key in ["on_enter", "on_death", "on_play", "floop"]:
		var miss: Array = []
		for t in buckets[key]:
			if not kw_src.has(t) and not combat_src.has(t):
				miss.append("%s.type = %s" % [key, t])
		_report("card %s types with no handler (%d distinct)" % [key, buckets[key].size()], miss)

	var pmiss: Array = []
	for p in passives:
		if not combat_src.has(p) and not kw_src.has(p):
			pmiss.append(p)
	_report("card passives never named in Combat/CombatNet/KeywordEffects (%d distinct)"
		% passives.size(), pmiss)

	var stmiss: Array = []
	for t in spell_types:
		if not combat_src.has(t):
			stmiss.append(t)
	_report("spell.type with no resolver arm (%d distinct)" % spell_types.size(), stmiss)
	var simiss: Array = []
	for t in spell_ids:
		if not combat_src.has(t):
			simiss.append(t)
	_report("spell.id with no resolver arm (%d distinct)" % spell_ids.size(), simiss)

	# ── 2. Keywords declared vs used ──────────────────────────────────────
	print("\n[reach] --- keywords ---")
	var declared := {}
	for k in KW.KEYWORDS:
		declared[String(k)] = true
	var undeclared: Array = []
	for k in kw_used:
		if not declared.has(k):
			undeclared.append(k)
	_report("keywords used on cards but NOT in KeywordEffects.KEYWORDS", undeclared)
	# A keyword can reach the board from three places, not one: printed on a CardDB
	# entry, stamped onto an enemy by EncounterDB's `kw` arrays (this is how every
	# `structure` in the game exists — scanning CardDB alone reported the whole
	# inert-structure system as dead vocabulary), or granted at runtime by a
	# resolver. Count all three before calling a word unused.
	var enc_src := _tokens_in(["res://scripts/data/EncounterDB.gd",
		"res://scripts/data/SetPieceDB.gd"])
	# The bare keyword is the item, so WAIVED_KEYWORDS can key on it. A word named
	# nowhere in code either is genuinely dead and fails; the three that are named
	# (prose-glossary words and the reserved sacrifice cost) are waived by name.
	var unused: Array = []
	for k in declared:
		if kw_used.has(k) or enc_src.has(k):
			continue
		unused.append(k)
	_report("keywords no DB entry carries", unused,
		"if it is named nowhere in code either, it is dead vocabulary", WAIVED_KEYWORDS)

	# ── 3. Dangling card / relic ids across the DBs ───────────────────────
	print("\n[reach] --- dangling ids across DBs ---")
	var bad_cards: Array = []
	if HDB != null:
		for h_v in HDB.HEROES:
			var h: Dictionary = HDB.HEROES[h_v]
			for cid in h.get("deck", []):
				if not CDB.CARD_POOL.has(String(cid)):
					bad_cards.append("HeroDB[%s].deck -> %s" % [h_v, cid])
			var alt = h.get("deck_alt", null)
			if alt is Dictionary:
				for cid in (alt as Dictionary).get("deck", []):
					if not CDB.CARD_POOL.has(String(cid)):
						bad_cards.append("HeroDB[%s].deck_alt -> %s" % [h_v, cid])
	if ENC != null:
		for e_v in ENC.ENCOUNTERS:
			var e: Dictionary = ENC.ENCOUNTERS[e_v]
			for entry in e.get("deck", []):
				var cid := String(entry) if not (entry is Dictionary) \
					else String((entry as Dictionary).get("id", ""))
				if cid != "" and not CDB.CARD_POOL.has(cid):
					bad_cards.append("EncounterDB[%s].deck -> %s" % [e_v, cid])
			var reinf = e.get("reinforcement", "")
			if reinf is String and String(reinf) != "" and not CDB.CARD_POOL.has(String(reinf)):
				bad_cards.append("EncounterDB[%s].reinforcement -> %s" % [e_v, reinf])
	_report("card ids referenced by HeroDB/EncounterDB that CardDB does not define",
		bad_cards)

	var bad_relics: Array = []
	if HDB != null:
		for h_v in HDB.HEROES:
			var h: Dictionary = HDB.HEROES[h_v]
			for key in ["relic", "relic_alt"]:
				var rid := String(h.get(key, ""))
				if rid != "" and RDB.get_relic(rid).is_empty():
					bad_relics.append("HeroDB[%s].%s -> %s" % [h_v, key, rid])
	_report("relic ids referenced by HeroDB that RelicDB does not define", bad_relics)

	# ── 4. Event effect types → a handler in Event.gd ─────────────────────
	print("\n[reach] --- event effects ---")
	var ev_types := {}
	var ev_cards: Array = []
	var ev_relics: Array = []
	# EVERY EMISSION SHAPE, not just `choices[].effects[]`. An event can also carry a
	# top-level `auto_effect` (The Wet Cards is the only one today, and scanning
	# choices alone reported its `stranger_hand_pick` as unreachable — a false
	# positive that would have got a live minigame deleted). Counted here by walking
	# the event dict recursively for anything with a "type", so a shape added later
	# cannot quietly slip past this the way `auto_effect` did.
	for ev_v in EDB.EVENTS:
		var ev: Dictionary = EDB.EVENTS[ev_v]
		var stack: Array = [ev]
		while not stack.is_empty():
			var node = stack.pop_back()
			if node is Dictionary:
				var nd: Dictionary = node
				var t := String(nd.get("type", ""))
				if t != "":
					ev_types[t] = true
				var acid := String(nd.get("card_id", ""))
				if acid != "" and not CDB.CARD_POOL.has(acid):
					ev_cards.append("EventDB[%s] card_id -> %s" % [ev_v, acid])
				var arid := String(nd.get("relic_id", ""))
				if arid != "" and RDB.get_relic(arid).is_empty():
					ev_relics.append("EventDB[%s] relic_id -> %s" % [ev_v, arid])
				for k in nd:
					var val = nd[k]
					if val is Dictionary or val is Array:
						stack.append(val)
			elif node is Array:
				for item in node:
					if item is Dictionary or item is Array:
						stack.append(item)
	var ev_miss: Array = []
	for t in ev_types:
		if not event_src.has(t):
			ev_miss.append(t)
	_report("event effect types with no handler in Event.gd (%d distinct)"
		% ev_types.size(), ev_miss)
	_report("card ids named by events that CardDB does not define", ev_cards)
	_report("relic ids named by events that RelicDB does not define", ev_relics)

	# ── 5. THE MINIGAME CLASS: dispatched but never emitted ───────────────
	print("\n[reach] --- dispatched-but-never-emitted (the minigame class) ---")
	var modal: Array = []
	if EDB != null and "MODAL_EFFECTS" in EDB:
		modal = EDB.MODAL_EFFECTS
	else:
		var ev_src_f := FileAccess.open("res://scripts/scenes/Event.gd", FileAccess.READ)
		if ev_src_f != null:
			var s := ev_src_f.get_as_text()
			ev_src_f.close()
			var block := RegEx.create_from_string("MODAL_EFFECTS[^\\[]*\\[([^\\]]*)\\]")
			var mm := block.search(s)
			if mm != null:
				var inner := mm.get_string(1)
				var lit := RegEx.create_from_string('"([a-z0-9_]+)"')
				for m in lit.search_all(inner):
					modal.append(m.get_string(1))
	var unreachable: Array = []
	for m in modal:
		if not ev_types.has(String(m)):
			unreachable.append(String(m))
	_report("MODAL_EFFECTS entries no event ever emits (%d listed)" % modal.size(),
		unreachable, "this is exactly the six-dead-minigames shape", WAIVED_ORPHANS)

	# ── 6. Potions ────────────────────────────────────────────────────────
	print("\n[reach] --- potions ---")
	if PDB != null:
		var pot_miss: Array = []
		for p_v in PDB.POTIONS:
			var p: Dictionary = PDB.POTIONS[p_v]
			var eff := String(p.get("effect", ""))
			if eff != "" and not combat_src.has(eff):
				pot_miss.append("%s -> %s" % [p_v, eff])
		_report("potion effects with no handler in Combat/CombatNet", pot_miss)

	print("\n[reach] %s" % ("ALL PASS" if _fails == 0
		else "%d unwaived finding group(s)" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)
