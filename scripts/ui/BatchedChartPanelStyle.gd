class_name BatchedChartPanelStyle
extends StyleBox
## Low-command chart furniture for dense, repeated UI.
##
## The shared GameTheme.ChartPanelStyle deliberately spends many canvas
## commands on hand-cut edge detail. This variant keeps the same structural
## language (chamfer, vertical field light, ink seam, metal rim, tacks and
## shadow) but submits the face as one indexed triangle array. Use it for
## repeated tiles where the richer micro-detail multiplies across the screen.

var bg_color := Color(0.06, 0.05, 0.042, 0.96)
var border_color := Color(0.60, 0.51, 0.34, 0.90):
	set(value):
		border_color = value
		emit_changed()
var rule_width := 1.0
var chamfer := 12.0
var shadow := true
var parchment := false
var corner_tacks := true
var shadow_color := Color(0, 0, 0, 1.0)
var shadow_size := 8.0


static func from_chart(source: StyleBox) -> BatchedChartPanelStyle:
	var style := BatchedChartPanelStyle.new()
	for property in ["bg_color", "border_color", "rule_width", "chamfer",
			"shadow", "parchment", "corner_tacks", "shadow_color", "shadow_size"]:
		style.set(property, source.get(property))
	style.content_margin_left = source.get_content_margin(SIDE_LEFT)
	style.content_margin_top = source.get_content_margin(SIDE_TOP)
	style.content_margin_right = source.get_content_margin(SIDE_RIGHT)
	style.content_margin_bottom = source.get_content_margin(SIDE_BOTTOM)
	return style


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow(3.0 + shadow_size * 0.65) if shadow else rect.grow(2.0)


static func _oct(rect: Rect2, inset: float, cut: float) -> PackedVector2Array:
	var left := rect.position.x + inset
	var top := rect.position.y + inset
	var right := rect.end.x - inset
	var bottom := rect.end.y - inset
	var corner := clampf(cut - inset * 0.45, 2.0,
		minf(right - left, bottom - top) * 0.26)
	return PackedVector2Array([
		Vector2(left + corner, top), Vector2(right - corner, top),
		Vector2(right, top + corner), Vector2(right, bottom - corner),
		Vector2(right - corner, bottom), Vector2(left + corner, bottom),
		Vector2(left, bottom - corner), Vector2(left, top + corner),
	])


static func _append_ring(points: Array[Vector2], colors: Array[Color],
		indices: Array[int], outer: PackedVector2Array,
		inner: PackedVector2Array, color: Color) -> void:
	for i in range(outer.size()):
		var j := (i + 1) % outer.size()
		var base := points.size()
		points.append_array([outer[i], outer[j], inner[j], inner[i]])
		colors.append_array([color, color, color, color])
		indices.append_array([base, base + 1, base + 2,
			base, base + 2, base + 3])


static func _append_fan(points: Array[Vector2], colors: Array[Color],
		indices: Array[int], poly: PackedVector2Array,
		top_color: Color, bottom_color: Color, bounds: Rect2) -> void:
	var center := Vector2.ZERO
	for point in poly:
		center += point
	center /= maxf(float(poly.size()), 1.0)
	var center_index := points.size()
	points.append(center)
	colors.append(top_color.lerp(bottom_color, 0.5))
	var first := points.size()
	for point in poly:
		points.append(point)
		var mix := clampf((point.y - bounds.position.y) /
			maxf(bounds.size.y, 1.0), 0.0, 1.0)
		colors.append(top_color.lerp(bottom_color, mix))
	for i in range(poly.size()):
		indices.append_array([center_index, first + i,
			first + ((i + 1) % poly.size())])


func _draw(canvas_item: RID, rect: Rect2) -> void:
	if minf(rect.size.x, rect.size.y) < 3.0:
		return
	var cut := clampf(chamfer, 4.0,
		minf(rect.size.x, rect.size.y) * 0.26)
	if shadow:
		var shadow_poly := _oct(rect.grow(shadow_size * 0.32), 0.0,
			cut + shadow_size * 0.32)
		for i in range(shadow_poly.size()):
			shadow_poly[i] += Vector2(0, 3)
		RenderingServer.canvas_item_add_polygon(canvas_item, shadow_poly,
			PackedColorArray([Color(shadow_color.r, shadow_color.g,
				shadow_color.b, shadow_color.a * 0.34)]))

	var seam := 1.4
	var outer := _oct(rect, 0.0, cut)
	var metal := _oct(rect, seam, cut)
	var inner := _oct(rect, seam + maxf(rule_width, 1.4), cut)
	var base := bg_color
	if parchment:
		base = bg_color.lerp(Color(0.16, 0.12, 0.08, bg_color.a), 0.35)
	var top_color := base.lerp(Color(0.30, 0.24, 0.16, base.a), 0.22)
	var bottom_color := base.lerp(Color(0.0, 0.0, 0.0, base.a), 0.30)
	var points: Array[Vector2] = []
	var colors: Array[Color] = []
	var indices: Array[int] = []
	_append_ring(points, colors, indices, outer, metal,
		Color(0.04, 0.03, 0.02, 0.90))
	_append_ring(points, colors, indices, metal, inner, border_color)
	_append_fan(points, colors, indices, inner, top_color, bottom_color, rect)

	if corner_tacks and minf(rect.size.x, rect.size.y) >= 70.0 and cut >= 7.0:
		var tack_size := clampf(cut * 0.27, 2.5, 4.3)
		var tack_color := Color(minf(border_color.r * 1.12, 1.0),
			minf(border_color.g * 1.12, 1.0),
			minf(border_color.b * 1.12, 1.0), border_color.a)
		for pair in [[7, 0], [1, 2], [3, 4], [5, 6]]:
			var at: Vector2 = (outer[pair[0]] + outer[pair[1]]) * 0.5
			var diamond := PackedVector2Array([
				at + Vector2(0, -tack_size), at + Vector2(tack_size, 0),
				at + Vector2(0, tack_size), at + Vector2(-tack_size, 0)])
			_append_fan(points, colors, indices, diamond,
				tack_color, tack_color, rect)

	RenderingServer.canvas_item_add_triangle_array(canvas_item,
		PackedInt32Array(indices), PackedVector2Array(points),
		PackedColorArray(colors))
