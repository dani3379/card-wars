extends SceneTree
## _probe_vanilla_scan.gd — lists draftable CREATURES with no rules text at all
## (no on_enter / on_death / on_play / floop / passive / adj_buff / wither and no
## keywords). These are the "vanilla" bodies — the cheapest place a keyword buys
## the most character, per the lenticular-commons finding in DESIGN_RESEARCH.
## Print-only. Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_vanilla_scan.gd

const EFFECT_KEYS := ["on_enter", "on_death", "on_play", "floop", "adj_buff",
	"type_buff", "passive", "wither", "doom", "extra_damage", "sniper"]


func _process(_d: float) -> bool:
	var CDB = root.get_node_or_null("CardDB")
	if CDB == null:
		print("FATAL no CardDB")
		quit(1)
		return true
	var rows: Array = []
	for id in CDB.CARD_POOL.keys():
		var c: Dictionary = CDB.CARD_POOL[id]
		if String(c.get("type", "")) != "creature":
			continue
		var rarity := String(c.get("rarity", ""))
		if rarity in ["enemy", "token"]:
			continue
		var has_effect := false
		for k in EFFECT_KEYS:
			if not c.has(k):
				continue
			# Type-aware emptiness. Comparing a Dictionary against 0 or "" is an
			# invalid-operands runtime error in GDScript, not a false result.
			var v = c[k]
			var empty := false
			if v == null:
				empty = true
			elif v is Dictionary:
				empty = (v as Dictionary).is_empty()
			elif v is Array:
				empty = (v as Array).is_empty()
			elif v is String:
				empty = String(v) == ""
			elif v is bool:
				empty = not bool(v)
			elif v is int or v is float:
				empty = float(v) == 0.0
			if not empty:
				has_effect = true
				break
		var kws: Array = c.get("keywords", [])
		if has_effect or not kws.is_empty():
			continue
		rows.append({
			"id": String(id), "rarity": rarity,
			"cost": int(c.get("cost", 0)),
			"atk": int(c.get("atk", 0)), "hp": int(c.get("hp", 0)),
			"ctype": String(c.get("ctype", "-")),
		})
	rows.sort_custom(func(a, b):
		if a["cost"] != b["cost"]:
			return a["cost"] < b["cost"]
		return a["atk"] + a["hp"] < b["atk"] + b["hp"])
	print("=== VANILLA CREATURES (no keywords, no effects): %d ===" % rows.size())
	for r in rows:
		print("  %-22s %-9s c%d  %d/%d  stats=%d  %s" % [
			r["id"], r["rarity"], r["cost"], r["atk"], r["hp"],
			r["atk"] + r["hp"], r["ctype"]])
	quit(0)
	return true
