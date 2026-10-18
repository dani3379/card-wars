## ChroniclePage — extracted from GameOver.gd (menus polish 2026-07-19) so the
## Credits roll can be written on the same paper as the run chronicle.
## A parchment sheet drawn with the cards' material kit: deckled edge, edge
## toast, sepia washes, foxing, a double bronze rule. Subclassing
## PanelContainer keeps auto-height-from-content layout; the stylebox is
## empty (margins only) and the paper is painted in _draw underneath the
## children. A lost run chars the page: blackened deckle, an ember line
## still eating inward, scorch blotches in the corners.
extends PanelContainer

var charred := false
var page_seed := 0

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

## Deckled perimeter path, seeded — same idiom as the cards' WritLeaf.
## amp: wobble depth — 5 is the torn sheet edge; pass less for hand-ruled
## interior furniture.
func _sheet_path(inset: float, rng: RandomNumberGenerator, amp: float = 5.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0))
	var step := 26.0
	# Walk the 4 edges; wobble perpendicular to each.
	var edges := [
		[r.position, Vector2(r.end.x, r.position.y), Vector2(0, 1)],
		[Vector2(r.end.x, r.position.y), r.end, Vector2(-1, 0)],
		[r.end, Vector2(r.position.x, r.end.y), Vector2(0, -1)],
		[Vector2(r.position.x, r.end.y), r.position, Vector2(1, 0)],
	]
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var n: Vector2 = e[2]
		var count := maxi(2, int(a.distance_to(b) / step))
		for i in range(count):
			var t := float(i) / float(count)
			# Corners stay pinned (wobble eases to 0 at each end) so the
			# sheet keeps its rectangular stance.
			var ease_w := sin(t * PI)
			pts.append(a.lerp(b, t) + n * rng.randf_range(-amp, amp) * ease_w)
	return pts

func _draw() -> void:
	if size.x < 120.0 or size.y < 120.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("chronicle_%d" % page_seed)
	var sheet := _sheet_path(8.0, rng)
	# Cast shadow — the page lies ON the scene, so it throws one.
	for sh in [[Vector2(0, 10), 0.30, 26.0], [Vector2(0, 5), 0.22, 10.0]]:
		var off: Vector2 = sh[0]
		var spts := PackedVector2Array()
		for p in sheet:
			spts.append(p + off)
		draw_colored_polygon(spts, Color(0, 0, 0, sh[1]))
	# The paper. A charred page is smoke-dimmed toward ash.
	var paper := Color(0.855, 0.795, 0.665)
	if charred:
		paper = Color(0.760, 0.690, 0.560)
	draw_colored_polygon(sheet, paper)
	# Interior ageing — broad sepia washes, foxing spots, stray fibers.
	var wash := Color(0.42, 0.30, 0.17)
	for i in range(6):
		var c := Vector2(rng.randf_range(size.x * 0.12, size.x * 0.88),
			rng.randf_range(size.y * 0.15, size.y * 0.85))
		draw_circle(c, rng.randf_range(70.0, 180.0),
			Color(wash.r, wash.g, wash.b, rng.randf_range(0.020, 0.040)), true, -1.0, true)
	for i in range(26):
		var c := Vector2(rng.randf_range(size.x * 0.06, size.x * 0.94),
			rng.randf_range(size.y * 0.06, size.y * 0.94))
		draw_circle(c, rng.randf_range(1.5, 5.5),
			Color(0.45, 0.32, 0.16, rng.randf_range(0.045, 0.11)), true, -1.0, true)
	for i in range(34):
		var c := Vector2(rng.randf_range(size.x * 0.08, size.x * 0.92),
			rng.randf_range(size.y * 0.08, size.y * 0.92))
		var d := Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-3.0, 3.0))
		draw_line(c, c + d, Color(0.40, 0.30, 0.18, 0.06), 1.0, true)
	# Edge treatment along the SAME deckled path, so shading never
	# separates from the silhouette (the WritLeaf rule).
	var loop := sheet.duplicate()
	loop.append(sheet[0])
	if charred:
		# Burnt: wide blackened toast, then the ember line still creeping.
		draw_polyline(loop, Color(0.10, 0.07, 0.05, 0.90), 7.0, true)
		draw_polyline(loop, Color(0.62, 0.25, 0.08, 0.28), 2.6, true)
		for i in range(5):
			var t := rng.randf()
			var idx := int(t * (sheet.size() - 1))
			draw_circle(sheet[idx], rng.randf_range(14.0, 34.0),
				Color(0.08, 0.055, 0.04, rng.randf_range(0.10, 0.22)), true, -1.0, true)
	else:
		draw_polyline(loop, Color(0.47, 0.33, 0.18, 0.50), 4.0, true)
		draw_polyline(loop, Color(0.47, 0.33, 0.18, 0.16), 11.0, true)
	draw_polyline(loop, Color(0.16, 0.11, 0.07, 0.80), 1.4, true)
	# Document furniture: the double bronze rule framing the entry — drawn as
	# a second deckled loop (soft wide bed under a crisp rule on the SAME
	# path), so the furniture follows the sheet's hand-ruled language instead
	# of floating as a straight rectangle on organic paper.
	var rng_rule := RandomNumberGenerator.new()
	rng_rule.seed = hash("chronicle_rule_%d" % page_seed)
	var rule := _sheet_path(26.0, rng_rule, 2.2)
	var rule_loop := rule.duplicate()
	rule_loop.append(rule[0])
	draw_polyline(rule_loop, Color(0.55, 0.40, 0.20, 0.20), 4.2, true)
	draw_polyline(rule_loop, Color(0.55, 0.40, 0.20, 0.50), 1.5, true)
