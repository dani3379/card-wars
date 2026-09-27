## WoundSeal — the lane forecast's numeral, in the card's own material (2026-09-16).
##
## THE DEFECT THIS REPLACES. The always-on forecast wrote its numbers into a
## `Label` on a rounded `StyleBoxFlat` and parked it on `_card_center` — measured
## by `tools/_shot_forecast.gd`: SIX of eight chips sat 100% over a creature's
## painting, one of them squarely across a face. It was the only piece of
## web-page chrome left on the board, and it sat next to the thing that shows
## the player every other number in this game: a pressed wax seal.
##
## So the forecast speaks in wax now. A body about to be struck grows a SECOND
## seal beside its HP seal, carrying the weight of the blow — and the seal is
## CRACKED by it. That is not decoration: the crack is the severity channel, and
## it is the reason this reads at a glance across eight bodies where eight
## sentences did not.
##
##   severity  = damage / HP standing, so the fissure opens as the blow gets
##               closer to fatal. A scratch is a hairline; a near-kill runs the
##               fissure most of the way across.
##   broken    = LETHAL. The seal is split clean through and the two halves have
##               PARTED, with table showing between them. A different SHAPE, not
##               a different colour — Slay the Spire's intent icons change at
##               damage thresholds for the same reason, and colour alone fails a
##               colour-blind player outright.
##
## THE NUMERAL IS THE BLOW, NOT THE REMAINDER, and that was a real decision. The
## card's own HP seal is 20px away showing what the body has now, so printing the
## result here would put two same-looking numerals side by side, one of them a
## prediction — the exact ambiguity the old "TAKES 5 - 1 HP" chip papered over
## with words. Damage is also this game's established unit: the hero panel says
## INCOMING 5, and every clash float is a damage number.
##
## Grammar follows WaxSeal.gd exactly (one light, top-left; seeded wobble;
## squeeze ridge; sunk face) because a forecast seal that lit differently from
## the stat seal beside it would read as a different kind of object. It is drawn
## rather than composed from WaxSeal because the crack has to cut the numeral —
## the fissure is drawn LAST, over the digits, so the number itself reads as
## broken through. A Label child could never be cut that way.
extends Control

const LayerStyle := preload("res://scripts/ui/painters/LayerStyle.gd")

const LIGHT_A := PI * 1.25          # light azimuth: top-left (y-down), as WaxSeal

var wax := Color(0.510, 0.137, 0.106)   # HEALTH_RED_DROP — the wound is the HP's own wax
var severity := 0.4                     # 0..1, how far the fissure runs
var broken := false                     # lethal: split clean through, halves parted
var amount := 0                         # the blow, printed in the sunk face
var seed_text := "wound"
var face_hit := false                   # a breach of the LINE, not a body


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(seed_text)
	return r


## The cooled-wax silhouette. Same construction as WaxSeal._blob — a couple of
## low harmonics plus one or two squeeze lobes, so it is wax rather than an
## imprecise circle.
func _blob(c: Vector2, base_r: float, n: int = 30) -> PackedVector2Array:
	var rng := _rng()
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var amp1 := 0.028 + rng.randf() * 0.018
	var amp2 := 0.016 + rng.randf() * 0.012
	var lobes := 1 + (rng.randi() % 2)
	var la: Array[float] = []
	var lamp: Array[float] = []
	var lw: Array[float] = []
	for i in lobes:
		la.append(rng.randf() * TAU)
		lamp.append(0.050 + rng.randf() * 0.040)
		lw.append(0.30 + rng.randf() * 0.20)
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var w := 1.0 + amp1 * sin(a * 3.0 + ph1) + amp2 * sin(a * 7.0 + ph2)
		for l in lobes:
			var d := absf(angle_difference(a, la[l]))
			w += lamp[l] * exp(-pow(d / lw[l], 2.0))
		pts.append(c + Vector2(cos(a), sin(a)) * base_r * w)
	return pts


## The fissure, as a jagged path across the seal. Seeded off the same text as the
## blob so a given body's wound always cracks the same way — a fissure that
## re-rolled every refresh would shimmer, and this overlay rebuilds on every HUD
## event.
##
## `run` is how far across it travels (severity); a broken seal always runs the
## full width because a break is a break.
func _fissure(c: Vector2, r: float, run: float) -> PackedVector2Array:
	var rng := _rng()
	rng.state = rng.state + 7919          # a different stream from the silhouette
	var axis := rng.randf() * TAU
	var dir := Vector2(cos(axis), sin(axis))
	var nrm := Vector2(-dir.y, dir.x)
	var start := c - dir * r * 1.06
	var span := r * 2.12 * clampf(run, 0.12, 1.0)
	var steps := 9
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		# Lateral wander, pinched at both ends so the crack starts and finishes
		# on the rim instead of wandering off it. At 0.20 of the radius the path
		# came out near-straight and photographed as a scratch ruled across the
		# wax; wax does not split in a line.
		var pinch := sin(t * PI)
		var jitter := (rng.randf() * 2.0 - 1.0) * r * 0.30 * pinch
		pts.append(start + dir * (span * t) + nrm * jitter)
	return pts


func _draw() -> void:
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.46
	var u := r / 18.0                      # every width scales with the seal
	var lightv := Vector2(cos(LIGHT_A), sin(LIGHT_A))

	var body := _blob(c, r)
	var run: float = 1.0 if broken else clampf(severity, 0.0, 1.0)
	var crack := _fissure(c, r, run)

	# Contact shadow — the seal is a physical object pressed onto the table, and
	# without this it floats like a sticker (WaxSeal's own 2026-07-19 lesson).
	var shadow := PackedVector2Array()
	for p in body:
		shadow.append(p + Vector2(0.0, u * 1.5))
	draw_colored_polygon(shadow, Color(0.02, 0.012, 0.008, 0.52))
	# THE SHINING, underneath (2026-09-17). A warm bloom bleeding out into the
	# dark wood before any wax is drawn. It is what separates "a red disc" from
	# "a hot seal on a table", and it costs one stack of grown copies at falling
	# alpha — see LayerStyle.outer_glow. A kill glows harder, which is a fourth
	# independent channel on the lethal read.
	LayerStyle.outer_glow(self, body, wax.lightened(0.34),
		u * (7.0 if broken else 4.6), 0.30 if broken else 0.19)

	if broken:
		# BROKEN CLEAN THROUGH. The blob is cut along the fissure and the halves
		# are parted, so the dark table shows in the gap. Half-planes are built
		# from the crack's own axis and clipped against the silhouette, which is
		# what keeps the two pieces' outer edges wobbled like the wax they came
		# from — offsetting a whole copy would give two smooth-edged crescents.
		var a0: Vector2 = crack[0]
		var a1: Vector2 = crack[crack.size() - 1]
		var dir := (a1 - a0).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		# THE HALVES HAVE TO ACTUALLY PART. At u*1.35 the gap was under two
		# pixels and the whole broken state photographed as "a line through it"
		# — indistinguishable at a glance from a deep crack, which defeats the
		# point of giving lethal its own SHAPE.
		var part: float = u * 3.2
		for s in [1.0, -1.0]:
			var plane := PackedVector2Array()
			# Walk the crack, then close the half-plane far out on one side.
			for p in crack:
				plane.append(p)
			plane.append(a1 + nrm * s * r * 3.0)
			plane.append(a0 + nrm * s * r * 3.0)
			for piece in Geometry2D.intersect_polygons(body, plane):
				var moved := PackedVector2Array()
				for p in piece:
					moved.append(p + nrm * s * part)
				_draw_wax_piece(moved, lightv, u)
	else:
		_draw_wax_piece(body, lightv, u)

	# The numeral, sunk into the face. Light on the dark impression — the
	# battlefield-legibility setup the stat seals already use.
	if amount > 0 and GameTheme.font_stat != null:
		var txt := str(amount)
		# 1.06 of the radius put a 20px glyph in a 40px seal and it read as a
		# smudge beside the card's own 18px-on-38px stat numeral. The stat seals
		# are the reference: this has to look like one of those, not like a
		# footnote pinned beside one.
		var fs := int(round(r * 1.30))
		var w := size.x
		var asc := GameTheme.font_stat.get_ascent(fs)
		var base := Vector2(0.0, c.y + asc * 0.5 - fs * 0.07)
		draw_string_outline(GameTheme.font_stat, base, txt,
			HORIZONTAL_ALIGNMENT_CENTER, w, fs, maxi(int(u * 3.0), 4),
			Color(0.05, 0.02, 0.015, 0.96))
		draw_string(GameTheme.font_stat, base, txt,
			HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(1.0, 0.96, 0.92))

	# THE FISSURE GOES LAST, OVER THE DIGITS. That ordering is the whole point:
	# the number is cracked through, so the damage and its severity are one
	# object instead of a number with a decoration beside it.
	_draw_fissure(crack, u, lightv)

	if face_hit:
		_draw_breach_barbs(c, r, u)


## One piece of wax: body, squeeze ridge lit on the light side, and the stamped
## recess sunk dark so a numeral can sit in it.
func _draw_wax_piece(poly: PackedVector2Array, lightv: Vector2, u: float) -> void:
	if poly.size() < 3:
		return
	var deep := Color(wax.r * 0.52, wax.g * 0.44, wax.b * 0.42, 1.0)
	draw_colored_polygon(poly, wax)

	# The ridge: a lit rim where the light strikes, a shade rim opposite. Drawn
	# as a polyline round the silhouette with per-vertex weighting rather than
	# two arcs, because a parted half is not a circle any more.
	var n := poly.size()
	var cen := Vector2.ZERO
	for p in poly:
		cen += p
	cen /= float(n)
	for i in range(n):
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % n]
		var outn := ((p0 + p1) * 0.5 - cen).normalized()
		# `lightv` UN-NEGATED -- see LayerStyle.bevel (2026-09-17). This is an
		# inline copy of that pass's Lambert and it carried the same inverted
		# sign, so the seal's squeeze ridge lit bottom-right. Fixing only
		# LayerStyle would have been worse than leaving both: the bracket's
		# bevel would light top-left while the seal beside it stayed
		# bottom-right, and these two marks sit within 20px of each other on
		# the same war table. NOTE the fissure lip below deliberately keeps
		# its negation -- a crack is a CONCAVE groove, whose lit wall is the
		# one facing away from the lamp. Different optic, different sign.
		var lam := outn.dot(lightv)              # 1 facing the light
		var col: Color
		if lam > 0.0:
			col = Color(wax.r + 0.34, wax.g + 0.23, wax.b + 0.19, lam * 0.92)
		else:
			col = Color(0.05, 0.02, 0.015, -lam * 0.70)
		# u*1.25 is barely a pixel at this size, so the squeeze ridge was not
		# being drawn at all and the seal read flat beside the card's own.
		draw_line(p0, p1, col, u * 2.1)

	# The impression — a smaller sunk face, offset AWAY from the light so the
	# near wall occludes and the far wall catches. >= 0.28 darker than the body
	# is the numeral-legibility contract WaxSeal states.
	var inner := PackedVector2Array()
	for p in poly:
		inner.append(cen + (p - cen) * 0.70 + lightv * u * 0.35)
	if inner.size() >= 3:
		draw_colored_polygon(inner, deep)
		# The recess has a WALL: a dark band hugging the rim away from the
		# light, so the face reads as sunk rather than as a darker sticker laid
		# on top of a lighter one.
		LayerStyle.inner_shadow(self, inner, u * 1.6, 0.55)
	# The specular sliver, last on the wax (the bevel above is the rim; this is
	# the surface). Wax is not matte — a pressed seal always catches the light
	# somewhere on its dome, and without it the whole token reads as felt.
	LayerStyle.shine(self, poly, 0.40, 0.17)


## The crack itself: a dark core with a lit lip on the light side, so it reads as
## an opening in a solid rather than a scratch drawn on top of one.
func _draw_fissure(pts: PackedVector2Array, u: float, lightv: Vector2) -> void:
	if pts.size() < 2:
		return
	var w: float = u * (1.9 if broken else 1.15)
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var seg := (p1 - p0)
		if seg.length_squared() < 0.01:
			continue
		var nrm := Vector2(-seg.y, seg.x).normalized()
		# Lip on whichever side faces the light; shadow on the other.
		var s: float = 1.0 if nrm.dot(-lightv) > 0.0 else -1.0
		# The lip is a LIP, not a highlight. On the kill wax (0.62, 0.15, 0.10) a
		# +0.40/+0.30/+0.25 lift clips past 1.0 in red and lands on near-white,
		# so the fissure photographed as white segments scattered over the
		# numeral rather than as an opening edge catching the light.
		draw_line(p0 + nrm * s * w * 0.80, p1 + nrm * s * w * 0.80,
			Color(minf(wax.r + 0.26, 0.92), wax.g + 0.17, wax.b + 0.13, 0.58),
			u * 1.05)
		draw_line(p0, p1, Color(0.03, 0.015, 0.012, 0.97), w)


## A breach of the LINE has no body to crack, so the seal wears the mark of the
## gap instead: two barbs driven inward, the same "nothing is holding this
## column" statement the chevrons used to make in four stacked hairlines.
func _draw_breach_barbs(c: Vector2, r: float, u: float) -> void:
	for s in [-1.0, 1.0]:
		var tip := c + Vector2(s * r * 1.30, 0.0)
		var quad := PackedVector2Array([
			tip,
			c + Vector2(s * r * 1.92, -r * 0.34),
			c + Vector2(s * r * 1.70, 0.0),
			c + Vector2(s * r * 1.92, r * 0.34),
		])
		var halo := PackedVector2Array()
		for p in quad:
			halo.append(p + Vector2(0.0, u * 1.1))
		draw_colored_polygon(halo, Color(0.02, 0.01, 0.008, 0.75))
		draw_colored_polygon(quad, Color(wax.r + 0.42, wax.g + 0.16, wax.b + 0.12, 0.95))
