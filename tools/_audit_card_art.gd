extends SceneTree
## Card-art duplicate audit. Resolves the ACTUAL image every card renders (via the
## real CardArtAliases loader: dedicated file → alias fallback → none) and groups
## cards that share a file, so we can see which portraits are reused across cards.
## Run: Godot..._console.exe --headless --path "D:\Godot" --script res://tools/_audit_card_art.gd

func _name(id: String) -> String:
	return String((CardDB.CARD_POOL.get(id, {}) as Dictionary).get("name", id))


func _initialize() -> void:
	var draftable := ["starter", "common", "uncommon", "rare"]

	# resolved-art-path → { "draft": [ids], "enemy": [ids], "type": "creature"/"spell" }
	var groups: Dictionary = {}
	var total := 0
	for id in CardDB.CARD_POOL.keys():
		var d: Dictionary = CardDB.CARD_POOL[id]
		var ctype := String(d.get("type", "creature"))
		if ctype == "token" or ctype == "curse":
			continue   # not real draft/enemy portraits
		total += 1
		var tex: Texture2D = null
		if ctype == "spell":
			tex = CardArtAliases.try_load_spell_art(id)
		else:
			tex = CardArtAliases.try_load_creature_art(id)
		var key := "NONE (placeholder)"
		if tex != null and tex.resource_path != "":
			key = tex.resource_path
		if not groups.has(key):
			groups[key] = {"draft": [], "enemy": [], "type": ctype}
		var bucket := "draft" if draftable.has(String(d.get("rarity", ""))) else "enemy"
		groups[key][bucket].append(id)

	# Sort groups by how many cards share them (worst offenders first).
	var keys := groups.keys()
	keys.sort_custom(func(a, b):
		var ga: Dictionary = groups[a]
		var gb: Dictionary = groups[b]
		return (ga["draft"].size() + ga["enemy"].size()) > (gb["draft"].size() + gb["enemy"].size()))

	var shared_files := 0
	var draft_cards_sharing := 0
	print("\n================  SHARED CARD ART  ================")
	print("(each block = one portrait file; the OWNER keeps it, the BORROWERS need new art)\n")
	for k in keys:
		var g: Dictionary = groups[k]
		var n: int = g["draft"].size() + g["enemy"].size()
		if n < 2:
			continue
		shared_files += 1
		draft_cards_sharing += g["draft"].size()
		var owner_file := String(k).get_file().get_basename()
		var all_ids: Array = (g["draft"] as Array) + (g["enemy"] as Array)
		all_ids.sort()
		# Borrowers = every card that isn't the file's namesake owner.
		var borrowers: Array = []
		var owner_present := false
		for cid in all_ids:
			if cid == owner_file:
				owner_present = true
			else:
				borrowers.append("%s (%s)" % [_name(cid), cid])
		var owner_label := "%s [owner]" % owner_file if owner_present else "%s [no card owns this file]" % owner_file
		print("● portrait '%s.png'  — shared by %d cards" % [owner_file, n])
		print("    keeps it: ", owner_label)
		print("    NEEDS OWN ART: ", ", ".join(borrowers))
		print("")

	# Cards with NO art at all (render the placeholder) — a different kind of "same".
	if groups.has("NONE (placeholder)"):
		var none: Dictionary = groups["NONE (placeholder)"]
		print("================  NO DEDICATED ART (placeholder)  ================")
		if not none["draft"].is_empty():
			none["draft"].sort()
			print("    DRAFTABLE: ", ", ".join(none["draft"]))
		if not none["enemy"].is_empty():
			none["enemy"].sort()
			print("    enemy/other: ", ", ".join(none["enemy"]))
		print("")

	print("================  SUMMARY  ================")
	print("Cards audited: ", total)
	print("Image files shared by 2+ cards: ", shared_files)
	print("Draftable cards that share art with another card: ", draft_cards_sharing)
	quit()
