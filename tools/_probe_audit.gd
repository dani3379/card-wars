extends SceneTree
## Content cross-reference audit (2026-06-18). Extracts the DISTINCT data-driven
## dispatch keys from the live databases so they can be grepped against the
## inline handlers in Combat.gd — anything referenced in data but unhandled in
## code is a silently-dead card/relic/encounter (no crash, just does nothing).
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_audit.gd

func _process(_d: float) -> bool:
	var CDB = root.get_node_or_null("CardDB")
	var RDB = root.get_node_or_null("RelicDB")
	var EDB = root.get_node_or_null("EncounterDB")
	var KE  = root.get_node_or_null("KeywordEffects")

	var spell_types := {}
	var keywords := {}
	var passives := {}      # creature card_data.passive
	var floop_types := {}
	var on_enter_types := {}
	var on_death_types := {}
	var missing_upgrades := []

	for id in CDB.CARD_POOL.keys():
		var d: Dictionary = CDB.CARD_POOL[id]
		var rarity := String(d.get("rarity", ""))
		if String(d.get("type","")) == "spell" and d.has("spell"):
			spell_types[String(d["spell"].get("type",""))] = true
		for kw in d.get("keywords", []):
			keywords[String(kw)] = true
		if d.has("passive"):
			passives[String(d["passive"])] = true
		if d.has("floop"):
			floop_types[String(d["floop"].get("type",""))] = true
		if d.has("on_enter"):
			on_enter_types[String(d["on_enter"].get("type",""))] = true
		if d.has("on_death"):
			on_death_types[String(d["on_death"].get("type",""))] = true
		# Upgrade coverage: draftable, non-curse cards should have a hand-crafted
		# UPGRADES entry (missing ones fall back to a generic +1/+1 / -1 cost).
		if rarity in ["starter","common","uncommon","rare"] and not CDB.is_curse(String(id)):
			if not CDB.UPGRADES.has(id):
				missing_upgrades.append(String(id))

	var relic_effects := {}
	for rid in RDB.RELICS.keys():
		var r: Dictionary = RDB.RELICS[rid]
		relic_effects[String(r.get("effect",""))] = true

	var enc_passives := {}
	var reactive := {}
	for eid in EDB.ENCOUNTERS.keys():
		var e: Dictionary = EDB.ENCOUNTERS[eid]
		var pid := String(e.get("passive_id",""))
		if pid != "":
			enc_passives[pid] = true
	if "REACTIVE_PASSIVES" in EDB:
		for k in EDB.REACTIVE_PASSIVES.keys():
			reactive[String(k)] = true

	_dump("SPELL_TYPES", spell_types)
	_dump("CARD_KEYWORDS", keywords)
	_dump("CARD_PASSIVES", passives)
	_dump("FLOOP_TYPES", floop_types)
	_dump("ON_ENTER_TYPES", on_enter_types)
	_dump("ON_DEATH_TYPES", on_death_types)
	_dump("RELIC_EFFECTS", relic_effects)
	_dump("ENCOUNTER_PASSIVE_IDS", enc_passives)
	_dump("REACTIVE_PASSIVE_KEYS", reactive)

	# Keyword registry coverage.
	var registered := {}
	if KE != null and "KEYWORDS" in KE:
		for k in KE.KEYWORDS.keys():
			registered[String(k)] = true
	var kw_unregistered := []
	for k in keywords.keys():
		if not registered.has(k):
			kw_unregistered.append(k)
	kw_unregistered.sort()
	print("[audit] KEYWORDS_NOT_IN_REGISTRY: ", kw_unregistered)

	missing_upgrades.sort()
	print("[audit] CARDS_USING_DEFAULT_UPGRADE (%d): %s" % [missing_upgrades.size(), str(missing_upgrades)])
	print("[audit] DONE")
	quit(0)
	return true

func _dump(label: String, d: Dictionary) -> void:
	var keys: Array = d.keys()
	keys.sort()
	print("[audit] %s (%d): %s" % [label, keys.size(), str(keys)])
