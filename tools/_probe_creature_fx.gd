extends SceneTree
## Creature-trigger FX coverage GATE (the spell plan's S1, applied to
## creatures — see the creature-trigger FX block in Combat.gd).
##
## Invariants, all of which FAIL the probe:
##   1. Every on_enter type used by a CARD_POOL card is acknowledged in
##      Combat.TRIGGER_FX_ENTER; every on_death type in TRIGGER_FX_DEATH;
##      every on_play type in TRIGGER_FX_PLAY. An unacknowledged type doesn't
##      error at runtime — it silently plays announce-only forever, which is
##      exactly how the spell map drifted to 42% untagged before S1.
##   2. Every ctype in the pool has a CTYPE_COLORS entry (the tribe's
##      material colour).
##   3. The keystone signatures point at LIVE cards: warden_line /
##      beast_encore / reap_on_ally_death / coven_spell / bastion_ramp each
##      exist on >=1 pool card, and >=1 card carries a type_buff aura. Dead
##      ids rot silently (S1's lesson).
##   4. The dispatch wiring exists: KeywordEffects calls ctx._play_trigger_fx
##      on both channels, and _resolve_on_play_ability calls it for on_play.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_creature_fx.gd
## Grep for "ALL PASS" — don't trust the exit code alone.

var _ran := false


func _scrape_keys(src: String, const_name: String, key_re: String) -> Dictionary:
	var out := {}
	var start := src.find("const %s := {" % const_name)
	if start < 0:
		return out
	# Entries are single lines, so the block's closing brace is the first
	# newline-anchored "}" after the const.
	var blk_end := src.find("\n}", start)
	var blk := src.substr(start, blk_end - start)
	var re := RegEx.new()
	re.compile(key_re)
	for m in re.search_all(blk):
		out[m.get_string(1)] = true
	return out


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true

	var C = load("res://scripts/data/CardDB.gd")
	var combat_src := FileAccess.open("res://scripts/scenes/Combat.gd",
		FileAccess.READ).get_as_text()
	var kw_src := FileAccess.open("res://scripts/data/KeywordEffects.gd",
		FileAccess.READ).get_as_text()

	var enter_map := _scrape_keys(combat_src, "TRIGGER_FX_ENTER", '\n\t"([a-z_0-9]+)":')
	var death_map := _scrape_keys(combat_src, "TRIGGER_FX_DEATH", '\n\t"([a-z_0-9]+)":')
	var play_map := _scrape_keys(combat_src, "TRIGGER_FX_PLAY", '\n\t"([a-z_0-9]+)":')
	var color_map := _scrape_keys(combat_src, "CTYPE_COLORS", '"([a-z]+)":\\s*Color')

	print("[creature_fx] scraped maps — enter:%d death:%d play:%d colors:%d" % [
		enter_map.size(), death_map.size(), play_map.size(), color_map.size()])

	var fails := 0
	if enter_map.is_empty() or death_map.is_empty() or play_map.is_empty() \
			or color_map.is_empty():
		fails += 1
		print("[creature_fx] FAIL  a TRIGGER_FX_* / CTYPE_COLORS const failed to scrape")

	var pool: Dictionary = C.CARD_POOL
	var miss_enter := {}
	var miss_death := {}
	var miss_play := {}
	var miss_ctype := {}
	var carriers := 0
	var creatures := 0
	print("")
	print("id | ctype | on_enter | on_death | on_play")
	print("---")
	var ids: Array = pool.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = pool[id]
		if String(d.get("type", "")) != "creature":
			continue
		creatures += 1
		var ct := String(d.get("ctype", ""))
		if ct != "" and not color_map.has(ct):
			miss_ctype[ct] = true
		var te := String(d.get("on_enter", {}).get("type", ""))
		var td := String(d.get("on_death", {}).get("type", ""))
		var tp := String(d.get("on_play", {}).get("type", ""))
		if te == "" and td == "" and tp == "":
			continue
		carriers += 1
		if te != "" and not enter_map.has(te):
			miss_enter[te] = true
		if td != "" and not death_map.has(td):
			miss_death[td] = true
		if tp != "" and not play_map.has(tp):
			miss_play[tp] = true
		print("%s | %s | %s | %s | %s" % [id, ct if ct != "" else "-",
			te if te != "" else "-", td if td != "" else "-",
			tp if tp != "" else "-"])

	print("")
	print("[creature_fx] creatures: %d, trigger carriers: %d" % [creatures, carriers])

	# INVARIANT 1 — every used effect type is acknowledged.
	for pair in [[miss_enter, "on_enter", "TRIGGER_FX_ENTER"],
			[miss_death, "on_death", "TRIGGER_FX_DEATH"],
			[miss_play, "on_play", "TRIGGER_FX_PLAY"]]:
		var missing: Dictionary = pair[0]
		if missing.is_empty():
			print("[creature_fx] PASS  every pool %s type acknowledged in %s"
				% [pair[1], pair[2]])
		else:
			fails += 1
			print("[creature_fx] FAIL  %s type(s) NOT in %s: %s — each plays"
				% [pair[1], pair[2], str(missing.keys())])
			print("            announce-only forever. Decide its beat and add it.")

	# INVARIANT 2 — every tribe has a colour.
	if miss_ctype.is_empty():
		print("[creature_fx] PASS  every pool ctype has a CTYPE_COLORS entry")
	else:
		fails += 1
		print("[creature_fx] FAIL  ctype(s) without a colour: %s" % str(miss_ctype.keys()))

	# INVARIANT 3 — keystone signatures point at live cards.
	var want_passives := ["warden_line", "beast_encore", "reap_on_ally_death",
		"coven_spell", "bastion_ramp"]
	var found := {}
	var typebuff_found := false
	for id in pool:
		var d2: Dictionary = pool[id]
		var p := String(d2.get("passive", ""))
		if p in want_passives:
			found[p] = true
		if d2.get("type_buff", null) is Dictionary:
			typebuff_found = true
	for p in want_passives:
		if not found.has(p):
			fails += 1
			print("[creature_fx] FAIL  keystone passive '%s' not on any pool card — its signature FX is dead code" % p)
	if typebuff_found and found.size() == want_passives.size():
		print("[creature_fx] PASS  all 6 keystone signatures point at live cards (5 passives + type_buff)")
	elif not typebuff_found:
		fails += 1
		print("[creature_fx] FAIL  no pool card carries type_buff — the aura announce is dead code")

	# INVARIANT 4 — the wiring exists.
	var kw_calls := kw_src.count("ctx._play_trigger_fx(")
	if kw_calls >= 2:
		print("[creature_fx] PASS  KeywordEffects wires both channels (%d call sites)" % kw_calls)
	else:
		fails += 1
		print("[creature_fx] FAIL  KeywordEffects has %d _play_trigger_fx call site(s), need 2 (enter + death)" % kw_calls)
	var play_wired := combat_src.find('_play_trigger_fx(floop_data, card, lane_idx, is_enemy, "play")') >= 0
	if play_wired:
		print("[creature_fx] PASS  _resolve_on_play_ability wires the play channel")
	else:
		fails += 1
		print("[creature_fx] FAIL  the on_play channel is not wired in _resolve_on_play_ability")

	print("")
	print("[creature_fx] ALL PASS" if fails == 0 else "[creature_fx] %d FAIL(S)" % fails)
	quit(1 if fails > 0 else 0)
	return true
