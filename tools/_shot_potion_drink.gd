extends Node
## _shot_potion_drink.gd — before/after capture for the potion-drink FX pass
## (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_potion_drink.tscn -- --phase=after
##   Godot.exe --path "D:\Godot" res://tools/_shot_potion_drink.tscn -- --phase=before
## Boots a real act-1 fight, stocks one Healing Potion, fires the drink FX the
## same way both drink paths do (_play_potion_drink_fx), and shoots four frames
## across the draught: launch / mid-flight / arrival+splash / tail (the tail is
## where a portrait reaction is legible). Outputs
## tools/screenshot/_potion_<phase>_<tag>.png. Timings assume default anim_speed.
##
## BEFORE mode does NOT call the live FX: it re-runs the pre-pass flight
## verbatim (old aim = belt + fixed offset, no portrait beat) so the working
## tree's Combat.gd — which carries unrelated in-flight edits — never has to be
## reverted to produce the comparison.

const SHOT_SEED := 20260917
const HERO_ID := "raider"

var _phase := "after"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			_phase = arg.substr(8)
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	RunState.start_new_run(HERO_ID, 0, SHOT_SEED)
	RunState.potions = ["healing", "", ""]
	var ids: Array = EncounterDB.get_ids_for(1, "combat")
	RunState.current_encounter_id = String(ids[0])
	RunState.current_node_type = "combat"
	RunState.current_act_idx = 0

	var combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(combat)
	# Readiness gate copied from _probe_autorun: Phase.PLAYER_TURN is enum 0,
	# so round_number is the honest signal that the fight is actually dealt.
	var waited := 0
	while not (combat.phase == combat.Phase.PLAYER_TURN \
			and combat.round_number >= 1) and waited < 150:
		await get_tree().create_timer(0.1).timeout
		waited += 1
	if waited >= 150:
		push_error("potion shot: combat never reached PLAYER_TURN")
		print("POTION_SHOTS_FAILED")
		get_tree().quit(1)
		return
	combat._rebuild_potion_bar()
	# Let the opening hand-deal stagger (0.08s/card) finish so no dealt card
	# occludes the flight — the first capture pass fired mid-deal and the hand
	# Photobombed every frame.
	await get_tree().create_timer(1.2).timeout

	# The frame the FX starts, then the beats of the flight (timings mirrored
	# from _play_potion_drink_fx: 0.26 flight, splash at 0.24).
	if _phase == "after":
		combat._play_potion_drink_fx("healing", null)
	else:
		_play_old_drink_fx(combat)
	await get_tree().create_timer(0.02).timeout
	await _shoot("launch")
	await get_tree().create_timer(0.10).timeout
	await _shoot("midflight")
	await get_tree().create_timer(0.14).timeout
	await _shoot("arrival")
	await get_tree().create_timer(0.28).timeout
	await _shoot("tail")

	print("POTION_SHOTS_DONE")
	get_tree().quit()


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_potion_%s_%s.png" % [_phase, tag])
	print("SAVED potion_", _phase, "_", tag, " ", img.get_size())


## The pre-pass flight, copied verbatim from _play_potion_drink_fx as it stood
## before the portrait pass (belt→fixed-offset aim, splash only, no swallow
## beat). Kept here so BEFORE never depends on mutating the live script.
func _play_old_drink_fx(combat: Node) -> void:
	var col: Color = Color(0.85, 0.30, 0.30)
	var icon: Texture2D = PotionDB.icon_for("healing")
	var from: Vector2 = Vector2(120.0, get_viewport().get_visible_rect().size.y * 0.60)
	if combat._potion_bar_root != null and is_instance_valid(combat._potion_bar_root):
		from = combat._potion_bar_root.get_global_rect().get_center()
	var to: Vector2 = from + Vector2(46.0, -110.0)
	if icon != null:
		var b := TextureRect.new()
		b.texture = icon
		b.modulate = col
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		b.size = Vector2(44, 44)
		b.pivot_offset = Vector2(22, 30)
		b.position = from - Vector2(22, 22)
		b.z_index = 235
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		combat._hud_layer.add_child(b)
		var tw := b.create_tween()
		tw.tween_property(b, "position", to - Vector2(22, 22),
			UserSettings.anim_time(0.26)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(b, "rotation_degrees", -38.0,
			UserSettings.anim_time(0.26)).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(b, "scale", Vector2(1.18, 1.18),
			UserSettings.anim_time(0.26)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "modulate:a", 0.0,
			UserSettings.anim_time(0.18)).set_ease(Tween.EASE_IN)
		tw.tween_callback(b.queue_free)
	get_tree().create_timer(UserSettings.anim_time(0.24)).timeout.connect(func():
		combat.spawn_spell_burst(to, col))
