extends SceneTree
## CPU-only timing of MapTerrain's first-act generation phases. No render or
## bake work is included, so this identifies where frame-yielding/density helps.

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var settings := root.get_node("UserSettings")
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("raider", 0, 20260903)
	rs.active_slot = -1
	rs.map_plate_cache.clear()
	var script := load("res://scripts/scenes/MapTerrain.gd") as GDScript
	var map: Control = script.new()
	map.size = Vector2(1600, 900)
	map.set("bake_mode", "plate")
	map.set("_act", 1)
	var rng: RandomNumberGenerator = map.get("_rng")
	rng.seed = 1207 + 101
	var phases := [
		"_resolve_faction", "_build_geo", "_read_run_map", "_build_mesh",
		"_assign_land", "_assign_elevation", "_carve_rivers",
		"_assign_moisture_biomes", "_assign_provinces", "_assign_zones",
		"_compute_hillshade", "_build_roads", "_place_labels",
		"_resolve_kingdoms", "_derive_terrain_tags",
	]
	var total_started := Time.get_ticks_usec()
	for phase in phases:
		var started := Time.get_ticks_usec()
		map.call(phase)
		print("[map-cpu] %-28s %8.3fms" % [phase,
			float(Time.get_ticks_usec() - started) / 1000.0])
	var snapshot_started := Time.get_ticks_usec()
	map.call("_mesh_snapshot")
	print("[map-cpu] %-28s %8.3fms" % ["_mesh_snapshot",
		float(Time.get_ticks_usec() - snapshot_started) / 1000.0])
	print("[map-cpu] total %.3fms cells=%d polys=%d" % [
		float(Time.get_ticks_usec() - total_started) / 1000.0,
		(map.get("_seed_pts") as PackedVector2Array).size(),
		(map.get("_polys") as Array).size()])
	map.free()
	_done = true
	quit(0)
