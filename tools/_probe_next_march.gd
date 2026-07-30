extends SceneTree
## Focused, diskless probe for THE NEXT MARCH.
##
## It never calls start_new_run(), save_run(), MetaState mutation or FileAccess.
## State is dealt directly in memory, and resume is exercised through a JSON
## value roundtrip. It is safe beside real user:// save generations.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" \
##     --script res://tools/_probe_next_march.gd

var _fails := 0
var _ran := false
var RS: Node
var HDB: Node
var EDB: Node


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	RS = root.get_node_or_null("RunState")
	HDB = root.get_node_or_null("HeroDB")
	EDB = root.get_node_or_null("EncounterDB")
	if RS == null or HDB == null or EDB == null:
		print("[next-march-probe] FATAL: required autoloads not found")
		quit(1)
		return true

	print("[next-march-probe] start (diskless)")
	_test_candidate_and_redeal_flow()
	_test_determinism()
	if _fails == 0:
		print("[next-march-probe] ALL PASS")
	else:
		print("[next-march-probe] %d FAILURES" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _deal(seed: int) -> void:
	# These are the pure state steps inside start_new_run, without PlayLog's
	# on-disk telemetry session or any save checkpoint.
	RS.current_hero_id = "raider"
	RS.current_act_idx = 0
	RS.run_seed = seed
	RS.map_data = []
	RS.map_plate_cache.clear()
	RS._select_rivals()
	RS._generate_map()


func _test_candidate_and_redeal_flow() -> void:
	print("-- candidates, swaps, and full future-act redeal")
	_deal(24681357)
	var opening_lord := String(RS.rival_lords[0])
	var displaced_act_two := String(RS.rival_lords[1])
	var provisional_finale := String(RS.finale_rival)
	var opening_content := _content_signature(0)
	var old_act_two_content := _content_signature(1)
	var structures: Array[String] = []
	for act_idx in 3:
		structures.append(_structure_signature(act_idx))

	var candidates: Array = RS.get_next_march_candidates()
	_check(candidates.size() == 3, "Act 1 offers all three living rivals")
	_check(candidates.has(provisional_finale),
		"Act 1 slate includes the provisional finale candidate")
	_check(not candidates.has(opening_lord),
		"Act 1 slate excludes the defeated opening lord")

	RS.choose_next_rival(provisional_finale)
	_check(String(RS.rival_lords[1]) == provisional_finale,
		"choosing the finale candidate puts that lord in Act 2")
	_check(String(RS.finale_rival) == displaced_act_two,
		"the displaced Act 2 lord becomes the new finale candidate")
	_check(_campaign_state_is_coherent(),
		"rivals, finale, and factions stay coherent")
	_check(_content_signature(0) == opening_content,
		"the seeded opening act is never re-dealt")
	_check(_content_signature(1) != old_act_two_content,
		"the chosen Act 2 kingdom receives a new full encounter deal")
	for act_idx in 3:
		_check(_structure_signature(act_idx) == structures[act_idx],
			"Act %d topology/types/setpieces/mutators are preserved" % (act_idx + 1))
	for act_idx in [1, 2]:
		_check(_act_encounters_match_faction(act_idx),
			"Act %d combat, General, and boss IDs match its ruler" % (act_idx + 1))

	# Exercise a save/resume-shaped JSON roundtrip without touching user://.
	var resumed_content := _content_signature(1) + "|" + _content_signature(2)
	var snapshot_text := JSON.stringify({
		"run_seed": RS.run_seed,
		"current_act_idx": 1,
		"rival_lords": RS.rival_lords,
		"finale_rival": RS.finale_rival,
		"act_faction": RS.act_faction,
		"map_data": RS.map_data,
	})
	_restore_json_snapshot(JSON.parse_string(snapshot_text))
	_check(_content_signature(1) + "|" + _content_signature(2) == resumed_content,
		"JSON save-shaped roundtrip preserves the late-bound maps")

	var second_candidates: Array = RS.get_next_march_candidates()
	_check(second_candidates.size() == 2,
		"Act 2 offers both remaining living rivals")
	_check(second_candidates.has(RS.finale_rival),
		"Act 2 slate still includes the current finale candidate")
	var displaced_act_three := String(RS.rival_lords[2])
	var second_pick := String(RS.finale_rival)
	RS.choose_next_rival(second_pick)
	_check(String(RS.rival_lords[2]) == second_pick,
		"second pick becomes the Act 3 rival")
	_check(String(RS.finale_rival) == displaced_act_three,
		"the ultimately unchosen rival becomes the finale")
	_check(_campaign_state_is_coherent(), "final rival order remains coherent")
	_check(_act_encounters_match_faction(2),
		"Act 3 ordinary fights, Generals, and boss match the final pick")


func _test_determinism() -> void:
	print("-- deterministic replay")
	var seed := 97531864
	_deal(seed)
	var first_pick := String(RS.finale_rival)
	RS.choose_next_rival(first_pick)
	RS.current_act_idx = 1
	var second_pick := String(RS.finale_rival)
	RS.choose_next_rival(second_pick)
	var expected := _full_signature()

	_deal(seed)
	RS.choose_next_rival(first_pick)
	RS.current_act_idx = 1
	RS.choose_next_rival(second_pick)
	_check(_full_signature() == expected,
		"same seed and march choices reproduce every future encounter ID")


func _restore_json_snapshot(value) -> void:
	var data: Dictionary = value
	RS.run_seed = int(data.get("run_seed", 0))
	RS.current_act_idx = int(data.get("current_act_idx", 0))
	RS.rival_lords.clear()
	for lord in data.get("rival_lords", []):
		RS.rival_lords.append(String(lord))
	RS.finale_rival = String(data.get("finale_rival", ""))
	RS.act_faction.clear()
	for faction in data.get("act_faction", []):
		RS.act_faction.append(String(faction))
	RS.map_data = data.get("map_data", [])


func _campaign_state_is_coherent() -> bool:
	if RS.rival_lords.size() != 3 or String(RS.finale_rival) == "":
		return false
	var seen := {}
	for i in RS.rival_lords.size():
		var lord := String(RS.rival_lords[i])
		if lord == RS.current_hero_id or seen.has(lord):
			return false
		seen[lord] = true
		if i >= RS.act_faction.size() \
				or String(RS.act_faction[i]) != HDB.get_faction(lord):
			return false
	if RS.finale_rival == RS.current_hero_id or seen.has(RS.finale_rival):
		return false
	seen[RS.finale_rival] = true
	return seen.size() == 4


func _act_encounters_match_faction(act_idx: int) -> bool:
	var act := act_idx + 1
	var faction := String(RS.act_faction[act_idx])
	var combat_pool: Array = EDB.get_kingdom_pool(act, "combat", faction)
	var elite_pool: Array = EDB.get_kingdom_pool(act, "elite", faction)
	for row in RS.map_data[act_idx]:
		for node in row:
			var node_type := String(node.get("type", ""))
			var encounter := String(node.get("encounter_id", ""))
			if String(node.get("setpiece_id", "")) != "":
				if encounter != "":
					return false
			elif node_type == "combat" and not combat_pool.has(encounter):
				return false
			elif node_type == "elite" and not elite_pool.has(encounter):
				return false
			elif node_type == "boss" \
					and encounter != "rival_" + String(RS.rival_lords[act_idx]):
				return false
	return true


func _structure_signature(act_idx: int) -> String:
	var out: Array = []
	for row in RS.map_data[act_idx]:
		for node in row:
			out.append([
				int(node.get("row", -1)),
				int(node.get("col", -1)),
				String(node.get("type", "")),
				Array(node.get("connections", [])).duplicate(),
				String(node.get("setpiece_id", "")),
				String(node.get("wayside_id", "")),
				String(node.get("mutator_id", "")),
			])
	return JSON.stringify(out)


func _content_signature(act_idx: int) -> String:
	var out: Array = []
	for row in RS.map_data[act_idx]:
		for node in row:
			if String(node.get("type", "")) in ["combat", "elite", "boss"]:
				out.append("%s:%s:%s" % [
					int(node.get("row", -1)), int(node.get("col", -1)),
					String(node.get("encounter_id", ""))])
	return "|".join(out)


func _full_signature() -> String:
	return JSON.stringify({
		"rivals": RS.rival_lords,
		"finale": RS.finale_rival,
		"factions": RS.act_faction,
		"act_1": _content_signature(0),
		"act_2": _content_signature(1),
		"act_3": _content_signature(2),
	})
