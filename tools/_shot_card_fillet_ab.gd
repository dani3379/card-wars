extends Control
## _shot_card_fillet_ab — the CARD art plate's fillet, flat rule vs molding.
##
## WHY A SECOND A/B TOOL RATHER THAN A CASE IN `_shot_frame_ab`. That one judges
## a frame on the shell's warm-black at 282x376. Every load-bearing fact about
## the card fillet is different, and each difference changes what has to be
## measured:
##
##   THE GROUND IS A BOUNDARY, NOT A PAGE. The fillet straddles the ink mat
##   (0.118, 0.096, 0.072) on its inner side and WritLeaf's parchment
##   (luminance ~0.81) on its outer. So the crest is NOT automatically a hole —
##   it sits mostly over the dark mat — but it becomes one the moment it passes
##   the paper. That is a number, printed below as CREST-PAPER: it must stay
##   NEGATIVE. The shell's oracle never had to ask.
##
##   THE SHADOWS ARE THE HARDER HALF. Four of PlateFrame's five layers are dark
##   (drop, mitre, seam, rebate, tack seat) and all five were authored near-black
##   for a near-black ground. On parchment a shadow is a warm BROWN, because the
##   light reaching it bounced off the page. DROP-CHROMA below reports the
##   saturation of the drop shadow where it falls on paper: a near-black drop
##   reads ~0.0 there and photographs as a grey smudge round the plate.
##
##   IT IS SMALL, AND IT GETS SMALLER. 209x133 against the shell's 282x376, and
##   MainMenu draws the whole card again at DECK_MINI_SCALE 0.62. A shape needs
##   AREA before it can be lit, so the mini pair exists to prove the molding does
##   not collapse back into the stroke it replaced. If INVERSION survives at 0.62
##   the swap is safe everywhere; if it does not, that is a real finding and not
##   a reason to abandon the pass — the full-size face is where the card is read.
##
## Samples render at TRUE card size. Measuring a scaled-up plate would answer a
## question nobody is asking.
##
## Run AFTER both edits land (PlateFrame's `shade`, Card2D's swap). It measures
## the painter directly, not Card2D, so it does not need the bake, the autoload
## warmers or a card_data dict — the same standalone-host approach
## `_shot_frame_ab` uses, and for the same reason: reading a profile through a
## real card confounds the frame with the cartouche and the rules band.

const OUT_DIR := "res://tools/screenshot"
const PlateFrame := preload("res://scripts/ui/painters/PlateFrame.gd")

## The fillet rect in `Card2D._build_chart_proto`: offsets 8,8 -> 217,141 inside
## a 225x300 card. Quoted, not rounded — the whole point is the real budget.
const PLATE := Vector2(209.0, 133.0)
## `WritLeaf.paper`. The leaf the card is cut from, and the ground the molding's
## outer shoulder and its entire drop shadow land on.
const PAPER := Color(0.871, 0.812, 0.694)
## The ink mat behind the art (`mat_st.bg_color`). The measured samples use it
## flat as the interior, for the reason `_shot_frame_ab` records: a profile read
## through a painting is measuring the painting.
const MAT := Color(0.118, 0.096, 0.072)
## MainMenu's deck-strip scale.
const MINI := 0.62

var _rects: Dictionary = {}     # tag -> Rect2 (CANVAS space)
## tag -> the molding width in CANVAS px. `_report` needs it to know where the
## metal ends and the page begins; without it every metric reads the parchment.
var _widths: Dictionary = {}
var _px := 1.0                  # framebuffer px per canvas px, MEASURED


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	size = Vector2(1600, 900)

	# The PAGE, not a neutral backdrop. Every sample sits on it with a wide
	# margin so the drop and the seam fall on paper and can be measured there.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = PAPER
	add_child(bg)

	# Common aged bronze — the middle of the five rarity alloys, so it flatters
	# neither the brightest (rare gold) nor the darkest (starter pewter).
	var metal := Color(0.62, 0.45, 0.25, 0.95)
	var opts := _card_opts()

	# ── measured pairs, flat ink interior ──
	_old_sample("old", Vector2(90, 90), PLATE, metal)
	_new_sample("new", Vector2(420, 90), PLATE, metal, opts)

	# ── the mini: does a 4px molding survive DECK_MINI_SCALE? ──
	_old_sample("old_mini", Vector2(90, 300), PLATE, metal, null, MINI)
	_new_sample("new_mini", Vector2(420, 300), PLATE, metal, opts, null, MINI)

	# ── eyes only: the same plates over real art ──
	var art := _find_art()
	_old_sample("old_art", Vector2(860, 90), PLATE, metal, art)
	_new_sample("new_art", Vector2(1190, 90), PLATE, metal, opts, art)

	# ── eyes only: all five rarity alloys through the molding. `alloy_mix` at
	# the shell's 0.78 pulls every one of these toward a single bronze, which
	# would flatten a gameplay cue. This strip is how that is caught.
	var alloys := [
		["rare", Color(0.97, 0.75, 0.22, 0.95)],
		["uncommon", Color(0.64, 0.76, 0.90, 0.95)],
		["common", Color(0.62, 0.45, 0.25, 0.95)],
		["starter", Color(0.47, 0.46, 0.44, 0.95)],
		["curse", Color(0.55, 0.52, 0.45, 0.95)]]
	for i in range(alloys.size()):
		_new_sample("alloy_%s" % alloys[i][0],
			Vector2(90 + i * 300, 560), Vector2(280.0, 120.0),
			alloys[i][1], opts, art)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/_card_fillet_ab.png" % OUT_DIR)
	print("SAVED _card_fillet_ab.png ", img.get_size())

	# THE FRAMEBUFFER IS NOT THE CANVAS — derive the ratio, never assume it.
	# `_shot_frame_ab`'s first run was voided by exactly this (asked for 1600x900,
	# got a 1920x1080 texture, every sample landed 20% off and the molding
	# measured identical to the flat rule).
	_px = float(img.get_width()) / maxf(size.x, 1.0)
	print("canvas=", size, "  framebuffer=", img.get_size(), "  scale=%.3f" % _px)
	print("paper luminance (const) = %.3f" % PAPER.get_luminance())
	for tag in ["old", "new", "old_mini", "new_mini"]:
		_report(img, tag)
	for tag in ["old", "new", "old_mini", "new_mini", "old_art", "new_art"]:
		_zoom(img, tag)
	get_tree().quit()


## READ FROM THE CARD, NEVER RESTATED HERE (2026-09-18).
##
## This function used to hold its own copy of the fillet's parameters. That makes
## the tool certify a frame the game may no longer draw — and this whole pass
## exists because `PlateFrame` was adopted by its own A/B harness and never by
## the actual screen, with nothing noticing for a day. So the numbers live at the
## call site (`Card2D.chart_fillet_cfg`) and the oracle asks for them.
##
## Loaded at RUNTIME rather than `preload`ed: naming `Card2D` at parse time drags
## that script into an early compile, which is the documented way a probe turns
## its own subject into a scriptless stand-in and then reports green.
func _card_opts() -> Dictionary:
	var c2d := load("res://scripts/Card2D.gd") as GDScript
	if c2d != null and c2d.has_method("chart_fillet_cfg"):
		return c2d.chart_fillet_cfg()
	push_error("_shot_card_fillet_ab: Card2D.chart_fillet_cfg() missing — "
		+ "falling back to a LOCAL COPY, so these numbers may not be the ship's.")
	return {
		# A molding needs AREA. 4px eats ~1px of the art edge, which is what a
		# rebate IS — that overlap is the frame holding the painting, not a bug.
		"rule_w": 4.0,
		# >= 7 or PlateFrame hides the tacks, and the tacks are the four plate
		# marks this swap is meant to absorb. Forcing the chamfer is what makes
		# the mitre patch load-bearing, hence `shade` below.
		"chamfer": 8.0,
		# 5 not 7: at 4px wide, 7 steps quantise onto the same pixels.
		"steps": 5,
		"rebate": 2.5,
		"drop": 1.2,
		# The shell's 1.1 is 27% of a 4px width — that reads as a wavy stripe.
		"wobble": 0.45,
		"body_drop": 0.52,
		"lit_gain": 0.50,
		# 0.78 would pull rare gold, silver-blue, pewter and bone into one
		# bronze. The card's metals are already deliberate, separated alloys.
		"alloy_mix": 0.12,
		# The card is lit by a warm candle; the specular is the LIGHT's colour.
		"lit": Color(1.0, 0.93, 0.78),
		# Warm sepia, not near-black: the shadow half of the ground inversion.
		"shade": Color(0.105, 0.072, 0.042),
	}


# ── samples ────────────────────────────────────────────────────────────────

func _body(at: Vector2, sz: Vector2, art: Texture2D, scale_by: float) -> Control:
	var host := Control.new()
	host.position = at
	host.size = sz
	host.custom_minimum_size = sz
	host.scale = Vector2(scale_by, scale_by)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	# The ink mat, exactly as Card2D layers it: mat inset 1px inside the fillet
	# rect, art clipped 3px inside that.
	var mat := ColorRect.new()
	mat.set_anchors_preset(Control.PRESET_FULL_RECT)
	mat.offset_left = 1; mat.offset_top = 1
	mat.offset_right = -1; mat.offset_bottom = -1
	mat.color = MAT
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(mat)
	if art != null:
		var clip := Control.new()
		clip.set_anchors_preset(Control.PRESET_FULL_RECT)
		clip.offset_left = 3; clip.offset_top = 3
		clip.offset_right = -3; clip.offset_bottom = -3
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(clip)
		var t := TextureRect.new()
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.texture = art
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(t)
	return host


## The fillet exactly as it ships today: `Card2D._build_chart_proto`'s
## `StyleBoxFlat` with `draw_center = false` and a 1px border, plus the four
## 5x5 plate marks. Quoted from the live call site, not approximated.
func _old_sample(tag: String, at: Vector2, sz: Vector2, metal: Color,
		art: Texture2D = null, scale_by: float = 1.0) -> void:
	var host := _body(at, sz, art, scale_by)
	var edge := Panel.new()
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fst := StyleBoxFlat.new()
	fst.draw_center = false
	fst.border_color = Color(metal.r, metal.g, metal.b, 0.78)
	fst.set_border_width_all(1)
	edge.add_theme_stylebox_override("panel", fst)
	host.add_child(edge)
	for pm in [Vector2(0, 0), Vector2(sz.x, 0), Vector2(0, sz.y), sz]:
		var mark := Panel.new()
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mst := StyleBoxFlat.new()
		mst.bg_color = Color(metal.r, metal.g, metal.b, 1.0)
		mst.border_color = Color(0.10, 0.08, 0.05, 0.9)
		mst.set_border_width_all(1)
		mark.add_theme_stylebox_override("panel", mst)
		mark.position = (pm as Vector2) - Vector2(2.5, 2.5)
		mark.size = Vector2(5, 5)
		host.add_child(mark)
	_rects[tag] = Rect2(at, sz * scale_by)
	_widths[tag] = 1.0 * scale_by


func _new_sample(tag: String, at: Vector2, sz: Vector2, metal: Color,
		opts: Dictionary, art: Texture2D = null, scale_by: float = 1.0) -> void:
	var host := _body(at, sz, art, scale_by)
	PlateFrame.over(host, metal, opts)
	_rects[tag] = Rect2(at, sz * scale_by)
	_widths[tag] = float(opts.get("rule_w", 6.0)) * scale_by


func _find_art() -> Texture2D:
	var dir := DirAccess.open("res://assets/creatures")
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".png"):
				return load("res://assets/creatures/%s" % f)
	return null


# ── the oracle ─────────────────────────────────────────────────────────────

func _sample(img: Image, x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return Color(0, 0, 0, 1)
	return img.get_pixel(x, y)


## Luminance profile crossing a run of the frame, outer -> inner.
func _profile(img: Image, x: int, y0: int, dir: int, n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append(_sample(img, x, y0 + dir * i).get_luminance())
	return out


## THREE METRICS WERE MEASURING THE PAGE, NOT THE FRAME — corrected 2026-09-18 on
## this tool's FIRST EVER RUN (it was written on 2026-09-17 from a worktree that
## could not execute it, and its own handoff said so). Every fix here is the same
## root cause: the profile opens 4px OUTSIDE the plate, so its leading samples are
## parchment, and parchment at luminance 0.816 is brighter than any part of a
## frame that is allowed to sit under it. Left alone, each metric latched onto the
## page:
##
##   * `peak`/`CREST-PAPER` took the max over the WHOLE profile, so on the flat
##     arm it returned the paper itself and printed a perfectly clean
##     `CREST-PAPER=+0.000` — a number about the page, not about the rule.
##   * `INVERSION` compared the two runs over that same lead. A 1px flat rule
##     whose edge lands one sample later on the bottom run scored **0.450**,
##     beating the molding's 0.392 — pure sub-pixel PHASE read as a light
##     inversion. The metric's own docstring predicts ~0.03 for a flat stroke,
##     which is what it measures on a DARK ground where no such step exists.
##   * `DROP-CHROMA` sampled diagonally off the CHAMFERED corner, where a cut
##     corner means there is no drop to find; it returned 0.203 for three of the
##     four arms, which is exactly bare parchment's own saturation
##     ((0.871-0.694)/0.871). A constant is not a measurement.
##
## All three now measure inside the metal, which is the only place the claims
## being tested live.
func _report(img: Image, tag: String) -> void:
	var r: Rect2 = _rects[tag]
	var w: float = _widths.get(tag, 1.0)
	var x := int((r.position.x + r.size.x * 0.5) * _px)
	var span := int(round(15.0 * _px))
	var lead := int(round(4.0 * _px))
	var top := _profile(img, x, int(r.position.y * _px) - lead, 1, span)
	var bot := _profile(img, x, int(r.end.y * _px) + lead, -1, span)

	# Paper well clear of the plate, MEASURED rather than taken from the const —
	# it is the thing the crest must not out-shine, and the thing the metal
	# window has to exclude.
	var paper := _sample(img, x, int((r.position.y - 26.0) * _px)).get_luminance()

	# THE WINDOW HOLDING THE METAL. One sample of slack on the OUTER side,
	# because a polyline is centred on its path and therefore straddles the
	# plate's own edge — measured, the molding's outermost band lands on
	# samples 4.7..5.9 where the geometry alone would say 5. Any sample that is
	# still PAPER is then dropped, which is what keeps that slack from handing
	# the flat arm the page as its crest.
	var m0 := maxi(lead - 1, 0)
	var m1 := mini(lead + int(ceil(w * _px)) + 1, span - 1)
	var idx: Array[int] = []
	for i in range(m0, m1 + 1):
		if absf(float(top[i]) - paper) > 0.04:
			idx.append(i)
	if idx.is_empty():
		idx.append(lead)

	var levels: Dictionary = {}
	for i in idx:
		levels[snappedf(float(top[i]), 0.02)] = true

	# ── THE CONGRUENCE FIGURE ──────────────────────────────────────────────────
	#
	# `max |top - bottom|` WAS THE METRIC AND IT CANNOT BE (2026-09-18). It is
	# sub-pixel PHASE sensitive: the flat 1px rule rasterises as ONE bright
	# sample on the top run and TWO on the bottom, so it scored **0.450** —
	# beating the real molding's 0.150 — on a frame that has no lighting model
	# in it at all. A gate carrying that number would certify the defect.
	#
	# What the molding actually claims (Anderson & Kim 2009) is that the
	# highlight MOVES ACROSS the width between opposite runs: outer shoulder on
	# the lit run, inner shoulder on the shadowed one. So measure WHERE the
	# metal's brightness sits, as a centroid over the window with the darkest
	# sample subtracted off as baseline, and report how far that centre travels.
	# A centroid is immune to a half-pixel shift — both runs move together — and
	# it is a direct reading of the claim rather than a proxy for it.
	var ct := _centroid(top, idx)
	var cb := _centroid(bot, idx)
	var shift := absf(ct - cb)
	var asym := 0.0
	for i in idx:
		asym = maxf(asym, absf(float(top[i]) - float(bot[i])))

	var peak := 0.0
	for i in idx:
		peak = maxf(peak, float(top[i]))
	# The drop falls just outside the BOTTOM run, under the lamp — sampled at
	# mid-span, never at a corner the chamfer has cut away.
	var drop_px := _sample(img, x, int((r.end.y + 1.5) * _px))

	print("── ", tag)
	print("   top    ", _fmt(top))
	print("   bottom ", _fmt(bot))
	print("   metal samples %s" % str(idx))
	print("   plateaus=%d  crest=%.3f  CREST-SHIFT=%.2f samples  (raw max|d|=%.3f, phase-prone)" % [
		levels.size(), peak, shift, asym])
	print("   paper=%.3f  CREST-PAPER=%+.3f (must stay NEGATIVE)  " % [
		paper, peak - paper] + "DROP-CHROMA=%.3f (paper itself = %.3f)" % [
		drop_px.s, PAPER.s])


## Where the metal's brightness sits across the window, in samples from its
## start. The darkest sample in the window is subtracted as baseline so the mat
## behind the frame contributes no mass.
func _centroid(prof: Array, idx: Array[int]) -> float:
	var lo := 1.0
	for i in idx:
		lo = minf(lo, float(prof[i]))
	var num := 0.0
	var den := 0.0
	for k in range(idx.size()):
		var wgt: float = maxf(float(prof[idx[k]]) - lo, 0.0)
		num += float(k) * wgt
		den += wgt
	return num / den if den > 0.0001 else 0.0


func _fmt(a: Array) -> String:
	var s := ""
	for v in a:
		s += "%.2f " % float(v)
	return s


func _peak(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m


## Zoom crops are NEAREST and 8-12x. A 4px molding's values are not decidable
## at 1:1 — that is the house rule, and at this size it is not close.
func _zoom(img: Image, tag: String) -> void:
	var r: Rect2 = _rects[tag]
	var z := 14.0 if tag.ends_with("_mini") else 9.0
	# Top-left: a run of the top molding, a run of the left, the chamfer between
	# them and a corner tack — the four things the plate marks used to be.
	_crop(img, tag + "_corner", r.position + Vector2(16, 13),
		Vector2(52, 42), z)
	# A span of the BOTTOM run at the same scale. The half of the claim a single
	# corner shot cannot show, because the inversion needs both shoulders.
	_crop(img, tag + "_bottom",
		Vector2(r.position.x + r.size.x * 0.5, r.end.y - 5),
		Vector2(52, 26), z)


func _crop(img: Image, tag: String, center: Vector2, sz: Vector2,
		zoom: float) -> void:
	var full := Rect2i(Vector2i.ZERO, img.get_size())
	var rr := Rect2i(Vector2i(((center - sz * 0.5) * _px).round()),
		Vector2i((sz * _px).round())).intersection(full)
	if rr.size.x < 4 or rr.size.y < 4:
		return
	var sub := img.get_region(rr)
	sub.resize(int(rr.size.x * zoom), int(rr.size.y * zoom),
		Image.INTERPOLATE_NEAREST)
	sub.save_png("%s/_card_fillet_%s.png" % [OUT_DIR, tag])
	print("SAVED _card_fillet_", tag, " ", sub.get_size())
