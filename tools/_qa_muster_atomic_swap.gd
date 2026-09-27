extends Node

var _fails: Array[String] = []
var _menu: Node


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[muster-swap] PASS  ", label)
	else:
		print("[muster-swap] FAIL  ", label)
		_fails.append(label)


func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
		print("[muster-swap] WATCHDOG")
		get_tree().quit(1))
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	_menu = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(_menu)
	await get_tree().create_timer(0.8).timeout
	_menu.call("_show_hero_select")
	await get_tree().create_timer(0.8).timeout

	var detail: Container = _menu.get("_hero_detail")
	var rail: VBoxContainer = _menu.get("_hero_deck_rail")
	_check(detail != null and rail != null, "run setup exposes both sheet roots")
	if detail == null or rail == null:
		get_tree().quit(1)
		return
	var old_detail := detail.get_children()
	var old_rail := rail.get_children()
	_menu.call("_focus_hero", "acolyte")
	_check(detail.get_child_count() == 2,
		"replacement portrait and dossier exist in the press frame")
	_check(rail.get_child_count() == 2,
		"replacement caption and complete deck exist in the press frame")
	var detached := true
	for child in old_detail + old_rail:
		detached = detached and child.get_parent() == null
	_check(detached, "outgoing sheet is synchronously detached")
	_check(is_equal_approx(detail.modulate.a, rail.modulate.a),
		"portrait/dossier and deck begin the same reveal beat")

	await get_tree().process_frame
	_check(detail.get_child_count() == 2 and rail.get_child_count() == 2,
		"layout frame contains no outgoing/incoming overlap")
	if DisplayServer.get_name() != "headless":
		_check(detail.modulate.a < 1.0 and rail.modulate.a < 1.0,
			"windowed swap is visibly in flight after layout")
	await get_tree().create_timer(0.35).timeout
	_check(detail.modulate.a > 0.99 and rail.modulate.a > 0.99,
		"both roots settle fully opaque together")

	# Supersede a live reveal immediately. The stale generation must not paint
	# over the final selection or leave either root transparent.
	_menu.call("_focus_hero", "kindler")
	_menu.call("_focus_hero", "stalwart")
	await get_tree().create_timer(0.38).timeout
	_check(String(_menu.get("_selected_hero")) == "stalwart",
		"rapid choices settle on the latest hero")
	_check(detail.get_child_count() == 2 and rail.get_child_count() == 2,
		"rapid choices retain one complete physical sheet")
	_check(detail.modulate.a > 0.99 and rail.modulate.a > 0.99,
		"superseded reveal cannot strand the latest sheet dim")

	# Reduced motion keeps the same atomic lifetime while snapping paint.
	UserSettings.reduce_motion = true
	_menu.call("_focus_hero", "raider")
	_check(detail.get_child_count() == 2 and rail.get_child_count() == 2,
		"reduced motion still swaps the complete sheet atomically")
	_check(detail.modulate == Color.WHITE and rail.modulate == Color.WHITE,
		"reduced motion snaps directly to the settled state")

	if _fails.is_empty():
		print("[muster-swap] ALL PASS")
		get_tree().quit(0)
	else:
		print("[muster-swap] FAILURES: ", _fails)
		get_tree().quit(1)

