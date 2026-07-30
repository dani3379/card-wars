extends Node
## _shot_verdict_fx.gd — visual check for the 2026-07-11 combat-juice pass
## (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_verdict_fx.tscn
## Shots (tools/screenshot/_verdictfx_*.png):
##   trail     — drag ember trail mid-sweep (synthetic _on_card_drag_trail feed)
##   victory   — VICTORY ceremony ~0.55s in (stamp landed, gold counting)
##   defeat    — DEFEAT ceremony ~0.6s in (word dropped, scrim dark)
##   shine     — GameTheme.rarity_reveal mid-glint on an uncommon + a rare writ
##   recruit   — real Recruit slate settled (integration: reveal + shine path)

var _combat: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	RunState.start_new_run("raider", 0, 4242)
	RunState.gold = 138
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "borrowed_faces"
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat
	# Wait out the fight intro + round-1 turn banner before staging anything.
	await get_tree().create_timer(6.0).timeout

	# ── 1. Drag ember trail: feed the breadcrumb handler a curved sweep, one
	# point per frame, and shoot with the ribbon at full length.
	var hand: Array = _combat.get("_hand")
	if hand != null and hand.size() > 0:
		var card: Control = hand[0]
		var p0 := Vector2(760.0, 800.0)
		var p1 := Vector2(1010.0, 430.0)
		for i in range(15):
			var t := float(i) / 14.0
			var pos := p0.lerp(p1, t) + Vector2(sin(t * PI) * 120.0, 0.0)
			_combat.call("_on_card_drag_trail", pos, card)
			await get_tree().process_frame
		await _shoot("trail")
		await get_tree().create_timer(0.5).timeout

	# ── 2/3. Verdict ceremonies (auto_fade so each cleans the stage). ──
	_combat.call("_show_battle_verdict", true, 42, true, true)
	await get_tree().create_timer(0.55).timeout
	await _shoot("victory")
	await get_tree().create_timer(2.4).timeout

	_combat.call("_show_battle_verdict", false, 0, true, true)
	await get_tree().create_timer(0.60).timeout
	await _shoot("defeat")
	await get_tree().create_timer(2.4).timeout

	_combat.queue_free()
	await get_tree().process_frame

	# ── 4. Rarity shine, deterministic: one uncommon + one rare writ. ──
	var stage := ColorRect.new()
	stage.color = Color(0.07, 0.055, 0.045)
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(stage)
	var ids: Array = [
		CardDB.get_pool_by_rarity("uncommon")[0],
		CardDB.get_pool_by_rarity("rare")[0]]
	var x := 480.0
	for id in ids:
		var data: Dictionary = CardDB.get_card_data(id)
		var wrap := Control.new()
		wrap.custom_minimum_size = Vector2(225, 300)
		wrap.size = Vector2(225, 300)
		wrap.position = Vector2(x, 300.0)
		stage.add_child(wrap)
		var cn = load("res://scenes/card_2d.tscn").instantiate()
		cn.static_display = true
		cn.card_data = data.duplicate(true)
		cn.live_baked_mode = true
		CardTextureCache.bake(data)
		wrap.add_child(cn)
		GameTheme.rarity_reveal(wrap, String(data.get("rarity", "")), 0.25)
		x += 420.0
	# Shine peaks ~0.25 delay + ~0.35 in-flight.
	await get_tree().create_timer(0.62).timeout
	await _shoot("shine")
	stage.queue_free()
	await get_tree().process_frame

	# ── 5. Real Recruit slate (integration; rarity mix is whatever rolled). ──
	var rec = load("res://scenes/recruit.tscn").instantiate()
	get_tree().root.add_child(rec)
	await get_tree().create_timer(0.85).timeout
	await _shoot("recruit")

	print("VERDICT_FX_SHOTS_DONE")
	get_tree().quit()


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_verdictfx_%s.png" % tag)
	print("SAVED verdictfx_", tag, " ", img.get_size())
