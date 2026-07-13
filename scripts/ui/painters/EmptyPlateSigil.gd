## EmptyPlateSigil — extracted from Card2D.gd (backend restructure 2026-07-14).
## Engraved device for the no-art plate: a small manuscript sigil drawn in
## dim gilt ink on the parchment — a compass-rosette for spells, a crossed-
## blade roundel for creatures. Replaces the old giant near-black initial
## letter (which read as a broken placeholder); a quiet centered device reads
## as intentional chart furniture instead. Deterministic, no letters.
extends Control

var is_spell_sigil := false
var ink := Color(0.82, 0.66, 0.30, 0.42)   # dim gilt

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var min_dim := minf(size.x, size.y)
	if min_dim <= 12.0:
		return
	var c := size * 0.5
	var r := min_dim * 0.34
	var shadow := Color(0.10, 0.07, 0.03, 0.30)
	# Twin engraved rings (shadow first, then the gilt line atop) — the
	# "set into the page" look the rest of the card's metal furniture uses.
	for ring_r in [r, r * 0.62]:
		draw_arc(c + Vector2(0, 1), ring_r, 0, TAU, 48, shadow, 1.6, true)
		draw_arc(c, ring_r, 0, TAU, 48, ink, 1.4, true)
	if is_spell_sigil:
		# Compass rosette: eight rays, the cardinals longer.
		for i in range(8):
			var a := TAU * float(i) / 8.0 - PI * 0.5
			var inner := r * 0.18
			var outer := r * (0.92 if i % 2 == 0 else 0.66)
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * inner + Vector2(0, 1),
				c + d * outer + Vector2(0, 1), shadow, 1.6, true)
			draw_line(c + d * inner, c + d * outer, ink, 1.4, true)
		draw_circle(c, r * 0.12, ink, true, -1.0, true)
	else:
		# Crossed blades: two slim quills/swords through the roundel.
		for ang in [PI * 0.25, -PI * 0.25]:
			var d := Vector2(cos(ang), sin(ang))
			var p0 := c - d * (r * 0.88)
			var p1 := c + d * (r * 0.88)
			draw_line(p0 + Vector2(0, 1), p1 + Vector2(0, 1),
				shadow, 2.0, true)
			draw_line(p0, p1, ink, 1.8, true)
		draw_circle(c + Vector2(0, 1), r * 0.16, shadow, true, -1.0, true)
		draw_circle(c, r * 0.14, ink, true, -1.0, true)
