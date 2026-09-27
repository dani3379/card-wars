extends Node
## _probe_card_art.gd — which cards fall back to the placeholder glyph?
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_card_art.tscn
## Runs as a SCENE so autoload names resolve (the --script SceneTree form fails
## to compile on a bare `CardDB` reference — same reason _probe_parsecheck is a
## scene). Mirrors Card2D._find_card_art exactly (spells through the spell
## loader first, then id → name_id → "e_"+name_id), so anything listed here
## really does render the line-art stand-in instead of a painting.
func _ready() -> void:
	var missing: Array = []
	for cid in CardDB.CARD_POOL.keys():
		var d: Dictionary = CardDB.get_card_data(String(cid))
		var rarity := String(d.get("rarity", ""))
		if rarity == "enemy":
			continue
		var name_id := String(d.get("name", "")).to_lower() \
			.replace(" ", "_").replace("'", "")
		var art = null
		# ARMAMENTS take the spell loader too — Card2D._find_card_art gates on
		# `is_spell() or is_armament()`, and missing that half of the condition
		# made the first run report six well-aliased weapons as artless.
		var ty := String(d.get("type", ""))
		if ty == "spell" or ty == "armament":
			art = CardArtAliases.try_load_spell_art(String(cid))
			if art == null:
				art = CardArtAliases.try_load_spell_art(name_id)
		if art == null:
			art = CardArtAliases.try_load_creature_art(String(cid))
		if art == null and name_id != "":
			art = CardArtAliases.try_load_creature_art(name_id)
		if art == null and name_id != "":
			art = CardArtAliases.try_load_creature_art("e_" + name_id)
		if art == null:
			missing.append("%-24s %-9s %-9s %s" % [cid, d.get("type", ""),
				rarity, d.get("name", "")])
	missing.sort()
	print("[card-art] %d playable cards with NO art:" % missing.size())
	for m in missing:
		print("  ", m)
	get_tree().quit()
