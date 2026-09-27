extends Node
## _shot_tutorial_manual.gd — EYES on the coaching system's two REFERENCE
## surfaces (2026-09-10). Windowed, editor closed:
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_tutorial_manual.tscn
##
## Neither of these can be gated headless, and both fail in ways only a picture
## shows. The Field Manual's coaching page is built from a registry that will grow
## — the failure mode is a column that overflows its panel, or a row whose
## SHOW AGAIN button collides with the body above it, and both look fine to any
## assertion about the data. The Settings row is a three-way OptionButton dropped
## into a column of sliders and toggles; the thing to check is that its label
## column lines up with its neighbours (C30's subject).
##
## Frames → tools/screenshot/:
##   _manual_basics    the HOW TO PLAY left column on its original page
##   _manual_coaching  the same column switched to COACHING — the lesson index
##   _manual_scrolled  the coaching page scrolled to the road/stop groups
##   _manual_settings  the Settings column carrying Coaching + Replay Lessons
##
## READ THEM. A PASS here is a set of files, not a verdict.

const OUT_DIR := "res://tools/screenshot"

var _host: Control = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(_host)
	get_tree().current_scene = _host

	await _shoot_manual()
	await _shoot_settings()
	await _shoot_combat_access()
	print("TUTORIAL_MANUAL_SHOTS_DONE")
	get_tree().quit()


## THE RETRIEVAL PATH FROM INSIDE A FIGHT — two frames, two different risks.
##
## `_primer` checks the BUTTON ROW: adding LESSONS made four buttons at 124px
## each, which is 520px inside a 414px usable panel, so the row was split in two.
## A clipped or wrapped row is invisible to every assertion about the code.
##
## `_lessons` checks the LAYER. The overlay sets `z_index = 50`, which is enough
## on the map (one canvas) and nothing at all in Combat, where the HUD is layer 12
## and the hand is layer 20 — if this frame shows the fight painted over the
## manual, the overlay went on the wrong layer.
func _shoot_combat_access() -> void:
	RunState.start_new_run("raider", 0, 1337)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "goblin_scouts"
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	await get_tree().process_frame

	var combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(combat)
	# HOUSE TRAP (from _shot_combat_hud): Card2D._combat_vfx_target() resolves the
	# VFX host through get_tree().current_scene, so add_child alone no-ops every
	# float, chip and log row.
	get_tree().current_scene = combat
	for _i in 400:
		await get_tree().create_timer(0.05).timeout
		if combat.round_number >= 1 and not combat.get("_hand").is_empty():
			break
	await get_tree().create_timer(1.2).timeout

	combat.call("_show_combat_primer")
	await get_tree().create_timer(0.6).timeout
	await _shoot("primer")

	combat.call("_show_coaching_lessons")
	await get_tree().create_timer(0.8).timeout
	await _shoot("lessons")
	combat.queue_free()
	await get_tree().process_frame


func _shoot_manual() -> void:
	var overlay := GameTheme.make_how_to_play_overlay()
	_host.add_child(overlay)
	await _settle()
	await _shoot("basics")

	# Switch to the COACHING page through the real tab button, not by poking
	# `visible` — the tab's own repaint (which page is live, which rule is drawn)
	# is half of what this frame is checking.
	var tab := _find_button(overlay, "COACHING")
	if tab == null:
		push_error("[manual] COACHING tab not found — the tab row did not build")
		return
	tab.emit_signal("pressed")
	await _settle()
	await _shoot("coaching")

	# The road and between-fights groups live below the fold. A manual whose
	# later groups are unreachable is the same defect as a lesson that never
	# fires, and only a scrolled frame shows it.
	var scroll := _find_visible_scroll(overlay)
	if scroll != null:
		scroll.scroll_vertical = 100000
		await _settle()
		await _shoot("scrolled")
	overlay.queue_free()
	await get_tree().process_frame


func _shoot_settings() -> void:
	GameTheme.open_settings_overlay()
	await _settle()
	await _shoot("settings")
	# IT IS NOT CREATED, SO IT CANNOT BE FREED. The settings overlay is a
	# PERSISTENT child of the UserSettings autoload that opens and closes — which
	# is why the obvious cleanup (diff the scene's children, free the new one)
	# found nothing and left it standing behind every later frame. Ask it to
	# close, the same way its own Esc handler does.
	for child in UserSettings.get_children():
		if child.has_method("_close"):
			child._close()
			break
	await _settle()


## Poll until the screen HOLDS. A fixed timer on an animated screen measures the
## machine it ran on, not the layout — deal-ins, fades and the scroll rail's own
## `changed` pass all settle at their own pace.
func _settle() -> void:
	var prev := ""
	for _i in 90:
		await get_tree().process_frame
		var now := _fingerprint(_host)
		if now == prev and now != "":
			return
		prev = now


func _fingerprint(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Control and child.is_visible_in_tree():
			var r: Rect2 = (child as Control).get_global_rect()
			out += "%d,%d,%d,%d;" % [roundi(r.position.x), roundi(r.position.y),
				roundi(r.size.x), roundi(r.size.y)]
		out += _fingerprint(child)
	return out


func _find_button(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root
	for child in root.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _find_visible_scroll(root: Node) -> ScrollContainer:
	if root is ScrollContainer and (root as ScrollContainer).is_visible_in_tree():
		return root
	for child in root.get_children():
		var found := _find_visible_scroll(child)
		if found != null:
			return found
	return null


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/_manual_%s.png" % [OUT_DIR, tag])
	print("SAVED _manual_", tag, " ", img.get_size())
