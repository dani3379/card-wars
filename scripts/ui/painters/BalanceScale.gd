## BalanceScale — the quartermaster's balance for scale_game. A fulcrum
## post, a beam that pivots by `tip` (radians; +tip = right pan down), and
## two hanging pans that show their coin counts as little stacks of discs.
## The engine tweens `tip` toward the honest result and sets `left_n` /
## `right_n`. Pure painter; the Event scene owns motion and hit-testing.
## (Reworked 2026-07-20 — the first pass was flat brass on a triangle
## post. Now: turned wooden column on a plinth, a level-gauge arc whose
## needle makes LEVEL readable at a glance, chain-hung dished pans.)
extends Control

var tip := 0.0          # beam rotation, radians (+ = right pan heavier/down)
var left_n := 0         # coins on the left pan
var right_n := 0        # coins on the right pan
var settled := false    # true once a weighing has been read (dishes lit)

const WOOD := Color(0.295, 0.205, 0.125)
const WOOD_LIT := Color(0.46, 0.34, 0.21)
const EDGE_INK := Color(0.075, 0.055, 0.038)
const BRASS := Color(0.66, 0.53, 0.28)
const BRASS_DK := Color(0.42, 0.33, 0.17)
const BRASS_LIT := Color(0.92, 0.80, 0.48)
const CHAIN := Color(0.55, 0.50, 0.42)
const COIN := Color(0.78, 0.66, 0.40)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _pan(center: Vector2, n: int) -> void:
	# A dished brass pan: under-shadow, outer dish, inner bowl shadow,
	# rim catch-light — then the pay-tokens clustered so the count reads.
	var rim_rx := 36.0
	var rim_ry := 7.0
	draw_colored_polygon(_ell(center + Vector2(2, 5), rim_rx * 0.95, rim_ry * 0.9),
		Color(0, 0, 0, 0.28))
	var dish := PackedVector2Array()
	for i in range(17):
		var a := PI * float(i) / 16.0
		dish.append(center + Vector2(cos(a) * rim_rx, sin(a) * 13.0 + 3.0))
	for i in range(16, -1, -1):
		var a := PI * float(i) / 16.0
		dish.append(center + Vector2(cos(a) * rim_rx, -sin(a) * rim_ry + 3.0))
	var body := BRASS.lerp(BRASS_LIT, 0.35 if settled else 0.0)
	draw_colored_polygon(dish, body)
	# Inner bowl: the dark inside the dish.
	draw_colored_polygon(_ell(center + Vector2(0, 3), rim_rx * 0.84, rim_ry * 0.8),
		Color(BRASS_DK.r, BRASS_DK.g, BRASS_DK.b, 0.85))
	draw_colored_polygon(_ell(center + Vector2(0, 3.6), rim_rx * 0.68, rim_ry * 0.62),
		Color(0.16, 0.12, 0.07, 0.6))
	# Rim ellipse ink + near-rim catch-light.
	var rim := _ell(center + Vector2(0, 3), rim_rx, rim_ry)
	rim.append(rim[0])
	draw_polyline(rim, EDGE_INK, 1.4, true)
	draw_arc(center + Vector2(0, 3), rim_rx * 0.97, PI * 0.15, PI * 0.85, 12,
		Color(1, 1, 0.9, 0.35), 1.6, true)
	# The coins, clustered so the count reads at a glance.
	var cols := 4
	for i in range(n):
		var cx := center.x - 24.0 + float(i % cols) * 16.0
		var cy := center.y - 4.0 - float(i / cols) * 7.0
		draw_circle(Vector2(cx, cy), 6.0, Color(0, 0, 0, 0.25), true, -1.0, true)
		draw_circle(Vector2(cx, cy - 1.0), 5.4, COIN, true, -1.0, true)
		draw_arc(Vector2(cx, cy - 1.0), 5.4, 0, TAU, 12,
			Color(EDGE_INK.r, EDGE_INK.g, EDGE_INK.b, 0.5), 1.0, true)
		draw_circle(Vector2(cx - 1.4, cy - 2.4), 1.8, Color(1, 1, 0.9, 0.5), true, -1.0, true)


func _ell(c: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw() -> void:
	if minf(size.x, size.y) <= 20.0:
		return
	var pivot := Vector2(size.x * 0.5, size.y * 0.24)
	var base_y := size.y * 0.9

	# ── the plinth and the turned column ─────────────────────────────────
	draw_colored_polygon(_ell(Vector2(pivot.x + 2, base_y + 4), 44.0, 7.0),
		Color(0, 0, 0, 0.30))
	draw_colored_polygon(PackedVector2Array([
		Vector2(pivot.x - 40, base_y - 6), Vector2(pivot.x + 40, base_y - 6),
		Vector2(pivot.x + 46, base_y + 2), Vector2(pivot.x - 46, base_y + 2)]),
		WOOD)
	draw_line(Vector2(pivot.x - 40, base_y - 6), Vector2(pivot.x + 40, base_y - 6),
		WOOD_LIT, 2.0, true)
	draw_line(Vector2(pivot.x - 46, base_y + 2), Vector2(pivot.x + 46, base_y + 2),
		EDGE_INK, 1.6, true)
	# Column: tapered, with two turned beads and a lit west face.
	var col := PackedVector2Array([
		Vector2(pivot.x - 5, pivot.y + 4), Vector2(pivot.x + 5, pivot.y + 4),
		Vector2(pivot.x + 9, base_y - 6), Vector2(pivot.x - 9, base_y - 6)])
	draw_colored_polygon(col, WOOD)
	draw_line(Vector2(pivot.x - 4.5, pivot.y + 6), Vector2(pivot.x - 8, base_y - 7),
		WOOD_LIT, 2.4, true)
	draw_line(Vector2(pivot.x + 4.5, pivot.y + 6), Vector2(pivot.x + 8, base_y - 7),
		Color(0, 0, 0, 0.30), 2.2, true)
	for by in [0.42, 0.62]:
		var yy := lerpf(pivot.y, base_y, by)
		var hw := lerpf(5.0, 9.0, by) + 2.5
		draw_colored_polygon(_ell(Vector2(pivot.x, yy), hw, 3.2), WOOD)
		draw_arc(Vector2(pivot.x, yy - 0.6), hw, PI * 1.1, PI * 1.9, 8,
			Color(WOOD_LIT.r, WOOD_LIT.g, WOOD_LIT.b, 0.8), 1.6, true)

	# ── the level gauge: an arc with a centre notch behind the needle ───
	draw_arc(pivot, 17.0, PI * 0.25, PI * 0.75, 12,
		Color(BRASS_DK.r, BRASS_DK.g, BRASS_DK.b, 0.8), 2.0, true)
	for tickf in [0.32, 0.5, 0.68]:
		var ta := PI * lerpf(0.25, 0.75, tickf)
		var t_in := pivot + Vector2(cos(ta), sin(ta)) * 14.0
		var t_out := pivot + Vector2(cos(ta), sin(ta)) * (20.0 if tickf == 0.5 else 17.5)
		draw_line(t_in, t_out, BRASS_LIT if tickf == 0.5 else BRASS, 2.0, true)
	# The needle rides the beam: plumb when the beam is level.
	var needle := pivot + Vector2(0, 19.0).rotated(tip)
	draw_line(pivot, needle, BRASS_LIT, 2.4, true)
	draw_circle(needle, 2.0, BRASS_LIT, true, -1.0, true)

	# ── the beam: brass bar, centre boss, ball finials ───────────────────
	var arm := size.x * 0.34
	var le := pivot + Vector2(-arm, 0).rotated(tip)
	var re := pivot + Vector2(arm, 0).rotated(tip)
	var perp := Vector2(0, 3.2).rotated(tip)
	draw_colored_polygon(PackedVector2Array([
		le - perp, re - perp, re + perp, le + perp]), BRASS)
	draw_line(le - perp * 0.5, re - perp * 0.5, BRASS_LIT, 1.6, true)
	draw_line(le + perp * 0.7, re + perp * 0.7,
		Color(BRASS_DK.r, BRASS_DK.g, BRASS_DK.b, 0.8), 1.4, true)
	for e in [le, re]:
		draw_circle(e, 4.4, BRASS_DK, true, -1.0, true)
		draw_circle(e, 3.2, BRASS, true, -1.0, true)
		draw_circle(e + Vector2(-1.0, -1.0), 1.1, Color(1, 1, 0.9, 0.6), true, -1.0, true)
	# Fulcrum boss.
	draw_circle(pivot, 6.6, BRASS_DK, true, -1.0, true)
	draw_circle(pivot, 4.8, BRASS, true, -1.0, true)
	draw_circle(pivot + Vector2(-1.4, -1.4), 1.6, Color(1, 1, 0.9, 0.55), true, -1.0, true)

	# ── chains: three light links per side, then the pans ────────────────
	var chain := size.y * 0.30
	var lp := Vector2(le.x, le.y + chain)
	var rp := Vector2(re.x, re.y + chain)
	for e in [[le, lp], [re, rp]]:
		var top_p: Vector2 = e[0]
		var pan_p: Vector2 = e[1]
		for off in [-11.0, 0.0, 11.0]:
			var anchor := pan_p + Vector2(off * 2.4, -4.0)
			var a := top_p
			var b := anchor
			var segs := 6
			for s in range(segs):
				var p0 := a.lerp(b, float(s) / float(segs))
				var p1 := a.lerp(b, float(s + 1) / float(segs))
				draw_line(p0, p1, CHAIN if s % 2 == 0 else
					Color(CHAIN.r, CHAIN.g, CHAIN.b, 0.55), 1.6, true)
	_pan(lp, left_n)
	_pan(rp, right_n)
