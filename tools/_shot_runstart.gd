extends Node
## _shot_runstart.gd — renders the RUN-OPENING FLOW (menu column → RUN SETUP,
## per lord → the starting bonus → a writ's card picker) to
## PNG for a design audit (windowed, editor closed):
##
## RUN SETUP is ONE screen (2026-09-14) and asks ONE question (2026-09-16), so
## the frames are named for the STATE they capture, not for a step number. The
## old step2_banner / step3_terms / step4_orders frames were dropped with the
## walk: every one of them re-entered the same screen and so was a byte-duplicate
## of the frame before it. The banner frames went with the banner system, and the
## terms moved to their own `bonus_*` pair.
##   Godot.exe --path "D:\Godot" res://tools/_shot_runstart.tscn
## Outputs tools/screenshot/_runstart_<state>.png

var _scene: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	_scene = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(_scene)
	# The menu column staggers its entrance; 1.4s is the settled window.
	await get_tree().create_timer(1.6).timeout
	await _snap("menu")

	# Fresh-profile on-ramp: one decision, with the authored standard package
	# printed beneath it. The full Muster is captured separately below.
	RunState.active_slot = 0
	_scene.call("_show_quick_march")
	await get_tree().create_timer(1.5).timeout
	await _snap("quick_march")
	var quick_rows: Dictionary = _scene.get("_hero_cards")
	var controller_row: Control = quick_rows.get("stalwart")
	if controller_row != null:
		controller_row.grab_focus()
		await get_tree().create_timer(0.25).timeout
		await _snap("quick_controller_focus")
	_scene.call("_show_quick_company")
	await get_tree().create_timer(1.2).timeout
	await _snap("quick_company")
	_scene.call("_show_muster_deck_inspector")
	await get_tree().create_timer(0.8).timeout
	await _snap("quick_deck_inspector")
	_scene.call("_hide_deck_inspector")

	# RUN SETUP holds all four decisions at once, so the audit is no longer "is
	# any step crowded" but "does the ONE screen stay uncrowded as each pane
	# changes underneath it". Shoot the opening state, then move each pane in
	# turn without re-entering the screen.
	_scene.call("_show_hero_select")
	await get_tree().create_timer(1.5).timeout
	await _snap("setup_open")

	for hid in ["acolyte", "kindler"]:
		_scene.call("_focus_hero", hid)
		await get_tree().create_timer(1.0).timeout
		await _snap("setup_hero_" + hid)

	# (Two banner frames stood here until 2026-09-16. The banner system is gone.)

	# THE STARTING BONUS, its own screen since 2026-09-16. Seed 1 deals a Forge
	# term, which is the one slate that needs the house-word gloss — most seeds
	# render none, so a random deal would shoot the gloss's absence.
	_scene.set("_muster_random_seed", 1)
	_scene.set("_muster_seed_text", "")
	_scene.call("_refresh_muster_deals")
	_scene.call("_show_starting_bonus")
	await get_tree().create_timer(1.2).timeout
	await _snap("bonus_gloss")

	# A tile under the cursor: the hover state is the only affordance saying a
	# tile IS the commit, so it is worth its own frame.
	var tiles: Dictionary = _scene.get("_muster_writ_buttons")
	for tid in tiles:
		var tile: Control = tiles[tid]
		if is_instance_valid(tile):
			tile.grab_focus()
			break
	await get_tree().create_timer(0.7).timeout
	await _snap("bonus_focus")
	_scene.call("_leave_starting_bonus")
	await get_tree().create_timer(1.0).timeout
	await _snap("setup_return_from_bonus")

	# Ascension pushed up the ladder — does the rules text stay legible? The
	# run options are a DIALOG now (2026-09-16), so these frames also check that
	# it lands centred over the screen it modifies rather than growing it.
	_scene.call("_toggle_muster_advanced")
	await get_tree().create_timer(0.7).timeout
	await _snap("setup_options_open")

	_scene.set("_selected_ascension", 5)
	if _scene.has_method("_update_asc_rules_text"):
		_scene.call("_update_asc_rules_text")
	await get_tree().create_timer(0.6).timeout
	await _snap("setup_ascension_5")
	_scene.set("_daily_pick", true)
	_scene.set("_muster_seed_text", "confidence-audit")
	_scene.call("_toggle_muster_advanced")
	await get_tree().create_timer(0.8).timeout
	await _snap("setup_options_active")
	_scene.set("_daily_pick", false)
	_scene.set("_muster_seed_text", "")
	_scene.set("_selected_ascension", 0)
	if _scene.has_method("_update_asc_rules_text"):
		_scene.call("_update_asc_rules_text")

	# Re-entry. `_show_muster_step` keeps its argument only so the probes and
	# tools that still pass one resolve; it ignores the value and rebuilds the one
	# screen. Shooting it proves that shim lands a complete screen — and that the
	# run options dialog closed with the rebuild instead of surviving it.
	_scene.call("_show_muster_step", 1)
	await get_tree().create_timer(1.2).timeout
	await _snap("setup_return")

	# THE HOST's campaign record. It only prints for a lord who has actually
	# marched, so the frame is worthless unless the profile HAS a record — fake
	# one, shoot it, put the real ledger back. Stalwart, so the same frame also
	# carries the doctrine unlocks (a win opens relic_alt; best_asc 4 opens the
	# deck), which is the crowded case: name + record on one row above a pane
	# that is already spending its height to the last pixel.
	var meta_stash: Dictionary = MetaState.hero_stats.duplicate(true)
	MetaState.hero_stats = {"stalwart": {"wins": 12, "losses": 9, "best_asc": 20}}
	_scene.call("_focus_hero", "raider")   # force the pane off stalwart first
	await get_tree().create_timer(0.4).timeout
	_scene.call("_focus_hero", "stalwart")
	await get_tree().create_timer(1.2).timeout
	await _snap("setup_hero_record")
	MetaState.hero_stats = meta_stash

	# The one screen MainMenu still lays out AFTER the run has begun: a writ's
	# follow-up card grid. (The four THE WAR CHEST frames that used to live here
	# were retired 2026-08-01 with the screen itself. Three of them re-rolled a
	# slate that has been seeded off run_seed since 2026-07-30, so they were
	# byte-identical to each other and the "one frame is not an audit" loop was
	# auditing nothing.)
	RunState.start_new_run("raider")
	_scene.call("_pick_blessing", {"effect": "forge", "value": 1})
	await get_tree().create_timer(1.6).timeout
	await _snap("writ_forge_picker")

	print("RUNSTART_SHOT_DONE")
	get_tree().quit()


func _snap(state: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_runstart_%s.png" % state)
	print("SAVED ", state, " ", img.get_size())
