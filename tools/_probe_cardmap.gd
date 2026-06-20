extends SceneTree
## Dump draftable creatures with their on_play / on_enter / passive / floop so the
## "flat deal-N filler" can be told apart from tactical verbs (2026-06-18).
func _process(_d: float) -> bool:
	var CDB = root.get_node_or_null("CardDB")
	var rows: Array = []
	for id in CDB.CARD_POOL.keys():
		var d: Dictionary = CDB.CARD_POOL[id]
		if String(d.get("type","")) != "creature": continue
		var rar := String(d.get("rarity",""))
		if not (rar in ["starter","common","uncommon","rare"]): continue
		var op := ""
		if d.has("on_play"): op = "on_play=%s/%s" % [String(d["on_play"].get("type","")), str(d["on_play"].get("value",""))]
		var oe := ""
		if d.has("on_enter"): oe = "on_enter=%s" % String(d["on_enter"].get("type",""))
		var od := ""
		if d.has("on_death"): od = "on_death=%s" % String(d["on_death"].get("type",""))
		var pa := ""
		if d.has("passive"): pa = "passive=%s" % String(d["passive"])
		var kw := ""
		if d.get("keywords",[]).size() > 0: kw = "kw=%s" % str(d["keywords"])
		var parts: Array = []
		for s in [op,oe,od,pa,kw]:
			if s != "": parts.append(s)
		var extra := " ".join(parts)
		if extra == "": extra = "— VANILLA —"
		rows.append("%-9s %-16s %d/%d/%d  %s" % [rar, String(id), int(d.get("cost",0)), int(d.get("atk",0)), int(d.get("hp",0)), extra])
	rows.sort()
	for r in rows: print("[cardmap] ", r)
	print("[cardmap] total=%d" % rows.size())
	quit(0)
	return true
