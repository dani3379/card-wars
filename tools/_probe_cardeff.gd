extends SceneTree
## Card efficiency analyzer (triage for the "bad for cost / unplayable" audit).
## Scores every DRAFTABLE card's body against the balance-curve budget and a
## transparent effect-discount map, then ranks the most overcosted. This is a
## HEURISTIC triage, not a verdict — it flags low-body cards; whether a weak
## body is justified by the effect is a judgment call left to the design pass.
##
## Curve (from the 2026-06-17 rebalance): vanilla body (ATK+HP) budget = cost*2+2
##   1-cost=4 · 2-cost=6 · 3-cost=8 · 4-cost=10 · 5-cost=12 · 0-cost=2.
## Effects/keywords are worth body: a fair effect card sits BELOW vanilla budget.
##   power_delta = body - (budget - discount).  ~0 = on-curve.  <0 = underpowered
##   for its cost (overcosted).  >0 = over-statted (undercosted).
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_cardeff.gd

# Effect value in body-points. Upside = positive (lowers fair body); drawback =
# negative (raises fair body). Trigger-LABEL keywords (on_enter/on_death/adj_buff/
# adjacent/slay) are scored from the DICTs below, not here, to avoid double-count.
const KW_VALUE := {
	"swift": 2.0, "ranged": 1.5, "poison": 2.0, "piercing": 2.0, "summon": 2.0,
	"guardian": 1.5, "shield": 1.5, "last_stand": 1.5, "structure": 1.5,
	"lifelink": 1.0, "overrun": 1.0, "formation": 1.0, "rampage": 1.0,
	"regenerate": 1.0, "thorns": 1.0, "armored": 1.0, "retain": 0.5,
	# drawbacks (negative — the card is weaker, so fair body is HIGHER)
	"doom": -0.5, "wither": -2.0, "exhaust": -1.0, "sacrifice": -1.5,
}
const DICT_VALUE := {
	"on_enter": 1.5, "on_death": 1.0, "floop": 1.5, "adj_buff": 1.5, "passive": 1.5,
}
# keywords that are pure labels (value comes from the matching dict / are neutral)
const LABEL_KW := ["on_enter", "on_death", "adj_buff", "adjacent", "slay"]

var CDB: Node
var _started := false


func _process(_d: float) -> bool:
	if _started:
		return true
	_started = true
	_run()
	return true


func _budget(cost: int) -> int:
	return cost * 2 + 2


func _run() -> void:
	CDB = root.get_node_or_null("CardDB")
	if CDB == null:
		print("[eff] FATAL: CardDB autoload missing"); quit(1); return
	print("[eff] === CARD EFFICIENCY ANALYZER ===")
	print("[eff] budget=cost*2+2 ; power_delta=body-(budget-discount) ; <0 underpowered, >0 over-statted")
	print("[eff] kw legend: ", KW_VALUE)

	var creatures: Array = []
	var spells: Array = []
	for id in CDB.CARD_POOL.keys():
		var sid := String(id)
		var d: Dictionary = CDB.CARD_POOL[sid]
		var rar := String(d.get("rarity", ""))
		if rar == "enemy":
			continue
		if CDB.has_method("is_curse") and CDB.is_curse(sid):
			continue
		var ctype := String(d.get("type", ""))
		if ctype == "creature":
			creatures.append(_score_creature(sid, d))
		elif ctype == "spell":
			spells.append(_score_spell(sid, d))

	# ── CREATURES, worst-on-curve first ──
	creatures.sort_custom(func(a, b): return a["pd"] < b["pd"])
	print("\n[eff] ===== CREATURES (%d) — power_delta ASC (most overcosted first) =====" % creatures.size())
	print("[eff] %6s %4s %6s %4s %5s  %-7s %s" % ["pdelta", "cost", "body", "bud", "disc", "rarity", "id  [tags]"])
	for c in creatures:
		print("[eff] %+6.1f %4d %6s %4d %5.1f  %-7s %s  %s" % [
			c["pd"], c["cost"], c["body_s"], c["bud"], c["disc"], c["rar"], c["id"], c["tags"]])

	# ── flagged overcosted creatures ──
	print("\n[eff] ===== FLAGGED: UNDERPOWERED FOR COST (power_delta <= -1.5) =====")
	for c in creatures:
		if c["pd"] <= -1.5:
			print("[eff] FLAG %+5.1f  %-16s c%d %s  rar=%s  tags=%s" % [
				c["pd"], c["id"], c["cost"], c["body_s"], c["rar"], c["tags"]])
	print("\n[eff] ===== FLAGGED: OVER-STATTED (power_delta >= +2.0) =====")
	for c in creatures:
		if c["pd"] >= 2.0:
			print("[eff] HIGH %+5.1f  %-16s c%d %s  rar=%s  tags=%s" % [
				c["pd"], c["id"], c["cost"], c["body_s"], c["rar"], c["tags"]])

	# ── SPELLS ──
	spells.sort_custom(func(a, b): return a["vpc"] < b["vpc"])
	print("\n[eff] ===== SPELLS (%d) — value/cost ASC (weakest payoff first) =====" % spells.size())
	print("[eff] %5s %4s %6s  %-14s %-16s %s" % ["v/cost", "cost", "value", "spell_type", "id", "targeting"])
	for s in spells:
		print("[eff] %5.1f %4d %6d  %-14s %-16s %s" % [
			s["vpc"], s["cost"], s["value"], s["stype"], s["id"], s["targeting"]])

	print("\n[eff] DONE")
	quit(0)


func _score_creature(sid: String, d: Dictionary) -> Dictionary:
	var cost := int(d.get("cost", 0))
	var atk := int(d.get("atk", 0))
	var hp := int(d.get("hp", 0))
	var body := atk + hp
	var bud := _budget(cost)
	var disc := 0.0
	var tags: Array = []
	for kw in d.get("keywords", []):
		var k := String(kw)
		if k in LABEL_KW:
			continue
		if KW_VALUE.has(k):
			disc += float(KW_VALUE[k])
			tags.append(k)
		else:
			disc += 1.0   # unknown keyword: assume a minor upside, flag it
			tags.append(k + "?")
	for dk in DICT_VALUE.keys():
		if d.has(dk):
			# passive is a String; the rest are Dicts
			var present: bool = (d[dk] is Dictionary and not (d[dk] as Dictionary).is_empty()) \
				or (d[dk] is String and String(d[dk]) != "")
			if present:
				disc += float(DICT_VALUE[dk])
				var label := String(dk)
				if dk == "on_enter" or dk == "on_death":
					label = "%s:%s" % [dk, String((d[dk] as Dictionary).get("type", "?"))]
				elif dk == "floop":
					label = "floop:%s" % String((d[dk] as Dictionary).get("type", "?"))
				elif dk == "passive":
					label = "passive:%s" % String(d[dk])
				tags.append(label)
	if int(d.get("extra_damage", 0)) > 0:
		disc += 0.5 * float(d["extra_damage"])
		tags.append("xdmg%d" % int(d["extra_damage"]))
	var expected := float(bud) - disc
	var pd := float(body) - expected
	return {
		"id": sid, "cost": cost, "body_s": "%d/%d" % [atk, hp], "body": body,
		"bud": bud, "disc": disc, "pd": pd, "rar": String(d.get("rarity", "")),
		"tags": str(tags),
	}


func _score_spell(sid: String, d: Dictionary) -> Dictionary:
	var cost := int(d.get("cost", 0))
	var sp: Dictionary = d.get("spell", {})
	var stype := String(sp.get("type", "?"))
	var value := int(sp.get("value", 0))
	var vpc := float(value) / float(max(1, cost))   # crude payoff/cost for damage/heal/buff
	return {
		"id": sid, "cost": cost, "stype": stype, "value": value,
		"vpc": vpc, "targeting": String(d.get("targeting", "none")),
	}
