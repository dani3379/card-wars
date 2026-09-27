## RunRoad — where the saved run actually IS, drawn as the road it is on.
##
## Replaces two dotted-leader rows on the title screen's CURRENT RUN plate:
##
##     ACT ...................... 1
##     PROVINCE ................. 1
##
## WHY THIS IS NOT A STYLING CHANGE. Cleveland & McGill (JASA 79(387), 1984)
## ranked the elementary perceptual tasks by how accurately people decode a
## quantity from them and put POSITION ALONG A COMMON SCALE first. Reading a
## numeral is not on that list at all: it is symbolic, not perceptual, so a
## printed "1" cannot be glanced at, only read — and then held in mind while the
## second number is read, and then both converted into an idea of how far
## through the run you are. A run has a KNOWN EXTENT (3 acts of `rows_per_act`
## provinces), which is precisely the precondition a positional encoding needs,
## and the game already draws that extent as a road on its own campaign chart.
## So the panel stops printing coordinates and draws the road.
##
## ONE OBJECT REPLACES TWO ROWS AND SAYS MORE THAN BOTH. Act and province are
## not two facts, they are one position stated in two units; splitting them
## across two ruled rows is what made a returning player do the arithmetic.
##
## MARCHED vs UNMARCHED is a second, redundant channel and it costs nothing —
## the road behind the standard is filled and lit, the road ahead is bare
## groove. Redundant preattentive encodings are located faster than either alone
## (Healey & Enns, IEEE TVCG 18(7), 2012), and it also means the figure survives
## being read at a glance, in peripheral vision, or by someone who cannot
## separate the accent hues.
##
## THE STANDARD IS THE ONLY SELF-LUMINOUS THING ON THE PLATE. That is built, not
## asserted: Zavagno & Caputo (Perception 30(2), 2001) showed a region reads as
## EMITTING rather than as merely pale when it is flanked by luminance ramps
## falling away from it, with self-luminosity appearing around 145% of the
## surrounding luminance. So the marker is not "drawn brighter" — it is drawn
## with a falloff AROUND it, which is a different instruction and the reason it
## reads as a lamp standing on a map rather than as a white dot.
##
## THE ROAD IS A CROSS-SECTION, NOT A LINE — see `ChannelBand` for the profile
## and for why a flat band cannot be fixed by stacking more flat bands.
##
## No `class_name`: preload under a same-name const like every painter here.
extends Control

const LayerStyle := preload("res://scripts/ui/painters/LayerStyle.gd")
const ChannelBand := preload("res://scripts/ui/painters/ChannelBand.gd")

## The plate this road is cut into. The shading is RELATIVE to it, so handing in
## the real plate colour is what keeps the groove looking cut rather than pasted.
var plate := Color(0.105, 0.082, 0.062)
## The metal the lit rim is struck from. Warm, never white — see ChannelBand.
var lit := Color(1.0, 0.88, 0.58)
## The marched road's own fill.
var marched := Color(0.74, 0.56, 0.26)
## The standard's colour — the one hot mark on the plate.
var standard := Color(1.0, 0.87, 0.47)

var acts := 3
var act := 1                  ## 1-based
var floor_row := 0            ## province within the act
var rows_per_act := 17        ## CampaignMapGenerator.BOSS_ROW

## Caption font, handed in rather than read off the GameTheme autoload: a painter
## that names an autoload is a hard compile error the moment a `--script` probe
## preloads it, and parsecheck runs as a SCENE so it cannot see that (CLAUDE.md,
## "parsecheck's ONE blind spot"). Null simply skips the captions.
var cap_font: Font = null
## 15, the CAPTION floor of COPY_STYLE §11 — not a number picked to fit.
##
## Worth stating because this text is drawn rather than set: `_probe_text_floor`
## reads font-size OVERRIDES off nodes, so a `draw_string` size is invisible to
## it exactly the way a `Control.scale` is (CLAUDE.md records that blind spot
## costing an 11.2px card face). A drawn caption has to hold the floor by hand.
var cap_size := 15

## 15, not the 9 this shipped with for one render.
##
## MEASURED: at 9 the whole cross-section — near wall, floor, far wall and lit
## rim — landed in ELEVEN image rows, of which the dark walls were three. The
## scanline read 0.036 / 0.086 / 0.122 / 0.323 / 0.629 and then stopped, so the
## groove was a hairline with a bright edge, i.e. exactly the flat band it was
## built to avoid, reached from the other direction. A SHAPE NEEDS AREA BEFORE IT
## CAN BE LIT — the StruckBracket lesson, and the same reason adopting PlateFrame
## widens a frame from 1px to 7. Widening this is the point, not a side effect.
const BAND_H := 15.0
const TERM_W := 18.0          ## room for the camp and keep marks at the ends


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func configure(a: int, fl: int, rows: int, total_acts: int = 3) -> void:
	act = maxi(a, 1)
	floor_row = maxi(fl, 0)
	rows_per_act = maxi(rows, 1)
	acts = maxi(total_acts, 1)
	queue_redraw()


## How far along the WHOLE run the army stands, 0..1.
func progress() -> float:
	var within := clampf(float(floor_row) / float(rows_per_act), 0.0, 1.0)
	return clampf((float(act - 1) + within) / float(acts), 0.0, 1.0)


func _band_rect() -> Rect2:
	var y := roundf(size.y * 0.30)
	return Rect2(TERM_W, y, maxf(size.x - TERM_W * 2.0, 8.0), BAND_H)


func _draw() -> void:
	if size.x < 60.0 or size.y < 24.0:
		return
	var band := _band_rect()

	# ── the road itself, cut into the plate ────────────────────────────────
	ChannelBand.draw_lip(self, band, plate, lit)
	ChannelBand.draw_channel(self, band, plate, lit)

	# ── act boundaries: milestone stones standing in the channel ───────────
	# Drawn BEFORE the marched fill so the fill buries the ones already passed,
	# which is the correct reading — a boundary behind you is not a boundary.
	for i in range(1, acts):
		var bx := band.position.x + band.size.x * (float(i) / float(acts))
		_draw_milestone(bx, band)

	# ── the marched road ───────────────────────────────────────────────────
	var p := progress()
	ChannelBand.draw_fill(self, band, p, marched, lit, 0.34)

	# ── terminals ──────────────────────────────────────────────────────────
	_draw_camp(Vector2(band.position.x - TERM_W * 0.52,
		band.position.y + band.size.y * 0.5))
	_draw_keep(Vector2(band.position.x + band.size.x + TERM_W * 0.52,
		band.position.y + band.size.y * 0.5), p >= 0.999)

	# ── the standard ───────────────────────────────────────────────────────
	var mx := band.position.x + band.size.x * p
	_draw_standard(Vector2(mx, band.position.y + band.size.y * 0.5))

	# ── act captions ───────────────────────────────────────────────────────
	if cap_font != null:
		_draw_act_captions(band)


## A boundary stone: a short dark post with a lit cap. Small, because it is a
## tick on a scale and not a landmark.
## A boundary stone standing in the channel: a short post with a lit cap. Small,
## because it is a tick on a scale and not a landmark.
##
## STONE, NOT A GAP. At `shade(-0.75)` and standing 3px proud either side these
## read as black NOTCHES cut through the road — the eye took them for breaks in
## the run rather than for marks on it, which is the opposite of what an act
## boundary means. A post is lighter than the trough it stands in.
func _draw_milestone(bx: float, band: Rect2) -> void:
	var w := 2.4
	draw_rect(Rect2(bx - w * 0.5, band.position.y + 1.0, w, band.size.y - 1.0),
		ChannelBand.shade(plate, lit, 0.16))
	draw_rect(Rect2(bx - w * 0.5, band.position.y + 1.0, w, 1.2),
		ChannelBand.shade(plate, lit, 0.52))
	draw_rect(Rect2(bx + w * 0.5 - 0.8, band.position.y + 1.0, 0.8,
		band.size.y - 1.0), ChannelBand.shade(plate, lit, -0.55))


## The camp the run started from: a low tent, lit on its left face.
func _draw_camp(c: Vector2) -> void:
	var r := 7.0
	var body := PackedVector2Array([
		c + Vector2(-r, r * 0.8), c + Vector2(0, -r), c + Vector2(r, r * 0.8)])
	# Canvas standing ON the plate, so it is LIGHTER than the plate — at -0.10 it
	# sank into the surface and the dark keyline round it was all that showed,
	# which reads as an outlined warning sign rather than as a tent.
	draw_colored_polygon(body, ChannelBand.shade(plate, lit, 0.16))
	# The lit face is the one turned toward the lamp (top-left).
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r, r * 0.8), c + Vector2(0, -r), c + Vector2(0, r * 0.8)]),
		ChannelBand.shade(plate, lit, 0.48))
	LayerStyle.stroke(self, body, ChannelBand.shade(plate, lit, -0.80), 1.0)


## The keep the run is marching on. `taken` lights it — the run is at the boss.
func _draw_keep(c: Vector2, taken: bool) -> void:
	var w := 6.2
	var h := 7.2
	var body := PackedVector2Array([
		c + Vector2(-w, h), c + Vector2(-w, -h * 0.45),
		c + Vector2(-w * 0.45, -h * 0.45), c + Vector2(-w * 0.45, -h),
		c + Vector2(w * 0.45, -h), c + Vector2(w * 0.45, -h * 0.45),
		c + Vector2(w, -h * 0.45), c + Vector2(w, h)])
	# Masonry standing on the plate: lighter than it, for the same reason the
	# camp is. `taken` pushes it to the lit end — the run is at the keep's gate.
	var base := ChannelBand.shade(plate, lit, 0.78 if taken else 0.20)
	draw_colored_polygon(body, base)
	LayerStyle.bevel(self, body, ChannelBand.shade(plate, lit, 0.60), 1.6, 0.9)
	LayerStyle.stroke(self, body, ChannelBand.shade(plate, lit, -0.80), 1.0)


## The army standard — a pennant on a staff, planted where the run stands.
##
## THE GLARE RAMP IS THE POINT (Zavagno & Caputo 2001): the falloff around the
## pennant is what makes it read as lit rather than as pale. `outer_glow` is the
## sanctioned funnel for it — concentric grown copies on a SQUARE alpha curve, so
## the falloff is fast near the shape and long in the tail; a linear ramp reads
## as a flat halo with an edge, which is what makes cheap glow look cheap.
func _draw_standard(c: Vector2) -> void:
	var staff_h := 19.0
	var top := c + Vector2(0, -staff_h)
	var pennant := PackedVector2Array([
		top, top + Vector2(12.0, 4.2), top + Vector2(0, 8.4)])

	LayerStyle.outer_glow(self, pennant, standard, 11.0, 0.26, 5)
	# The staff reads as a planted post: dark on the shadow side, lit on the
	# lamp side, which at 2px is two 1px rects rather than a bevel.
	draw_rect(Rect2(c.x - 1.0, top.y, 1.0, staff_h + 2.0),
		ChannelBand.shade(plate, lit, 0.30))
	draw_rect(Rect2(c.x, top.y, 1.0, staff_h + 2.0),
		ChannelBand.shade(plate, lit, -0.70))
	LayerStyle.fill_graded(self, pennant, standard, 0.30, 3)
	LayerStyle.stroke(self, pennant, standard.lerp(Color.BLACK, 0.55), 1.0)
	# The hot core: the smallest, brightest step, at the hoist where the cloth
	# catches the lamp square on.
	draw_circle(top + Vector2(1.2, 1.4), 1.5, standard.lerp(Color.WHITE, 0.55))


## "ACT I / II / III" centred under their own segments, the current one lit.
##
## The act is therefore stated TWICE — by which segment the standard stands in,
## and by which caption is lit — and that redundancy is deliberate rather than
## wasteful: it is the same figure in a positional and a symbolic channel, so
## the glance and the read agree.
func _draw_act_captions(band: Rect2) -> void:
	const NUM := ["I", "II", "III", "IV", "V"]
	var y := band.position.y + band.size.y + 15.0
	for i in range(acts):
		var seg_mid := band.position.x + band.size.x * ((float(i) + 0.5) / float(acts))
		# Annotated, not inferred: `NUM` is an untyped const Array, so `NUM[i]` is
		# a Variant and the ternary keeps it one, which makes the whole expression
		# Variant and `:=` a hard parse error (it took MainMenu down with it, since
		# that preloads this file).
		var txt: String = "ACT " + (NUM[i] if i < NUM.size() else str(i + 1))
		var w := cap_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
			cap_size).x
		var here := (i + 1) == act
		var col := standard if here else ChannelBand.shade(plate, lit, 0.10)
		if not here:
			col.a = 0.85
		draw_string(cap_font, Vector2(seg_mid - w * 0.5, y),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size, col)
