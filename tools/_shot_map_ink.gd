extends Node
# THE ROAD-INK HARNESS (2026-09-10). Shoots the map's committed march at three
# points along it plus the hover ruling, zoomed in far enough that the STROKE is
# what fills the frame rather than the chart.
#
#   Godot.exe --path "D:\Godot" res://tools/_shot_map_ink.tscn
#
# What each frame is evidence for:
#   ink_hover  — the dry-point ruling. Must read as SCORED: thin, matte, no
#                gloss anywhere along it.
#   ink_early / ink_mid / ink_done — the march. The claim under test is that a
#                bright WET lead of roughly constant length rides the nib while
#                everything behind it has gone dark and matte. If the whole
#                stroke is one brightness at any of the three, the wet/dry split
#                is not landing and the "setting" read is not there.
#
# Zoom is deliberately 2.0: at the map's own 1.10 open zoom the road is ~6 px of
# a 1600px frame, which is enough to see that SOMETHING changed and not nearly
# enough to judge a cross-section. The whole point of the profile is what it
# does across its width.

const HERO_ID := "raider"
# Pinned for the same reason _shot_map_states pins it: an unseeded run rolls a
# fresh map every session and two runs of the harness cannot then be diffed.
const SHOT_SEED := 20260804
const MARCH_ZOOM := 2.0
# The zoom MapView._ready actually opens at — see its own note on why 1.15 is
# the rejected pick.
const PLAY_ZOOM := 1.10
# The real march runs 0.55s, which is far too fast to catch a mid-stroke frame
# reliably — the harness stretches it and shoots by PROGRESS, not by clock.
const MARCH_DUR := 4.0

var _map: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	RunState.start_new_run(HERO_ID, -1, SHOT_SEED)
	await get_tree().process_frame

	_map = load("res://scenes/map.tscn").instantiate()
	get_tree().root.add_child(_map)
	await get_tree().create_timer(3.5).timeout

	var avail: Array = RunState.get_available_nodes()
	if avail.is_empty():
		print("SHOT FAIL: no available nodes")
		get_tree().quit(1)
		return
	var dest_nd: Dictionary = avail[0]
	var dest: Vector2 = _node_pos(int(dest_nd.row), int(dest_nd.col))
	var from_p: Vector2 = _map._player_pos if bool(_map._has_player) \
		else (_map._camp_pos as Vector2)
	var path: PackedVector2Array = _map.road_path_between(from_p, dest)
	if path.size() < 2:
		print("SHOT FAIL: empty road path")
		get_tree().quit(1)
		return

	# Frame the ROAD, not the island: centre the view on the midpoint of the leg.
	var mid: Vector2 = path[path.size() / 2]
	_map._set_view(MARCH_ZOOM, Vector2(1600, 900) * 0.5 - mid * MARCH_ZOOM)
	await get_tree().process_frame

	var ov = _map._overlay
	# 1 — the hovered branch, before anything is committed.
	ov.preview_route(path, dest, "THE HOLD")
	await _shoot("_shot_ink_hover.png")
	ov.clear_route_preview()

	# 1.5 — the dispatch riders. TWO frames a beat apart, because the claim under
	# test is motion: one frame proves a streak exists, two prove it is running
	# the road and that the roads are not firing in unison.
	await _shoot("_shot_ink_glint_a.png")
	await get_tree().create_timer(0.55).timeout
	await _shoot("_shot_ink_glint_b.png")

	# 2..4 — the march. march_along is a coroutine that returns at the end, so it
	# is deliberately NOT awaited here; the harness watches _march_prog instead.
	ov.march_along(path, "THE HOLD", MARCH_DUR)
	await _shoot_at_progress(ov, 0.30, "_shot_ink_early.png")
	await _shoot_at_progress(ov, 0.68, "_shot_ink_mid.png")
	await _shoot_at_progress(ov, 1.0, "_shot_ink_done.png")

	# 5 — AS PLAYED. Every frame above is at zoom 2.0 so the cross-section is
	# big enough to judge, and a stroke tuned only at that magnification is tuned
	# for a view nobody uses: 1.10 is the zoom MapView actually opens at, where a
	# 12px plate stroke is 13 screen px next to a 7px road. Shoot the thing the
	# player sees or the tuning is fiction.
	_map._set_view(PLAY_ZOOM, Vector2(1600, 900) * 0.5 - mid * PLAY_ZOOM)
	await _shoot("_shot_ink_played.png")

	# 6 — the frontier reveal, re-fired on the settled chart: the roads opening
	# nearest-first. Shot part-way through the stagger, since the whole point is
	# that they do NOT all land together.
	ov.play_frontier_reveal(0.0)
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_shot_ink_reveal.png")
	print("SAVED _shot_ink_reveal.png")

	# 7 — Etna. Framed on the vent at a zoom where the lobes are readable, twice
	# a second apart: a plume that photographs identically twice is a decal.
	var etna: Vector2 = _map._etna_peak
	_map._set_view(1.6, Vector2(1600, 900) * 0.5 - (etna + Vector2(20, -90)) * 1.6)
	await _shoot("_shot_ink_etna_a.png")
	await get_tree().create_timer(1.1).timeout
	await _shoot("_shot_ink_etna_b.png")

	# 8 — THE STROKE RHYTHM, measured rather than eyeballed. Every frame above is
	# shot BY PROGRESS precisely so it cannot be thrown off by a slow frame — but
	# that also means none of them can see the thing the pen rhythm changed, which
	# is purely temporal. So: re-run the march at its real duration, sample the
	# progress every frame, and report where the pen was moving and where it
	# rested. Three accelerate-and-settle runs separated by two near-zero plateaus
	# is the pass; one smooth ramp is the old single-tween behaviour.
	ov._march_prog = -1.0
	ov.march_along(path, "THE HOLD", 0.55)
	var t0: float = Time.get_ticks_msec() / 1000.0
	var samples: Array = []
	while float(ov._march_prog) < 1.0 and samples.size() < 600:
		await get_tree().process_frame
		samples.append([Time.get_ticks_msec() / 1000.0 - t0,
			float(ov._march_prog)])
	var rests := 0
	var line := ""
	for i in range(1, samples.size()):
		var dt: float = float(samples[i][0]) - float(samples[i - 1][0])
		var dp: float = float(samples[i][1]) - float(samples[i - 1][1])
		var rate: float = 0.0 if dt <= 0.0 else dp / dt
		if rate < 0.02:
			rests += 1
			line += "."
		else:
			line += "#"
	print("RHYTHM %s  (%d rest frames of %d)" % [line, rests, samples.size()])

	print("SHOTS_DONE")
	get_tree().quit()


func _node_pos(row: int, col: int) -> Vector2:
	for nd in _map._nodes:
		if int(nd.row) == row and int(nd.col) == col:
			return nd.pos
	return Vector2.ZERO


## Poll until the march has walked at least `p` of its length, then shoot. Timed
## sleeps were the first cut and they measure the MACHINE — a loaded frame slips
## the sample and the "30%" frame is really 45%, which is exactly the sort of
## drift that makes an A/B unreadable.
func _shoot_at_progress(ov, p: float, path: String) -> void:
	var guard := 0
	while float(ov._march_prog) < p and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://" + path)
	print("SAVED %s  (prog %.2f)" % [path, float(ov._march_prog)])


func _shoot(path: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://" + path)
	print("SAVED ", path)
