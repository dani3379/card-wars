extends SceneTree
## Read-only structural probe for the live campaign-road presentation slice.
##
## It compiles both map scripts, then checks that live march feedback remains
## inside MapPulseOverlay while claimed-stop dressing remains deterministic and
## downstream of the per-open plate ink bake. It never starts or saves a run.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" \
##     --script res://tools/_probe_map_operations.gd

var _ran := false
var _fails := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _between(source: String, start_mark: String, end_mark: String) -> String:
	var a := source.find(start_mark)
	if a < 0:
		return ""
	var b := source.find(end_mark, a + start_mark.length())
	if b < 0:
		b = source.length()
	return source.substr(a, b - a)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	print("[map-operations-probe] start (read-only)")

	var terrain_path := "res://scripts/scenes/MapTerrain.gd"
	var view_path := "res://scripts/scenes/MapView.gd"
	var terrain_script := load(terrain_path) as GDScript
	var view_script := load(view_path) as GDScript
	_check(terrain_script != null and terrain_script.can_instantiate(),
		"MapTerrain compiles")
	_check(view_script != null and view_script.can_instantiate(),
		"MapView compiles")

	var terrain := FileAccess.get_file_as_string(terrain_path)
	var view := FileAccess.get_file_as_string(view_path)
	_check(not terrain.is_empty() and not view.is_empty(),
		"map sources are readable")

	var plate := _between(terrain, "class PlateItem extends Control:",
		"## SIMPLE_BACKDROP geography")
	_check(not plate.contains("_draw_committed_route")
			and not plate.contains("_draw_march_column"),
		"animated march work never enters PlateItem or its bake")
	_check(terrain.count("_draw_claimed_bivouac(") == 2,
		"claimed bivouac has exactly one draw call and one definition")
	var bivouac := _between(terrain,
		"func _draw_claimed_bivouac(", "\nfunc ")
	_check(not bivouac.is_empty()
			and not bivouac.contains("queue_redraw")
			and not bivouac.contains("randf")
			and not bivouac.contains("_process(")
			and not bivouac.contains("sin(_t"),
		"claimed-stop dressing is deterministic static ink")

	var overlay_at := view.find("class MapPulseOverlay extends Control:")
	var commit_at := view.find("\tfunc _draw_committed_route(")
	var column_at := view.find("\tfunc _draw_march_column(")
	_check(overlay_at >= 0 and commit_at > overlay_at and column_at > overlay_at,
		"committed route and column remain in the single live overlay")
	_check(view.contains("_site_label_for_preview(dest_nd)")
			and view.contains("_march_label = label"),
		"the committed march keeps its destination operation label")

	var march := _between(view, "\tfunc march_along(", "\n\tfunc _march_pos")
	_check(march.contains("UserSettings.reduce_motion")
			and march.contains("_march_prog = 1.0")
			and march.contains("queue_redraw()"),
		"Reduce Motion snaps the march to a fully rendered committed state")
	var draw_block := _between(view, "\tfunc _draw() -> void:",
		"\n\tfunc _draw_route_preview")
	_check(draw_block.contains("_draw_committed_route(amber)")
			and draw_block.contains("_draw_march_column(amber)"),
		"live draw path includes issued-road ink and the marching column")

	print("[map-operations-probe] %s" % ("ALL PASS" if _fails == 0
		else "%d FAILURES" % _fails))
	quit(0 if _fails == 0 else 1)
	return true
