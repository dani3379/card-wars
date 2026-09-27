extends Node
## _shot_bonus.gd — LOOK AT THE STARTING BONUS SCREEN.
##
##   Godot_v4.6.2-stable_win64.exe --path "D:\Godot" res://tools/_shot_bonus.tscn
##
## `_shot_runstart` already shoots this screen twice, at 1600x900, which answers
## "how loud is it" and nothing else. The two questions this pass was handed are
## both sub-pixel-argument questions that a full frame cannot settle:
##
##  1. THE CORNER MARKS. Something draws short angled strokes at the corner of
##     every tile, and the owner's reading is that the idea is right and the
##     execution is not. A 2px stroke is not decidable at 1:1 — shoot it at 6x
##     and print the scanline across it, per the house rule that any harness
##     judging a THIN mark prints a scanline beside its crop.
##  2. IS THE PAGE FULL. Measured rather than eyeballed: the ink census walks
##     the canvas and reports the fraction of rows/columns carrying anything
##     above the table's own value, plus the biggest empty band. "Feels empty"
##     is two faults (a hole under the content vs flat surfaces) and they need
##     different fixes, so the harness reports WHICH.
##
## Headless prints the measurements and skips the PNGs (get_image is blank under
## the dummy renderer). DO NOT run beside run_ui_gates.ps1 or another windowed
## shot tool — they compete for the display and the run exits 0 having printed
## nothing.

const SHOT_DIR := "res://tools/screenshot/bonus"
## Depths into the sheet the edge claim is about. `WritLeaf.edge_w` is 7; past
## that the two runs carry different furniture and stop being comparable.
const EDGE_DEPTHS := 7

var _scene: Node = null
var _headless := false
var _shots := 0
## Which arm of the A/B is being measured, for the printed one-liner.
var _ab_tag := "NEW (lit section)"
## Which file `_dump_regions` writes. The settled screen owns "regions".
var _regions_tag := "regions"


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	await get_tree().process_frame
	await get_tree().process_frame
	if not _headless:
		var ss := get_node_or_null("/root/Supersample")
		if ss != null and ss.has_method("apply_scale"):
			ss.apply_scale(1.0)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))
		DisplayServer.window_move_to_foreground()

	_scene = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(1.2).timeout

	RunState.active_slot = 0
	_scene.set("_selected_hero", "raider")
	_scene.set("_muster_random_seed", 1)
	_scene.set("_muster_seed_text", "")
	_scene.call("_refresh_muster_deals")
	_scene.call("_show_starting_bonus")
	await get_tree().create_timer(1.6).timeout

	# The dossier is a harness artifact: entering the screen through
	# `_show_starting_bonus` directly skips the menu rebuild that removes it.
	if _scene.has_method("_remove_command_dossier"):
		_scene.call("_remove_command_dossier")
	await _settle()
	# THE RESTING LOOK IS WHAT THE MEASUREMENTS ARE ABOUT. The screen hands focus
	# to a tile on entry and focus LIGHTS a sheet (candle + a 1.022 lift), so the
	# `full` frame and the edge profile would otherwise both be of a tile under a
	# hand that is not there. The lit state gets its own frame further down.
	_defocus()
	await get_tree().create_timer(0.35).timeout

	await _snap("full")
	_dump_layout()
	await _dump_regions()
	_census()
	# ── THE SWEEPS ARE OPT-IN ──
	#
	# These six are DERIVATION scaffolding, not a standing measurement: together
	# they render ~40 frames and take minutes, and their output is a table you
	# read once to pick a constant. The default run is the audit — full frame,
	# regions, ink census, layout dump, the edge A/B and the zooms — which is what
	# anyone touching this screen wants back quickly.
	#
	# Kept rather than deleted because three of the four composition sweeps
	# returned NEGATIVE results, and a negative result nobody can reproduce gets
	# re-litigated: the next person to wonder whether a bigger portrait would fill
	# this page out can re-run it in one command and see bal-H fall.
	#
	#   Godot.exe --path "D:\Godot" res://tools/_shot_bonus.tscn -- --sweeps
	if "--sweeps" in OS.get_cmdline_user_args():
		print("[sb] --sweeps: rendering the derivation ladders (slow)")
		await _table_sweep()
		await _plate_sweep()
		await _tile_sweep()
		await _lift_sweep()
		await _rect_sweep()
		await _final_sweep()
	await _inversion_ab()
	await _corner_zooms()

	# A tile under the hand: the candle pool is the only thing on the page that
	# answers the cursor, so its reach is worth a frame of its own.
	var tiles: Dictionary = _scene.get("_muster_writ_buttons")
	var first: Control = null
	for tid in tiles:
		var t: Control = tiles[tid]
		if is_instance_valid(t):
			first = t
			break
	if first != null:
		_scene.call("_light_writ", first, true)
		await get_tree().create_timer(0.6).timeout
		await _snap("hover")
		_scene.call("_light_writ", first, false)

	# THE SEAL COMING DOWN is the screen's payoff and the one state the signature
	# line exists to receive, so it gets a frame. `_select_muster_writ` is the
	# commit, and on a live screen it goes on to change scene — the tile styles
	# are repainted first, which is what this is here to photograph.
	_scene.set("_bonus_pick_made", true)
	_scene.call("_refresh_muster_writ_styles")
	await get_tree().create_timer(0.5).timeout
	await _snap("sealed")
	if first != null:
		# THE SEAL SITS ON THE SIGNATURE LINE (bottom-left), not in the top
		# corner — a mark aimed at the old spot photographs the cartouche.
		await _zoom_at(first.global_position
			+ Vector2(56.0, first.size.y - 26.0),
			"seal", 4, 220, 150)

	# OWNERSHIP. Two renders were nearly spent arguing about which layer was
	# washing the lower page pale. Tinting the suspect bright red for one frame
	# settles it in seconds — the house method, and cheaper than any amount of
	# reading the tree.
	var tbl := _scene.get_node_or_null("BonusTable")
	if tbl != null:
		tbl.modulate = Color(1, 0, 0, 1)
		await get_tree().create_timer(0.3).timeout
		await _snap("own_table")
		tbl.modulate = Color(1, 1, 1, 1)
	var atm := _scene.get_node_or_null("Atmosphere")
	if atm != null:
		atm.modulate = Color(0, 1, 0, 1)
		await get_tree().create_timer(0.3).timeout
		await _snap("own_atmosphere")
		atm.modulate = Color(1, 1, 1, 1)

	# Which node owns each pixel of a tile? Tint one child of the first writ at a
	# time and report what actually moved, at the three places the edge profile is
	# measured. This is the cheapest instrument in the box and it should have been
	# reached for two renders earlier than it was.
	if first != null:
		for cname in ["WritPaper", "WritAge", "WritRule"]:
			var n := first.get_node_or_null(cname) as Control
			if n == null:
				print("[sb] own %s — absent" % cname)
				continue
			n.modulate = Color(1, 0, 0, 1)
			await get_tree().create_timer(0.25).timeout
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			var cx := first.global_position.x + first.size.x * 0.5
			var probes := {
				"above top ": Vector2(cx, first.global_position.y - 2.0),
				"inside top": Vector2(cx, first.global_position.y + 4.0),
				"at bottom ": Vector2(cx, first.global_position.y
					+ first.size.y + 2.0),
				"inside bot": Vector2(cx, first.global_position.y
					+ first.size.y - 6.0),
			}
			var out: Array[String] = []
			for k in probes:
				var c := img.get_pixelv(Vector2i(_to_image(img, probes[k])))
				out.append("%s r%.2f g%.2f" % [k, c.r, c.g])
			print("[sb] own %-9s %s" % [cname, " | ".join(out)])
			n.modulate = Color(1, 1, 1, 1)
	await _reentry_check()
	print("[sb] %d shots" % _shots)
	get_tree().quit(0)


## RE-ENTRY: the lift must not ACCUMULATE.
##
## `_lift_menu_block` mutates `menu.offset_top/bottom` RELATIVELY, and it sits one
## line after `_center_menu_for_subscreen`, which sets them ABSOLUTELY. That pair
## is safe only for as long as every path to this screen goes through the setter —
## and "a relative mutation beside an absolute setter" is precisely the shape that
## accumulates the first time some path does not.
##
## So it is asserted rather than reasoned about: leave to run setup, come back,
## and require the column to land on the same offsets. A drift here would push the
## block off the top of the canvas on the second visit only, which is the kind of
## defect that ships.
func _reentry_check() -> void:
	var menu := _scene.get_node_or_null("Menu") as Control
	if menu == null:
		return
	var first := menu.offset_top
	_scene.call("_leave_starting_bonus")
	await _settle()
	await get_tree().create_timer(0.4).timeout
	_scene.call("_show_starting_bonus")
	await _settle()
	await get_tree().create_timer(0.4).timeout
	menu = _scene.get_node_or_null("Menu") as Control
	var second: float = menu.offset_top if menu != null else NAN
	var ok: bool = is_equal_approx(first, second)
	print("[sb] re-entry offset_top %.1f -> %.1f  %s"
		% [first, second, "OK" if ok else "*** LIFT ACCUMULATED ***"])


## Hand focus to BACK, which is a plain button and lights nothing, so every writ
## on the page is in its resting state.
func _defocus() -> void:
	var back := _scene.find_child("BonusBack", true, false) as Control
	if back != null:
		back.grab_focus()
		return
	var tiles: Dictionary = _scene.get("_muster_writ_buttons")
	for tid in tiles:
		var t: Control = tiles[tid]
		if is_instance_valid(t):
			t.release_focus()


## SETTLE UNTIL STABLE, never on a clock. Two renders disagreed by 17px on where
## the row sat, which made the edge-profile scanlines land on different parts of
## the sheet and read as a change I had not made — the subscreen reveal is still
## tweening at 1.6s, and the table's own fade runs 0.45s on top of it. Poll the
## first tile's rect until it HOLDS; on real time with a floor, because headless
## runs the main loop as fast as it can and "0, 0, 0" is perfectly stable.
func _settle() -> void:
	var tiles: Dictionary = _scene.get("_muster_writ_buttons")
	var first: Control = null
	for tid in tiles:
		var t: Control = tiles[tid]
		if is_instance_valid(t):
			first = t
			break
	if first == null:
		await get_tree().create_timer(1.0).timeout
		return
	var last := Rect2()
	var held := 0
	var waited := 0.0
	while waited < 6.0:
		await get_tree().create_timer(0.12).timeout
		waited += 0.12
		var now := Rect2(first.global_position, first.size)
		if now == last and now.size.y > 1.0:
			held += 1
			if held >= 4 and waited > 1.2:
				break
		else:
			held = 0
		last = now
	print("[sb] settled after %.2fs at %s" % [waited, str(last)])
	# THE BUTTON'S RECT IS NOT NECESSARILY THE SHEET'S. Print both, because an
	# edge walk keyed off the wrong one measures the wrong pixels and reports it
	# as a finding about shading (this cost two renders).
	for cname in ["WritPaper", "WritAge", "WritRule"]:
		var n := first.get_node_or_null(cname) as Control
		if n != null:
			print("[sb]   %-10s pos %s size %s  (btn scale %s pivot %s)"
				% [cname, str(n.global_position), str(n.size),
				str(first.scale), str(first.pivot_offset)])


## Every corner of every tile, at 6x. The marks are the subject, so the crop is
## centred ON the corner rather than on the tile.
func _corner_zooms() -> void:
	var tiles: Dictionary = _scene.get("_muster_writ_buttons")
	var idx := 0
	for tid in tiles:
		var t: Control = tiles[tid]
		if not is_instance_valid(t):
			continue
		if idx == 0:
			await _zoom_at(t.global_position, "corner_tl", 6)
			await _zoom_at(t.global_position + Vector2(t.size.x, 0.0),
				"corner_tr", 6)
			await _zoom_at(t.global_position + Vector2(0.0, t.size.y),
				"corner_bl", 6)
			# The whole tile at 2x, so the marks can be read in context.
			await _zoom_at(t.global_position + t.size * 0.5, "tile", 2, 420, 260)
		idx += 1
	print("[sb] %d tiles" % idx)


## THE A/B. The inversion number only means something against the draw it
## replaced, so the harness measures BOTH: it flips every sheet's `edge_profile`
## off, redraws, measures, and puts it back. Same screen, same seed, same tiles —
## the only difference is the painter's opt-in path.
##
## This is the whole argument of the pass in one pair of numbers, and it is the
## same instrument `PlateFrame` was accepted on (0.033 -> 0.343 there). A stack
## of concentric flat rings cannot score here BY CONSTRUCTION, however many rings
## it has, because every ring carries one colour all the way round.
func _inversion_ab() -> void:
	if _headless:
		return
	var leaves: Array[Node] = []
	var tiles: Dictionary = _scene.get("_muster_writ_buttons")
	for tid in tiles:
		var t: Control = tiles[tid]
		if is_instance_valid(t):
			var leaf := t.get_node_or_null("WritPaper")
			if leaf != null:
				leaves.append(leaf)
	if leaves.is_empty():
		print("[sb] A/B skipped — no WritPaper found")
		return
	for leaf in leaves:
		leaf.set("edge_profile", false)
		(leaf as Control).queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_ab_tag = "OLD (flat rings)"
	await _inversion()
	await _snap("ab_old")
	for leaf in leaves:
		leaf.set("edge_profile", true)
		(leaf as Control).queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_ab_tag = "NEW (lit section)"
	await _inversion()


## THE INVERSION — the one number that separates "a thicker line" from "an
## object", lifted from the `PlateFrame` A/B because it is the same claim.
##
## A sheet lit from up-left presents its TOP edge's wall to the lamp and its
## BOTTOM edge's wall away from it, so at equal depth into the edge band the two
## runs must differ. **A stack of concentric flat rings scores ~0 here no matter
## how many rings it has**, because every ring carries one colour all the way
## round — which is exactly what the old rim was and why it read as vector art.
func _inversion() -> void:
	if _headless:
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var tiles: Dictionary = _scene.get("_muster_writ_buttons")
	# ── ACROSS EVERY SHEET, NOT DOWN ONE COLUMN OF ONE SHEET ──
	#
	# Two earlier spellings of this measurement both reported a confound as if it
	# were the result, and each one names a real property of the screen:
	#
	#  1. ONE COLUMN put the old flat-ring draw at 0.194 against the new
	#     section's 0.274 — too close to be evidence. `ParchmentPlate`'s ageing
	#     is a seeded mottle, so at any single x the top margin and the bottom
	#     one can differ by hundredths for no reason at all.
	#  2. AVERAGING THE COLUMNS OF ONE TILE did not fix it and briefly reported
	#     the new draw as WORSE (0.186 vs 0.209). That painter's washes are radii
	#     of 0.10-0.40 of the sheet's WIDTH — up to 147px on a sheet 172px tall —
	#     so a single light patch sitting low covers the whole bottom run at
	#     EVERY x. Column-averaging cannot remove a bias that is constant in x;
	#     only averaging over SEEDS can, and the four tiles are four seeds.
	#
	# Depth is capped at the edge band. Past it the two runs stop being
	# comparable: the top margin carries the slot cartouche and the bottom one
	# the clerk's rule and the signature line, so `max |top - bot|` over the full
	# sheet was reporting FURNITURE at unequal depths — that is where both of the
	# old numbers came from, on both arms.
	var tops: Array[float] = []
	var bots: Array[float] = []
	var n := 0
	for tid in tiles:
		var t: Control = tiles[tid]
		if not is_instance_valid(t):
			continue
		var top := _profile_avg(img, t, 1.0)
		var bot := _profile_avg(img, t, -1.0)
		if top.is_empty() or bot.is_empty():
			continue
		if tops.is_empty():
			tops.resize(EDGE_DEPTHS)
			bots.resize(EDGE_DEPTHS)
		for d in range(mini(EDGE_DEPTHS, mini(top.size(), bot.size()))):
			tops[d] += float(top[d])
			bots[d] += float(bot[d])
		n += 1
	if n == 0:
		print("[sb] INVERSION — no paper edge found")
		return
	var peak := 0.0
	var signed := 0.0
	var ts: Array[String] = []
	var bs: Array[String] = []
	for d in range(tops.size()):
		var a: float = tops[d] / float(n)
		var b: float = bots[d] / float(n)
		peak = maxf(peak, absf(a - b))
		signed += a - b
		ts.append("%.3f" % a)
		bs.append("%.3f" % b)
	signed /= float(tops.size())
	# THE SIGNED MEAN IS THE DISCRIMINATOR, not the peak. "The light inverts
	# between opposite runs" is a claim about DIRECTION holding all the way
	# across the band; a symmetric stack of rings scores ~0 here by construction
	# however many rings it has, while a peak can be earned by any one-off
	# difference in either direction.
	print("[sb] %s  signed %+.3f  peak %.3f  (%d sheets)"
		% [_ab_tag, signed, peak, n])
	print("      lit run   %s
      shade run %s" % [" ".join(ts), " ".join(bs)])


## AVERAGED ACROSS THE SHEET, NOT READ DOWN ONE COLUMN, and the A/B is what
## forced it. A single column put the old flat-ring draw at 0.194 against the new
## section's 0.274 — two numbers too close to be evidence of anything, and the
## reason is that `ParchmentPlate`'s ageing is a SEEDED MOTTLE: at one x it can
## differ by several hundredths between the top margin and the bottom one purely
## by chance, which is noise the size of the signal.
##
## The claim being tested is SYSTEMATIC — every point along the top run is lit
## and every point along the bottom run is shaded — so averaging across the run
## is not smoothing the result, it is measuring the thing the claim is about. The
## mottle averages out; a lighting inversion cannot.
func _profile_avg(img: Image, t: Control, dir: float) -> Array:
	var edge_y: float = t.global_position.y if dir > 0.0 \
		else t.global_position.y + t.size.y
	var sums: Array[float] = []
	var hits := 0
	# The middle 70% of the width: the deckle's corners curve away from the run,
	# and the chamfered ends would average a corner's lighting into a run's.
	for i in range(24):
		var fx: float = lerpf(0.15, 0.85, float(i) / 23.0)
		var col := _profile_from_edge(img, t.global_position.x + t.size.x * fx,
			edge_y, dir, false)
		if col.is_empty():
			continue
		if sums.is_empty():
			sums.resize(col.size())
		for d in range(mini(sums.size(), col.size())):
			sums[d] += float(col[d])
		hits += 1
	var out: Array = []
	if hits == 0:
		return out
	for d in range(sums.size()):
		out.append(sums[d] / float(hits))
	return out


## Luminance profile inward from the PAPER's edge along a column. `dir` is +1 to
## walk down from the top edge, -1 to walk up from the bottom. Finds the paper by
## the first sample above `PAPER_FLOOR` — the sheets sit at ~0.8 on a ~0.15 table,
## so the transition is unambiguous.
func _profile_from_edge(img: Image, cx: float, edge_y: float,
		dir: float, verbose: bool = true) -> Array:
	# LOCK ONTO A TRANSITION, not onto the first bright sample. A tile that is
	# FOCUS-LIT carries `scale 1.022`, so its drawn sheet stands ~2.5px proud of
	# the rect on every side and a walk starting at the rect is already on paper —
	# which is what made the shaded run read brighter than the page and cost two
	# renders' worth of wrong theories. Requiring a sub-floor sample first makes
	# the search find the actual edge wherever the sheet really is.
	var out: Array = []
	var start := -1
	var seen_ground := false
	var walk: Array[String] = []
	for probe in range(-8, 10):
		var p := _to_image(img, Vector2(cx, edge_y + dir * float(probe)))
		var v: float = img.get_pixelv(Vector2i(p)).get_luminance()
		walk.append("%.2f" % v)
		if v < 0.45:
			seen_ground = true
		elif seen_ground and start < 0:
			start = probe
	if verbose:
		print("[sb]   edge walk dir %+d from y=%.1f: %s (start %d)"
			% [int(dir), edge_y, " ".join(walk), start])
	if start < 0:
		return out
	for d in range(0, 10):
		var p := _to_image(img, Vector2(cx, edge_y + dir * float(start + d)))
		out.append(img.get_pixelv(Vector2i(p)).get_luminance())
	return out


## THE LANDING SWEEP: lift x rect, graded on BOTH oracles at once — Ngo balance
## (which a painted ground can satisfy with a void) and the tallest empty spacer
## (which is what that void actually is). A frame only counts if it scores on one
## without failing the other.
func _final_sweep() -> void:
	if _headless:
		return
	var menu := _scene.get_node_or_null("Menu") as Control
	if menu == null:
		return
	for rect in [600, 660, 712]:
		for lift in [76, 105, 120]:
			_scene.call("_center_menu_for_subscreen", 1560.0, float(rect))
			menu.offset_top -= float(lift)
			menu.offset_bottom -= float(lift)
			await _settle()
			await get_tree().create_timer(0.2).timeout
			var worst := 0.0
			for c in menu.get_children():
				var n := c as Control
				if n != null and not n.is_queued_for_deletion() 						and n.get_combined_minimum_size().y <= 0.5:
					worst = maxf(worst, n.size.y)
			var title := _scene.find_child("BonusTitle", true, false) as Control
			var ty: float = title.global_position.y if title != null else -1.0
			print("[sb]   rect %d lift %2d -> title y=%.0f  worst spacer %.0fpx"
				% [rect, lift, ty, worst])
			await _snap("fin_r%dl%02d" % [rect, lift])
			await _dump_regions_as("regions_f%dl%02d" % [rect, lift])
	await _settle()


## THE COLUMN'S ACTUAL LAYOUT. Two guesses in a row about why the block would not
## translate were both wrong, and the house rule for exactly this is to stop
## arguing from the geometry and print what the container actually did: rect,
## per-child position/size/minimum/flags. A VBox whose children EXPAND absorbs a
## rect change as SLACK instead of as movement, and that is invisible from the
## outside — the block looks pinned.
func _dump_layout() -> void:
	var menu := _scene.get_node_or_null("Menu") as Control
	if menu == null:
		return
	print("[sb] Menu rect pos=%s size=%s  offsets t=%.0f b=%.0f  minY=%.0f"
		% [str(menu.position), str(menu.size), menu.offset_top,
		menu.offset_bottom, menu.get_combined_minimum_size().y])
	var worst := 0.0
	for c in menu.get_children():
		var n := c as Control
		if n == null or n.is_queued_for_deletion():
			continue
		print("[sb]    %-22s y=%6.1f h=%6.1f  min=%6.1f  vflag=%d ratio=%.1f"
			% [n.name, n.position.y, n.size.y,
			n.get_combined_minimum_size().y, n.size_flags_vertical,
			n.size_flags_stretch_ratio])
		if String(n.name).begins_with("Slack") or n.get_combined_minimum_size().y <= 0.5:
			worst = maxf(worst, n.size.y)
	# ── THE HOLE, MEASURED (2026-09-18) ──
	#
	# Ngo balance counts the TABLE's dim wash as mass, so this page can score a
	# near-perfect 0.997 while reading as a void: pushing all 113px of the
	# column's slack below the writ row balanced the quadrants to
	# 25.5/24.6/25.1/24.8 and simultaneously opened a 200px gap between the gloss
	# and BACK. Both statements were true of the same frame.
	#
	# So balance is not a sufficient oracle on a screen with a painted ground, and
	# the second number is the one it is blind to: the tallest EMPTY spacer. Space
	# around a composed block is margin; space inside it is a hole.
	print("[sb] tallest empty spacer inside the column: %.0fpx%s"
		% [worst, "   <- HOLE" if worst > 60.0 else ""])


## THE COLUMN'S OWN RECT, SWEPT — the lift sweep's finding, expressed through the
## dial the screen already has instead of through a raw offset.
##
## `_center_menu_for_subscreen(w, h)` centres the column in an h-tall rect, and
## `_show_muster_step`'s own header records the mechanism: once the content
## outgrows the rect the column lays out from `(900 - h) / 2` DOWNWARD. This
## screen asks for 640 and its content is ~711 tall, so the block starts at 130
## and overflows past the foot — which is precisely why its heavy band sits 117px
## below the midline.
##
## So a TALLER rect raises the block, and unlike the raw lift it cannot walk the
## title off the top: the start is `(900 - h) / 2`, which is bounded below by 0.
## The risk is the opposite one and it is what the sweep is for — once h exceeds
## the content the spacers stop being pinned and start EXPANDING, which pushes
## the bands apart again rather than lifting them together.
func _rect_sweep() -> void:
	if _headless:
		return
	if not _scene.has_method("_center_menu_for_subscreen"):
		print("[sb] rect sweep skipped")
		return
	for h in [640, 700, 760, 820, 880]:
		_scene.call("_center_menu_for_subscreen", 1540.0, float(h))
		await _settle()
		await get_tree().create_timer(0.25).timeout
		var title := _scene.find_child("BonusTitle", true, false) as Control
		var foot := _scene.find_child("BonusBack", true, false) as Control
		var ty: float = title.global_position.y if title != null else -1.0
		var fy: float = (foot.global_position.y + foot.size.y) if foot != null else -1.0
		print("[sb]   rect %d -> title y=%.0f  footer bottom y=%.0f%s"
			% [h, ty, fy, "  OUT OF CANVAS" if (ty < 4.0 or fy > 896.0) else ""])
		await _snap("rect_%03d" % h)
		await _dump_regions_as("regions_r%03d" % h)
	_scene.call("_center_menu_for_subscreen", 1540.0, 640.0)
	await _settle()


## THE BLOCK'S VERTICAL POSITION, SWEPT — and this is the one the other three
## sweeps were pointing at all along.
##
## Measured on the settled screen: the writ row carries 82% of the page's optical
## weight and its centre sits **117px BELOW the canvas midline**, with nothing but
## faint text above it. That is what every other number was reporting from a
## different angle — bal-H 0.141 against a shell range of 0.43-1.00, quadrants
## 6.6/5.8/43.8/43.7, mass centre at y 0.621.
##
## Growing things did not move it (the plate sweep made it worse, the tile sweep
## barely moved it and cost 3% density) because the column is CENTRED: growth
## above the row pushes the row down, and growth of the row keeps it on the same
## side of the line. The only lever that changes which side of the midline the
## mass is on is where the block starts.
##
## Moving it up is also the right answer in fiction rather than only in
## arithmetic: Palmer's vertical-composition work finds people prefer an object's
## AFFORDANCE SPACE centred in the frame, and the affordance space of a table with
## documents on it is the surface you reach across. Paperwork belongs at reading
## height with the table running away below it — not floating in the middle of the
## wood with a void of ceiling overhead.
func _lift_sweep() -> void:
	if _headless:
		return
	var menu := _scene.get_node_or_null("Menu") as Control
	if menu == null:
		print("[sb] lift sweep skipped — no Menu")
		return
	var t0: float = menu.offset_top
	var b0: float = menu.offset_bottom
	for lift in [0, 40, 80, 120, 160]:
		menu.offset_top = t0 - float(lift)
		menu.offset_bottom = b0 - float(lift)
		await _settle()
		await get_tree().create_timer(0.25).timeout
		var title := _scene.find_child("BonusTitle", true, false) as Control
		var top: float = title.global_position.y if title != null else -1.0
		print("[sb]   lift %3dpx -> title top y=%.0f%s"
			% [lift, top, "  OFF-CANVAS" if top < 0.0 else ""])
		await _snap("lift_%03d" % lift)
		await _dump_regions_as("regions_l%03d" % lift)
	menu.offset_top = t0
	menu.offset_bottom = b0
	await _settle()


## THE SHEETS' OWN HEIGHT, SWEPT — the hypothesis the plate sweep left standing.
##
## Growing the LORD made every number worse (bal-H 0.142 -> 0.056, equilibrium
## 0.875 -> 0.738) and the reason is structural: the column is vertically centred,
## so anything that grows the HEADER pushes the subject further down and the row's
## displacement costs more weight than the plate gains. Any fix that adds height
## above the writs is fighting the same mechanism.
##
## That leaves growing the subject itself. The writs already carry 82% of the
## page's optical weight in one 227px band with voids above and below; making that
## band taller is the one move that spends the empty vertical space ON the
## decision rather than around it — no new elements (complexity is the punished
## direction), more room for the thing that IS the screen's question.
##
## THE FOOTER'S BOTTOM EDGE IS PRINTED BESIDE EVERY ROW, because this column lays
## out from `(900 - R) / 2` downward once its content outgrows its rect — so a
## taller row does not centre, it pushes the commit row toward the canvas edge.
## A composition win that walks BACK off the bottom of the screen is not a win.
func _tile_sweep() -> void:
	if _headless:
		return
	var tiles: Dictionary = _scene.get("_muster_writ_buttons")
	var list: Array[Control] = []
	for tid in tiles:
		var t: Control = tiles[tid]
		if is_instance_valid(t):
			list.append(t)
	if list.is_empty():
		print("[sb] tile sweep skipped — no writs")
		return
	var was: Vector2 = list[0].custom_minimum_size
	for h in [172, 210, 250, 290]:
		for t in list:
			t.custom_minimum_size = Vector2(was.x, float(h))
		await _settle()
		await get_tree().create_timer(0.25).timeout
		var foot := _scene.find_child("BonusBack", true, false) as Control
		var fb: float = -1.0
		if foot != null:
			fb = foot.global_position.y + foot.size.y
		print("[sb]   tile_h %d -> writ %.0fpx, footer bottom y=%.0f of 900%s"
			% [h, list[0].size.y, fb, "  OFF-CANVAS" if fb > 900.0 else ""])
		await _snap("tile_h%03d" % h)
		await _dump_regions_as("regions_t%03d" % h)
	for t in list:
		t.custom_minimum_size = was
	await _settle()


## THE LORD'S PLATE, SWEPT. The honest per-region shares say the four writs carry
## **82.07%** of the page's optical weight in one horizontal band while the whole
## top third carries about 1.2% — which is what "it still feels empty" measures
## as. The literature is explicit that the answer is NOT to add elements
## (complexity is the punished direction, and asymmetrically so), so the lever
## has to be an object already on the page.
##
## The lord IS that object: he is the reason there is a favour at all, so he is
## MEANING rather than decoration — and meaning is what drives every fixation
## after the first. He is also currently 118x158 on a 1920 page, a size borrowed
## from the two-column run-setup pane where he sits beside other things.
##
## Swept rather than chosen, and the guard rail is explicit: the writs must stay
## top of the squint ranking. RUN SETUP is on record as the failure mode, where
## the portrait took 31.7% of the page and the decision became the faintest thing
## on it.
func _plate_sweep() -> void:
	if _headless:
		return
	var plate := _scene.find_child("BonusHeroPlate", true, false) as Control
	if plate == null:
		print("[sb] plate sweep skipped — no BonusHeroPlate")
		return
	var was := plate.custom_minimum_size
	var ar: float = was.x / maxf(was.y, 1.0)
	for h in [158, 210, 260, 310, 360]:
		plate.custom_minimum_size = Vector2(roundf(float(h) * ar), float(h))
		await _settle()
		await get_tree().create_timer(0.25).timeout
		await _snap("plate_h%03d" % h)
		await _dump_regions_as("regions_h%03d" % h)
	plate.custom_minimum_size = was
	await _settle()


## A SWEEP MUST NOT OVERWRITE THE SETTLED SCREEN'S REGION LIST. It did, and the
## consequence was a measurement of `_bonus_full.png` graded against rects from
## whatever frame the last sweep happened to end on — which is how the title came
## to be reported at canvas y=10 when the container had it at 36.
func _dump_regions_as(tag: String) -> void:
	_regions_tag = tag
	await _dump_regions()
	_regions_tag = "regions"


## THE TABLE'S WEIGHT, SWEPT. `measure_screen_aesthetics.py` reported this layer
## holding **96.69% of the page's total optical weight over 57.5% of its area**,
## which drove the screen to bal-H 0.141 and 43% ink density — both outliers
## against every other screen in the shell (0.43-1.00 and 14-36%).
##
## The dial is one number, so it is derived rather than guessed: render the same
## settled screen at a ladder of layer alphas and let the measurement pick. Each
## frame is a real capture, so the tool that grades them is the same one that
## graded the defect.
func _table_sweep() -> void:
	if _headless:
		return
	var tbl := _scene.get_node_or_null("BonusTable") as Control
	if tbl == null:
		print("[sb] table sweep skipped — no BonusTable")
		return
	var was := tbl.modulate.a
	for a in [1.0, 0.70, 0.50, 0.35, 0.22, 0.12]:
		tbl.modulate.a = float(a)
		await get_tree().process_frame
		await get_tree().process_frame
		await _snap("sweep_a%03d" % int(float(a) * 100.0))
	tbl.modulate.a = was
	await get_tree().process_frame


## REGIONS for `tools/measure_screen_aesthetics.py --regions`, written from the
## REAL node rects rather than typed in by eye.
##
## The squint ranking is only as good as its region list, and hand-entered
## coordinates rot the first time a row moves — which on this screen is every
## time the other pane changes, since `fit_tile_height` grows a tile to its own
## copy. Dumping them from the live tree means the ranking always describes the
## screen that was just shot.
##
## SHOT pixel coordinates, so every rect goes through `_to_image`: layout is on
## the 1600x900 logical canvas and the capture comes back 1920x1080.
func _dump_regions() -> void:
	if _headless:
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out := {}
	var named := {
		"title": "BonusTitle", "lead": "BonusLead",
		"back": "BonusBack", "gloss": "BonusGloss",
		"hero_plate": "BonusHeroPlate",
	}
	for label in named:
		var n := _scene.find_child(String(named[label]), true, false) as Control
		if n != null and n.size.x > 1.0:
			out[label] = _rect_px(img, n)
	var tiles: Dictionary = _scene.get("_muster_writ_buttons")
	var i := 0
	for tid in tiles:
		var t: Control = tiles[tid]
		if is_instance_valid(t):
			out["writ_%d" % i] = _rect_px(img, t)
			i += 1
	# THE TABLE IS SPLIT INTO THE STRIPS THE WRITS DO NOT COVER, and that is not
	# tidiness — a share-of-weight figure is only meaningful over DISJOINT
	# regions. Dumped whole, the table rect [0,459,1920,1080] CONTAINS all four
	# sheets, so it reported 96.69% of the page's optical weight and read as one
	# decorative layer swamping the screen. It was measuring the writs. The
	# alpha sweep is what caught it: taking the layer to 12% moved balance from
	# 0.142 to 0.172 and left the region at 95.94%, which no single-cause story
	# survives.
	var tbl := _scene.get_node_or_null("BonusTable") as Control
	if tbl != null:
		var tr := _rect_px(img, tbl)
		var row_top: int = tr[3]
		var row_bot: int = tr[1]
		for k in out:
			if String(k).begins_with("writ_"):
				row_top = mini(row_top, int(out[k][1]))
				row_bot = maxi(row_bot, int(out[k][3]))
		if row_top > tr[1]:
			out["table_above"] = [tr[0], tr[1], tr[2], row_top]
		if row_bot < tr[3]:
			out["table_below"] = [tr[0], row_bot, tr[2], tr[3]]
	var f := FileAccess.open("res://tools/screenshot/bonus/%s.json" % _regions_tag,
		FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	print("[sb] regions.json — %d regions" % out.size())


func _rect_px(img: Image, n: Control) -> Array:
	var a := _to_image(img, n.global_position)
	var b := _to_image(img, n.global_position + n.size)
	return [int(a.x), int(a.y), int(b.x), int(b.y)]


## THE INK CENSUS. Fraction of canvas rows and columns carrying ink above the
## dark-table floor, and the tallest fully-empty horizontal band. A page pinned
## to the top of its rect shows up as one big band at the FOOT; a page of flat
## washes shows up as a healthy spread with nothing to look at, which is why the
## contrast spread is printed beside it.
func _census() -> void:
	if _headless:
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var floor_v := 0.085
	var rows_ink := 0
	var run := 0
	var worst_run := 0
	var worst_at := 0
	var lo := 2.0
	var hi := -1.0
	for y in range(0, h, 2):
		var inked := false
		for x in range(0, w, 3):
			var v: float = img.get_pixel(x, y).get_luminance()
			lo = minf(lo, v)
			hi = maxf(hi, v)
			if v > floor_v:
				inked = true
		if inked:
			rows_ink += 1
			run = 0
		else:
			run += 2
			if run > worst_run:
				worst_run = run
				worst_at = y
	print("[sb] ink rows %.0f%% · tallest empty band %dpx ending y=%d · luminance %.3f..%.3f"
		% [100.0 * float(rows_ink) / float(h / 2), worst_run, worst_at, lo, hi])


func _to_image(img: Image, p: Vector2) -> Vector2:
	var vis := get_viewport().get_visible_rect().size
	if vis.x <= 0.0 or vis.y <= 0.0:
		return p
	return p * (Vector2(img.get_size()) / vis)


func _zoom_at(focus: Vector2, tag: String, mag: int = 6,
		bw: int = 150, bh: int = 110) -> void:
	if _headless:
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var box := Vector2i(bw, bh)
	var org := Vector2i(_to_image(img, focus)) - box / 2
	org.x = clampi(org.x, 0, maxi(0, img.get_width() - box.x))
	org.y = clampi(org.y, 0, maxi(0, img.get_height() - box.y))
	var crop := img.get_region(Rect2i(org, box))
	# The scanline through the crop's middle, because a 2px stroke carrying a
	# 1px highlight is four pixels of argument at any magnification.
	var row: Array[String] = []
	for x in range(0, mini(crop.get_width(), 34)):
		row.append("%.2f" % crop.get_pixel(x, crop.get_height() / 2).get_luminance())
	print("[sb] %s scanline y=mid: %s" % [tag, " ".join(row)])
	crop.resize(box.x * mag, box.y * mag, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/_bonus_%s.png" % [SHOT_DIR, tag])
	_shots += 1
	print("[sb] SAVED _bonus_%s.png (%dx at %s)" % [tag, mag, str(Vector2i(focus))])


func _snap(tag: String) -> void:
	if _headless:
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/_bonus_%s.png" % [SHOT_DIR, tag])
	_shots += 1
	print("[sb] SAVED _bonus_%s.png (%dx%d)" % [tag, img.get_width(), img.get_height()])
