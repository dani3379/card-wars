extends SceneTree
## Focused WINDOWED attribution probe for Combat's authored chart furniture.
##
## The probe creates one deterministic solo fight, waits until the real player
## phase has settled, then measures the same live scene twice:
##   1. all authored visuals intact;
##   2. only visible, explicit GameTheme.ChartPanelStyle overrides replaced by
##      StyleBoxEmpty instances carrying the exact same content margins.
##
## No game resource is changed. Every override is restored before exit. The
## inventory identifies each affected control by path, class, slot and size so
## a measured draw-call delta can be traced back to concrete HUD furniture.
##
## Run WINDOWED and serially (never beside another renderer benchmark):
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\\Godot" \
##       --script res://tools/_probe_combat_chart_styles.gd
## Parse/autoload smoke only:
##   ... --headless --script res://tools/_probe_combat_chart_styles.gd -- --check-only

const HERO := "pyromancer"
const ENCOUNTER_FALLBACK := "goblin_scouts"
const RUN_SEED := 4242
const SAMPLE_SECONDS := 1.25
const SETTLE_SECONDS := 1.25
const COMMON_STYLE_SLOTS: Array[StringName] = [
	&"panel", &"normal", &"hover", &"pressed", &"disabled", &"focus",
	&"background", &"fill", &"read_only", &"grabber",
	&"grabber_highlight", &"grabber_pressed", &"scroll", &"scroll_focus",
]

var _run_state: Node
var _encounter_db: Node
var _settings: Node
var _scene_preload: Node
var _combat: Node
var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	if OS.get_cmdline_user_args().has("--check-only"):
		print("[combat-chart] CHECK_ONLY_OK")
		_done = true
		quit(0)
		return

	_run_state = root.get_node_or_null("RunState")
	_encounter_db = root.get_node_or_null("EncounterDB")
	_settings = root.get_node_or_null("UserSettings")
	_scene_preload = root.get_node_or_null("ScenePreload")
	if _run_state == null or _encounter_db == null or _settings == null:
		push_error("[combat-chart] required autoloads are missing")
		_finish(1)
		return

	# Stable, uncapped native-resolution baseline. Direct assignment deliberately
	# avoids persisting probe settings to the player's profile.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_settings.graphics_preset = "medium"
	_settings.anim_speed = 3.0
	_settings.end_turn_warning = false
	_settings.render_scale = 1.0
	_settings.adaptive_render_scale = false
	_settings.particles = false
	_settings.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_session_warmup()

	var encounter_id := _find_encounter()
	_run_state.start_new_run(HERO, 0, RUN_SEED)
	_run_state.current_encounter_id = encounter_id
	_run_state.current_node_type = "combat"
	if _scene_preload != null and _scene_preload.has_method("warm_run_deck"):
		_scene_preload.warm_run_deck()
	await create_timer(3.5).timeout

	var packed := load("res://scenes/combat.tscn") as PackedScene
	if packed == null:
		push_error("[combat-chart] combat scene failed to load")
		_finish(1)
		return
	_combat = packed.instantiate()
	root.add_child(_combat)
	if not await _wait_for_player_turn():
		push_error("[combat-chart] timed out waiting for the player turn")
		_finish(1)
		return

	var audio := root.get_node_or_null("AudioBank")
	if audio != null:
		audio.stop_music()
		audio.stop_ambience()
	await create_timer(SETTLE_SECONDS).timeout

	var records := _visible_explicit_chart_style_records()
	_print_inventory(records, encounter_id)
	if records.is_empty():
		push_error("[combat-chart] no visible explicit ChartPanelStyle overrides found")
		_finish(1)
		return

	var viewport_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	var full := await _sample("full", viewport_rid)

	_apply_empty_styles(records)
	await process_frame
	_print_layout_drift(records)
	var empty := await _sample("chart_styles_empty", viewport_rid)
	_print_delta(full, empty)

	_restore_styles(records)
	for _i in 4:
		await RenderingServer.frame_post_draw
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	_finish(0)


func _wait_for_session_warmup() -> void:
	if _scene_preload == null:
		return
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var queue_done: bool = not _scene_preload.has_method("is_warmup_complete") \
			or bool(_scene_preload.is_warmup_complete())
		var pipeline_done: bool = bool(_scene_preload.get("_prewarmed"))
		if queue_done and pipeline_done:
			break
		await create_timer(0.1).timeout
	await create_timer(0.5).timeout


func _find_encounter() -> String:
	if _encounter_db.ENCOUNTERS.has(ENCOUNTER_FALLBACK):
		return ENCOUNTER_FALLBACK
	for id_variant in _encounter_db.ENCOUNTERS.keys():
		var id := String(id_variant)
		var data: Dictionary = _encounter_db.ENCOUNTERS[id]
		if int(data.get("act", 1)) == 1 \
				and String(data.get("type", "combat")) == "combat":
			return id
	return String(_encounter_db.ENCOUNTERS.keys()[0])


func _wait_for_player_turn() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and is_instance_valid(_combat):
		if _combat.phase == _combat.Phase.PLAYER_TURN and not _combat._hand.is_empty():
			return true
		await create_timer(0.05).timeout
	return false


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _control_is_visible_on_root_viewport(control: Control) -> bool:
	if not control.is_visible_in_tree() or control.get_viewport() != root:
		return false
	if control.size.x <= 0.5 or control.size.y <= 0.5:
		return false
	if control.modulate.a <= 0.001 or control.self_modulate.a <= 0.001:
		return false
	return control.get_global_rect().intersects(root.get_visible_rect())


func _is_chart_panel_style(style: StyleBox) -> bool:
	# Avoid compiling against GameTheme's inner class during lightweight script
	# startup; these properties are the style's distinctive runtime signature.
	for property in style.get_property_list():
		if String(property.name) == "corner_tacks":
			return true
	return false

func _explicit_style_slots(control: Control) -> Array[StringName]:
	var found := {}
	for slot in COMMON_STYLE_SLOTS:
		if control.has_theme_stylebox_override(slot):
			found[slot] = true
	var slots: Array[StringName] = []
	for slot_variant in found.keys():
		slots.append(StringName(slot_variant))
	slots.sort()
	return slots


func _visible_explicit_chart_style_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for node in _walk(_combat):
		if not (node is Control):
			continue
		var control := node as Control
		if not _control_is_visible_on_root_viewport(control):
			continue
		for slot in _explicit_style_slots(control):
			var style := control.get_theme_stylebox(slot)
			if not _is_chart_panel_style(style):
				continue
			records.append({
				"control": control,
				"path": String(control.get_path()),
				"class": control.get_class(),
				"slot": slot,
				"style": style,
				"size": control.size,
				"global_position": control.global_position,
			})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := "%s:%s" % [String(a.path), String(a.slot)]
		var right := "%s:%s" % [String(b.path), String(b.slot)]
		return left < right)
	return records


func _print_inventory(records: Array[Dictionary], encounter_id: String) -> void:
	var controls := {}
	var total_area := 0.0
	var shadow_slots := 0
	var parchment_slots := 0
	for record in records:
		var control: Control = record["control"]
		var style: StyleBox = record["style"]
		controls[control.get_instance_id()] = true
		total_area += control.size.x * control.size.y
		if bool(style.get("shadow")):
			shadow_slots += 1
		if bool(style.get("parchment")):
			parchment_slots += 1
		print("[combat-chart] chart path=%s class=%s slot=%s pos=%s size=%s margins=(%.1f,%.1f,%.1f,%.1f) shadow=%s parchment=%s tacks=%s" % [
			String(record["path"]), String(record["class"]), String(record["slot"]),
			str(control.global_position), str(control.size),
			style.get_content_margin(SIDE_LEFT), style.get_content_margin(SIDE_TOP),
			style.get_content_margin(SIDE_RIGHT), style.get_content_margin(SIDE_BOTTOM),
			str(style.get("shadow")), str(style.get("parchment")),
			str(style.get("corner_tacks"))])
	print("[combat-chart] inventory encounter=%s controls=%d style_slots=%d shadow_slots=%d parchment_slots=%d total_area=%.0f" % [
		encounter_id, controls.size(), records.size(), shadow_slots,
		parchment_slots, total_area])


func _empty_with_same_margins(style: StyleBox) -> StyleBoxEmpty:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = style.get_content_margin(SIDE_LEFT)
	empty.content_margin_top = style.get_content_margin(SIDE_TOP)
	empty.content_margin_right = style.get_content_margin(SIDE_RIGHT)
	empty.content_margin_bottom = style.get_content_margin(SIDE_BOTTOM)
	return empty


func _apply_empty_styles(records: Array[Dictionary]) -> void:
	for record in records:
		var control: Control = record["control"]
		if is_instance_valid(control):
			control.add_theme_stylebox_override(record["slot"],
				_empty_with_same_margins(record["style"]))


func _restore_styles(records: Array[Dictionary]) -> void:
	for record in records:
		var control: Control = record["control"]
		if is_instance_valid(control):
			control.add_theme_stylebox_override(record["slot"], record["style"])


func _print_layout_drift(records: Array[Dictionary]) -> void:
	var moved := 0
	var resized := 0
	for record in records:
		var control: Control = record["control"]
		if not is_instance_valid(control):
			continue
		if not control.size.is_equal_approx(record["size"]):
			resized += 1
		if not control.global_position.is_equal_approx(record["global_position"]):
			moved += 1
	print("[combat-chart] margin_equivalence moved=%d resized=%d" % [moved, resized])


func _sample(label: String, viewport_rid: RID) -> Dictionary:
	# Flush layout changes and delayed renderer counters before recording.
	for _i in 8:
		await RenderingServer.frame_post_draw
	var frame_ms: Array[float] = []
	var cpu_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var draws: Array[float] = []
	var objects: Array[float] = []
	var primitives: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	while float(Time.get_ticks_usec() - started) / 1000000.0 < SAMPLE_SECONDS:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - previous) / 1000.0)
		previous = now
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
			+ RenderingServer.get_frame_setup_time_cpu())
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
		draws.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)))
		objects.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)))
		primitives.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)))
	var result := {
		"frame_avg": _average(frame_ms),
		"frame_p95": _percentile(frame_ms, 0.95),
		"cpu": _average(cpu_ms),
		"gpu": _average(gpu_ms),
		"draws": _average(draws),
		"objects": _average(objects),
		"primitives": _average(primitives),
		"frames": frame_ms.size(),
	}
	print("[combat-chart] %s frames=%d frame_avg=%.2f p95=%.2f cpu=%.2f gpu=%.2f draws=%.0f objects=%.0f primitives=%.0f" % [
		label, int(result["frames"]), float(result["frame_avg"]), float(result["frame_p95"]),
		float(result["cpu"]), float(result["gpu"]), float(result["draws"]),
		float(result["objects"]), float(result["primitives"])])
	return result


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	var index := clampi(int(ceil(float(ordered.size()) * fraction)) - 1,
		0, ordered.size() - 1)
	return ordered[index]


func _print_delta(full: Dictionary, empty: Dictionary) -> void:
	print("[combat-chart] delta_empty_minus_full frame_avg=%.2f p95=%.2f cpu=%.2f gpu=%.2f draws=%.0f objects=%.0f primitives=%.0f" % [
		float(empty["frame_avg"]) - float(full["frame_avg"]),
		float(empty["frame_p95"]) - float(full["frame_p95"]),
		float(empty["cpu"]) - float(full["cpu"]), float(empty["gpu"]) - float(full["gpu"]),
		float(empty["draws"]) - float(full["draws"]),
		float(empty["objects"]) - float(full["objects"]),
		float(empty["primitives"]) - float(full["primitives"])])


func _finish(code: int) -> void:
	if is_instance_valid(_combat):
		_combat.queue_free()
	_done = true
	quit(code)
