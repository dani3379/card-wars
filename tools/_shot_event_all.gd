extends Node
## _shot_event_all.gd — renders EVERY event's opening screen + the five engine
## screens (dice, risk, appraisal, wet-cards, relic-sacrifice) and composites
## them into one contact sheet for layout inspection. Windowed, editor closed:
##   Godot.exe --path "D:\Godot" res://tools/_shot_event_all.tscn
## Outputs tools/_shot_ev/<name>.png (full res) + tools/_shot_event_sheet.png

const EVENT_SCENE := "res://scenes/event.tscn"
const TILE_W := 480
const TILE_H := 270
const COLS := 4

var _tiles: Array = []   # [{name, Image}]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://tools/_shot_ev")
	# Fixture: mid-run stalwart with every campaign-memory hook armed so the
	# gated blues and tokens all render.
	RunState.start_new_run("stalwart")
	RunState.gold = 137
	RunState.hero_hp = 17
	RunState.current_act_idx = 2
	for _i in 3:
		RunState.add_potion("healing")
	RunState.fallen.append({"uid": -1, "id": "x", "name": "Pikeman the Grim",
		"enc": "the long road", "act": 1, "round": 3})
	if RunState.deck_uids.size() > 0:
		RunState.creature_kills[RunState.deck_uids[0]] = 7
	RunState.pawned_cards = [RunState.deck[0]]

	var script = load("res://scripts/scenes/Event.gd")
	var ids: Array = script.EVENTS.keys()
	ids.sort()
	for id in ids:
		var ev = await _spawn_event(String(id))
		await _settle(1.3)
		await _capture(String(id))
		ev.queue_free()
		await get_tree().process_frame

	# Engine screens.
	var ev = await _spawn_event("the_bone_pit")
	ev._start_dice_run({"start": 85})
	await _settle(1.2)
	await _capture("zz_engine_dice")
	ev.queue_free()
	await get_tree().process_frame

	ev = await _spawn_event("gravesong_choir")
	ev._start_risk_loop(ev.EVENTS["gravesong_choir"].choices[0].effects[0])
	await _settle(1.2)
	await _capture("zz_engine_risk")
	ev.queue_free()
	await get_tree().process_frame

	ev = await _spawn_event("pawnbrokers_window")
	ev._start_appraisal_mode()
	await _settle(1.2)
	await _capture("zz_engine_appraisal")
	ev.queue_free()
	await get_tree().process_frame

	ev = await _spawn_event("strangers_hand")
	await _settle(1.2)
	await _capture("zz_engine_wetcards")
	ev.queue_free()
	await get_tree().process_frame

	RunState.add_relic("bag_of_marbles")
	ev = await _spawn_event("the_bone_pit")
	ev._start_relic_sacrifice_mode()
	await _settle(1.2)
	await _capture("zz_engine_relicpick")
	ev.queue_free()
	await get_tree().process_frame

	_save_sheet()
	print("[shot-all] done: ", _tiles.size(), " tiles")
	get_tree().quit()


func _spawn_event(id: String) -> Node:
	var ev = load(EVENT_SCENE).instantiate()
	add_child(ev)
	await get_tree().process_frame
	for n in ["EventArt", "EventOverlayLeft"]:
		var node = ev.get_node_or_null(n)
		if node != null:
			ev.remove_child(node)
			node.free()
	ev._event_id = id
	ev._event_data = ev.EVENTS[id]
	ev._current_node = ev._event_data
	# `_ready()` has already run `_pick_event()` and hydrated a RANDOMLY ROLLED
	# event's painting. Overriding the id afterwards does NOT re-hydrate:
	# `_begin_event_art_hydration()` early-returns while `_event_image` is set,
	# and `_build_ui()` re-installs that stale texture — so every frame this
	# harness produced showed some other event's picture, and the scrim was
	# calibrated for that picture too. Clear the hydrator and re-request against
	# the id we actually want, then wait for the worker to land it.
	ev._event_art_request_serial += 1
	ev._event_art_loading = false
	ev._event_image = null
	ev._event_image_path = ""
	ev._build_ui()
	ev._begin_event_art_hydration()
	await _await_art(ev)
	return ev


## The painting arrives on a worker thread. Without this the capture races
## hydration and shoots the forest fallback.
func _await_art(ev: Node) -> void:
	var expected: String = ev._resolve_event_image_path()
	if expected == "":
		return  # This event genuinely has no painting; the fallback IS the shot.
	for _i in 240:
		if ev._event_image != null:
			await get_tree().process_frame
			return
		await get_tree().process_frame
	push_warning("[shot-all] art never landed for %s" % ev._event_id)


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/_shot_ev/%s.png" % name)
	img.resize(TILE_W, TILE_H, Image.INTERPOLATE_LANCZOS)
	_tiles.append({"name": name, "img": img})
	print("[shot-all] ", name)


func _save_sheet() -> void:
	var rows: int = int(ceil(float(_tiles.size()) / COLS))
	var sheet := Image.create(COLS * TILE_W, rows * TILE_H, false, Image.FORMAT_RGBA8)
	for i in range(_tiles.size()):
		var img: Image = _tiles[i].img
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, TILE_W, TILE_H),
			Vector2i((i % COLS) * TILE_W, (i / COLS) * TILE_H))
	sheet.save_png("res://tools/_shot_event_sheet.png")
