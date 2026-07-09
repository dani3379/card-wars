extends SceneTree
## Headless check of the War Chest opener pools (remade 2026-07-03).
## The blessing screen itself is UI-driven, but everything under it is pure
## logic: the roll (3 honest + 1 priced, distinct, shuffled), the entry copy
## (every id must render a name+desc), the non-modal applies, and the
## transform helper the Remount Line picker calls. This walks all of it on a
## MainMenu instance that never enters the tree (_ready never fires).
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_warchest.gd

var _fails := 0


func _check(ok: bool, label: String) -> void:
	print(("ok  " if ok else "  FAIL  ") + label)
	if not ok:
		_fails += 1


func _process(_delta: float) -> bool:
	var RS: Node = root.get_node_or_null("RunState")
	var CDB: Node = root.get_node_or_null("CardDB")
	if RS == null or CDB == null:
		print("[warchest] FATAL: autoloads missing")
		quit(1)
		return true

	var mm = load("res://scenes/main_menu.tscn").instantiate()

	# ── Entry copy: every pool id renders a real tile ──
	var honest := ["gold", "upgrade", "transform2", "recruit", "max_hp", "potions", "relic"]
	var priced := ["black_ledger", "widows_coin", "butchers_kindness", "hollow_levy"]
	for id in honest + priced:
		var e: Dictionary = mm._blessing_entry(id, id in priced)
		_check(String(e.get("name", "")) != String(id) and String(e.get("desc", "")) != "",
			"entry '%s' has bespoke name+desc" % id)

	# ── The roll: 4 tiles, exactly 1 priced, honest ids distinct ──
	for _i in 20:
		var entries: Array = mm._roll_blessings()
		var risky_n := 0
		var ids: Array = []
		for e in entries:
			ids.append(e.id)
			if e.risky:
				risky_n += 1
		if entries.size() != 4 or risky_n != 1 or ids.size() != 4:
			_check(false, "roll shape (4 tiles, 1 priced): got %d tiles, %d priced" \
				% [entries.size(), risky_n])
			break
		var seen := {}
		for id in ids:
			if seen.has(id):
				_check(false, "roll repeats id '%s'" % id)
				break
			seen[id] = true
	_check(true, "20 rolls: 4 tiles, exactly 1 priced, no repeats")

	# ── Non-modal applies ──
	RS.start_new_run("raider")
	var g0: int = RS.gold
	mm._apply_blessing("gold")
	_check(RS.gold == g0 + 75, "gold: +75 (was %d, now %d)" % [g0, RS.gold])

	RS.start_new_run("raider")
	var m0: int = RS.hero_max_hp
	var h0: int = RS.hero_hp
	mm._apply_blessing("max_hp")
	_check(RS.hero_max_hp == m0 + 7 and RS.hero_hp == h0 + 7,
		"max_hp: +7 cap and +7 current (%d/%d)" % [RS.hero_hp, RS.hero_max_hp])

	RS.start_new_run("raider")
	var p0: int = RS.potions.size()
	mm._apply_blessing("potions")
	_check(RS.potions.size() == mini(p0 + 2, RS.MAX_POTIONS), "potions: +2 bottles")

	RS.start_new_run("raider")
	var r0: int = RS.relics.size()
	mm._apply_blessing("relic")
	_check(RS.relics.size() == r0 + 1, "relic: +1 relic")

	RS.start_new_run("raider")
	r0 = RS.relics.size()
	var d0: int = RS.deck.size()
	mm._apply_blessing("black_ledger")
	var curses := 0
	for cid in RS.deck:
		if CDB.is_curse(cid):
			curses += 1
	_check(RS.relics.size() == r0 + 1 and RS.deck.size() == d0 + 2 and curses == 2,
		"black_ledger: +1 relic, +2 Curses")

	RS.start_new_run("raider")
	g0 = RS.gold
	m0 = RS.hero_max_hp
	mm._apply_blessing("widows_coin")
	_check(RS.gold == g0 + 150 and RS.hero_max_hp == m0 - 6 and RS.hero_hp <= RS.hero_max_hp,
		"widows_coin: +150 gold, -6 max HP, hp clamped")

	# ── The Remount Line's transform helper ──
	RS.start_new_run("raider")
	d0 = RS.deck.size()
	var old_id: String = RS.deck[0]
	mm._blessing_transform_at(0)
	var changed: bool = RS.deck.size() == d0 and RS.deck[RS.deck.size() - 1] != old_id
	_check(changed, "transform_at: deck size stable, card changed (%s -> %s)" \
		% [old_id, RS.deck[RS.deck.size() - 1]])

	# ── The Muster Tent's offer pool ──
	var unc: Array = CDB.cards_of_rarity("uncommon")
	_check(unc.size() >= 3, "recruit: uncommon pool holds 3+ offers (%d)" % unc.size())

	print("[warchest] RESULT: %s — fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	mm.free()
	quit(0 if _fails == 0 else 1)
	return true
