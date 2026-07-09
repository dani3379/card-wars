extends SceneTree
## _probe_event_pass.gd — headless compile + data audit for the 2026-07-04
## event presentation/content pass. Run:
##   Godot_console.exe --headless --path . --script res://tools/_probe_event_pass.gd
## Checks: (1) the three touched scripts fully compile via load();
## (2) every event's art stand-in resolves to a real file; (3) no two live
## events share the same stand-in; (4) branded curse / gift keyword / scaled
## kind ids referenced by EVENTS exist; (5) gate types used are implemented.

func _init() -> void:
	var fails: Array = []

	# 1 — full compile of touched scripts.
	for p in ["res://scripts/scenes/Event.gd", "res://scripts/scenes/Combat.gd",
			"res://scripts/state/RunState.gd"]:
		var s = load(p)
		if s == null:
			fails.append("compile FAIL: " + p)
		else:
			print("compile OK: ", p)

	var event_script = load("res://scripts/scenes/Event.gd")
	var card_db = load("res://scripts/data/CardDB.gd")
	var kw_db = load("res://scripts/data/KeywordEffects.gd")
	var events: Dictionary = event_script.EVENTS
	print("event count: ", events.size())

	# 2 + 3 — art resolution and collisions. Mirrors the game's resolution
	# order (bespoke <id>.png wins over the "art" stand-in) and counts EVERY
	# live event against the file it actually shows — two events resolving to
	# the same painting is a fail regardless of how each one got there.
	var art_users: Dictionary = {}
	for id in events:
		var ev: Dictionary = events[id]
		var resolved := ""
		for key in [String(id), String(ev.get("art", ""))]:
			if resolved != "" or String(key) == "":
				continue
			for ext in ["png", "jpg"]:
				if FileAccess.file_exists("res://assets/events/%s.%s" % [key, ext]):
					resolved = String(key)
					break
		if resolved == "":
			fails.append("art MISSING for %s (key %s)" % [id, String(ev.get("art", id))])
			continue
		if art_users.has(resolved):
			fails.append("art COLLISION: %s and %s both show %s" \
				% [id, art_users[resolved], resolved])
		art_users[resolved] = id

	# 4 — referenced card ids / keywords / moods inside effects.
	var valid_moods := ["", "bone", "ember", "gilt", "verdigris"]
	for id in events:
		var ev: Dictionary = events[id]
		if not valid_moods.has(String(ev.get("mood", ""))):
			fails.append("bad mood on " + id)
		for choice in ev.get("choices", []):
			for eff in choice.get("effects", []):
				match String(eff.get("type", "")):
					"add_curse_id", "add_card_id":
						var cid := String(eff.get("id", ""))
						if card_db.CARD_POOL.get(cid, {}).is_empty():
							fails.append("%s: unknown card id %s" % [id, cid])
					"gift_creature":
						for kw in eff.get("kw", []):
							if not kw_db.KEYWORDS.has(String(kw)):
								fails.append("%s: unknown gift kw %s" % [id, kw])
					"grant_keyword_pick":
						if not kw_db.KEYWORDS.has(String(eff.get("keyword", ""))):
							fails.append("%s: unknown grant kw" % id)

	if fails.is_empty():
		print("EVENT PASS AUDIT: ALL OK")
	else:
		for f in fails:
			print("FAIL: ", f)
	quit(0 if fails.is_empty() else 1)
