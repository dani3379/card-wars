extends Control
## _probe_frame_molding — THE GATE under `PlateFrame`, the shell's frames and the
## card's art fillet (2026-09-18).
##
## WHY THIS EXISTS, and it is not a hypothetical. `PlateFrame` shipped on
## 2026-09-17 with an A/B harness that measured it and a header claiming RUN
## SETUP's hero plate as a first consumer. The harness was a SHOT TOOL — it
## printed numbers and never failed — and the hero plate it named was a different
## screen's. So the biggest frame in the game kept the flat 2px rule the file was
## written to delete, the recorded "before/after" table described a synthetic
## sample nobody could see, and nothing anywhere went red. It took a player
## saying "the lines are kind of weird" to find it, a day later.
##
## A number nobody fails on is not a gate.
##
## IT GATES THE CLAIMS, NOT THE TABLE. Pinning measured values would just get
## re-blessed on every tuning pass and stop meaning anything (the golden-master
## lesson, C25). Every assertion below is a PROPERTY the molding either has or
## does not, with the threshold set where a flat stroke provably sits — each one
## is annotated with the flat rule's own measured score so the margin is visible.
##
## WINDOWED. It measures the framebuffer, so it cannot run --headless; it belongs
## in `tools/run_ui_gates.ps1` beside the other pixel gates, not in
## `run_safe_probes.ps1`.

const PlateFrame := preload("res://scripts/ui/painters/PlateFrame.gd")

## `WritLeaf.paper` — the card's ground, and the value a crest must stay under.
const PAPER := Color(0.871, 0.812, 0.694)
## The ink mat behind a card's art.
const MAT := Color(0.118, 0.096, 0.072)
## The shell's warm-black page.
const GROUND := Color(0.118, 0.094, 0.074)
## A flat mid-dark interior for shell samples — a frame read against pure black
## exaggerates every value it has.
const INTERIOR := Color(0.20, 0.17, 0.14)
## MainMenu's deck-strip scale. The molding must survive it.
const MINI := 0.62
## Check 10's two thresholds, set where the DEFECT provably sits rather than
## just under what today's tuning scores — pinning the latter is the
## golden-master trap this file's header warns about. Measured 2026-09-18:
##
##   collapsed (the control arm)      0.1 deg   OKLab 0.0002
##   shipped, these samples          29.1 deg   OKLab 0.0107
##   shipped, IN SITU on the roster  27.6 deg   OKLab 0.0146
##
## So both thresholds sit ~200x and ~30x above the collapse, with ~45% headroom
## under the shipped figure — room for the metals to be retuned without
## re-blessing, and none at all for them to fall back together. For reference,
## re-raising `FACTION_ALLOY_MIX` to the shell default of 0.78 would land near
## the control arm; 0.60 lands near 16 deg and fails.
const FAC_SPREAD_MIN := 20.0
const FAC_OKLAB_MIN := 0.006
## Check 9's two thresholds, with a guard band either side of the numbers that
## check prints on EVERY run rather than only on failure.
##
## MEASURED, both sides flat-shimmer and byte-identical across three runs:
## chamfer arm **1.100**, mitre portrait **1.000**, mitre tile **1.017** — an
## 8.3pp gap with nothing in it. The thresholds sit ~0.02-0.03 either side, which
## is guard band against a future retune of `lit_gain` or `hot_shift` moving both
## modes together, not against run-to-run noise: there is none left.
##
## NARROWER HERE THAN ON THE LIVE SCREEN, where the same ratio read 1.47x
## chamfered. That difference is not the silhouette — it is the tack's specular
## dot plus `Sheen.plinth`/`sheen` piling onto the corner, none of which these
## bare samples carry. The geometry alone is worth ~10%, and that is the honest
## figure for what this check can see.
const CORNER_ARM_MIN := 1.07
const CORNER_MITRE_MAX := 1.04
## How many points along a run check 10 averages the moulding over.
const CREST_SAMPLES := 12

var _rects: Dictionary = {}
var _widths: Dictionary = {}
var _px := 1.0
var _fails: Array[String] = []
var _checks := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	size = Vector2(1600, 900)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = GROUND
	add_child(bg)

	# ── the CARD fillet, on the card's own two grounds ─────────────────────────
	#
	# READ FROM THE CALL SITE. A gate holding its own copy of the parameters
	# certifies a frame the game may not draw — which is the precise failure this
	# file exists to prevent, so it must not commit it itself.
	var card_cfg := _card_cfg()
	var card_metal := Color(0.62, 0.45, 0.25, 0.95)
	_card_sample("card", Vector2(70, 70), Vector2(209, 133), card_metal, card_cfg)
	_card_sample("card_mini", Vector2(70, 250), Vector2(209, 133), card_metal,
		card_cfg, MINI)
	# The flat rule this replaced, as the CONTROL ARM. Every threshold below is
	# stated against what this scores, so the gate can show its own margin.
	_flat_card_sample("card_flat", Vector2(70, 400), Vector2(209, 133), card_metal)

	# ── the SHELL frames, on the shell's page ─────────────────────────────────
	#
	# MITRED, because that is what the screen draws (2026-09-18). Leaving these on
	# `chamfer` after the call sites moved would have re-committed this file's own
	# founding defect in miniature: a gate certifying a frame nobody can see.
	_shell_sample("portrait", Vector2(420, 70), Vector2(282, 376),
		Color(0.78, 0.36, 0.22), {"corner": "mitre", "rule_w": 6.0, "rebate": 3.0,
			"drop": 1.8, "shimmer": 0.40})
	_shell_sample("tile", Vector2(760, 70), Vector2(211, 140),
		Color(0.52, 0.44, 0.31, 0.82), {"corner": "mitre", "rule_w": 4.2,
			"rebate": 2.2, "drop": 1.6, "lit_gain": 0.62, "shimmer": 0.30})
	# THE CONTROL ARM for check 9: the same frame as `tile`, still chamfered. It
	# is what `PlaqueStyle`'s buttons still draw, and it is the arm that makes the
	# corner-brightness threshold a measurement rather than a guess.
	#
	# `shimmer` 0 ON THE ARM, and only on the arm. It is here to prove the check
	# below discriminates a CUT silhouette from a MITRED one — a claim about
	# geometry — and `_glint` is seeded off the node's instance id, so leaving the
	# lamp texture on made the arm's own ratio a coin flip (measured 1.22x and
	# 1.01x on consecutive runs of identical code). A control arm carrying a
	# random variable is not a control. The mitre samples above keep the shipped
	# shimmer, because those must be measured exactly as the screen draws them.
	_shell_sample("tile_chamfer", Vector2(1040, 70), Vector2(211, 140),
		Color(0.52, 0.44, 0.31, 0.82), {"rule_w": 4.2, "chamfer": 9.0,
			"rebate": 2.2, "drop": 1.6, "lit_gain": 0.62, "shimmer": 0.0})
	# ...AND THE MITRED SIDE OF CHECK 9 IS MEASURED THE SAME WAY, for the same
	# reason. The claim being gated is about the SILHOUETTE. Measuring one side
	# with a seeded lamp texture and the other without is not a comparison: the
	# glint moves the run's peak, i.e. the DENOMINATOR, so the shipped-shimmer
	# samples scored 0.935 / 0.953 / 1.002 on three runs of identical code and
	# straddled any threshold narrow enough to be worth setting. With both sides
	# flat the two modes separate deterministically, ~1.00 against the arm's
	# ~1.10. The shipped shimmer is still gated — by checks 1, 2 and 6 on the
	# `portrait` and `tile` samples above, which ARE drawn as the screen draws.
	_shell_sample("portrait_flat", Vector2(420, 470), Vector2(282, 140),
		Color(0.78, 0.36, 0.22), {"corner": "mitre", "rule_w": 6.0, "rebate": 3.0,
			"drop": 1.8, "shimmer": 0.0})
	_shell_sample("tile_flat", Vector2(760, 470), Vector2(211, 140),
		Color(0.52, 0.44, 0.31, 0.82), {"corner": "mitre", "rule_w": 4.2,
			"rebate": 2.2, "drop": 1.6, "lit_gain": 0.62, "shimmer": 0.0})

	# ── the five card alloys, for the rarity-separation check ─────────────────
	var alloys := {
		"rare": Color(0.97, 0.75, 0.22, 0.95),
		"uncommon": Color(0.64, 0.76, 0.90, 0.95),
		"common": Color(0.62, 0.45, 0.25, 0.95),
		"starter": Color(0.47, 0.46, 0.44, 0.95),
		"curse": Color(0.55, 0.52, 0.45, 0.95)}
	var ax := 70.0
	for k in alloys:
		_card_sample("alloy_%s" % k, Vector2(ax, 620), Vector2(200, 110),
			alloys[k], card_cfg)
		ax += 230.0

	# ── the five FACTION frames, for the shell-side separation check ─────────
	#
	# READ FROM THE CALL SITE, the same rule the card fillet above follows: the
	# metals and the mix come out of `MainMenu.faction_frame_cfg`, so this cannot
	# certify frames the screen does not draw. The opts are RUN SETUP's portrait
	# plate — the biggest frame in the game, and the one the collapse was
	# measured on.
	var mm := load("res://scripts/scenes/MainMenu.gd") as GDScript
	if mm == null or not mm.has_method("faction_frame_cfg"):
		push_error("_probe_frame_molding: MainMenu.faction_frame_cfg() missing")
	var fac_keys: Array = []
	var fy := 90.0
	for fid in HeroDB.FACTIONS:
		var fcfg: Dictionary = mm.faction_frame_cfg(fid)
		# `shimmer` 0, and it is the difference between measuring the METAL and
		# measuring the LAMP. At 0.40 the per-node seed moves each frame's crest
		# independently, and the first run proved how badly: the control arm below
		# -- two colours 0.002 apart per channel -- came out 0.0658 apart in OKLab,
		# four times the separation of five genuinely different metals. Check 7
		# survives the same texture because HUE barely moves under a luminance
		# perturbation; an OKLab distance carries lightness and eats it whole.
		# Metal and mix still come from the call site, which is what check 11 holds.
		_shell_sample("faction_%s" % fid, Vector2(1300, fy), Vector2(160, 50),
			fcfg["metal"], {"corner": "mitre", "rule_w": 6.0, "rebate": 3.0,
				"drop": 1.8, "shimmer": 0.0, "tacks": false,
				"alloy_mix": fcfg["alloy_mix"]})
		fac_keys.append(fid)
		fy += 100.0

	# THE CONTROL ARM for check 10, and it is what makes those thresholds a
	# measurement rather than a taste. These two are the SHIPPED-BEFORE pair —
	# `last_wall` and `lanternhall` through `_faction_accent` at the old
	# `alloy_mix` 0.78, the configuration that rendered them 1.2 degrees apart.
	#
	# THE COLOURS ARE FROZEN ON PURPOSE. A before-state that tracks the live code
	# is not a control: if `_faction_accent` is retuned tomorrow this arm has to
	# keep measuring the collapse the thresholds were set against.
	var old_opts := {"corner": "mitre", "rule_w": 6.0, "rebate": 3.0,
		"drop": 1.8, "shimmer": 0.0, "tacks": false, "alloy_mix": 0.78}
	_shell_sample("was_last_wall", Vector2(1300, 590), Vector2(160, 50),
		Color(0.849, 0.799, 0.666), old_opts)
	_shell_sample("was_lanternhall", Vector2(1300, 690), Vector2(160, 50),
		Color(0.851, 0.800, 0.653), old_opts)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	# THE FRAMEBUFFER IS NOT THE CANVAS — derive, never assume. `_shot_frame_ab`'s
	# first run was voided by exactly this.
	_px = float(img.get_width()) / maxf(size.x, 1.0)

	_run_checks(img, alloys.keys(), fac_keys)

	print("[frame_molding] %d checks" % _checks)
	if _fails.is_empty():
		print("PROBE PASS: frame_molding")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("PROBE FAIL: frame_molding (%d failures)" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


# ── assertions ─────────────────────────────────────────────────────────────

func _run_checks(img: Image, alloy_keys: Array, fac_keys: Array) -> void:
	var flat := _measure(img, "card_flat")
	var card := _measure(img, "card")
	var mini := _measure(img, "card_mini")
	var portrait := _measure(img, "portrait")
	var tile := _measure(img, "tile")

	# 1. A MOLDING HAS A CROSS-SECTION. A stroke is one value across its width;
	#    the flat control measures 2 distinct levels, so 4 is a real margin.
	for pair in [["card", card], ["card_mini", mini], ["portrait", portrait],
			["tile", tile]]:
		_ok(pair[0] + ": cross-section (plateaus >= 4, flat control = %d)" % flat.plateaus,
			int(pair[1].plateaus) >= 4, "got %d" % int(pair[1].plateaus))

	# 2. THE HIGHLIGHT TRAVERSES THE WIDTH between opposite runs — the congruence
	#    claim (Anderson & Kim 2009). Measured as a centroid shift, which is
	#    immune to the sub-pixel edge PHASE that makes a raw max|top-bottom|
	#    score the flat rule at 0.45. Flat control measures ~0.5 samples.
	for pair in [["card", card], ["portrait", portrait], ["tile", tile]]:
		_ok(pair[0] + ": highlight traverses (CREST-SHIFT >= 1.0, flat = %.2f)" % flat.shift,
			float(pair[1].shift) >= 1.0, "got %.2f" % float(pair[1].shift))

	# 3. IT SURVIVES THE DECK MINI. A shape needs AREA before it can be lit, and
	#    MainMenu draws the whole card again at 0.62. This is the check that says
	#    the molding did not collapse back into the stroke it replaced.
	_ok("card_mini: still a molding at DECK_MINI_SCALE %.2f (CREST-SHIFT >= 0.8)" % MINI,
		float(mini.shift) >= 0.8, "got %.2f" % float(mini.shift))

	# 4. THE CREST NEVER OUT-SHINES PARCHMENT. On the card the outer shoulder
	#    lands on paper at luminance ~0.82; a crest above it punches a hole in
	#    the page rather than sitting on it.
	for pair in [["card", card], ["card_mini", mini]]:
		_ok(pair[0] + ": crest under paper (CREST-PAPER < 0)",
			float(pair[1].crest) < float(pair[1].paper),
			"crest %.3f vs paper %.3f" % [float(pair[1].crest), float(pair[1].paper)])

	# 5. A SHADOW ON PARCHMENT IS WARM. Every dark layer in PlateFrame was
	#    authored near-black for a near-black page; on paper that reads as a grey
	#    smudge. If `shade` ever reverts, this drops to the paper's own
	#    saturation (0.203) — a constant, which is the tell.
	_ok("card: drop shadow is chromatic on paper (> paper's own %.3f)" % PAPER.s,
		float(card.drop_s) > PAPER.s + 0.04,
		"got %.3f" % float(card.drop_s))

	# 6. THE FRAME IS STRAIGHT. Silhouette position is hyperacute (vernier
	#    thresholds run 2-5 arcsec), so a "hand-cut" wobble on cast metal reads
	#    as a warped length of material — measured at SIX pixels of sag across a
	#    300px run on the shipped hero plate, which is what a player called
	#    "the lines are kind of weird".
	for tag in ["portrait", "tile", "card"]:
		var sag := _sag(img, tag)
		_ok(tag + ": run is straight (sag <= 1px)", sag <= 1,
			"sag %dpx" % sag)

	# 7. THE FIVE RARITY ALLOYS STAY SEPARATED. `alloy_mix` pulls the caller's
	#    colour toward one metal, and at the shell's 0.78 it flattens everything
	#    handed to it — MEASURED on RUN SETUP the same week, three heroes' frames
	#    came out inside a 2.5 degree hue spread. On a card the fillet is one of
	#    the cues carrying RARITY, so that collapse would delete a gameplay
	#    signal. Compares the two ends of the pool, which is where it shows.
	var hues: Dictionary = {}
	for k in alloy_keys:
		hues[k] = _crest_hue(img, "alloy_%s" % k)
	var spread: float = _hue_gap(float(hues["rare"]), float(hues["uncommon"]))
	_ok("rarity alloys stay distinct (rare vs uncommon hue gap >= 15 deg)",
		spread >= 15.0,
		"gap %.1f deg (rare %.1f, uncommon %.1f)" % [
			spread, float(hues["rare"]), float(hues["uncommon"])])

	# 9. A PICTURE FRAME'S CORNER IS NOT ITS BRIGHTEST POINT (2026-09-18).
	#
	#    `PlateFrame` got the CROSS-SECTION right in one pass and kept the wrong
	#    SILHOUETTE for a day: a chamfered octagon, which is a token and not a
	#    frame. That is not a soft defect — a chamfer's outward normal sits at 45
	#    degrees and `LayerStyle.LIGHT_A` IS 45 degrees, so the cut corner is the
	#    one place on the whole frame facing the lamp DEAD ON and takes peak
	#    diffuse and peak specular together. Four bright diagonal dashes per
	#    frame, sixteen frames on RUN SETUP, and the eye reached every one of them
	#    before it reached a picture.
	#
	#    Measured on the shipped screen: 1.47x on the hero plate, 1.24x on a
	#    roster thumbnail, 1.18x on a deck tile. Mitred they run 0.83-1.01x. The
	#    chamfered control arm beside these samples is what keeps the threshold
	#    honest — if the ratio ever stops separating the two modes, the number
	#    below is measuring noise rather than a silhouette.
	var cham_ratio := _corner_ratio(img, "tile_chamfer")
	var mit_p := _corner_ratio(img, "portrait_flat")
	var mit_t := _corner_ratio(img, "tile_flat")
	# PRINTED EVERY RUN, like the faction spread above. A threshold whose margin
	# is only visible on failure is a threshold nobody can check is still real.
	print("[frame_molding] corner/run — chamfer arm %.3f | mitre portrait %.3f, tile %.3f"
		% [cham_ratio, mit_p, mit_t])
	_ok("chamfer control arm still lights its cut corner (>= %.2f)" % CORNER_ARM_MIN,
		cham_ratio >= CORNER_ARM_MIN,
		"got %.3fx — threshold below is not discriminating" % cham_ratio)
	for pair in [["portrait", mit_p], ["tile", mit_t]]:
		_ok(pair[0] + ": mitred corner is not the brightest part (<= %.2f, chamfer arm = %.3f)"
			% [CORNER_MITRE_MAX, cham_ratio], float(pair[1]) <= CORNER_MITRE_MAX,
			"got %.3fx" % float(pair[1]))

	# 10. THE FIVE KINGDOMS ARE FIVE COLOURS (2026-09-18).
	#
	#    Check 7 above gates the CARD's five alloys, and notes in passing that the
	#    shell's had collapsed — "MEASURED on RUN SETUP the same week, three
	#    heroes' frames came out inside a 2.5 degree hue spread" — and then gates
	#    only the card. So the note was true, recorded, and load-bearing on
	#    nothing. Pushed through the real chain, the full five measured a 3.9
	#    DEGREE spread: a teal, a slate blue, an olive, a stone grey and an ember
	#    rendering as one colour. A defect written into a gate's comment and not
	#    asserted is a defect with a bookmark in it.
	#
	#    TWO MEASURES, because hue alone cannot carry this one. `last_wall` is iron
	#    and `owed` is bronze: plainly different objects that sit close in HUE and
	#    separate by CHROMA — and a near-neutral's hue is numerically unstable in a
	#    framebuffer anyway. Hue spread catches the global collapse; the OKLab
	#    minimum catches a partial one, where four fall together and a single
	#    outlier keeps the spread looking healthy.
	#
	#    CONFIRMED IN SITU, which is the measurement that actually counts: sampled
	#    off `_runstart_setup_hero_acolyte.png`, the five roster frames on the
	#    shipped screen read olive 52.5 / stone 39.5 / bronze 35.6 / gold 41.1 /
	#    ember 24.9, a 27.6 degree spread at OKLab 0.0146. These samples are a
	#    proxy for that screen and score 29.1 / 0.0107 — close enough that the
	#    proxy is honest, and the roster is what a player looks at.
	var fac_hue: Array[float] = []
	var fac_col: Array[Color] = []
	for fid in fac_keys:
		var fc := _metal_mean(img, "faction_%s" % fid, CREST_SAMPLES)
		fac_hue.append(fc.h * 360.0)
		fac_col.append(fc)
	var fac_spread := _max_hue_spread(fac_hue)
	var fac_min := _min_oklab_gap(fac_col)
	var was_a := _metal_mean(img, "was_last_wall", CREST_SAMPLES)
	var was_b := _metal_mean(img, "was_lanternhall", CREST_SAMPLES)
	var was_gap := _hue_gap(was_a.h * 360.0, was_b.h * 360.0)
	var was_min := _min_oklab_gap([was_a, was_b] as Array[Color])
	print("[frame_molding] faction spread %.1f deg, closest OKLab %.4f"
		% [fac_spread, fac_min])
	print("[frame_molding] old-accent arm: gap %.1f deg, OKLab %.4f"
		% [was_gap, was_min])
	_ok("faction frames: hue spread >= %.1f deg (old accents = %.1f on the closest pair)"
		% [FAC_SPREAD_MIN, was_gap], fac_spread >= FAC_SPREAD_MIN,
		"got %.1f deg" % fac_spread)
	_ok("faction frames: closest pair separated (OKLab >= %.3f, old arm = %.4f)"
		% [FAC_OKLAB_MIN, was_min], fac_min >= FAC_OKLAB_MIN,
		"got %.4f" % fac_min)
	#    THE CONTROL ARM has to stay collapsed, or the two thresholds above are
	#    measuring noise rather than a signal — the same discipline `tile_chamfer`
	#    provides for check 9.
	_ok("old-accent control arm is still collapsed (hue gap < 10 deg)",
		was_gap < 10.0,
		"got %.1f deg — thresholds above are not discriminating" % was_gap)

	# 11. THE GATE IS MEASURING THE SHIPPED FRAMES — check 8's rule, applied to
	#    the shell. If `MainMenu.faction_frame_cfg` disappears or stops being read,
	#    check 10 silently starts certifying this file's own guesses instead.
	var mm_s := load("res://scripts/scenes/MainMenu.gd") as GDScript
	_ok("faction frame config is read from MainMenu, not restated here",
		mm_s != null and mm_s.has_method("faction_frame_cfg"),
		"MainMenu.faction_frame_cfg() not found")

	# 8. THE GATE IS MEASURING THE SHIPPED FRAME. If `Card2D.chart_fillet_cfg`
	#    ever disappears or stops being read, this gate silently starts
	#    certifying its own defaults — the exact failure mode described at the
	#    top of this file, re-committed by the thing meant to prevent it.
	var c2d := load("res://scripts/Card2D.gd") as GDScript
	_ok("card fillet config is read from Card2D, not restated here",
		c2d != null and c2d.has_method("chart_fillet_cfg"),
		"Card2D.chart_fillet_cfg() not found")


func _ok(what: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fails.append(what + (" — " + detail if detail != "" else ""))


# ── measurement ────────────────────────────────────────────────────────────

func _sample(img: Image, x: int, y: int) -> Color:
	x = clampi(x, 0, img.get_width() - 1)
	y = clampi(y, 0, img.get_height() - 1)
	return img.get_pixel(x, y)


func _profile(img: Image, x: int, y0: int, dir: int, n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append(_sample(img, x, y0 + dir * i).get_luminance())
	return out


## The samples that are actually METAL: geometry gives the window, then anything
## still at ground value is dropped. One sample of slack on the outer side,
## because a polyline is centred on its path and straddles the plate's own edge.
func _metal_idx(top: Array, lead: int, w: float, span: int, ground: float) -> Array[int]:
	var m0 := maxi(lead - 1, 0)
	var m1 := mini(lead + int(ceil(w * _px)) + 1, span - 1)
	var idx: Array[int] = []
	for i in range(m0, m1 + 1):
		if absf(float(top[i]) - ground) > 0.04:
			idx.append(i)
	if idx.is_empty():
		idx.append(lead)
	return idx


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


func _measure(img: Image, tag: String) -> Dictionary:
	var r: Rect2 = _rects[tag]
	var w: float = _widths.get(tag, 1.0)
	var x := int((r.position.x + r.size.x * 0.5) * _px)
	var span := int(round(15.0 * _px))
	var lead := int(round(4.0 * _px))
	var top := _profile(img, x, int(r.position.y * _px) - lead, 1, span)
	var bot := _profile(img, x, int(r.end.y * _px) + lead, -1, span)
	var ground := _sample(img, x, int((r.position.y - 26.0) * _px)).get_luminance()
	var idx := _metal_idx(top, lead, w, span, ground)

	var levels: Dictionary = {}
	var crest := 0.0
	for i in idx:
		levels[snappedf(float(top[i]), 0.02)] = true
		crest = maxf(crest, float(top[i]))

	return {
		"plateaus": levels.size(),
		"crest": crest,
		"paper": ground,
		"shift": absf(_centroid(top, idx) - _centroid(bot, idx)),
		"drop_s": _sample(img, x, int((r.end.y + 1.5) * _px)).s,
	}


## Vertical wander of the crest along the TOP run, in framebuffer px. This is the
## straightness figure; `wobble` is what moves it.
func _sag(img: Image, tag: String) -> int:
	var r: Rect2 = _rects[tag]
	var y0 := int(r.position.y * _px) - int(round(4.0 * _px))
	var n := int(round(14.0 * _px))
	var lo := 9999
	var hi := -9999
	var x0 := int((r.position.x + r.size.x * 0.22) * _px)
	var x1 := int((r.position.x + r.size.x * 0.78) * _px)
	var step: int = maxi((x1 - x0) / 12, 1)
	for x in range(x0, x1, step):
		var best := 0.0
		var besty := 0
		for i in range(n):
			var v: float = _sample(img, x, y0 + i).get_luminance()
			if v > best:
				best = v
				besty = i
		lo = mini(lo, besty)
		hi = maxi(hi, besty)
	return maxi(hi - lo, 0)


## Peak luminance in the TOP-LEFT corner block, over peak luminance in the middle
## of the straight top run. Above 1 means the corner is the loudest thing on the
## frame, which is a chamfer and not a mitre — see check 9.
##
## The corner window is a square of 2.2 moulding-widths so it catches the whole
## cut on a chamfer AND the whole joint on a mitre; the run window is sampled
## from the middle third, well clear of either.
func _corner_ratio(img: Image, tag: String) -> float:
	var r: Rect2 = _rects[tag]
	var w: float = _widths.get(tag, 4.0)
	var pad := 4.0
	var box := maxf(w * 2.2, 8.0)
	var corner := _peak(img,
		Rect2(r.position - Vector2(pad, pad), Vector2(box + pad, box + pad)))
	# THE WHOLE RUN, not a middle slice. The claim is "the corner is not the
	# brightest part OF THE FRAME", and a denominator sampled from one third of
	# the run is a different question — `shimmer` crawls along the run, so where
	# its high spot lands relative to that slice varies with the node's instance
	# id, and the ratio moved between identical runs of this gate. Comparing the
	# corner against the run's OWN maximum puts the glint on both sides of the
	# division, which is what makes this a measurement of the silhouette.
	# CLEAR OF BOTH CORNERS BY A REAL MARGIN. At exactly `box` the window opened
	# on the last framebuffer column of the chamfer's own bright diagonal, so the
	# arm was being divided by itself and read 1.03x — a control arm measuring
	# nothing, which is worse than a noisy one because it is stable.
	var margin: float = maxf(box * 2.0, r.size.x * 0.15)
	var run := _peak(img, Rect2(
		Vector2(r.position.x + margin, r.position.y - pad),
		Vector2(maxf(r.size.x - margin * 2.0, 4.0), w + pad * 2.0)))
	return corner / maxf(run, 0.0001)


func _peak(img: Image, r: Rect2) -> float:
	var best := 0.0
	var x := int(r.position.x * _px)
	while x < int(r.end.x * _px):
		var y := int(r.position.y * _px)
		while y < int(r.end.y * _px):
			best = maxf(best, _sample(img, x, y).get_luminance())
			y += 1
		x += 1
	return best


## Hue of the brightest point on the TOP run, in degrees.
##
## IT HAS TO SKIP THE GROUND, AND THE GATE'S OWN CHECK 4 IS THE PROOF (fixed
## 2026-09-18). This took the brightest pixel in a 14px window that STARTS 4px
## ABOVE the frame — so it always included parchment at luminance 0.82, while
## check 4 three screens up asserts the crest must be DIMMER than parchment. The
## two checks were in direct contradiction: whenever check 4 held, this one could
## only ever return PAPER's hue. Measured, it reported 38.5 degrees for rare AND
## for uncommon — the same number, which is the tell, because those two alloys
## are gold and silver-blue and `alloy_mix` on a card is 0.12.
##
## A HUE THAT IS IDENTICAL ACROSS EVERY INPUT IS NOT A MEASUREMENT OF THE INPUT.
## Same family as the chaos-save lesson (a uniform result across 14 different
## corruptions was a broken predicate, not 14 findings) and the C20 census's
## denominator faults: suspect the oracle first.
##
## The metal window is the one `_measure` already uses — geometry gives the
## bracket, then anything still at ground value is dropped.
func _crest_hue(img: Image, tag: String) -> float:
	return _crest_colour(img, tag).h * 360.0


## The crest COLOUR. Check 10 needs chroma as well as hue, and deriving the two
## from separate windows is how they drift; `_crest_hue` above is now a view on
## this, so check 7 keeps measuring exactly what it always did.
func _crest_colour(img: Image, tag: String) -> Color:
	var r: Rect2 = _rects[tag]
	var w: float = _widths.get(tag, 4.0)
	var x := int((r.position.x + r.size.x * 0.5) * _px)
	var span := int(round(15.0 * _px))
	var lead := int(round(4.0 * _px))
	var y0 := int(r.position.y * _px) - lead
	var top := _profile(img, x, y0, 1, span)
	var ground := _sample(img, x, int((r.position.y - 26.0) * _px)).get_luminance()
	var best := 0.0
	var bestc := Color.BLACK
	for i in _metal_idx(top, lead, w, span, ground):
		var c := _sample(img, x, y0 + i)
		if c.get_luminance() > best:
			best = c.get_luminance()
			bestc = c
	return bestc


## THE FRAME'S OWN COLOUR: the mean across the whole metal window, averaged along
## the run. This is what check 10 asks about, and it is deliberately NOT the
## crest.
##
## `draw_molding` lerps the specular toward the cream `lit`, so the crest is
## precisely where five different metals are washed most alike -- and by
## `PlateFrame`'s own header the specular is about a SIXTH of the width, so it is
## also the least of the frame. Measured both ways on the same five samples: 25.9
## degrees of separation at the crest against 43.5 predicted across the body.
##
## Check 7 is still right to use the crest, because a rarity fillet's bright tip
## IS the cue there. Same pixels, different question, different weighting.
func _metal_mean(img: Image, tag: String, samples: int = 12) -> Color:
	var r: Rect2 = _rects[tag]
	var w: float = _widths.get(tag, 4.0)
	var span := int(round(15.0 * _px))
	var lead := int(round(4.0 * _px))
	var y0 := int(r.position.y * _px) - lead
	var ground := _sample(img, int((r.position.x + r.size.x * 0.5) * _px),
		int((r.position.y - 26.0) * _px)).get_luminance()
	var n: int = maxi(samples, 1)
	var rr := 0.0
	var gg := 0.0
	var bb := 0.0
	var hits := 0
	for k in range(n):
		var fx := 0.34 + 0.32 * (float(k) / float(maxi(n - 1, 1)))
		var x := int((r.position.x + r.size.x * fx) * _px)
		var top := _profile(img, x, y0, 1, span)
		for i in _metal_idx(top, lead, w, span, ground):
			var c := _sample(img, x, y0 + i)
			rr += c.r
			gg += c.g
			bb += c.b
			hits += 1
	if hits == 0:
		return Color.BLACK
	return Color(rr / float(hits), gg / float(hits), bb / float(hits), 1.0)


## Shortest angular distance between two hues, in degrees.
func _hue_gap(a: float, b: float) -> float:
	var d: float = absf(a - b)
	return minf(d, 360.0 - d)


## Widest pairwise hue gap in a set, in degrees.
func _max_hue_spread(hues: Array) -> float:
	var worst := 0.0
	for i in range(hues.size()):
		for j in range(i + 1, hues.size()):
			worst = maxf(worst, _hue_gap(float(hues[i]), float(hues[j])))
	return worst


## OKLab (Ottosson), on the framebuffer's own non-linear values — that is the
## space the moulding blended in, so it is the space to judge it in.
##
## WHY NOT HSV, which this file already has: two of the five shell metals are
## iron and bronze, which sit close in hue and separate by CHROMA, and the hue
## of a near-neutral is numerically unstable. HSV can neither see the first nor
## be trusted on the second. OKLab counts hue, chroma and lightness at once.
static func _oklab(c: Color) -> Vector3:
	var l := 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
	var m := 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
	var s := 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b
	var l3 := _cbrt(l)
	var m3 := _cbrt(m)
	var s3 := _cbrt(s)
	return Vector3(
		0.2104542553 * l3 + 0.7936177850 * m3 - 0.0040720468 * s3,
		1.9779984951 * l3 - 2.4285922050 * m3 + 0.4505937099 * s3,
		0.0259040371 * l3 + 0.7827717662 * m3 - 0.8086757660 * s3)


static func _cbrt(x: float) -> float:
	return signf(x) * pow(absf(x), 1.0 / 3.0)


## The closest pair in a set, as an OKLab distance — which is what "are these
## five telling themselves apart" actually asks.
func _min_oklab_gap(cols: Array) -> float:
	if cols.size() < 2:
		return 0.0
	var worst := 999.0
	for i in range(cols.size()):
		for j in range(i + 1, cols.size()):
			worst = minf(worst, (_oklab(cols[i] as Color)
				- _oklab(cols[j] as Color)).length())
	return worst


# ── samples ────────────────────────────────────────────────────────────────

func _card_cfg() -> Dictionary:
	var c2d := load("res://scripts/Card2D.gd") as GDScript
	if c2d != null and c2d.has_method("chart_fillet_cfg"):
		return c2d.chart_fillet_cfg()
	push_error("_probe_frame_molding: Card2D.chart_fillet_cfg() missing")
	return {"rule_w": 4.0}


func _host(at: Vector2, sz: Vector2, interior: Color, scale_by: float) -> Control:
	var host := Control.new()
	host.position = at
	host.size = sz
	host.scale = Vector2(scale_by, scale_by)
	add_child(host)
	var fill := ColorRect.new()
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.color = interior
	host.add_child(fill)
	return host


## A card plate: parchment page, ink mat interior.
func _card_sample(tag: String, at: Vector2, sz: Vector2, metal: Color,
		cfg: Dictionary, scale_by: float = 1.0) -> void:
	var page := ColorRect.new()
	page.position = at - Vector2(30, 30)
	page.size = sz * scale_by + Vector2(60, 60)
	page.color = PAPER
	add_child(page)
	var host := _host(at, sz, MAT, scale_by)
	PlateFrame.over(host, metal, cfg)
	_rects[tag] = Rect2(at, sz * scale_by)
	_widths[tag] = float(cfg.get("rule_w", 4.0)) * scale_by


## The flat 1px rule the card fillet replaced — the control arm.
func _flat_card_sample(tag: String, at: Vector2, sz: Vector2,
		metal: Color) -> void:
	var page := ColorRect.new()
	page.position = at - Vector2(30, 30)
	page.size = sz + Vector2(60, 60)
	page.color = PAPER
	add_child(page)
	var host := _host(at, sz, MAT, 1.0)
	var edge := Panel.new()
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	var st := StyleBoxFlat.new()
	st.draw_center = false
	st.border_color = Color(metal.r, metal.g, metal.b, 0.78)
	st.set_border_width_all(1)
	edge.add_theme_stylebox_override("panel", st)
	host.add_child(edge)
	_rects[tag] = Rect2(at, sz)
	_widths[tag] = 1.0


## A shell frame: warm-black page, mid-dark interior.
func _shell_sample(tag: String, at: Vector2, sz: Vector2, metal: Color,
		cfg: Dictionary) -> void:
	var host := _host(at, sz, INTERIOR, 1.0)
	PlateFrame.over(host, metal, cfg)
	_rects[tag] = Rect2(at, sz)
	_widths[tag] = float(cfg.get("rule_w", 6.0))
