extends Node
## _probe_menu_relatch.gd — C3/C11 gate: the main menu must survive being REBUILT.
##   APPDATA=<throwaway> Godot.exe --path "D:\Godot" res://tools/_probe_menu_relatch.tscn
##
## THE DEFECT THIS EXISTS FOR (2026-09-14). `_rebuild_menu` queue_free()d the
## outgoing column and immediately add_child()ed a new one ALSO named "Menu".
## queue_free is DEFERRED, so for that frame both were children — and add_child
## resolves a name collision by renaming the INCOMING node (@VBoxContainer@N),
## never renaming it back once the old one is freed. Nine call sites open with
## `var menu := get_node_or_null("Menu")` / `if menu == null: return`, so from
## the first return-to-menu onward NEW RUN, LOAD GAME and the muster silently
## did NOTHING. No error, no log line, and the button still hovered and clicked.
##
## It is invisible to every other gate here because the menu's FIRST build is
## clean (the .tscn's column is named "VBox"), so anything that boots the screen
## and asserts once passes. The bug needs a SECOND build to exist at all.

var _scene: Node = null
var _fails: Array[String] = []
var _done := false


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails.append(label)


func _ready() -> void:
	var wd := get_tree().create_timer(60.0)
	wd.timeout.connect(func() -> void:
		if not _done:
			_fails.append("watchdog: probe never finished")
			_verdict())

	await get_tree().process_frame
	if OS.get_user_data_dir().find("Temp") < 0:
		# _on_new_run claims a save slot via clear_save. Refuse to run against
		# the player's real user:// dir.
		print("[relatch] REFUSING: APPDATA is not isolated")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.8).timeout

	_scene = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(1.5).timeout

	_check(_menu() != null, "boot: the column is reachable as \"Menu\"")
	_check(_scene.get_node_or_null("MenuScrim") != null,
		"boot: the legibility scrim is reachable as \"MenuScrim\"")
	var boot_children := _menu_children()

	# 1st NEW RUN — the muster must replace the column's contents.
	_check(_click("NEW RUN"), "1st NEW RUN: button found and pressed")
	await get_tree().create_timer(1.5).timeout
	_check(_menu() != null, "1st NEW RUN: \"Menu\" still reachable")
	# VACUITY GUARD: _menu_children() answers -1 when the column is unreachable,
	# which is != boot_children and would let this pass on the very failure it
	# tests. Require the column to EXIST and to have changed.
	_check(_menu() != null and _menu_children() != boot_children,
		"1st NEW RUN: the muster actually built (column contents changed)")

	# BACK to the menu — this is the rebuild that used to orphan the name.
	_scene.call("_abandon_muster")
	await get_tree().create_timer(1.5).timeout
	_check(_menu() != null,
		"after BACK: \"Menu\" STILL REACHABLE (the rebuilt column kept its name)")
	_check(_scene.get_node_or_null("MenuScrim") != null,
		"after BACK: \"MenuScrim\" still reachable")
	_check(_menu_children() == boot_children,
		"after BACK: the main column is back (same child count as boot)")
	# Exactly one column — a renamed survivor would leave two.
	var cols := 0
	for c in _scene.get_children():
		if c is VBoxContainer:
			cols += 1
	_check(cols == 1, "after BACK: exactly one column in the tree (got %d)" % cols)

	# 2nd NEW RUN — the press that used to be swallowed.
	_check(_click("NEW RUN"), "2nd NEW RUN: button found and pressed")
	await get_tree().create_timer(1.5).timeout
	_check(_menu() != null, "2nd NEW RUN: \"Menu\" still reachable")
	_check(_menu() != null and _menu_children() != boot_children,
		"2nd NEW RUN: THE MUSTER OPENED AGAIN (this is the regression)")

	# HOW TO PLAY carries the same fixed-name rebuild — press it twice.
	_scene.call("_abandon_muster")
	await get_tree().create_timer(1.0).timeout
	_scene.call("_show_how_to_play")
	await get_tree().create_timer(0.6).timeout
	_scene.call("_show_how_to_play")
	await get_tree().create_timer(0.6).timeout
	var overlays := 0
	for c in _scene.get_children():
		if String(c.name).begins_with("HowToPlayOverlay") or c == _scene.get("_how_to_play_overlay"):
			overlays += 1
	_check(_scene.get_node_or_null("HowToPlayOverlay") != null,
		"HOW TO PLAY twice: the overlay is still reachable by name")
	_check(overlays <= 1, "HOW TO PLAY twice: scrims did not stack (got %d)" % overlays)

	_verdict()


func _verdict() -> void:
	if _done:
		return
	_done = true
	if _fails.is_empty():
		print("PROBE PASS: menu_relatch")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("PROBE FAIL: menu_relatch (%d)" % _fails.size())
		get_tree().quit(1)


func _menu() -> Node:
	return _scene.get_node_or_null("Menu")


func _menu_children() -> int:
	var m := _menu()
	return (m.get_child_count() if m != null else -1)


func _click(want: String) -> bool:
	var btn := _find_button(_scene, want)
	if btn == null or not btn.is_visible_in_tree() or btn.disabled:
		return false
	btn.emit_signal("pressed")
	return true


func _find_button(n: Node, want: String) -> Button:
	if n is Button:
		var b := n as Button
		if String(b.text).begins_with(want):
			return b
		for ch in b.get_children():
			if _find_label(ch, want) != null:
				return b
	for ch in n.get_children():
		var f := _find_button(ch, want)
		if f != null:
			return f
	return null


func _find_label(n: Node, want: String) -> Label:
	if n is Label and String((n as Label).text).begins_with(want):
		return n
	for ch in n.get_children():
		var f := _find_label(ch, want)
		if f != null:
			return f
	return null
