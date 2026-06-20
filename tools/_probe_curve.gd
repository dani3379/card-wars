extends SceneTree
## Card stat-curve audit (2026-06-18). Checks every DRAFTABLE creature in
## CardDB.CARD_POOL against the 2026-06-17 rebalance curve (see memory
## project_card_balance_curve):
##   vanilla body budget (ATK+HP, no keyword/effect): 1c=4 2c=6 3c=8 4c=10 (0c=3, +2/cost beyond).
##   keywords/effects cost body: a loaded card should run BELOW vanilla; a
##   premium keyword (swift/ranged/poison/lifelink/...) ≈ -2, a minor one ≈ -1,
##   each effect dict (on_enter/on_death/adj_buff/passive/wither/floop) ≈ -1.
##   Uncommon/rare get +1 rarity tax (the gate IS the rarity).
## Flags creatures whose body exceeds the loadout-adjusted ceiling (= under-costed
## = too strong). Pure logic, no combat. Starters/enemy/curse excluded.
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_curve.gd

var CDB: Node
var _started := false

# Keywords that are real combat value (premium = -2, minor = -1). Anything not
# listed and not an effect-marker / downside is treated as minor.
const PREMIUM := {
	"swift": true, "ranged": true, "piercing": true, "poison": true,
	"lifelink": true, "armored": true, "regenerate": true, "last_stand": true,
	"shield": true, "rampage": true, "overrun": true,
}
const MINOR := {"thorns": true, "formation": true, "taunt": true}
# DOWNSIDES for a player creature — the body is temporary/shrinking, so bigger
# stats are JUSTIFIED (doom = detonates on a timer; wither = loses stats each
# round). These RAISE the ceiling instead of lowering it.
const DOWNSIDE := {"doom": true, "wither": true}
# Listed in `keywords` but NOT a body-costing keyword — they just mark that an
# effect dict exists (counted separately) or are display-only.
const MARKERS := {"on_enter": true, "on_death": true, "on_play": true, "floop": true}


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[curve] start")
	CDB = root.get_node_or_null("CardDB")
	if CDB == null:
		print("[curve] FATAL no CardDB"); quit(1); return

	var flags: Array = []
	var under: Array = []
	var walls: Array = []
	var n := 0
	for id in CDB.CARD_POOL.keys():
		var d: Dictionary = CDB.CARD_POOL[id]
		if String(d.get("type", "")) != "creature":
			continue
		var rarity := String(d.get("rarity", ""))
		if rarity in ["starter", "enemy"] or CDB.is_curse(String(id)):
			continue
		n += 1
		var cost := int(d.get("cost", 0))
		var atk := int(d.get("atk", 0))
		var hp := int(d.get("hp", 0))
		var body := atk + hp
		var budget := _budget(cost)

		# Loadout discount.
		var discount := 0
		var loadout: Array = []
		for kw in d.get("keywords", []):
			var k := String(kw)
			if MARKERS.has(k):
				continue
			if DOWNSIDE.has(k):
				discount -= 2; loadout.append(k + "↓")   # drawback: bigger body is OK
			elif PREMIUM.has(k):
				discount += 2; loadout.append(k + "*")
			else:
				discount += 1; loadout.append(k)
		for ek in ["on_enter", "on_death", "floop", "adj_buff", "passive", "wither", "extra_damage"]:
			if d.has(ek):
				discount += 1; loadout.append(ek)
		# adj_buff that buffs 2 stats / on_death summon are stronger — small extra.
		if d.has("adj_buff"):
			var ab: Dictionary = d.get("adj_buff", {})
			if int(ab.get("atk", 0)) + int(ab.get("hp", 0)) >= 2:
				discount += 1

		var rarity_tax := 1 if rarity in ["uncommon", "rare"] else 0
		var ceiling := budget - discount + rarity_tax
		var over := body - ceiling
		var row := "%-18s c%d %d/%d body=%-2d budget=%d disc=%d tax=%d ceil=%-2d over=%+d [%s] %s" \
			% [id, cost, atk, hp, body, budget, discount, rarity_tax, ceiling, over,
				rarity, ",".join(PackedStringArray(loadout))]
		if over >= 1:
			# 0-1 ATK bodies are defensive walls (high HP isn't a value engine);
			# bucket them apart so they don't read as "too strong".
			if atk <= 1:
				walls.append({"over": over, "row": row})
			else:
				flags.append({"over": over, "row": row})
		elif over <= -3:
			under.append({"over": over, "row": row})

	flags.sort_custom(func(a, b): return a["over"] > b["over"])
	walls.sort_custom(func(a, b): return a["over"] > b["over"])
	under.sort_custom(func(a, b): return a["over"] < b["over"])
	print("[curve] audited %d draftable creatures" % n)
	print("[curve] ===== OVER-CURVE OFFENSIVE (under-costed / too strong; atk>=2, over>=+1) =====")
	for f in flags:
		print("[curve] ", f["row"])
	print("[curve] ===== over-budget WALLS (atk<=1; high HP but no offense — usually fine) =====")
	for w in walls:
		print("[curve] ", w["row"])
	print("[curve] ===== well UNDER curve (weak; over<=-3) =====")
	for u in under:
		print("[curve] ", u["row"])
	print("[curve] (%d offensive over-curve, %d walls, %d under-curve)" % [flags.size(), walls.size(), under.size()])
	print("[curve] DONE")
	quit(0)


func _budget(cost: int) -> int:
	if cost <= 0:
		return 3
	return 2 + cost * 2   # 1c=4, 2c=6, 3c=8, 4c=10, 5c=12
