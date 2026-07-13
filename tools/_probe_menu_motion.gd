extends SceneTree
## Focused regression probe for MainMenu's throttled/suspendable cosmetics.

var _fails := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings: Node = root.get_node_or_null("UserSettings")
	_check(settings != null, "UserSettings is present")
	if settings == null:
		quit(1)
		return
	var old_reduce_motion := bool(settings.reduce_motion)
	var old_particles := bool(settings.particles)
	settings.reduce_motion = false
	settings.particles = true

	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	for _i in 3:
		await process_frame
	_check(menu.is_processing(), "menu keeps lightweight state polling enabled")
	_check(not menu._menu_motion_suspended, "landing-screen cosmetics start active")

	var particles: Array[Node] = []
	for path in ["Atmosphere/AmbientMotes", "Atmosphere/MenuEmbers"]:
		var emitter: Node = menu.get_node_or_null(path)
		if emitter != null:
			particles.append(emitter)
	_check(particles.size() == 2, "both menu CPU particle emitters are present")

	# Sub-frame calls must not touch transforms; crossing one quantum advances by
	# exactly 1/30 second even when the display refresh rate is higher.
	menu._menu_motion_accumulator = 0.0
	menu._kb_time = 0.0
	var pose_before: Vector2 = menu._bg_node.position
	menu._process(menu.MENU_MOTION_STEP * 0.49)
	menu._process(menu.MENU_MOTION_STEP * 0.49)
	_check(is_zero_approx(menu._kb_time) and menu._bg_node.position == pose_before,
		"background transforms are throttled below 30 Hz")
	menu._process(menu.MENU_MOTION_STEP * 0.03)
	_check(is_equal_approx(menu._kb_time, menu.MENU_MOTION_STEP),
		"crossing the threshold advances one exact motion quantum")

	# A representative looping cosmetic verifies that only the shimmer is paused;
	# the MainMenu itself remains processing so UI/input and close fades stay live.
	var marker := Control.new()
	menu.add_child(marker)
	var shimmer: Tween = menu.create_tween().set_loops()
	shimmer.tween_property(marker, "modulate:a", 0.5, 1.0)
	menu._title_shimmer_tween = shimmer
	menu._set_subscreen_motion_obscured(true)
	_check(menu._menu_motion_suspended and not shimmer.is_running(),
		"sub-screen pauses the looping title shimmer")
	var all_particles_paused := true
	for emitter in particles:
		all_particles_paused = all_particles_paused \
			and emitter.process_mode == Node.PROCESS_MODE_DISABLED
	_check(all_particles_paused, "sub-screen disables both CPU particle simulations")
	_check(menu.is_processing() and menu.process_mode != Node.PROCESS_MODE_DISABLED,
		"suspending cosmetics leaves menu processing and input alive")

	var frozen_clock: float = menu._kb_time
	var frozen_pose: Vector2 = menu._bg_node.position
	menu._process(5.0)
	_check(is_equal_approx(menu._kb_time, frozen_clock) \
			and menu._bg_node.position == frozen_pose \
			and is_zero_approx(menu._menu_motion_accumulator),
		"hidden time is discarded while a sub-screen is open")
	menu._set_subscreen_motion_obscured(false)
	_check(not menu._menu_motion_suspended and shimmer.is_running(),
		"closing the sub-screen resumes the frozen shimmer")
	menu._process(menu.MENU_MOTION_STEP * 1.01)
	_check(is_equal_approx(menu._kb_time, frozen_clock + menu.MENU_MOTION_STEP),
		"resume continues from the frozen pose without catch-up drift")

	# Reduce Motion is read live every frame, rather than only once in _ready().
	settings.reduce_motion = true
	menu._process(0.0)
	_check(menu._menu_motion_suspended,
		"live Reduce Motion toggle suspends an already-open menu")
	var reduced_clock: float = menu._kb_time
	menu._process(3.0)
	_check(is_equal_approx(menu._kb_time, reduced_clock),
		"Reduce Motion does not accumulate hidden animation time")
	settings.reduce_motion = false
	menu._process(0.0)
	menu._process(menu.MENU_MOTION_STEP * 1.01)
	_check(is_equal_approx(menu._kb_time, reduced_clock + menu.MENU_MOTION_STEP),
		"turning Reduce Motion off resumes without a jump")

	# Settings' actual panel visibility covers both its open state and close fade.
	var overlay: Node = null
	for child in settings.get_children():
		if child.has_method("_open") and child.has_method("_close"):
			overlay = child
			break
	_check(overlay != null, "persistent SettingsOverlay is present")
	if overlay != null:
		var panel = overlay.get("_panel_root")
		panel.visible = true
		menu._process(0.0)
		_check(menu._menu_motion_suspended,
			"visible settings panel suspends background cosmetics")
		panel.visible = false
		menu._process(0.0)
		_check(not menu._menu_motion_suspended,
			"motion resumes after the settings close fade finishes")

	shimmer.kill()
	settings.reduce_motion = old_reduce_motion
	settings.particles = old_particles
	menu.queue_free()
	await process_frame
	print("RESULT: %s (%d fails)" % ["ALL PASS" if _fails == 0 else "FAILURES", _fails])
	quit(0 if _fails == 0 else 1)
