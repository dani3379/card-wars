extends Node2D
## One route for one facedown hand. Registered card backs remain ordinary
## Container content; this Node2D is ignored by HBox/Grid/HFlow layout and only
## paints the war-table fiction that binds the already-reserved slots together.
##
## The route deliberately owns the only CPU animation for the whole set. Card
## backs keep sharing Motion's GPU lamplight material; there is never a process
## or tween per card. When a back begins its existing turn, the little standard
## finishes the road while the ink retires, then this node frees itself.

const TRAVEL_SECONDS := 1.55
const RELEASE_SECONDS := 0.14
const META_ROUTE := &"loading_muster_route"

var _covers: Array[WeakRef] = []
var _elapsed := 0.20
var _age := 0.0
var _alpha := 0.0
var _layout_seen := false
var _releasing := false
var _release_elapsed := 0.0
var _release_alpha := 1.0
var _release_from_phase := 0.0
var _last_route := PackedVector2Array()
var _last_stops := PackedVector2Array()
var _scale_hint := 1.0


func _ready() -> void:
	# Above the backs, but still inside the loading group's canvas/scroll clip.
	# Node2D (not Control) is the invariant that keeps Container geometry untouched.
	z_index = 48
	z_as_relative = true
	set_process(true)


func register_cover(cover: CanvasItem) -> void:
	if cover == null or not is_instance_valid(cover):
		return
	for existing in _covers:
		if existing.get_ref() == cover:
			return
	_covers.append(weakref(cover))
	cover.set_meta(META_ROUTE, weakref(self))


func is_accepting_covers() -> bool:
	return not _releasing and not is_queued_for_deletion()


func _process(delta: float) -> void:
	_age += delta
	_elapsed += delta
	_prune_cover_refs()
	if UserSettings != null and UserSettings.reduce_motion:
		# Also retire the sleeve shader if the setting is changed during a cold
		# load, not only when it was already enabled as the screen opened.
		for cover in _valid_covers(false):
			cover.material = null
		queue_free()
		return

	var live := _valid_covers(true)
	if not _releasing:
		_alpha = minf(1.0, _alpha + delta / 0.10)
		if live.size() >= 2:
			_layout_seen = true
		elif _layout_seen:
			_begin_release()
		elif _age > 0.30 and _covers.size() < 2:
			# A one-card offer has nothing to connect. Do not leave an idle group
			# painter behind for the lifetime of its screen.
			queue_free()
			return
		if _any_cover_turning(live):
			_begin_release()
	else:
		_release_elapsed += delta
		var t := clampf(_release_elapsed / RELEASE_SECONDS, 0.0, 1.0)
		_alpha = _release_alpha * (1.0 - smoothstep(0.0, 1.0, t))
		if t >= 1.0:
			queue_free()
			return
	queue_redraw()


func _begin_release() -> void:
	if _releasing:
		return
	_releasing = true
	_release_elapsed = 0.0
	_release_alpha = _alpha
	_release_from_phase = fposmod(_elapsed / TRAVEL_SECONDS, 1.0)


func _prune_cover_refs() -> void:
	# Same-parent rebuilds (notably repeated Arsenal slates) can retire covers
	# before their first draw. Do not let dead weak refs keep an idle route alive
	# or accumulate across rerolls.
	var kept: Array[WeakRef] = []
	for ref in _covers:
		var cover = ref.get_ref()
		if cover is CanvasItem and is_instance_valid(cover) \
				and not cover.is_queued_for_deletion():
			kept.append(ref)
	_covers = kept


func _valid_covers(require_visible: bool) -> Array[Control]:
	var out: Array[Control] = []
	for ref in _covers:
		var cover = ref.get_ref()
		if not (cover is Control) or not is_instance_valid(cover) \
				or cover.is_queued_for_deletion() or not cover.is_inside_tree():
			continue
		if require_visible and not cover.is_visible_in_tree():
			continue
		out.append(cover as Control)
	return out


func _any_cover_turning(covers: Array[Control]) -> bool:
	for cover in covers:
		# Normal loading backs sit at local scale 1. flip_out writes this exact
		# axis, so the route starts retiring on the first closing frame.
		if cover.scale.x < 0.985:
			return true
	return false


func _draw() -> void:
	if _alpha <= 0.002:
		return
	if not _releasing:
		var geometry := _route_geometry(_valid_covers(true))
		var route: PackedVector2Array = geometry.get("route", PackedVector2Array())
		var stops: PackedVector2Array = geometry.get("stops", PackedVector2Array())
		if route.size() >= 2 and stops.size() >= 2:
			_last_route = route
			_last_stops = stops
			_scale_hint = float(geometry.get("scale", 1.0))
	if _last_route.size() < 2:
		return

	var a := _alpha
	# Blind-debossed road + restrained gilt ink: the same two-pass grammar as
	# the campaign's conquered-route strip, sized down onto a packet of writs.
	draw_polyline(_last_route, Color(0.015, 0.010, 0.006, 0.58 * a),
		4.8 * _scale_hint, true)
	draw_polyline(_last_route, Color(0.76, 0.52, 0.19, 0.48 * a),
		1.45 * _scale_hint, true)
	for stop in _last_stops:
		_draw_stop(stop, a)

	var phase := fposmod(_elapsed / TRAVEL_SECONDS, 1.0)
	if _releasing:
		var release_t := clampf(_release_elapsed / RELEASE_SECONDS, 0.0, 1.0)
		phase = lerpf(_release_from_phase, 1.0,
			smoothstep(0.0, 1.0, release_t))
	var total := _path_length(_last_route)
	if total <= 0.01:
		return
	var head_distance := total * phase
	var trail := _path_slice(_last_route,
		maxf(0.0, head_distance - total * 0.16), head_distance)
	if trail.size() >= 2:
		draw_polyline(trail, Color(1.0, 0.72, 0.26, 0.86 * a),
			2.2 * _scale_hint, true)
	var edge_fade := smoothstep(0.0, 0.07, phase) \
		* (1.0 - smoothstep(0.94, 1.0, phase))
	_draw_standard(_point_at_distance(_last_route, head_distance), a * edge_fade)


func _route_geometry(covers: Array[Control]) -> Dictionary:
	if covers.size() < 2:
		return {}
	var inv := get_global_transform_with_canvas().affine_inverse()
	var records: Array[Dictionary] = []
	var height_total := 0.0
	for cover in covers:
		if cover.size.x < 2.0 or cover.size.y < 2.0:
			continue
		var cover_xform := cover.get_global_transform_with_canvas()
		var canvas_point := cover_xform \
			* Vector2(cover.size.x * 0.5, cover.size.y * 0.80)
		var local_point: Vector2 = inv * canvas_point
		var local_top: Vector2 = inv * (cover_xform * Vector2(cover.size.x * 0.5, 0.0))
		var local_bottom: Vector2 = inv * (cover_xform \
			* Vector2(cover.size.x * 0.5, cover.size.y))
		var local_height := local_top.distance_to(local_bottom)
		records.append({"point": local_point, "height": local_height})
		height_total += local_height
	if records.size() < 2:
		return {}
	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return (left.point as Vector2).y < (right.point as Vector2).y)

	var rows: Array = []
	for record in records:
		var point: Vector2 = record.point
		var threshold: float = maxf(18.0, float(record.height) * 0.28)
		if rows.is_empty() \
				or absf(point.y - float(rows[-1].mean_y)) > threshold:
			rows.append({"mean_y": point.y, "records": [record]})
		else:
			var row_records: Array = rows[-1].records
			row_records.append(record)
			rows[-1].records = row_records
			rows[-1].mean_y = (float(rows[-1].mean_y) \
				* float(row_records.size() - 1) + point.y) / float(row_records.size())

	var stops := PackedVector2Array()
	for row_index in range(rows.size()):
		var row_records: Array = rows[row_index].records
		row_records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return (left.point as Vector2).x < (right.point as Vector2).x)
		if row_index % 2 == 1:
			row_records.reverse()
		for record in row_records:
			stops.append(record.point)
	var route_scale := clampf(
		(height_total / float(records.size())) / 300.0, 0.55, 1.0)
	return {
		"stops": stops,
		"route": _bowed_path(stops, route_scale),
		"scale": route_scale,
	}


func _bowed_path(stops: PackedVector2Array, route_scale: float) -> PackedVector2Array:
	var path := PackedVector2Array()
	if stops.is_empty():
		return path
	path.append(stops[0])
	for i in range(stops.size() - 1):
		var from := stops[i]
		var to := stops[i + 1]
		var delta := to - from
		var normal := Vector2(-delta.y, delta.x).normalized()
		var bow := minf(7.0 * route_scale, delta.length() * 0.035)
		for step in range(1, 7):
			var t := float(step) / 6.0
			path.append(from.lerp(to, t) + normal * sin(PI * t) * bow)
	return path


func _draw_stop(point: Vector2, alpha: float) -> void:
	var r := 4.2 * _scale_hint
	var diamond := PackedVector2Array([
		point + Vector2(0, -r), point + Vector2(r, 0),
		point + Vector2(0, r), point + Vector2(-r, 0), point + Vector2(0, -r),
	])
	draw_colored_polygon(PackedVector2Array(diamond.slice(0, 4)),
		Color(0.33, 0.075, 0.045, 0.78 * alpha))
	draw_polyline(diamond, Color(0.98, 0.72, 0.28, 0.80 * alpha),
		1.15 * _scale_hint, true)


func _draw_standard(point: Vector2, alpha: float) -> void:
	if alpha <= 0.002:
		return
	var s := _scale_hint
	draw_circle(point, 8.0 * s, Color(1.0, 0.58, 0.16, 0.09 * alpha))
	draw_line(point + Vector2(0, 4.0 * s), point + Vector2(0, -13.0 * s),
		Color(0.08, 0.045, 0.025, 0.92 * alpha), 1.8 * s, true)
	draw_colored_polygon(PackedVector2Array([
		point + Vector2(0, -13.0 * s), point + Vector2(11.0 * s, -11.0 * s),
		point + Vector2(7.0 * s, -6.5 * s), point + Vector2(11.0 * s, -2.5 * s),
		point + Vector2(0, -4.0 * s),
	]), Color(0.88, 0.56, 0.16, 0.94 * alpha))


func _path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total


func _point_at_distance(path: PackedVector2Array, distance: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	var remaining := maxf(distance, 0.0)
	for i in range(path.size() - 1):
		var segment := path[i].distance_to(path[i + 1])
		if remaining <= segment or i == path.size() - 2:
			return path[i].lerp(path[i + 1],
				clampf(remaining / maxf(segment, 0.001), 0.0, 1.0))
		remaining -= segment
	return path[-1]


func _path_slice(path: PackedVector2Array, from_distance: float,
		to_distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.size() < 2 or to_distance <= from_distance:
		return out
	out.append(_point_at_distance(path, from_distance))
	var walked := 0.0
	for i in range(path.size() - 1):
		walked += path[i].distance_to(path[i + 1])
		if walked > from_distance and walked < to_distance:
			out.append(path[i + 1])
	out.append(_point_at_distance(path, to_distance))
	return out
