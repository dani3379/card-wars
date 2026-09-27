extends Node
## _shot_occlusion_check.gd — eyes for the C27/C28 passes (2026-09-02).
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_occlusion_check.tscn
##
## Two jobs. (1) The character event stage, whose description column used to print
## the stakes ledger's deck row inside its first line. (2) The event MODALS — the
## ten minigames and the card pickers — which `_probe_occlusion` clears
## geometrically but which no pixel gate had ever actually looked at. Event.gd
## builds every one of them as a plain child of the scene, sharing a canvas with
## the ledger, so "does the modal own the screen" is a question worth seeing
## answered rather than inferred.

const EVENT_SCENE := "res://scenes/event.tscn"

# (label, event id, effect) — configs lifted from EventDB, never invented.
const SHOTS := [
	["scale", "the_quartermasters_scale"],
	["box", "the_fourths_strongbox"],
	["crown", "the_drummers_tattoo"],
	["shell", "old_army_game"],
	["straw", "the_short_straw"],
]


func _ready() -> void:
	RunState.start_new_run("stalwart", 0, 606061)
	RunState.gold = 800
	RunState.hero_hp = RunState.hero_max_hp
	await get_tree().process_frame

	await _shoot_event("the_siege_kitchen", "stage")

	var EvScript = load("res://scripts/scenes/Event.gd")
	for row in SHOTS:
		var label: String = row[0]
		var ev_id: String = row[1]
		if not EvScript.EVENTS.has(ev_id):
			print("[shot] SKIP %s — no such event id %s" % [label, ev_id])
			continue
		var effect := _first_modal_effect(EvScript, ev_id)
		if effect.is_empty():
			print("[shot] SKIP %s — %s emits no modal effect" % [label, ev_id])
			continue
		await _shoot_event(ev_id, label, effect)

	get_tree().quit()


func _first_modal_effect(EvScript, ev_id: String) -> Dictionary:
	var data: Dictionary = EvScript.EVENTS[ev_id]
	var pools: Array = []
	if data.has("auto_effect"):
		pools.append(data["auto_effect"])
	for ch in data.get("choices", []):
		if ch is Dictionary:
			for e in ch.get("effects", []):
				pools.append(e)
	for e in pools:
		if e is Dictionary and EvScript.MODAL_EFFECTS.has(String(e.get("type", ""))):
			return e
	return {}


func _shoot_event(ev_id: String, label: String, effect: Dictionary = {}) -> void:
	var ev = load(EVENT_SCENE).instantiate()
	add_child(ev)
	await get_tree().process_frame
	for n in ["EventArt", "EventOverlayLeft"]:
		var node = ev.get_node_or_null(n)
		if node != null:
			ev.remove_child(node)
			node.free()
	ev._event_id = ev_id
	ev._event_data = ev.EVENTS[ev_id].duplicate(true)
	ev._current_node = ev._event_data
	ev._event_art_request_serial += 1
	ev._event_art_loading = false
	ev._event_image = null
	ev._event_image_path = ""
	ev._build_ui()
	ev._begin_event_art_hydration()
	await get_tree().create_timer(1.6).timeout
	if not effect.is_empty():
		ev._apply_effect(effect.duplicate(true))
		await get_tree().create_timer(2.0).timeout

	if is_instance_valid(ev):
		var hud = ev.get_node_or_null("StakesLedger")
		if hud is Control:
			print("[shot] %-6s ledger visible=%s rect=%s" % [label,
				str((hud as Control).is_visible_in_tree()),
				str((hud as Control).get_global_rect())])
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/_shot_occl_%s.png" % label)
	print("[shot] saved %s (%s)" % [label, str(img.get_size())])
	if is_instance_valid(ev):
		ev.queue_free()
	await get_tree().process_frame
