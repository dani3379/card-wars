## PaperSlip — one folded lot out of the helmet, drawn OPEN: the creases it
## was pressed into still standing, the writing an illegible field-hand
## scrawl (the real outcome text lands on the page beneath — the slip is the
## gesture, not the ledger). The unfold beat is played by the Event scene
## scaling the control up from a folded sliver; the painter never animates
## itself.
##
## (2026-07-22 craft pass. Was: a flat cream quad, two vertical bands so
## faint they read as artefacts rather than folds, three identical sawtooth
## squiggles, and a shadow drawn as the silhouette offset 2px — which on a
## sheet this size is a hard black fringe, not a shadow. Now: aged stock
## with a seeded wash, foxing and fibre; creases built the way a crease
## actually reads (a dark valley beside a lit ridge, thirds vertically and
## once across, because that is how a lot gets folded small enough for a
## helmet); a torn bite out of one edge; word-grouped writing with a ragged
## right margin and a short last line; and a soft two-stage drop shadow,
## because the slip is held ABOVE the helm, not lying on it.)
extends Control

var seed_text := "slip"

const PAPER := Color(0.862, 0.812, 0.694)
const PAPER_LIT := Color(0.930, 0.889, 0.784)
const WASH := Color(0.660, 0.588, 0.452)
const FOXING := Color(0.560, 0.408, 0.246)
const INK := Color(0.28, 0.23, 0.17, 0.80)
const EDGE_INK := Color(0.40, 0.32, 0.22)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The deckled sheet, with one torn bite. `grow` fattens it for the shadow
## layers so they read as diffuse light rather than a traced outline.
func _sheet(off: Vector2, grow := 0.0) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph := rng.randf() * TAU
	var bite := rng.randi_range(0, 21)
	var pts := PackedVector2Array()
	var n := 22
	for i in range(n):
		var t := float(i) / float(n)
		var a := TAU * t
		var v := Vector2(cos(a), sin(a))
		var sq := 1.0 / maxf(absf(v.x), absf(v.y))
		var w := 1.0 + 0.035 * sin(a * 5.0 + ph)
		# One corner went with the fold — a torn bite, not a clean edge.
		if i == bite or i == (bite + 1) % n:
			w -= 0.11
		pts.append(size * 0.5 + off
			+ v * sq * w * (size * 0.5 - Vector2(3, 3) + Vector2(grow, grow)))
	return pts


func _draw() -> void:
	if minf(size.x, size.y) <= 10.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) + 3
	var ph := rng.randf() * TAU

	# ── the shadow ───────────────────────────────────────────────────────
	# The slip is HELD, above the helm — so a soft two-stage drop, thrown
	# well clear and fattened. A silhouette offset a couple of pixels only
	# ever draws a hard fringe along one edge.
	draw_colored_polygon(_sheet(Vector2(9, 13), 3.0), Color(0, 0, 0, 0.13))
	draw_colored_polygon(_sheet(Vector2(5, 7), 0.0), Color(0, 0, 0, 0.20))

	# ── the stock ────────────────────────────────────────────────────────
	var sheet := _sheet(Vector2.ZERO)
	draw_colored_polygon(sheet, PAPER)
	# A seeded wash — damp, thumbed, carried in a pocket for a week.
	for i in range(6):
		var wc := Vector2(rng.randf_range(0.10, 0.90) * size.x,
			rng.randf_range(0.12, 0.88) * size.y)
		var wr := rng.randf_range(size.x * 0.13, size.x * 0.30)
		draw_circle(wc, wr, Color(WASH.r, WASH.g, WASH.b, 0.055), true, -1.0, true)
	# Light pooled toward the upper-left, the kit's one lamp.
	draw_circle(Vector2(size.x * 0.34, size.y * 0.30), size.x * 0.44,
		Color(PAPER_LIT.r, PAPER_LIT.g, PAPER_LIT.b, 0.34), true, -1.0, true)
	# Foxing: rust freckles where the damp got in.
	for i in range(5):
		var fc := Vector2(rng.randf_range(0.08, 0.92) * size.x,
			rng.randf_range(0.10, 0.90) * size.y)
		draw_circle(fc, rng.randf_range(1.0, 2.6),
			Color(FOXING.r, FOXING.g, FOXING.b, rng.randf_range(0.10, 0.22)),
			true, -1.0, true)
	# Fibre: a few short laid lines in the pulp.
	for i in range(7):
		var fp := Vector2(rng.randf_range(0.10, 0.90) * size.x,
			rng.randf_range(0.10, 0.90) * size.y)
		draw_line(fp, fp + Vector2(rng.randf_range(4.0, 11.0),
			rng.randf_range(-1.5, 1.5)),
			Color(WASH.r, WASH.g, WASH.b, 0.11), 1.0, true)

	# ── the creases ──────────────────────────────────────────────────────
	# Folded in thirds, then once across — helmet-sized. A crease reads as a
	# dark valley with a lit ridge beside it; a lone tinted band reads as a
	# printing fault, which is what the old one looked like.
	for fx in [size.x * 0.34, size.x * 0.67]:
		draw_line(Vector2(fx, 5.0), Vector2(fx, size.y - 5.0),
			Color(WASH.r, WASH.g, WASH.b, 0.34), 2.6, true)
		draw_line(Vector2(fx + 2.0, 5.0), Vector2(fx + 2.0, size.y - 5.0),
			Color(1.0, 0.98, 0.92, 0.30), 1.6, true)
	var fy := size.y * 0.5
	draw_line(Vector2(5.0, fy), Vector2(size.x - 5.0, fy),
		Color(WASH.r, WASH.g, WASH.b, 0.28), 2.4, true)
	draw_line(Vector2(5.0, fy + 1.8), Vector2(size.x - 5.0, fy + 1.8),
		Color(1.0, 0.98, 0.92, 0.26), 1.5, true)

	# ── the hand ─────────────────────────────────────────────────────────
	# Word groups, not a continuous sawtooth: gaps, a wandering baseline, a
	# ragged right margin and a last line that stops short — somebody wrote
	# this in a hurry on their knee.
	var rows := 4
	for row in range(rows):
		var y := size.y * (0.24 + 0.17 * float(row))
		var x := size.x * rng.randf_range(0.12, 0.16)
		var margin := size.x * (0.88 - (0.34 if row == rows - 1 else 0.0)
			- 0.06 * rng.randf())
		var amp := 1.5 + 0.7 * rng.randf()
		while x < margin:
			var wlen := size.x * rng.randf_range(0.09, 0.20)
			wlen = minf(wlen, margin - x)
			if wlen < size.x * 0.045:
				break
			var word := PackedVector2Array()
			var wx := x
			while wx <= x + wlen:
				word.append(Vector2(wx, y
					+ sin(wx * 0.62 + ph + float(row) * 2.1) * amp
					+ sin(float(row) * 1.7 + wx * 0.05) * 1.1))
				wx += 3.0
			if word.size() >= 2:
				draw_polyline(word, INK, 1.5, true)
				# One ascender or descender per word — the hand's spikes.
				if rng.randf() < 0.55:
					var ai := rng.randi_range(0, word.size() - 1)
					var up := -1.0 if rng.randf() < 0.6 else 1.0
					draw_line(word[ai], word[ai] + Vector2(0.8, up * amp * 2.6),
						INK, 1.3, true)
			x += wlen + size.x * rng.randf_range(0.035, 0.065)

	# ── edge and thumb ───────────────────────────────────────────────────
	# Aged stock darkens at the cut; and whoever drew it left a mark.
	var closed := sheet.duplicate()
	closed.append(sheet[0])
	draw_polyline(closed, Color(EDGE_INK.r, EDGE_INK.g, EDGE_INK.b, 0.30), 2.6, true)
	draw_polyline(closed, Color(EDGE_INK.r, EDGE_INK.g, EDGE_INK.b, 0.55), 1.0, true)
	draw_circle(Vector2(size.x * 0.13, size.y * 0.80), size.x * 0.075,
		Color(0.36, 0.28, 0.19, 0.13), true, -1.0, true)
