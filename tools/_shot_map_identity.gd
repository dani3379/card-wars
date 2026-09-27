extends Node
# Map identity / tooltip screenshot harness (2026-08-01).
#
# _shot_map_states covers the PLATE; it starts its run with no declared banner
# and never opens an overlay or a tooltip, so it cannot see the three surfaces
# the run-identity pass touches. This one shoots those three:
#   1. the title cartouche with the LONGEST possible arms line (Pyromancer of
#      the Lanternhall, under The Contract) — the clip test
#   2. the company ledger, which carries the arms + the banner's verb +
#      RunState.season_line()
#   3. a live combat site tooltip, which now carries the fight's standing rule
#
#   Godot.exe --path "D:\Godot" res://tools/_shot_map_identity.tscn

const HERO_ID := "pyromancer"

var _map: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	RunState.start_new_run(HERO_ID)
	await get_tree().process_frame

	_map = load("res://scenes/map.tscn").instantiate()
	get_tree().root.add_child(_map)
	await get_tree().create_timer(3.5).timeout
	_map._set_view(1.0, Vector2.ZERO)
	await _shoot("_shot_ident_cartouche.png")

	_map._show_company_ledger()
	await _shoot("_shot_ident_company.png")
	var ov := _map.get_node_or_null("CompanyLedgerOverlay")
	if ov != null:
		ov.queue_free()
	await get_tree().process_frame

	# A real combat node's tooltip, parented onto the map so the panel lays out
	# exactly as the hover path builds it.
	var picked: Dictionary = {}
	for nd in _map._nodes:
		var enc := String(nd.get("encounter_id", ""))
		if String(nd.get("type", "")) in ["combat", "elite"] and enc != "":
			var rule := String(EncounterDB.get_encounter(enc).get(
				"passive_desc", ""))
			if rule.length() > 80:
				picked = nd
				break
	if picked.is_empty():
		for nd2 in _map._nodes:
			if String(nd2.get("type", "")) == "combat":
				picked = nd2
				break
	if not picked.is_empty():
		var tip: Control = _map._build_map_tooltip(_map._tip(picked))
		tip.position = Vector2(420, 240)
		_map.add_child(tip)
		await _shoot("_shot_ident_tooltip.png")
		tip.queue_free()
		await get_tree().process_frame

	# The zero-click identity read: the COMPANY button's own hover panel.
	var ctip: Control = _map._build_map_tooltip(_map._company_tip_text())
	ctip.position = Vector2(600, 74)
	_map.add_child(ctip)
	await _shoot("_shot_ident_companytip.png")

	print("SHOTS_DONE")
	get_tree().quit()


func _shoot(path: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://" + path)
	print("SAVED ", path)
