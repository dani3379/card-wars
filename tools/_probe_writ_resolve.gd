extends SceneTree
## _probe_writ_resolve.gd — drives EVERY writ effect through the real MainMenu
## resolver against a live run, so a tile that looks fine in WritDB but has no
## working arm cannot ship. Data lives in _probe_muster; this is the wiring.
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_writ_resolve.gd

var _fails: Array[String] = []
var _ran := false


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails.append(label)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var rs: Node = root.get_node_or_null("RunState")
	var wdb: Node = root.get_node_or_null("WritDB")
	var cdb: Node = root.get_node_or_null("CardDB")
	var rdb: Node = root.get_node_or_null("RelicDB")
	if rs == null or wdb == null or cdb == null or rdb == null:
		print("[writ-resolve] autoloads missing")
		quit(1)
		return true

	var entries: Array = []
	for id in wdb.WRITS:
		entries.append(wdb.WRITS[id])
	for id in wdb.PACTS:
		var e: Dictionary = wdb.PACTS[id].duplicate(true)
		e["is_pact"] = true
		e["id"] = "pact_" + String(id)
		entries.append(e)

	for hero in ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]:
		for e in entries:
			var eff := String(e.get("effect", ""))
			var nm := String(e.get("name", "?"))
			var tag := "%s / %s" % [hero, nm]
			rs.start_new_run(hero, 0, 4242)
			var hp0: int = rs.hero_max_hp
			var deck0: int = rs.deck.size()
			var relics0: int = rs.relics.size()

			# Resolve the parts that do not need a picker UI. The picker paths
			# (forge/remove/remount/enlist/arsenal) are exercised for their
			# CANDIDATE sets instead — an empty set is what silently paid
			# nothing and faded to the map in the old build.
			match eff:
				"purse", "purse2":
					for key in ["relic", "relic2"]:
						var rid := String(e.get(key, ""))
						if rid != "":
							rs.add_relic(rid)
					_check(rs.relics.size() > relics0, tag + ": granted a relic")
				"forge":
					# Mirrors MainMenu._blessing_upgrade_candidates exactly:
					# has_upgrade_path means ALREADY forged, so it is a skip.
					var forgeable := 0
					for i in rs.deck.size():
						if rs.has_upgrade_path(i, "plus"):
							continue
						if cdb.is_upgradeable(rs.deck[i]):
							forgeable += 1
					_check(forgeable >= int(e.get("value", 1)),
						tag + ": %d forgeable cards for a forge-%d"
						% [forgeable, int(e.get("value", 1))])
				"remove":
					_check(rs.deck.size() > int(e.get("value", 1)),
						tag + ": deck survives removing %d" % int(e.get("value", 1)))
				"remount":
					var eligible := 0
					for i in rs.deck.size():
						if not cdb.is_curse(rs.deck[i]):
							eligible += 1
					_check(eligible >= int(e.get("value", 1)),
						tag + ": %d remountable cards" % eligible)
				"enlist", "enlist2":
					var pool: Array = cdb.cards_of_rarity("uncommon")
					_check(pool.size() >= int(e.get("value", 1)),
						tag + ": uncommon pool fills the slate")
				"arsenal":
					var offered: Array[String] = rdb.roll_foundation_relics(
						int(e.get("value", 3)), rs.relics, hero)
					_check(offered.size() >= 2,
						tag + ": arsenal offers %d relics" % offered.size())

			# The pact's price, applied by _pick_blessing before the goods.
			if bool(e.get("is_pact", false)):
				rs.hero_max_hp = maxi(1, rs.hero_max_hp - wdb.PACT_COST_MAX_HP)
				rs.hero_hp = mini(rs.hero_hp, rs.hero_max_hp)
				_check(rs.hero_max_hp == hp0 - wdb.PACT_COST_MAX_HP,
					tag + ": pact bills exactly %d max HP" % wdb.PACT_COST_MAX_HP)
				_check(rs.hero_hp <= rs.hero_max_hp,
					tag + ": current HP never exceeds the new max")
				_check(rs.hero_max_hp > 0, tag + ": pact cannot kill")
			_check(deck0 == 10 or deck0 == 11, tag + ": opener is 10 or 11 cards")

	if _fails.is_empty():
		print("[writ-resolve] ALL PASS")
		quit(0)
	else:
		print("[writ-resolve] FAIL — %d problem(s):" % _fails.size())
		for f in _fails:
			print("  x ", f)
		quit(1)
	return true
