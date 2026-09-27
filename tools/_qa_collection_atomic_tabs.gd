extends Node

var _fails: Array[String] = []
var _scene: Control


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[collection-atomic] PASS  ", label)
	else:
		print("[collection-atomic] FAIL  ", label)
		_fails.append(label)


func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		print("[collection-atomic] WATCHDOG")
		get_tree().quit(1))
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	_scene = load("res://scenes/collection.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().process_frame

	# A synchronous tab still uses the same one-beat swap and arrives complete.
	_scene.call("show_tab", "potions")
	var content: VBoxContainer = _scene.get("_content")
	var scroll: ScrollContainer = _scene.get("_scroll")
	_check(content.get_child_count() == 2,
		"potions commit heading and complete grid in the press frame")
	if DisplayServer.get_name() != "headless":
		_check(_scene.get("_loading_overlay") != null,
			"windowed tab swap exposes one archive tableau")
		_check(scroll.modulate.a < 1.0,
			"real shelf stays covered through its first layout")
	await get_tree().create_timer(0.55).timeout
	_check(_scene.get("_loading_overlay") == null,
		"archive tableau clears after the coordinated reveal")
	_check(scroll.modulate.a > 0.99, "settled shelf is fully visible")

	# Cards are expensive: no subset may enter the live VBox while the detached
	# stage yields. It must jump from empty to the complete indexed shelf.
	var old_children := content.get_children()
	_scene.call("show_tab", "cards")
	var detached := true
	for child in old_children:
		detached = detached and child.get_parent() == null
	_check(detached, "outgoing tab is synchronously detached")
	_check(content.get_child_count() == 0,
		"live shelf is empty rather than partially populated while staging")
	var generation: int = int(_scene.get("_view_gen"))
	var committed := false
	var partial_seen := false
	for _i in 240:
		var staged_gen := int(content.get_meta("collection_stage_generation", -1))
		var count := content.get_child_count()
		if staged_gen == generation:
			committed = count > 0
			break
		partial_seen = partial_seen or count > 0
		await get_tree().process_frame
	_check(not partial_seen, "no partial card batch enters the live layout")
	_check(committed, "complete card shelf commits within the deadline")
	var jobs: Array = _scene.get("_card_jobs")
	_check(jobs.size() > 100,
		"atomic commit retains the full virtualized card index")
	await get_tree().create_timer(0.32).timeout
	_check(scroll.modulate.a > 0.99,
		"card shelf and loader complete the same reveal")

	# Supersede an async relic build immediately. Its detached stage must never
	# reappear over the final potion tab when its next yield resumes.
	_scene.call("show_tab", "relics")
	await get_tree().process_frame
	_scene.call("show_tab", "potions")
	await get_tree().create_timer(0.45).timeout
	_check(String(_scene.get("_current_tab")) == "potions",
		"rapid tab changes settle on the latest tab")
	_check((_scene.get("_relic_jobs") as Array).is_empty(),
		"superseded relic stage cannot publish stale jobs")
	_check(content.get_child_count() == 2,
		"latest potion shelf remains complete after stale work resumes")

	UserSettings.reduce_motion = true
	_scene.call("show_tab", "history")
	await get_tree().process_frame
	_check(_scene.get("_loading_overlay") == null,
		"reduced motion creates no animated loading tableau")
	_check(scroll.modulate == Color.WHITE,
		"reduced motion snaps the committed shelf to settled paint")

	if _fails.is_empty():
		print("[collection-atomic] ALL PASS")
		get_tree().quit(0)
	else:
		print("[collection-atomic] FAILURES: ", _fails)
		get_tree().quit(1)

