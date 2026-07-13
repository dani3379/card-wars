extends SceneTree
## _probe_card_dump.gd — one-shot audit dump: every draftable card's rules text
## next to its mechanical data, so desc-vs-implementation drift can be read
## side by side. Print-only; no assertions.
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_card_dump.gd

func _init() -> void:
	var cdb = root.get_node_or_null("/root/CardDB")
	if cdb == null:
		# Autoloads may not be up in _init for SceneTree scripts; use the class.
		pass

func _process(_d: float) -> bool:
	var CDB = root.get_node_or_null("CardDB")
	if CDB == null:
		print("FATAL no CardDB")
		quit(1)
		return true
	var ids: Array = CDB.CARD_POOL.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = CDB.CARD_POOL[id]
		var rar: String = String(d.get("rarity", ""))
		if rar == "enemy" or CDB.is_curse(id):
			continue
		var mech: Array[String] = []
		for k in ["on_enter", "on_death", "floop", "spell", "adj_buff", "type_buff",
				"passive", "wither", "extra_damage", "rampage", "grow", "sniper",
				"doom", "keywords", "ctype"]:
			if d.has(k):
				var v = d[k]
				if (v is Array and (v as Array).is_empty()) or (v is Dictionary and (v as Dictionary).is_empty()):
					continue
				mech.append("%s=%s" % [k, str(v)])
		print("■ %s [%s %s c%s %s/%s]" % [id, rar, String(d.get("type", "")),
			str(d.get("cost", "")), str(d.get("atk", "-")), str(d.get("hp", "-"))])
		print("   desc: %s" % String(d.get("desc", "")))
		print("   mech: %s" % " | ".join(mech))
	quit(0)
	return true
