extends SceneTree
## Spell-VFX coverage GATE (S1 of docs/SPELL_FX_PLAN_20260717.md).
##
## Two invariants, both of which FAIL the probe:
##   1. Every spell in CardDB.CARD_POOL is tagged into a Combat.SPELL_FAMILIES
##      family. An untagged spell doesn't error at runtime — it silently casts a
##      generic colour puff forever, which is how the map drifted to 42%
##      untagged (33 of 78) before anyone noticed.
##   2. No family tag points at an id that isn't in the pool. Six such corpses
##      had accumulated (`lightning`, `bloodletting`, `second_wind`,
##      `reposition`, `barricade`, `scrap`) — they made the shock family look
##      twice its real size.
##
## Also dumps the full table (family / spell.type / targeting / scope) — the
## inventory the FX plan's per-spell assignment is built from.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_spell_fx_audit.gd
## Grep for "ALL PASS" — don't trust the exit code alone.

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true

	var C = load("res://scripts/data/CardDB.gd")
	var combat_src := FileAccess.open("res://scripts/scenes/Combat.gd",
		FileAccess.READ).get_as_text()

	# Scrape SPELL_FAMILIES straight out of Combat.gd so the audit can't drift
	# from the live map.
	var fam := {}
	var blk_start := combat_src.find("const SPELL_FAMILIES := {")
	var blk_end := combat_src.find("}", blk_start)
	var blk := combat_src.substr(blk_start, blk_end - blk_start)
	# The family list is DELIBERATELY hardcoded: a brand-new family fails the
	# probe until it's acknowledged here — which is also the reminder that a
	# new family needs its _vfx_* impact, a _spell_vfx_color entry, and an
	# impact-ring oval decision. ("frost" added 2026-07-17, the 7th.)
	var re := RegEx.new()
	re.compile('"([a-z_0-9]+)"\\s*:\\s*"(fire|shock|frost|blight|blessing|earth|mind)"')
	for m in re.search_all(blk):
		fam[m.get_string(1)] = m.get_string(2)

	var pool: Dictionary = C.CARD_POOL
	var spells: Array = []
	for id in pool:
		var d: Dictionary = pool[id]
		if String(d.get("type", "")) != "spell":
			continue
		spells.append(id)
	spells.sort()

	var by_fam := {}
	var untagged: Array = []
	print("id | name | rarity | family | spell.type | targeting | scope")
	print("---")
	for id in spells:
		var d: Dictionary = pool[id]
		var sp: Dictionary = d.get("spell", {})
		var f: String = String(fam.get(id, ""))
		if f == "":
			untagged.append(id)
		else:
			by_fam[f] = int(by_fam.get(f, 0)) + 1
		print("%s | %s | %s | %s | %s | %s | %s" % [
			id, d.get("name", "?"), d.get("rarity", "?"),
			f if f != "" else "** NONE **",
			sp.get("type", "?"), d.get("targeting", "-"), d.get("scope", "-")])

	print("")
	print("[spell_fx] TOTAL SPELLS: %d" % spells.size())
	print("[spell_fx] BY FAMILY   : %s" % str(by_fam))

	var fails := 0

	# INVARIANT 1 — every spell is tagged.
	if untagged.is_empty():
		print("[spell_fx] PASS  every spell is tagged into a family (%d/%d)"
			% [spells.size(), spells.size()])
	else:
		fails += 1
		print("[spell_fx] FAIL  %d spell(s) UNTAGGED — each casts a generic colour puff:"
			% untagged.size())
		for id in untagged:
			var d2: Dictionary = pool[id]
			print("            %s (%s) — spell.type=%s" % [
				id, d2.get("name", "?"), d2.get("spell", {}).get("type", "?")])
		print("            → add each to Combat.SPELL_FAMILIES (see")
		print("              docs/SPELL_FX_PLAN_20260717.md §4 for the assignment).")

	# INVARIANT 2 — no family tag points at a card that no longer exists.
	var dead: Array = []
	for id in fam:
		if not pool.has(id):
			dead.append(id)
	if dead.is_empty():
		print("[spell_fx] PASS  no dead family tags (every tagged id is a live card)")
	else:
		fails += 1
		print("[spell_fx] FAIL  %d DEAD family tag(s) — id not in CARD_POOL: %s"
			% [dead.size(), str(dead)])
		print("            → delete them from Combat.SPELL_FAMILIES; they inflate")
		print("              a family's apparent size and route nothing.")

	print("")
	print("[spell_fx] ALL PASS" if fails == 0 else "[spell_fx] %d FAIL(S)" % fails)
	quit(1 if fails > 0 else 0)
	return true
