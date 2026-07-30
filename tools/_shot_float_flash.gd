extends Node
## _shot_float_flash.gd — pixel + geometry proof for the two 2026-07-28 fixes
## that docs/COMBAT_LEGIBILITY_20260728.md §11 #9 lists as UNCONFIRMED BY EYE.
## Windowed, editor closed:
##
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_shot_float_flash.tscn
##
## Both claims were verified arithmetically and by a clean run, never by a
## frame. Arithmetic cannot catch "the number is over the RIGHT card but the
## card moved", and it cannot catch "the ink is dark in the node tree but the
## shader washed it out on the way to the framebuffer". So this harness measures
## the rendered result twice over: once in node geometry, once in real pixels
## sampled out of the viewport image.
##
## ── CLAIM A — the damage number stays anchored on its victim ────────────────
## The float used to drift clear of the body that took it: captured at t=454 ms
## it was floating over a DIFFERENT creature's art. The fix is Card2D's
## `_float_anchor_y` (:3786) — start the numeral LOW enough that the 54 px rise
## (72 px when `big`) ENDS at `card_h * FLOAT_END_FRAC`, i.e. 16% down the
## card, instead of starting at the top edge and climbing off the token.
## Measured here by sampling the live Label's rect against the victim's rect
## across the whole 0.72 s rise — the interesting sample is the LAST one.
##
## ── CLAIM B — the hit flash must not wash out the wax seals ─────────────────
## `_flash_face_hit` (:4048) drives the baked face toward hot white
## (`flash` 0 → 0.75). If the numerals just sat there they would be
## near-white-on-white at the exact instant the new HP is the thing worth
## reading. The fix is in `_apply_hit_flash` (:4037): the ATK/HP labels are
## lerped toward FLASH_INK (0.20, 0.17, 0.14) on the SAME curve, so the ink
## darkens as the paper brightens. Verified here at the peak of the curve, in
## pixels, against an unflashed baseline of the same seals.
##
## Outputs tools/screenshot/_ff_*.png

const STATE_TIMEOUT := 60.0
const POLL := 0.2
const FLOAT_Z := 200
## _flash_face_hit's own ceiling — 0.75, not a full wash (see its note).
const FLASH_PEAK := 0.75

var _combat: Node = null
var _fail := 0
var _notes: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		print("[ff] WATCHDOG fired — never finished")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# This machine's saved settings have Reduce Motion ON — force the shipping
	# feel, or the harness photographs the accessibility fallback instead of the
	# thing under test.
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.particles = true
	# Screen shake is the ONE confound that would corrupt claim A: it offsets the
	# HUD CanvasLayer the float is parented to, which moves the numeral relative
	# to the board without the anchor being wrong. Off, so a drift measured here
	# is a real drift.
	UserSettings.screen_shake = false
	UserSettings.end_turn_warning = false

	RunState.start_new_run("raider")
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "borrowed_faces"
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number and keyword chip silently no-ops — which is the bug that made all
	# 24 shot harnesses blind in the first place.
	get_tree().current_scene = _combat
	_combat.set_process_input(false)
	_park_cursor()

	# Round 1 opens against an EMPTY hold: TAKE THE FIELD (2026-07-27) leaves
	# `_opening_muster_pending` standing and `_enemy_place_creatures` consumes it
	# inside `_post_combat_sequence`, so the enemy line lands at the END of round
	# 1. Never sleep for this — play into round 2 and poll for it.
	if not await _await_state(1, false, "round 1 player turn"):
		return
	_combat.call("_on_end_turn")
	if not await _await_state(2, true, "round 2 player turn with a live hold"):
		return
	print("[ff] staged at round %d — enemy bodies=%d" % [
		int(_combat.get("round_number")),
		(_combat.call("_all_enemy_creatures") as Array).size()])
	# Let the "ROUND 2" banner clear — 70px type across the middle of the arena
	# would sit on top of everything being photographed.
	await get_tree().create_timer(1.8).timeout

	# CLAIM B FIRST, deliberately. Claim A's staged blows (4 and 6 damage) kill
	# most of a starting hold, and an earlier ordering left claim B measuring the
	# one survivor — at 1/2 HP, with a single-digit HP seal. The flash claim is
	# about reading the seals, so it gets a full board and undamaged numerals.
	await _claim_b_flash_contrast()
	await _claim_a_float_anchor()

	print("")
	print("[ff] ============ RESULT ============")
	for n in _notes:
		print("[ff]   %s" % n)
	# A GDScript runtime error inside a claim aborts that coroutine and returns
	# here with its assertions simply missing — the harness printed "ALL PASS"
	# over a claim that never ran once already. Count the expected assertions so
	# a silent abort is a failure, not a clean sheet.
	var ran := 0
	for n in _notes:
		if String(n).begins_with("PASS") or String(n).begins_with("FAIL"):
			ran += 1
	if ran < 7:
		print("[ff] FAIL  only %d of 7 assertions ran — a claim aborted early (check for SCRIPT ERROR above)" % ran)
		_fail += 1
	print("[ff] %s" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	print("[ff] DONE")
	get_tree().quit(1 if _fail > 0 else 0)


# ── CLAIM A ─────────────────────────────────────────────────────────────────

func _claim_a_float_anchor() -> void:
	print("")
	print("[ff] === CLAIM A — the damage number stays on its victim ===")
	# A real encounter body, not a summoned token: tokens can lack a baked face,
	# and the historical drift capture was taken over real card art.
	var enemies: Array = _combat.call("_all_enemy_creatures")
	var victim = enemies[0]
	# THE VICTIM MUST SURVIVE ITS OWN DAMAGE NUMBER. First pass of this harness
	# hit a 2 HP body for 4 and photographed a correctly-anchored "-2" hanging
	# over an EMPTY lane — the card had died and been cleared, which looks
	# exactly like the drift bug under test and proves nothing either way. Give
	# the body enough life to still be standing when the rise ends.
	# Max HP is not a Card2D property — it is read from card_data["hp"] (see
	# Combat.gd:25705). Raise both or the HP seal prints "30/2".
	victim.card_data["hp"] = 30
	victim.current_hp = 30
	victim.call("update_stat_display")
	# update_stat_display is the house funnel that floats "+N HP" on a GAIN, so
	# topping the body up throws a green "+28 HP" of its own. Let it die before
	# the real measurement or it sits in frame next to the numeral under test.
	await get_tree().create_timer(1.2).timeout
	var vrect: Rect2 = victim.get_global_rect()
	print("[ff] victim '%s' rect %s (h=%.1f) hp=%d" % [
		String(victim.card_data.get("name", "?")), str(vrect), vrect.size.y,
		int(victim.current_hp)])

	# 4 damage — under the `heavy` threshold of 5, so this exercises the NORMAL
	# 54 px rise. The big variant is checked separately below.
	victim.call("take_damage", 4)
	await get_tree().process_frame

	var lbl := _newest_float()
	if lbl == null:
		_bad("CLAIM A: no floating number spawned at all — the VFX host is not wired")
		return

	# Sample across the whole rise. The position tween runs 0.72 s eased-out, so
	# the last sample is where the numeral COMES TO REST — the one that matters,
	# and the one the old build got wrong.
	var marks := [0.10, 0.25, 0.454, 0.60, 0.72]
	var prev := 0.0
	var rest_inside := false
	for t in marks:
		await get_tree().create_timer(float(t) - prev).timeout
		prev = float(t)
		if not is_instance_valid(lbl):
			break
		var c: Vector2 = lbl.get_global_rect().get_center()
		var inside_x: bool = c.x >= vrect.position.x and c.x <= vrect.end.x
		var inside_y: bool = c.y >= vrect.position.y and c.y <= vrect.end.y
		# How far ABOVE the token's top edge the numeral has climbed. Negative
		# means it is still on the card. This is the number that was positive
		# (drifted clear) in the old build.
		var above: float = vrect.position.y - c.y
		print("[ff]   t=%4d ms  centre=(%.0f, %.0f)  on-card x:%s y:%s  above-top=%+.0f px" % [
			int(t * 1000.0), c.x, c.y, str(inside_x), str(inside_y), above])
		if abs(t - 0.454) < 0.001:
			await _shoot("a_float_t454")
		if abs(t - 0.72) < 0.001:
			rest_inside = inside_x and inside_y
			await _shoot("a_float_rest")

	_check(rest_inside,
		"CLAIM A: the numeral ENDS its rise inside its own victim's rect")

	# The `big` numeral is the harder case: 72 px of rise instead of 54. If the
	# anchor did not compensate, this is the one that would climb off.
	await get_tree().create_timer(1.0).timeout
	var enemies2: Array = _combat.call("_all_enemy_creatures")
	if enemies2.size() >= 2:
		var v2 = enemies2[1]
		v2.card_data["hp"] = 30
		v2.current_hp = 30
		v2.call("update_stat_display")
		await get_tree().create_timer(1.2).timeout   # see the note above
		var r2: Rect2 = v2.get_global_rect()
		v2.call("take_damage", 6)      # >= 5 → heavy → the 72 px rise
		await get_tree().process_frame
		var l2 := _newest_float()
		if l2 != null:
			await get_tree().create_timer(0.72).timeout
			if is_instance_valid(l2):
				var c2: Vector2 = l2.get_global_rect().get_center()
				print("[ff]   BIG numeral at rest: centre=(%.0f, %.0f) victim %s" % [
					c2.x, c2.y, str(r2)])
				_check(c2.x >= r2.position.x and c2.x <= r2.end.x \
					and c2.y >= r2.position.y and c2.y <= r2.end.y,
					"CLAIM A: the BIG (>=5 dmg, 72px rise) numeral also ends on its victim")
				await _shoot("a_float_big_rest")
			else:
				_note("BIG numeral freed before the sample — inconclusive")
	await get_tree().create_timer(0.8).timeout


# ── CLAIM B ─────────────────────────────────────────────────────────────────

func _claim_b_flash_contrast() -> void:
	print("")
	print("[ff] === CLAIM B — the hit flash must not wash out the seals ===")
	var enemies: Array = _combat.call("_all_enemy_creatures")
	var card = enemies[0]
	var atk: Label = card.get("_atk_label")
	var hp: Label = card.get("_hp_label")
	var face = card.get("_compact_face")
	if atk == null or hp == null:
		_bad("CLAIM B: the token has no ATK/HP seal labels to measure")
		return
	# Which path fires matters: the ★4 baked-face flash is the one whose fix is
	# under test. The historical fallback tints the WHOLE node's modulate, seals
	# included, and would be a different (weaker) claim — so say which ran.
	var has_face: bool = face != null and is_instance_valid(face)
	print("[ff] baked face present: %s → %s path" % [
		str(has_face), "★4 _flash_face_hit" if has_face else "legacy modulate fallback"])
	_note("flash path exercised: %s" % (
		"_flash_face_hit (baked face)" if has_face else "legacy modulate fallback"))

	# Three regions, because the seal rect alone cannot tell the story:
	#   paper  — a strip of the baked face well clear of both seals. This is the
	#            control that proves the flash REACHED PIXELS at all. Without it
	#            a card that simply failed to flash would sail through every
	#            contrast assertion below.
	#   blob   — the whole _chart_seal Control (the wax disc), which is a sibling
	#            node drawn OVER _compact_face, not part of it.
	#   glyph  — the Label rect: the numeral itself.
	var blob_atk_rect: Rect2 = (atk.get_parent() as Control).get_global_rect()
	var blob_hp_rect: Rect2 = (hp.get_parent() as Control).get_global_rect()
	var cr: Rect2 = card.get_global_rect()
	var paper_rect := Rect2(cr.position + Vector2(cr.size.x * 0.30, cr.size.y * 0.10),
		Vector2(cr.size.x * 0.40, cr.size.y * 0.25))

	# ── Baseline: seals at rest, no flash. ──
	await get_tree().create_timer(0.4).timeout
	var base_paper := await _sample_rect(paper_rect)
	var base_blob := await _sample_rect(blob_atk_rect)
	var base_blob_hp := await _sample_rect(blob_hp_rect)
	var base_atk := await _sample_rect(atk.get_global_rect())
	var base_hp := await _sample_rect(hp.get_global_rect())
	await _shoot("b_seals_rest")
	await _shoot_crop("b_card_rest", cr)
	print("[ff]   REST  paper   : %s" % _fmt(base_paper))
	print("[ff]   REST  atk blob: %s" % _fmt(base_blob))
	print("[ff]   REST  hp  blob: %s" % _fmt(base_blob_hp))
	print("[ff]   REST  atk seal: %s" % _fmt(base_atk))
	print("[ff]   REST  hp  seal: %s" % _fmt(base_hp))

	# ── Peak: hold the flash at its ceiling. ──
	# The real tween reaches 0.75 in 0.05 s and leaves immediately; sampling that
	# with a timer is a race, so the value is parked instead.
	#
	# HARNESS TRAP, PAID FOR ONCE: _apply_hit_flash only pushes the shader
	# parameter `if _flash_mat != null`, and _flash_mat is built and installed on
	# _compact_face by _flash_face_hit — nowhere else. Calling _apply_hit_flash
	# cold therefore darkens the LABELS and leaves the paper untouched, which
	# looks exactly like a passing test (contrast preserved!) while proving
	# nothing. The paper control below is what caught it. So: fire the REAL
	# _flash_hit first to build and install the material, then freeze its tween
	# at the ceiling.
	if not card.has_method("_apply_hit_flash") or not card.has_method("_flash_hit"):
		_bad("CLAIM B: the flash entry points are gone — the harness needs updating")
		return
	card.call("_flash_hit")
	await get_tree().process_frame
	var tw = card.get("_flash_tween")
	if tw != null and tw.is_valid():
		tw.kill()
	card.call("_apply_hit_flash", FLASH_PEAK)
	await get_tree().process_frame
	print("[ff]   seal label modulate at peak: atk=%s hp=%s" % [
		str(atk.modulate), str(hp.modulate)])
	var peak_paper := await _sample_rect(paper_rect)
	var peak_blob := await _sample_rect(blob_atk_rect)
	var peak_blob_hp := await _sample_rect(blob_hp_rect)
	var peak_atk := await _sample_rect(atk.get_global_rect())
	var peak_hp := await _sample_rect(hp.get_global_rect())
	await _shoot("b_seals_flash_peak")
	await _shoot_crop("b_card_flash_peak", cr)
	print("[ff]   PEAK  paper   : %s" % _fmt(peak_paper))
	print("[ff]   PEAK  atk blob: %s" % _fmt(peak_blob))
	print("[ff]   PEAK  hp  blob: %s" % _fmt(peak_blob_hp))
	print("[ff]   PEAK  atk seal: %s" % _fmt(peak_atk))
	print("[ff]   PEAK  hp  seal: %s" % _fmt(peak_hp))
	print("[ff]   delta mean  paper %+.3f  atk blob %+.3f  hp blob %+.3f" % [
		float(peak_paper["mean"]) - float(base_paper["mean"]),
		float(peak_blob["mean"]) - float(base_blob["mean"]),
		float(peak_blob_hp["mean"]) - float(base_blob_hp["mean"])])

	# THE CONTROL. If the paper did not brighten, nothing below is evidence of
	# anything — the card simply never flashed and every contrast check would
	# pass for free. This is the assertion that gives the rest teeth.
	_check(float(peak_paper["mean"]) > float(base_paper["mean"]) + 0.02,
		"CLAIM B (control): the flash really did brighten the card's paper (%.3f -> %.3f)" % [
			float(base_paper["mean"]), float(peak_paper["mean"])])

	# THE MEASUREMENT. "Washed out" is specifically NUMERAL-AGAINST-ITS-PAPER
	# collapsing: the sheet goes hot while the glyph stays bright, and the two
	# meet in the middle. So the honest quantity is the SEPARATION between the
	# glyph's own ink and the flashed paper around it — not the spread inside the
	# label rect, which is dominated by the glyph's black outline and stays near
	# 1.0 whatever the flash does. (That was the first draft of this check, and
	# it passed even when the flash was not running at all.)
	#
	# Note the POLARITY FLIP this measures across, which is the whole design: at
	# rest the numeral is bright ivory on a dark wax seal; at the flash peak the
	# seal is hot and the numeral is dark ON it. Contrast is the same quantity in
	# both regimes, which is why it is the one asserted — a metric anchored to
	# "the ink is the bright pixels" would silently start reading the paper
	# instead the moment the flash inverted the card.
	for pair in [{"n": "ATK", "r": peak_atk, "b": base_atk},
			{"n": "HP", "r": peak_hp, "b": base_hp}]:
		var s: Dictionary = pair["r"]
		var b: Dictionary = pair["b"]
		print("[ff]   %s seal legibility: rest %.3f (%s ink) -> flash peak %.3f (%s ink)" % [
			pair["n"], float(b["legibility"]), "dark" if bool(b["dark_ink"]) else "light",
			float(s["legibility"]), "dark" if bool(s["dark_ink"]) else "light"])
		# 0.45 is a demanding floor: a genuine white-on-white washout leaves the
		# glyph indistinguishable from its seal (well under 0.10), while these
		# carry ~0.7-0.8 in both polarities. Passing it is not a rubber stamp.
		_check(float(s["legibility"]) >= 0.45,
			"CLAIM B: %s numeral stays legible against its seal at the flash peak (%.3f)" % [
				pair["n"], float(s["legibility"])])
	# THE POLARITY FLIP IS THE FIX. At rest the numeral is the BRIGHT thing on a
	# dark wax seal; at the peak the seal is bleached and the numeral must have
	# become the DARK thing on it. A numeral still reading "light" at the peak
	# means the ink tracked the paper upward — that is precisely the old
	# white-on-white washout, and it is what `_apply_hit_flash`'s lerp toward
	# FLASH_INK exists to prevent.
	_check(not bool(base_atk["dark_ink"]) and bool(peak_atk["dark_ink"]),
		"CLAIM B: the ATK numeral flips from light-on-dark to DARK-on-light under the flash")
	_check(not bool(base_hp["dark_ink"]) and bool(peak_hp["dark_ink"]),
		"CLAIM B: the HP numeral flips from light-on-dark to DARK-on-light under the flash")

	# The peak is one frame. The curve spends 0.22 s coming back DOWN from it
	# (against 0.05 s going up), so most of what a player actually sees is the
	# decay — sample the middle of it too, or the verdict is drawn entirely from
	# the single harshest instant the effect ever reaches.
	card.call("_apply_hit_flash", FLASH_PEAK * 0.5)
	await get_tree().process_frame
	var mid_atk := await _sample_rect(atk.get_global_rect())
	var mid_hp := await _sample_rect(hp.get_global_rect())
	await _shoot_crop("b_card_flash_mid", cr)
	print("[ff]   MID (%.2f) atk seal: %s" % [FLASH_PEAK * 0.5, _fmt(mid_atk)])
	print("[ff]   MID (%.2f) hp  seal: %s" % [FLASH_PEAK * 0.5, _fmt(mid_hp)])

	# Release it so the frame does not end mid-flash.
	card.call("_apply_hit_flash", 0.0)
	await get_tree().create_timer(0.3).timeout


# ── plumbing ────────────────────────────────────────────────────────────────

## Sample the rendered viewport inside `rect` (canvas coords) and report the
## luminance floor / mean / spread. The image comes back at the framebuffer's
## size, which is NOT the canvas size when the desktop applies DPI scaling
## (1600x900 canvas -> 1920x1080 image here), so map through the measured ratio
## rather than assuming 1:1.
func _sample_rect(rect: Rect2) -> Dictionary:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var ratio: float = float(img.get_width()) / maxf(vis.x, 1.0)
	var x0 := int(floor(rect.position.x * ratio))
	var y0 := int(floor(rect.position.y * ratio))
	var x1 := int(ceil(rect.end.x * ratio))
	var y1 := int(ceil(rect.end.y * ratio))
	x0 = clampi(x0, 0, img.get_width() - 1)
	y0 = clampi(y0, 0, img.get_height() - 1)
	x1 = clampi(x1, x0 + 1, img.get_width())
	y1 = clampi(y1, y0 + 1, img.get_height())
	var lum: Array[float] = []
	var sum := 0.0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var l: float = img.get_pixel(x, y).get_luminance()
			lum.append(l)
			sum += l
	lum.sort()
	var n := lum.size()
	# ── HOW THIS METRIC WAS GOT WRONG TWICE, AND WHAT FIXED IT ──────────────
	# 1st attempt, `max - min` over the rect: passed even with the flash not
	#    running at all, because the glyph's black outline pins min at 0.0
	#    regardless of what the paper does.
	# 2nd attempt, `p90 - p10`: FAILED the shipping build and would have been
	#    reported as a regression. It is wrong because the NUMERAL IS ONLY A FEW
	#    PERCENT OF THE LABEL RECT — at the flash peak p10 is still bleached
	#    seal (0.68), not ink. The magnified crop showed the glyphs rendering as
	#    dark charcoal with an intact black outline, i.e. perfectly legible,
	#    while the metric called them washed out.
	# The real difficulty is that the flash INVERTS the polarity: at rest the
	# numeral is white on a dark wax seal, at the peak it is dark on a bleached
	# one. So legibility is measured as "how far the ink sits from its
	# background, in EITHER direction" — p50 is the seal body, p02/p98 are the
	# ink under each polarity, and the larger excursion wins.
	var p02: float = lum[clampi(int(n * 0.02), 0, n - 1)]
	var p50: float = lum[clampi(int(n * 0.50), 0, n - 1)]
	var p98: float = lum[clampi(int(n * 0.98), 0, n - 1)]
	return {
		"min": lum[0], "max": lum[n - 1], "mean": (sum / float(maxi(n, 1))),
		"p02": p02, "p50": p50, "p98": p98,
		"legibility": maxf(absf(p98 - p50), absf(p02 - p50)),
		"dark_ink": absf(p02 - p50) >= absf(p98 - p50),
		"px": n, "ratio": ratio,
	}


func _fmt(s: Dictionary) -> String:
	return "ink p02=%.3f / seal p50=%.3f / p98=%.3f  legibility=%.3f (%s ink)  (%d px)" % [
		float(s["p02"]), float(s["p50"]), float(s["p98"]), float(s["legibility"]),
		"dark" if bool(s["dark_ink"]) else "light", int(s["px"])]


## The most recently spawned floating number: a Label parked on Combat's HUD
## layer at z_index 200. Every other Label there is HUD furniture, so the
## z-index is the honest discriminator (same rule _shot_vfx_host uses).
func _newest_float() -> Label:
	var hud = _combat.get("_hud_layer")
	if hud == null or not is_instance_valid(hud):
		return null
	var best: Label = null
	for ch in hud.get_children():
		if ch is Label and int(ch.z_index) == FLOAT_Z:
			best = ch
	return best


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail += 1
	print("[ff] %s  %s" % ["PASS" if ok else "FAIL", what])
	_notes.append("%s  %s" % ["PASS" if ok else "FAIL", what])


func _bad(what: String) -> void:
	_fail += 1
	print("[ff] FAIL  %s" % what)
	_notes.append("FAIL  %s" % what)


func _note(what: String) -> void:
	_notes.append("note  %s" % what)


func _await_state(min_round: int, want_enemies: bool, what: String) -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if _combat == null or not is_instance_valid(_combat):
			print("[ff] ABORT — combat scene gone while waiting for ", what)
			get_tree().quit(1)
			return false
		if int(_combat.get("round_number")) >= min_round \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN \
				and (not want_enemies
					or (_combat.call("_all_enemy_creatures") as Array).size() > 0):
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("[ff] ABORT — timed out waiting for ", what)
	get_tree().quit(1)
	return false


## Shove the REAL desktop cursor into the top-left corner, clear of the board.
## `set_process_input(false)` stops keystrokes but NOT mouse hover — that
## arrives through mouse_entered / _gui_input on the cards themselves. A run
## whose victim happened to land under the parked pointer photographed the
## card wearing its hover targeting overlay ("HELD", INCOMING chip) with the
## damage numeral hidden behind it. Which lane the victim occupies varies per
## run, so this has to be handled, not hoped past.
func _park_cursor() -> void:
	Input.warp_mouse(Vector2(4, 4))


func _shoot(tag: String) -> void:
	_park_cursor()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_ff_%s.png" % tag)
	print("[ff] SAVED _ff_%s.png  %s" % [tag, str(img.get_size())])


## Crop `rect` (canvas coords) out of the rendered frame and blow it up, nearest
## neighbour, so the seals can be JUDGED and not merely measured. A 200x150
## token inside a 1920x1080 frame is ~40 px of numeral — too small to call
## readable or not by eye in the full shot, which is how "the numerals stay
## readable" stayed unverified in the first place.
func _shoot_crop(tag: String, rect: Rect2, zoom: int = 4) -> void:
	_park_cursor()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var ratio: float = float(img.get_width()) / maxf(vis.x, 1.0)
	var r := Rect2i(
		Vector2i(int(rect.position.x * ratio), int(rect.position.y * ratio)),
		Vector2i(int(rect.size.x * ratio), int(rect.size.y * ratio)))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		print("[ff] crop '%s' fell outside the frame — skipped" % tag)
		return
	var cut := img.get_region(r)
	cut.resize(cut.get_width() * zoom, cut.get_height() * zoom,
		Image.INTERPOLATE_NEAREST)
	cut.save_png("res://tools/screenshot/_ff_%s.png" % tag)
	print("[ff] SAVED _ff_%s.png  %s (crop x%d)" % [tag, str(cut.get_size()), zoom])
