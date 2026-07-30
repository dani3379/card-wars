extends Node
## _shot_general_intro.gd — ★9 "The General arrives" + ★10 deck peel +
## Muster the Fallen's rise (docs/ANIMATION_COOL_PITCH_20260717.md §5b,
## docs/SPELL_FX_PLAN_20260717.md S6).
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_general_intro.tscn
##
## Boots a REAL act-1 elite (orc_warband) so the non-quick intro plays:
## the name stamps in oversized, the world desaturates for the banner's
## length, and when it lifts the army presents — ranks press in sequence,
## the lord seats last with dust + the table's blow.
##
## Frames are taken on a fixed clock from add_child because the intro runs
## inside Combat._ready — several frames bracket the stamp/hold/roll-call so
## at least one catches each beat. Then, with the fight idle: the deck-peel
## VFX on demand, and a staged Muster the Fallen mid-rise.
## Outputs _shot_gen_*.png at the project root.

var _combat: Node = null


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func():
		print("[genintro] WATCHDOG fired — _ready never completed")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	if UserSettings != null:
		UserSettings.reduce_motion = false
		UserSettings.anim_speed = 1.0
		UserSettings.particles = true

	RunState.start_new_run("raider")
	RunState.current_node_type = "elite"
	RunState.current_encounter_id = "orc_warband"
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat

	# Bracket the intro: stamp lands ~+0.3 into the banner; banner holds 1.0;
	# roll-call runs ~0.4-0.8 after the fade. Exact offset from add_child
	# depends on setup cost, so take a spread and inspect.
	# Clock recalibrated by the first run: banner holds t+1.2..3.0, lifts
	# ~t+3.2, roll-call ranks ~t+3.3..3.6, lord press ~t+3.7..4.0.
	await get_tree().create_timer(1.2).timeout
	await _snap("res://_shot_gen_a.png", "t+1.2 (stamp landing)")
	await get_tree().create_timer(0.6).timeout
	await _snap("res://_shot_gen_b.png", "t+1.8 (banner hold, world desat)")
	await get_tree().create_timer(1.55).timeout
	await _snap("res://_shot_gen_c.png", "t+3.35 (lift / roll-call ranks)")
	await get_tree().create_timer(0.45).timeout
	await _snap("res://_shot_gen_d.png", "t+3.8 (lord press / dust)")
	await get_tree().create_timer(0.4).timeout
	await _snap("res://_shot_gen_e.png", "t+4.2 (settle / deal)")

	# Let the fight settle past the round-1 banner and opening deal.
	await get_tree().create_timer(3.0).timeout

	# ── ★10 — the deck peel, on demand ──────────────────────────────────
	_combat.call("_play_deck_peel_vfx")
	await get_tree().create_timer(0.09).timeout
	await _snap("res://_shot_gen_peel.png", "deck peel @0.09")
	await get_tree().create_timer(0.6).timeout

	# ── Muster the Fallen — wisps from the discard pile, staggered rise ──
	RunState.fallen = [{"name": "Pikeman"}, {"name": "Mourner"}, {"name": "Outrider"}]
	_combat.call("_resolve_spell",
		CardDB.get_card_data("muster_fallen"), null, -1)
	await get_tree().create_timer(0.16).timeout
	await _snap("res://_shot_gen_muster1.png", "muster rise @0.16 (first wisps)")
	await get_tree().create_timer(0.26).timeout
	await _snap("res://_shot_gen_muster2.png", "muster rise @0.42 (later shades)")

	print("[genintro] DONE")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _snap(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[genintro] wrote %s — %s" % [path.get_file(), label])
