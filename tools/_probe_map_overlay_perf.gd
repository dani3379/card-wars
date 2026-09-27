extends SceneTree
## Focused open/settle benchmark for MapView's in-place reference overlays.
## Keeps the map alive between cases so map generation/baking is not charged to
## the overlay being measured.

const EXTRA_CARDS := [
	"pikeman", "shieldmaiden", "warden_sergeant", "iron_bastion",
	"brute", "troll", "bloodmoon_alpha", "dragon_hatchling",
	"mourner", "gravedigger", "the_sexton", "gravepact",
	"witch", "hedge_caster", "coven_mother", "siege_golem",
	"siegewright", "the_leveler", "kingpin", "spark",
	"star_chart", "fireball", "offering", "war_cry",
]

var _started := false
var _done := false
var _recording := false
var _last_usec := 0
var _max_gap_ms := 0.0


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _recording and _last_usec > 0:
		_max_gap_ms = maxf(_max_gap_ms, float(now - _last_usec) / 1000.0)
	_last_usec = now
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var settings := root.get_node("UserSettings")
	settings.reduce_motion = false
	settings.coaching_mode = 0
	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("raider", 0, 20260914)
	rs.active_slot = -1
	# Runtime load matters for --script probes: preloading MapView while this
	# SceneTree script compiles runs before project autoload identifiers exist.
	var map = load("res://scenes/map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if map.get("_hud_root") != null and not bool(map.get("_plate_bake_pending")):
			break
		await process_frame
	for _i in 8:
		await RenderingServer.frame_post_draw

	# A long but plausible late-run deck, with a representative relic roll.
	for cid in EXTRA_CARDS:
		rs.add_card(cid)
	var relic_ids: Array = root.get_node("RelicDB").RELICS.keys()
	relic_ids.sort()
	rs.relics.clear()
	for i in mini(30, relic_ids.size()):
		rs.relics.append(String(relic_ids[i]))

	await _measure(map, "war_council", "_show_war_council", "WarCouncilOverlay", 12)
	await _measure(map, "company_ledger", "_show_company_ledger", "CompanyLedgerOverlay", 12)
	await _measure(map, "relics_30", "_show_relic_viewer", "RelicOverlay", 12)
	await _measure(map, "how_to_play", "_show_how_to_play", "HowToPlayOverlay", 12)
	await _measure_deck(map, "deck_%d" % rs.deck.size())

	map.queue_free()
	await process_frame
	_done = true
	quit(0)


func _measure(map: Node, label: String, method: String, overlay_name: String,
		frames: int) -> void:
	_reset_recording()
	var started := Time.get_ticks_usec()
	map.call(method)
	var sync_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var first_started := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var first_ms := float(Time.get_ticks_usec() - first_started) / 1000.0
	for _i in maxi(frames - 1, 0):
		await RenderingServer.frame_post_draw
	_recording = false
	var ov := map.get_node_or_null(overlay_name)
	print("[map-overlay] %-16s sync=%7.2fms first=%7.2fms max_gap=%7.2fms nodes=%d" % [
		label, sync_ms, first_ms, _max_gap_ms, _count_nodes(ov)])
	if ov != null:
		ov.queue_free()
	await process_frame


func _measure_deck(map: Node, label: String) -> void:
	_reset_recording()
	var started := Time.get_ticks_usec()
	map.call("_show_deck_viewer")
	var sync_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var first_started := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var first_ms := float(Time.get_ticks_usec() - first_started) / 1000.0
	var settle_started := Time.get_ticks_usec()
	var expected: int = root.get_node("RunState").deck.size()
	var count := 0
	for _i in 360:
		await RenderingServer.frame_post_draw
		var ov := map.get_node_or_null("DeckOverlay")
		count = _count_cards(ov)
		if count >= expected:
			# Let the final Card2D layout/render work land.
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			break
	var settle_ms := float(Time.get_ticks_usec() - settle_started) / 1000.0
	_recording = false
	var deck_ov := map.get_node_or_null("DeckOverlay")
	print("[map-overlay] %-16s sync=%7.2fms first=%7.2fms settle=%7.2fms max_gap=%7.2fms cards=%d/%d nodes=%d" % [
		label, sync_ms, first_ms, settle_ms, _max_gap_ms, count, expected,
		_count_nodes(deck_ov)])
	if deck_ov != null:
		deck_ov.queue_free()
	await process_frame


func _reset_recording() -> void:
	_recording = true
	_last_usec = Time.get_ticks_usec()
	_max_gap_ms = 0.0


func _count_nodes(host: Node) -> int:
	if host == null:
		return 0
	var total := 1
	for child in host.get_children():
		total += _count_nodes(child)
	return total


func _count_cards(host: Node) -> int:
	if host == null:
		return 0
	var total := 0
	var script = host.get_script()
	if script != null and String(script.resource_path).ends_with("/Card2D.gd"):
		total += 1
	for child in host.get_children():
		total += _count_cards(child)
	return total
