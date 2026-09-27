extends Node
## _shot_muster.gd — LOOK AT THE ROUND-1 MUSTER MARK.
##
##   Godot_v4.6.2-stable_win64.exe --path "D:\Godot" res://tools/_shot_muster.tscn
##
## The one combat state no harness had ever photographed. `_shot_forecast`
## (2026-09-16) ends its own round 1 in its third line in order to get a board
## with bodies on it, so the muster round is the frame every combat tool skips on
## its way somewhere else — which is how four rounded `Label` pills reading
## "MUSTER  ?" survived the pass that deleted exactly that construction from the
## lane forecast.
##
## FOUR QUESTIONS, and three of them are arithmetic rather than taste.
##
##  1. THE CENSUS. A `Label` or a `PanelContainer` in the mark's node list means
##     the board is wearing web-page chrome again. This is the same oracle
##     `_shot_forecast` runs, pointed at the other overlay.
##  2. THE TRUTH ORACLE. One mark per planned slot, no more and no fewer, and
##     every planned slot standing on ground the hold can actually take — empty,
##     and not shut by a set-piece's closed ground.
##  3. THE PROMISE, which is the one that matters. The mark now claims to show
##     WHERE THE HOLD WILL STAND, so the harness drives the real muster and
##     asserts the bodies landed on exactly those slots. Everything else here
##     judges how the mark looks; this judges whether it is telling the truth.
##  4. THE EYES. 3x nearest-neighbour zooms — the `_shot_coach_devices`
##     precedent. Whether a pike's lit edge is a sliver or has washed the shaft,
##     whether the dust's far edge is ragged or ruled, and whether a standard
##     reads as cloth are not decidable at 1600x900. Judge this pass on the
##     zooms; the full frame only answers "how loud is it".
##
## Headless runs print every measurement and skip the PNGs (get_image is blank
## under the dummy renderer), so the oracle is CI-able and only the eyes need a
## display.
##
## DO NOT run this at the same time as `tools/run_ui_gates.ps1` or
## `_shot_forecast` — they all open real windowed Godot instances and competing
## for the display produces a run that exits 0 having printed nothing.

const SHOT_DIR := "res://tools/screenshot/muster"
const ENC := "bandit_camp"
const STATE_TIMEOUT := 90.0
const POLL := 0.2

var _combat: Node = null
var _shots := 0
var _headless := false
var _problems: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[ms] WATCHDOG — never finished")
		get_tree().quit(1))

	_headless = DisplayServer.get_name() == "headless"
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	if not _headless:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))
		DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	# Ship settings, not this machine's. Reduce Motion in particular would
	# photograph the held fallback and answer a different question.
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.particles = true
	UserSettings.combat_telegraph = true
	UserSettings.end_turn_warning = false
	# The guided first-battle walkthrough owns the screen on round 1 of a fresh
	# profile and would scrim the very thing this shoots.
	UserSettings.mark_first_battle_tutorial_complete()
	for m in ["mark_combat_model_tutorial_seen", "mark_intents_tutorial_seen",
			"mark_pile_tutorial_seen", "mark_dismiss_tutorial_seen",
			"mark_banking_tutorial_seen", "mark_floop_tutorial_seen",
			"mark_sacrifice_tutorial_seen"]:
		if UserSettings.has_method(m):
			UserSettings.call(m)

	RunState.start_new_run("stalwart")
	RunState.current_act_idx = 1
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = ENC
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	get_tree().current_scene = _combat
	_combat.set_process_input(false)
	Input.warp_mouse(Vector2(4, 4))
	await get_tree().process_frame
	get_viewport().gui_disable_input = true

	if not await _await_muster():
		return
	# The band arrives on a deferred call and then runs a 0.95s `settle`. Let it
	# finish, or the first frame photographs a half-risen bank and every
	# measurement below reads a mark that is still fading in.
	await get_tree().create_timer(1.6).timeout

	_census()
	_geometry()
	_truth_oracle()

	await _shoot("muster_board")
	await _zoom_band(0, "muster_band")
	await _zoom_pike("muster_pike")
	await _zoom_standard("muster_standard")

	# DRIFT. A still frame cannot tell a moving cloud from a painted one, and the
	# whole argument for a shader here is that it is not painted. Two frames far
	# enough apart to be obviously different, plus the shader's own travel
	# reported as a number so headless can see it too.
	var before := _drift_of(0)
	await get_tree().create_timer(2.4).timeout
	var after := _drift_of(0)
	print("[ms] drift over 2.4s: %.4f -> %.4f (delta %.4f)" % [
		before, after, after - before])
	# HEADLESS IS SUPPOSED TO BE FROZEN — the painter holds a pinned drift and
	# never starts processing without a display, the same contract Reduce Motion
	# gets. Asserting movement here would fail the CI-able half of this harness
	# for the painter doing exactly what it promises.
	if not _headless and absf(after - before) < 0.02:
		_problems.append("the bank is not moving (drift delta %.4f)" % (after - before))
	await _shoot("muster_board_drifted")
	await _zoom_band(0, "muster_band_drifted")

	await _shoot_reduced()
	await _verify_plan_kept()
	# LAST, and the order is not arbitrary: this re-plans, which consumes RNG and
	# hands the scene a DIFFERENT opening from the one currently drawn on it. Run
	# before the promise check it silently desynced the mark on screen from the
	# plan being verified — the harness inventing the exact defect it exists to
	# catch.
	_verify_reactive_is_silent()

	print("[ms] frames written: %d -> %s" % [_shots, SHOT_DIR])
	if _problems.is_empty():
		print("[ms] MUSTER_SHOT_DONE")
	else:
		for p in _problems:
			print("[ms] PROBLEM: ", p)
		print("[ms] MUSTER_SHOT_DONE_WITH_FINDINGS")
	get_tree().quit()


# ── the measurements ───────────────────────────────────────────────────────

func _marks() -> Array:
	var raw = _combat.get("_opening_muster_forecast")
	var out: Array = []
	for n in (raw as Array):
		if n != null and is_instance_valid(n):
			out.append(n)
	return out


## Chrome check. The rebuilt mark should be a drawn Control plus a shader quad —
## a `Label` or a rounded `PanelContainer` anywhere in it means the board has
## grown a web page again.
func _census() -> void:
	var marks := _marks()
	print("[ms] muster marks: %d" % marks.size())
	if marks.is_empty():
		_problems.append("no muster mark on screen at all during the muster round")
		return
	var by_class: Dictionary = {}
	var chrome := 0
	for m in marks:
		for n in _walk(m):
			var k: String = n.get_class()
			by_class[k] = int(by_class.get(k, 0)) + 1
			if n is Label or n is PanelContainer or n is Button:
				chrome += 1
				print("[ms]   CHROME: %s %s" % [k, String(n.name)])
	var parts: Array[String] = []
	for k in by_class:
		parts.append("%s=%d" % [k, int(by_class[k])])
	parts.sort()
	print("[ms] mark node census: %s" % ", ".join(parts))
	if chrome > 0:
		_problems.append("%d UI-chrome nodes in the muster mark" % chrome)


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _geometry() -> void:
	print("[ms] --- board geometry ---")
	for row in [0, 1]:
		for lane in range(4):
			var slot = _slot(row, lane)
			if slot == null:
				continue
			print("[ms]   enemy %s lane %d slot %s  occupied=%s" % [
				"front" if row == 0 else "back ", lane,
				_r(slot.get_global_rect()),
				str(_combat.call("_row_array", true, row)[lane] != null)])
	for i in _marks().size():
		var m: Control = _marks()[i]
		print("[ms]   band %d %s  z=%d  pikes=%d" % [
			i, _r(Rect2(m.global_position, m.size)), m.z_index,
			(m.get("_pikes") as Array).size()])


## THE MARK MUST STAND ON THE PLAN, AND THE PLAN ON OPEN GROUND. One mark per
## planned slot, no more and no fewer — a mark that is not in the plan is a claim
## the game cannot cash, and a planned slot with no mark is ground that fills
## without warning.
func _truth_oracle() -> void:
	var plan: Array = _plan()
	var marks := _marks()
	print("[ms] plan: %s" % _fmt_slots(plan))
	if marks.size() != plan.size():
		_problems.append("%d marks for a %d-slot plan" % [marks.size(), plan.size()])
	var bad := 0
	for s in plan:
		var row := int(s["row"])
		var lane := int(s["lane"])
		if _combat.call("_row_array", true, row)[lane] != null:
			bad += 1
			print("[ms]   PLANNED ONTO A BODY: row %d lane %d" % [row, lane])
		elif bool(_combat.call("_sp_lane_closed", lane)):
			bad += 1
			print("[ms]   PLANNED ONTO CLOSED GROUND: row %d lane %d" % [row, lane])
	print("[ms] truth oracle: %d planned slots the hold cannot take" % bad)
	if bad > 0:
		_problems.append("%d planned slots are occupied or closed" % bad)


## THE CLAIM, not the stored order. `_opening_muster_plan` ranks every legal slot
## so the seating can fall through when one is taken; only its first
## `_opening_muster_count` entries are what the mark promises.
func _plan() -> Array:
	var raw = _combat.call("_opening_muster_claim")
	return (raw as Array) if raw != null else []


func _fmt_slots(arr: Array) -> String:
	var parts: Array[String] = []
	for s in arr:
		parts.append("%s%d" % ["F" if int(s["row"]) == 0 else "B", int(s["lane"])])
	parts.sort()
	return "[" + " ".join(parts) + "]" if not parts.is_empty() else "[]"


## Enemy-side occupancy as a comparable set of slot keys.
func _occupied() -> Array:
	var out: Array = []
	for row in [0, 1]:
		for lane in range(4):
			if _combat.call("_row_array", true, row)[lane] != null:
				out.append({"row": row, "lane": lane})
	return out


## THE OTHER HALF OF THE PROMISE: a mark that cannot be honest must not appear.
##
## Under THE INITIATIVE's GO FIRST the hold answers the line you set, so its
## ground does not exist until you commit — and the failure mode if that branch
## were wrong is the worst one available here, a confident telegraph pointing at
## slots chosen by a roll that has not happened. Checked by flipping the live
## scene's `_initiative` and re-planning rather than by booting an elite: headless
## auto-takes the first option on the initiative modal, so an elite would reach
## this state by a route the harness cannot steer.
func _verify_reactive_is_silent() -> void:
	var keep = _combat.get("_initiative")
	_combat.set("_initiative", "field")
	_combat.call("_plan_opening_muster")
	var plan := _plan()
	print("[ms] --- reactive opening ---")
	print("[ms] plan when the hold answers your line: %s (want empty)"
		% _fmt_slots(plan))
	if not plan.is_empty():
		_problems.append(
			"a reactive opening published a plan (%s) it cannot know yet"
				% _fmt_slots(plan))
	if int(_combat.get("_opening_muster_count")) <= 0:
		_problems.append("the reactive opening lost its body count")
	# Put the fight back the way it was found, and re-plan, or the promise check
	# below measures a scene this function broke.
	_combat.set("_initiative", keep)
	_combat.call("_plan_opening_muster")


## THE PROMISE, AND THE ONLY CHECK THAT NOW MATTERS. The mark says where the hold
## will stand; this ends the turn, lets the real muster deal, and asserts the
## bodies landed on exactly those slots and no others.
##
## It subtracts the PRE-MUSTER occupancy first, because a fight's structures and
## a siege fight's gates are already standing before round 1 and are not part of
## the opening — comparing raw board state would fail every encounter that has
## scenery, which is the harness accusing the game of its own arithmetic.
func _verify_plan_kept() -> void:
	var plan := _fmt_slots(_plan())
	var before := _occupied()
	print("[ms] --- the promise ---")
	print("[ms] before the deal: %s occupied" % _fmt_slots(before))
	# DRIVEN THROUGH THE MUSTER'S OWN ENTRY POINT, NOT THROUGH END TURN. The first
	# version pressed END TURN and compared at round 2, and reported "THE MARK
	# LIED — planned [F1], dealt [F0 F1]" against a mark that was telling the
	# truth: `bandit_camp`'s passive summons a Raider at the start of round 2, so
	# the board it measured was the muster PLUS a passive. `_enemy_place_creatures`
	# is the real beat and only that beat — it clears the forecast (so the
	# dispersal below is the genuine one) and deals the opening without advancing
	# the round or firing anything else.
	#
	# Un-awaited on purpose: the dissolve has to be photographed mid-flight, and
	# awaiting the deal first would only ever produce a settled board.
	_combat.call("_enemy_place_creatures")
	await get_tree().create_timer(0.30).timeout
	await _shoot("muster_dissolve")
	await get_tree().create_timer(1.6).timeout
	var added: Array = []
	for s in _occupied():
		var seen := false
		for b in before:
			if int(b["row"]) == int(s["row"]) and int(b["lane"]) == int(s["lane"]):
				seen = true
				break
		if not seen:
			added.append(s)
	var dealt := _fmt_slots(added)
	print("[ms] planned: %s" % plan)
	print("[ms] dealt:   %s" % dealt)
	if dealt != plan:
		_problems.append(
			"THE MARK LIED — planned %s, dealt %s" % [plan, dealt])
	else:
		print("[ms] the hold stood exactly where the mark said")
	await _shoot("muster_after")



func _drift_of(idx: int) -> float:
	var marks := _marks()
	if idx >= marks.size():
		return 0.0
	return float(marks[idx].get("_drift"))


# ── the staged cases ───────────────────────────────────────────────────────

## REDUCE MOTION HOLDS AN INFORMATIONAL OVERLAY; IT DOES NOT DELETE ONE. The mark
## states a rule of the round, so a player who has turned motion off still has to
## be told it — what they lose is the drift and the arrival, not the telegraph.
##
## Worth a frame rather than a code read, because the failure mode here is
## INVISIBLE in the source: `settle()` returns early under the setting, and if the
## entrance had been the thing that raised `modulate.a` off zero, "returns early"
## and "never appears at all" would be the same line of code. Asserted on ink, not
## on the flag.
func _shoot_reduced() -> void:
	UserSettings.reduce_motion = true
	_combat.call("_clear_opening_muster_forecast", false)
	_combat.set("_opening_muster_forecast", [] as Array[Control])
	await _combat.call("_show_opening_muster_forecast")
	await get_tree().create_timer(0.5).timeout
	var marks := _marks()
	print("[ms] --- reduce motion ---")
	print("[ms] marks with reduce_motion on: %d" % marks.size())
	if marks.is_empty():
		_problems.append("reduce motion DELETED the muster mark instead of holding it")
	else:
		var m: Control = marks[0]
		var processing: bool = m.is_processing()
		print("[ms]   modulate.a %.2f  processing %s  drift %.3f" % [
			m.modulate.a, str(processing), float(m.get("_drift"))])
		if m.modulate.a < 0.9:
			_problems.append("reduce motion left the mark at alpha %.2f" % m.modulate.a)
		if processing:
			_problems.append("reduce motion left the mark animating")
	await _shoot("muster_reduced")
	UserSettings.reduce_motion = false


# ── shooting ───────────────────────────────────────────────────────────────

func _shoot(tag: String) -> void:
	if _headless:
		return
	Input.warp_mouse(Vector2(4, 4))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT_DIR, tag])
	_shots += 1
	print("[ms] SAVED %s.png %s" % [tag, str(img.get_size())])


## 3x nearest-neighbour, cropped on the LEFT END of a band — the end is where the
## `rim` erosion has to prove it frays rather than stops, and it carries pike
## tips, the dust's far edge and bare table in one frame.
func _zoom_band(idx: int, tag: String) -> void:
	var marks := _marks()
	if idx >= marks.size():
		print("[ms] no band %d — zoom skipped" % idx)
		return
	var m: Control = marks[idx]
	await _zoom_at(m.global_position + Vector2(m.size.x * 0.26, m.size.y * 0.62), tag)


## Centred on a standard, which is the one element that has to read as CLOTH.
func _zoom_standard(tag: String) -> void:
	var marks := _marks()
	if marks.is_empty():
		return
	var m: Control = marks[0]
	for p in (m.get("_pikes") as Array):
		if not bool(p.get("banner", false)):
			continue
		await _zoom_at(m.global_position + Vector2(
			float(p["x"]), m.size.y * 0.70 - float(p["h"]) - 6.0), tag)
		return
	print("[ms] no standard in band 0 — zoom skipped")


## ONE SHAFT AT 8x. The 3x band frame answers "does the rank read as an army";
## it cannot answer "which of the two colours in a pike is winning", and that is
## the question the first two renders both got wrong. Centred on the TALLEST
## shaft in the band, upper third, where the dust is thin and the steel is
## supposed to be carrying itself.
func _zoom_pike(tag: String) -> void:
	if _headless:
		return
	var marks := _marks()
	if marks.is_empty():
		return
	var m: Control = marks[0]
	var best: Dictionary = {}
	for p in (m.get("_pikes") as Array):
		if bool(p.get("banner", false)):
			continue
		if best.is_empty() or float(p["h"]) > float(best["h"]):
			best = p
	if best.is_empty():
		return
	# The shaft LEANS, so its x at any height is not its foot's x — following the
	# same arithmetic the painter uses rather than eyeballing the column.
	var h: float = float(best["h"])
	var frac := 0.55
	var focus := m.global_position + Vector2(
		float(best["x"]) + sin(float(best["lean"])) * h * frac,
		m.size.y * 0.88 - h * frac)
	Input.warp_mouse(Vector2(4, 4))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var box := Vector2i(120, 90)
	var org := Vector2i(_to_image(img, focus)) - box / 2
	org.x = clampi(org.x, 0, img.get_width() - box.x)
	org.y = clampi(org.y, 0, img.get_height() - box.y)
	var crop := img.get_region(Rect2i(org, box))
	# The numbers, so a later pass does not have to squint at a PNG the way this
	# one did: darkest and lightest pixel in the crop, and where they are.
	var lo := 2.0
	var hi := -1.0
	for y in crop.get_height():
		for x in crop.get_width():
			var v: float = crop.get_pixel(x, y).get_luminance()
			lo = minf(lo, v)
			hi = maxf(hi, v)
	print("[ms] pike micro-crop luminance: min %.3f max %.3f" % [lo, hi])
	# THE SCANLINE, and it is the only thing that settled this. Two renders were
	# spent arguing from the geometry about which of a pike's two colours was
	# winning, and a 3x PNG cannot answer it: a 5px shaft carrying a 1px highlight
	# is four pixels of argument. Printing the row across the shaft says outright
	# whether the dark core or the lit edge owns the stroke.
	var mid := box / 2
	var row: Array[String] = []
	for x in range(maxi(0, mid.x - 12), mini(crop.get_width(), mid.x + 13)):
		row.append("%.2f" % crop.get_pixel(x, mid.y).get_luminance())
	print("[ms] scanline across the shaft (centre at index 12):")
	print("[ms]   ", " ".join(row))
	crop.resize(box.x * 8, box.y * 8, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [SHOT_DIR, tag])
	_shots += 1
	print("[ms] SAVED %s.png (8x zoom at %s)" % [tag, str(Vector2i(focus))])


## A CONTROL'S `global_position` IS NOT A PIXEL IN THE CAPTURE, and assuming it
## is cost this harness two renders of wrong conclusions. The board lays out on
## the 1600x900 logical canvas while `get_texture().get_image()` comes back at
## the real render size — 1920x1080 here — so every crop centre was 20% short and
## landed up and to the left of what it was named after. Wide crops survive that
## (the feature is still somewhere in frame, which is exactly why it went
## unnoticed); a 120px micro-crop does not, and its scanline read bare table.
func _to_image(img: Image, p: Vector2) -> Vector2:
	var vis := get_viewport().get_visible_rect().size
	if vis.x <= 0.0 or vis.y <= 0.0:
		return p
	return p * (Vector2(img.get_size()) / vis)


func _zoom_at(focus: Vector2, tag: String) -> void:
	if _headless:
		return
	Input.warp_mouse(Vector2(4, 4))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var box := Vector2i(330, 230)
	var org := Vector2i(_to_image(img, focus)) - box / 2
	org.x = clampi(org.x, 0, img.get_width() - box.x)
	org.y = clampi(org.y, 0, img.get_height() - box.y)
	var crop := img.get_region(Rect2i(org, box))
	crop.resize(box.x * 3, box.y * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [SHOT_DIR, tag])
	_shots += 1
	print("[ms] SAVED %s.png (3x zoom at %s)" % [tag, str(Vector2i(focus))])


# ── boot ───────────────────────────────────────────────────────────────────

func _slot(row: int, lane: int):
	var arr = _combat.call("_slot_array", true, row)
	if arr == null or lane >= (arr as Array).size():
		return null
	var s = (arr as Array)[lane]
	return s if (s != null and is_instance_valid(s)) else null


func _r(r: Rect2) -> String:
	return "[%d,%d %dx%d]" % [int(r.position.x), int(r.position.y),
		int(r.size.x), int(r.size.y)]


## Round 1, player's turn, opening still pending — the state this harness exists
## for and the one every other combat tool ends before it looks at anything.
func _await_muster() -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if _combat == null or not is_instance_valid(_combat):
			print("[ms] ABORT — combat scene gone")
			get_tree().quit(1)
			return false
		if int(_combat.get("round_number")) == 1 \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN \
				and bool(_combat.get("_opening_muster_pending")):
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("[ms] ABORT — timed out waiting for the muster round")
	get_tree().quit(1)
	return false
