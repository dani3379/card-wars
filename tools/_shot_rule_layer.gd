extends Node2D
## Windowed harness for THE RUBRIC (docs/RULE_FX_PASS_20260728.md).
##
## Four questions a parse check cannot answer:
##  1. Does the mark read on DARK WOOD *and* on LIGHT PARCHMENT? A cream core
##     alone is lower-contrast than parchment; an ink line alone vanishes on the
##     table. The house value law says every mark must carry both extremes.
##  2. Does the stroke still read once it has DRIED? This is the named revert
##     risk — a core that narrows into sub-pixel territory dissolves rather than
##     narrows, and it fails only in motion, only late, which is exactly the
##     window a settle-late shot harness never captures.
##  3. Does OVERKILL (tapers to a blunt heel) read differently from PIERCING
##     (widens, then splits dry)?
##  4. THE GREYSCALE TEST. If the mark substantially disappears in greyscale it
##     is colour-carried: it will camouflage on the warm table AND fail for a
##     red-green colourblind player, and no amount of material honesty saves it.
##     This is the free test that would have caught both prior reverts.
##
## Run WINDOWED (editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_rule_layer.tscn

const RubricStroke := preload("res://scripts/ui/painters/RubricStroke.gd")

const CARD_W := 200.0
const CARD_H := 150.0
const ROW_GAP := 6.0        # the real front→back gap in the column stack
const CELL_W := 250.0
const CELL_H := 340.0
const MARGIN := 16.0

const WOOD := Color(0.16, 0.115, 0.085)
const PARCHMENT := Color(0.86, 0.79, 0.63)
# Battlefield tokens are full-bleed art: mid-to-dark, painted, and variable.
const ART_A := Color(0.34, 0.27, 0.22)
const ART_B := Color(0.27, 0.31, 0.29)

var _cells: Array = []


func _ready() -> void:
	get_tree().create_timer(45.0).timeout.connect(func():
		print("[rubric] WATCHDOG fired — _ready never completed")
		get_tree().quit(1))
	# This machine ships Reduce Motion ON; the harness must measure the full mark.
	if UserSettings != null:
		UserSettings.reduce_motion = false
	await get_tree().process_frame

	# The capture is the PROJECT's 1600x900 stretch canvas, not the OS window, so
	# the grid has to fit that box: 6 columns x 2 rows of 250x340 = 1500x680.
	# Laying out to the window instead cost one run with the bottom row clipped.
	var blocks := [
		{"bg": WOOD, "pierce": false, "tag": "wood/overkill", "col": 0, "row": 0},
		{"bg": PARCHMENT, "pierce": false, "tag": "parch/overkill", "col": 3, "row": 0},
		{"bg": WOOD, "pierce": true, "tag": "wood/piercing", "col": 0, "row": 1},
		{"bg": PARCHMENT, "pierce": true, "tag": "parch/piercing", "col": 3, "row": 1},
	]
	var dries := [0.0, 0.5, 1.0]
	for b in blocks.size():
		var blk: Dictionary = blocks[b]
		for c in dries.size():
			var org := Vector2(
				MARGIN + float(int(blk["col"]) + c) * CELL_W,
				MARGIN + float(int(blk["row"])) * CELL_H)
			_build_cell(org, blk, float(dries[c]), b, c)

	# Await real frames — RenderingServer.force_draw() returns before newly added
	# CanvasItems have drawn and captures a black frame. (The long "hangs" that
	# made force_draw look necessary were a PARSE ERROR in the painter: the scene
	# script failed to load, so the harness never ran and the window just sat
	# there. Always parse-check before blaming the renderer.)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shot_rubric.png")
	_measure(img)
	_save_greyscale(img)
	print("[rubric] DONE — rows: wood/overkill, parchment/overkill, wood/piercing")
	print("[rubric]        cols: dry=0.0 (wet), dry=0.5, dry=1.0 (dried)")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)


func _build_cell(org: Vector2, cfg: Dictionary, dry: float, r: int, c: int) -> void:
	var bg := ColorRect.new()
	bg.position = org
	bg.size = Vector2(CELL_W, CELL_H)
	bg.color = cfg["bg"]
	bg.z_index = -10
	add_child(bg)

	# Two tokens in one column, at the real 200x150 with the real 6px gap.
	var x := org.x + (CELL_W - CARD_W) * 0.5
	var y_a := org.y + 14.0
	var y_b := y_a + CARD_H + ROW_GAP
	for i in 2:
		var t := ColorRect.new()
		t.position = Vector2(x, y_a if i == 0 else y_b)
		t.size = Vector2(CARD_W, CARD_H)
		t.color = ART_A if i == 0 else ART_B
		t.z_index = -5
		add_child(t)

	var a := Vector2(x + CARD_W * 0.5, y_a + CARD_H * 0.5)
	var b := Vector2(x + CARD_W * 0.5, y_b + CARD_H * 0.5)
	var s = RubricStroke.new()
	s.z_index = 10
	add_child(s)
	s.configure(a, b, hash("cell_%d_%d" % [r, c]), bool(cfg["pierce"]))
	# The bare-table span between the two tokens, computed the same way Combat
	# does it (by sampling, so it stays orientation-agnostic).
	var gap_t0: float = (y_a + CARD_H - a.y) / (b.y - a.y)
	var gap_t1: float = (y_b - a.y) / (b.y - a.y)
	s.gutter_spans = [Vector2(gap_t0, gap_t1)]
	s.progress = 1.0
	s.dry = dry
	_cells.append({"a": a, "b": b, "dry": dry, "tag": cfg["tag"], "bg": cfg["bg"]})


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _measure(img: Image) -> void:
	# THE GREYSCALE TEST, stated numerically: at each of three points along the
	# mark, the max |luminance delta| between the stroke and its background 20px
	# to the side. A mark that survives colourblind vision and a warm table needs
	# a real VALUE difference, not a hue difference.
	# The captured image is the stretch canvas at the window's real resolution, so
	# design-space coordinates must be scaled into image pixels. Skipping this is
	# why the first run measured 0.000 everywhere against a stroke that was
	# plainly visible in the PNG — the sampler was reading empty margin.
	var sc: float = float(img.get_width()) / maxf(get_viewport_rect().size.x, 1.0)
	print("[rubric] ── greyscale contrast (max |luma delta| vs bg 20px aside) ──")
	print("[rubric]    capture %dx%d, design->image scale %.2f" % [
		img.get_width(), img.get_height(), sc])
	for cell in _cells:
		var a: Vector2 = cell["a"]
		var b: Vector2 = cell["b"]
		var worst := 999.0
		var at_gutter := 0.0
		for k in 21:
			var t := 0.10 + 0.80 * (float(k) / 20.0)
			var p: Vector2 = a.lerp(b, t) * sc
			var best := 0.0
			# The stroke wobbles + leans, so sweep wide enough to find its core.
			for dx in range(-int(18 * sc), int(18 * sc) + 1):
				var px := int(p.x) + dx
				var py := int(p.y)
				if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
					continue
				var bgx: int = clampi(px + int(34 * sc), 0, img.get_width() - 1)
				var d: float = absf(_luma(img.get_pixel(px, py))
					- _luma(img.get_pixel(bgx, py)))
				best = maxf(best, d)
			worst = minf(worst, best)
			if absf(t - 0.5) < 0.03:
				at_gutter = best
		print("[rubric]   %-20s dry=%.1f   weakest=%.3f   at-gutter=%.3f%s" % [
			cell["tag"], cell["dry"], worst, at_gutter,
			"   <-- FAILS (<0.08)" if worst < 0.08 else ""])


func _dump_particle_sheet() -> void:
	# The other half of this pass: every burst in the game used to be an
	# untextured CPUParticles2D, i.e. a hard-edged SQUARE. Dump the four new
	# silhouettes magnified so the falloff and the seeded lopsidedness can be
	# eyeballed at a size the eye can actually judge.
	var kinds := ["fleck", "spark", "disc", "ink"]
	var cell := 32
	var mag := 5
	var pad := 6
	var w := (cell * mag + pad) * kinds.size() + pad
	var h := cell * mag + pad * 2
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.35, 0.30, 0.26, 1.0))  # mid grey: shows core AND surround
	var x0 := pad
	for k in kinds:
		var tex: Texture2D = Motion.particle_tex(k)
		var src: Image = tex.get_image()
		print("[rubric] ptex %-6s center_a=%.2f mid_a=%.2f edge_a=%.2f" % [
			k, src.get_pixel(16, 16).a, src.get_pixel(24, 16).a, src.get_pixel(31, 16).a])
		for y in cell * mag:
			for x in cell * mag:
				var sp := src.get_pixel(x / mag, y / mag)
				var bg := sheet.get_pixel(x0 + x, pad + y)
				sheet.set_pixel(x0 + x, pad + y, bg.lerp(Color(1, 1, 1, 1), sp.a))
		x0 += cell * mag + pad
	sheet.save_png("res://_shot_ptex.png")
	print("[rubric] wrote _shot_ptex.png (fleck / spark / disc / ink, 5x)")


func _save_greyscale(img: Image) -> void:
	# NATIVE desaturation. The per-pixel GDScript version was 3.24M set_pixel calls
	# on a 2400x1350 capture and blew a two-minute budget on its own.
	var g := Image.create_from_data(img.get_width(), img.get_height(), false,
		img.get_format(), img.get_data())
	g.adjust_bcs(1.0, 1.0, 0.0)
	g.save_png("res://_shot_rubric_grey.png")
	print("[rubric] wrote _shot_rubric.png + _shot_rubric_grey.png")
