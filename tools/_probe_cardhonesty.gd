extends SceneTree
## Card-honesty probe (2026-07-01). For every creature effect that carries a
## numeric `value` (on_enter / on_death / on_play), check that the number shows up
## in the card's desc. A damage/draw/heal effect whose value is absent from the
## desc is a likely "card that doesn't do what it says". Heuristic + conservative:
## it only flags effect TYPES that are meant to name their number, and skips the
## handful of "equal to X" / positional descs that legitimately omit a literal.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_cardhonesty.gd

# Effect types whose desc SHOULD contain the effect's value (a number).
const NUMERIC_TYPES := {
	"damage_opposing": true, "damage_opposing_lane": true, "damage_any": true,
	"damage_all_enemies": true, "damage_random_player": true, "damage_face": true,
	"draw": true, "gain_gold": true, "bonus_mana": true, "debuff_opposing_atk": true,
	"shove_back": true, "haul_front": true, "snipe_back": true, "vanguard_split": true,
	"heal_all_friendly": true, "damage_adjacent": true,
	# plain spell types
	"damage": true, "heal": true, "buff_atk": true, "buff_hp": true, "damage_all": true,
}
# Descs that legitimately omit a literal number (scaled / conditional effects).
const DESC_OK_WITHOUT_NUM := ["equal to", "its ATK", "their ATK", "missing HP", "for each"]

func _num_in_desc(desc: String, v: int) -> bool:
	# crude word-boundary check for the integer v in the desc
	for tok in desc.replace(".", " ").replace(",", " ").replace("+", " ").split(" ", false):
		if tok.is_valid_int() and int(tok) == v:
			return true
	return false

func _desc_excused(desc: String) -> bool:
	for phrase in DESC_OK_WITHOUT_NUM:
		if desc.findn(phrase) != -1:
			return true
	return false

func _check(id: String, desc: String, eff: Dictionary, slot: String, flags: Array) -> void:
	var t := String(eff.get("type", ""))
	if not NUMERIC_TYPES.has(t):
		return
	if not eff.has("value"):
		return
	var v := int(eff["value"])
	if v == 0:
		return
	if _desc_excused(desc):
		return
	if not _num_in_desc(desc, v):
		flags.append("  %-22s %-8s type=%-20s value=%d  | desc: %s" % [id, slot, t, v, desc])

func _process(_d: float) -> bool:
	var CDB = root.get_node_or_null("CardDB")
	if CDB == null:
		print("[honesty] CardDB autoload missing"); return true
	var flags: Array = []
	var upg_flags: Array = []
	for id in CDB.CARD_POOL.keys():
		var d: Dictionary = CDB.CARD_POOL[id]
		var desc := String(d.get("desc", ""))
		for slot in ["on_enter", "on_death", "on_play"]:
			if d.has(slot):
				_check(String(id), desc, d[slot], slot, flags)
		# Plain-type spells (custom spells keep their numbers in Combat.gd — spot-
		# checked separately). Check the spell.value against the desc.
		if d.has("spell") and String(d["spell"].get("type","")) in \
				["damage","damage_face","heal","buff_atk","buff_hp","damage_all_enemies","damage_all"]:
			_check(String(id), desc, d["spell"], "spell", flags)
		# Upgraded variant: fold the delta and re-check against the upgrade desc.
		if CDB.UPGRADES.has(id):
			var u: Dictionary = CDB.UPGRADES[id]
			var udesc := String(u.get("desc", desc))
			# Re-derive the upgraded effect values the same way _apply_plus does:
			# on_<slot>_value bumps the sub-effect .value.
			for slot in ["on_enter", "on_death", "on_play"]:
				if d.has(slot):
					var merged: Dictionary = (d[slot] as Dictionary).duplicate(true)
					var vkmap := {"on_enter":"on_enter_value","on_death":"on_death_value","on_play":"on_play_value"}
					var vk: String = vkmap[slot]
					if u.has(vk) and merged.has("value"):
						merged["value"] = int(merged["value"]) + int(u[vk])
					_check(String(id), udesc, merged, slot + "+", upg_flags)
	print("[honesty] === BASE mismatches (value not in desc) ===")
	if flags.is_empty():
		print("  (none)")
	for f in flags:
		print(f)
	print("[honesty] === UPGRADE mismatches ===")
	if upg_flags.is_empty():
		print("  (none)")
	for f in upg_flags:
		print(f)
	print("[honesty] DONE")
	return true
