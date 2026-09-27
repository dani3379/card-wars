extends Node
## Renders THE OLD FORGE — the event wired on 2026-08-29 — in both its states:
## the choice screen, and the relic picker that no player had ever been able to
## reach (the effect, its UI and its art all shipped; nothing emitted it).
##   Godot.exe --path "D:\Godot" res://tools/_shot_old_forge.tscn

const EVENT_SCENE := "res://scenes/event.tscn"
const EVENT_ID := "old_forge"
const OUT_DIR := "res://tools/screenshot/"


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "_oldforge_%s.png" % name))
	print("SAVED ", name, " ", img.get_size())


func _ready() -> void:
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# A run carrying two NON-STARTING relics, which is what the event's gate and
	# the picker both key on. Without them the choice correctly refuses.
	RunState.start_new_run("stalwart", 0, 31415)
	RunState.run_active = true
	RunState.gold = 180
	RunState.hero_hp = 22
	RunState.hero_max_hp = 30
	# THE WORDIEST NON-STARTING RELICS IN THE DATABASE — the true worst case, and
	# the state the boundary probe stages. A picker sized by estimate rather than
	# by measurement cuts the last visible entry's rules text here.
	var by_len: Array = []
	for rid_v in RelicDB.RELICS:
		var rid := String(rid_v)
		if String(RelicDB.get_relic(rid).get("tier", "starting")) == "starting":
			continue
		by_len.append(rid)
	by_len.sort_custom(func(a, b):
		return String(RelicDB.get_relic(a).get("desc", "")).length() 			> String(RelicDB.get_relic(b).get("desc", "")).length())
	for i in mini(6, by_len.size()):
		RunState.add_relic(String(by_len[i]))
	await get_tree().process_frame

	var ev = load(EVENT_SCENE).instantiate()
	add_child(ev)
	await get_tree().process_frame
	ev._clear_ui()
	ev._event_id = EVENT_ID
	ev._event_data = ev.EVENTS[EVENT_ID].duplicate(true)
	ev._current_node = ev._event_data
	ev._build_ui()
	await get_tree().create_timer(1.4).timeout
	await _snap("choices")

	# Take the anvil option — this opens `_start_relic_sacrifice_mode`, the picker
	# that has never been on a player's screen.
	ev._apply_effect({"type": "relic_sacrifice_pick"})
	await get_tree().create_timer(1.2).timeout
	await _snap("picker")

	print("OLD_FORGE_SHOTS_DONE")
	get_tree().quit()
