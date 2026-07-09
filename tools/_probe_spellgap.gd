extends SceneTree
## One-shot diagnostic: which draftable spells are NOT net-playable in skirmish.
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_spellgap.gd

var _started := false
var _done := false

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_report()
		_done = true
	return _done

func _report() -> void:
	var CDB = root.get_node_or_null("CardDB")
	var SS = root.get_node_or_null("SkirmishState")
	if CDB == null or SS == null:
		print("FATAL autoloads missing"); quit(1); return

	var draftable := ["starter", "common", "uncommon", "rare"]
	var all_spells: Array = []
	for rarity in draftable:
		for id in CDB.get_pool_by_rarity(rarity):
			var d: Dictionary = CDB.get_card_data(id)
			if String(d.get("type", "")) == "spell":
				all_spells.append(id)
	all_spells.sort()

	print("=== DRAFTABLE SPELLS: net-playable status ===")
	var blocked: Array = []
	for id in all_spells:
		var d: Dictionary = CDB.get_card_data(id)
		var sp: Dictionary = d.get("spell", {})
		var stype := String(sp.get("type", ""))
		var sid := String(sp.get("id", ""))
		var ok: bool = SS.is_net_playable_spell(d)
		var tag := ("custom:%s" % sid) if stype == "custom" else stype
		if not ok:
			var denied: bool = SS.SKIRMISH_DENYLIST.has(id)
			blocked.append("%s  (%s)  targeting=%s%s" % [id, tag, String(d.get("targeting", "none")), ("  [DENYLIST]" if denied else "")])
	print("  total draftable spells: %d" % all_spells.size())
	print("  BLOCKED (would show 'not in skirmish yet'): %d" % blocked.size())
	for b in blocked:
		print("    - ", b)

	var pool: Array = SS.skirmish_legal_pool()
	var pool_spells := 0
	for id in pool:
		if String(CDB.get_card_data(id).get("type", "")) == "spell":
			pool_spells += 1
	print("=== legal pool: %d cards (%d spells) ===" % [pool.size(), pool_spells])
	quit(0)
