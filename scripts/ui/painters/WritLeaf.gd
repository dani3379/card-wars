## WritLeaf — extracted from Card2D.gd (backend restructure 2026-07-14).
## The cut sheet itself: a deckled (seeded, slightly irregular) leaf
## silhouette with its ink contour and edge toast drawn along the SAME
## wobbled path, so the organic edge never separates from its shading.
## Replaces a StyleBox rounded rect — a mathematically perfect corner is
## the one thing real cut paper never has. The wobble only pushes INWARD,
## so children inset by >=3px always stay on the paper.
extends Control

var seed_text := "leaf"
var paper := Color(0.871, 0.812, 0.694)
var edge_ink := Color(0.165, 0.125, 0.082)
var toast := Color(0.298, 0.208, 0.110)
var toast_strength := 1.0
var corner_radius := 8.0

var _ph1 := 0.0
var _ph2 := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	_ph1 = rng.randf() * TAU
	_ph2 = rng.randf() * TAU

## Rounded-rect ring at `inset`, deckled: a fixed-count path (so nested
## toast rings stay parallel) where each vertex is pushed inward along
## the local path normal by a smooth two-frequency seeded wave.
func _ring(inset: float, amp: float) -> PackedVector2Array:
	var r := maxf(corner_radius - inset, 0.5)
	var x0 := inset
	var y0 := inset
	var x1 := size.x - inset
	var y1 := size.y - inset
	var cs := [
		[Vector2(x0 + r, y0 + r), PI, PI * 1.5],
		[Vector2(x1 - r, y0 + r), PI * 1.5, TAU],
		[Vector2(x1 - r, y1 - r), 0.0, PI * 0.5],
		[Vector2(x0 + r, y1 - r), PI * 0.5, PI],
	]
	var arc_n := 7
	var edge_n := 21
	var ideal := PackedVector2Array()
	for ci in range(4):
		var ctr: Vector2 = cs[ci][0]
		var a0: float = cs[ci][1]
		var a1: float = cs[ci][2]
		for s in range(arc_n):
			var a := lerpf(a0, a1, float(s) / float(arc_n - 1))
			ideal.append(ctr + Vector2(cos(a), sin(a)) * r)
		var nci := (ci + 1) % 4
		var nctr: Vector2 = cs[nci][0]
		var na0: float = cs[nci][1]
		var p_from := ctr + Vector2(cos(a1), sin(a1)) * r
		var p_to := nctr + Vector2(cos(na0), sin(na0)) * r
		for s in range(1, edge_n + 1):
			ideal.append(p_from.lerp(p_to, float(s) / float(edge_n + 1)))
	var n := ideal.size()
	var pts := PackedVector2Array()
	for i in range(n):
		var prev := ideal[(i - 1 + n) % n]
		var next := ideal[(i + 1) % n]
		var tang := (next - prev).normalized()
		var inward := Vector2(-tang.y, tang.x)
		var u := float(i) / float(n) * TAU
		var wob := clampf(0.34 + 0.33 * sin(u * 5.0 + _ph1)
			+ 0.33 * sin(u * 13.0 + _ph2), 0.0, 1.0) * amp
		pts.append(ideal[i] + inward * wob)
	return pts

func _draw() -> void:
	if size.x <= 8.0 or size.y <= 8.0:
		return
	# 1 — the sheet.
	var sheet := _ring(1.0, 1.7)
	draw_colored_polygon(sheet, paper)
	# 2 — ink contour: hand-cut edge line, doubles as silhouette AA.
	var closed := sheet.duplicate()
	closed.append(sheet[0])
	draw_polyline(closed, edge_ink, 1.3, true)
	# 3 — edge toast along the SAME deckle, fading inward, per-segment
	# alpha jitter so it reads hand-inked rather than printed.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) + 3
	for k in range(4):
		var ring := _ring(2.2 + float(k) * 1.7, 1.7)
		var base_a := (0.105 - float(k) * 0.019) * toast_strength
		for j in range(ring.size() - 1):
			draw_line(ring[j], ring[j + 1],
				Color(toast.r, toast.g, toast.b,
				base_a * (0.7 + rng.randf() * 0.6)),
				2.4 - float(k) * 0.3, true)
