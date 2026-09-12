extends Node
## _shot_fx_rebuild.gd — eyes on the two findings of the FX technique audit
## (tools/_fx_technique_audit.py, 2026-09-09). Windowed, editor closed:
##
##   Godot_v4.6.2-stable_win64.exe --path "D:\Godot" res://tools/_shot_fx_rebuild.tscn
##
## Both were the ring engine's defect in a different costume — an ENERGY effect
## built from a bare flat primitive:
##
##   _spawn_lightning_bolt   one flat 4px Line2D, five random bumps, no glow,
##                           no core. Now midpoint-displacement + halo/bolt/
##                           white-hot-core + forks.
##   _play_face_damage_flash a UNIFORM full-screen red ColorRect plus a
##                           StyleBoxFlat border band — while its own comment
##                           asked for "blood at the EDGES of your vision" and
##                           warned it must never mask the damage numeral it
##                           punctuates. Now one aspect-corrected vignette,
##                           zero at the centre by construction.
##
## The vignette frame is the one worth measuring rather than admiring: the whole
## claim is CENTRE STAYS CLEAR, so the pass samples centre ink against edge ink
## and fails if the centre is not far quieter.
##
## Writes tools/screenshot/_fxr_*.png.

const ENC := "borrowed_faces"

var _fail := 0
var _baseline: Image = null
var _combat: Node = null
var _lines := 0
var _rings_seen := 0


## Live ring nodes. Motion.ring builds a Sprite2D over a cached blank quad, so on
## a layer whose only other FX are Line2D beams the type is unambiguous.
func _count_rings() -> int:
	if _combat == null or not is_instance_valid(_combat):
		return 0
	var hud = _combat.get("_hud_layer")
	if hud == null or not is_instance_valid(hud):
		return 0
	var n := 0
	for c in hud.get_children():
		if c is Sprite2D:
			n += 1
	return n


## How many bolt segments are alive right now. The pixel diff cannot tell a
## missing stroke from a dim one; this can.
func _count_lines() -> int:
	if _combat == null or not is_instance_valid(_combat):
		return 0
	var hud = _combat.get("_hud_layer")
	if hud == null or not is_instance_valid(hud):
		return 0
	var n := 0
	for c in hud.get_children():
		if c is Line2D:
			n += 1
	return n


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[fxr] WATCHDOG fired — never finished")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.particles = true
	UserSettings.screen_shake = false   # keep the frame square for measuring

	RunState.start_new_run("raider", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = ENC
	await get_tree().process_frame

	var combat: Node = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(combat)
	get_tree().current_scene = combat
	_combat = combat
	if not await _wait_for_player_turn(combat, 60.0):
		print("[fxr] FAIL — never reached the player's turn")
		get_tree().quit(1)
		return

	# ── The bolt, sampled ACROSS ITS LIFE ────────────────────────────────
	# A flicker cannot be judged from one frame. The bolt is three overlapping
	# strokes on offset cycles (0 / 0.048 / 0.096s, each ~0.165s), so this walks
	# the whole discharge: consecutive frames must differ, or it is one static
	# bolt again wearing a nicer texture.
	var vp: Vector2 = combat.get_viewport_rect().size
	var a := Vector2(vp.x * 0.20, vp.y * 0.16)
	var b := Vector2(vp.x * 0.72, vp.y * 0.62)
	# A CLEAN PLATE FIRST. Hue is the wrong discriminator for this effect — the
	# core mixes to WHITE (so blue never exceeds red) and the halo is too
	# transparent to shift the warm board's hue at all. Diffing against a
	# bolt-free frame isolates exactly the pixels the bolt touched, whatever
	# colour they came out.
	_baseline = await _grab()
	combat.call("_spawn_lightning_bolt", a, b, Color(0.85, 0.95, 1.0, 1.0))
	# GRAB FIRST, ANALYSE AFTER. Scanning ~19k pixels and writing a PNG between
	# samples costs far more than the nominal gap, so the taps drifted right and
	# the whole 0.165s discharge was over by the third one — the harness
	# measuring itself, not the bolt. Collect frames at speed, then think.
	var frames: Array[Image] = []
	var counts: Array[int] = []
	var prev := 0.0
	# The FIRST tap has almost no drift (one baseline grab before it); every tap
	# after it pays for the previous get_image(). So the instant that most needs
	# to be caught exactly — the return stroke plus the strike bloom at ~0.048s —
	# is placed first, and the rest walk the decay.
	for t in [0.075, 0.11, 0.16, 0.24, 0.34, 0.46]:
		await get_tree().create_timer(maxf(float(t) - prev, 0.0)).timeout
		prev = float(t)
		counts.append(_count_lines())
		_rings_seen = maxi(_rings_seen, _count_rings())
		await RenderingServer.frame_post_draw
		frames.append(get_viewport().get_texture().get_image())
	var inks: Array[float] = []
	for i in frames.size():
		var nm := "bolt_%d" % i
		frames[i].save_png("res://tools/screenshot/_fxr_%s.png" % nm)
		var lit := _ink(frames[i])
		inks.append(lit)
		print("[fxr] SAVED _fxr_%s.png  lit=%d  bolt_lines=%d"
			% [nm, int(lit), maxi(counts[i] - 2, 0)])
	print("")
	print("[fxr] ============ BOLT: IT MUST FLICKER ============")
	print("[fxr]   lit px per frame across the discharge: %s" % str(inks))
	# ASSERT ON THE NODE COUNT, NOT ON INK. The pixel diff was a drifting proxy:
	# each get_image() costs real time, so by the third tap the whole 0.165s
	# discharge is over and every later frame reports the same static floor —
	# which then reads as "the bolt stopped changing". Worse, a pixel diff cannot
	# tell a MISSING stroke from a dim one.
	#
	# `bolt_lines` measures the actual claim directly. One stroke is a trunk plus
	# its forks, so a peak of 6+ means at least two discharges were alive AT THE
	# SAME TIME — which is what "it flickers" means — and reaching 0 proves they
	# clear instead of piling up into one thickening bolt.
	var peak := 0
	var cleared := false
	for c in counts:
		var n: int = maxi(c - 2, 0)   # minus the 2 standing HUD lines
		peak = maxi(peak, n)
		if n == 0 and peak > 0:
			cleared = true
	_check(peak >= 6,
		"strokes OVERLAP — two discharges alive at once (peak %d segments)" % peak)
	_check(cleared, "and they clear, rather than piling into one bolt")
	var moved := 0
	for i in range(1, inks.size()):
		if absf(inks[i] - inks[i - 1]) > 40.0:
			moved += 1
	_check(moved >= 1, "the bolt visibly changes the board (%d step(s) moved)"
		% moved)
	# THE STRIKE BLOOM, verified by NODE rather than by eye. It fires 0.048s in,
	# at the bolt's landing point, and every frame that catches it also catches
	# the bolt's own brightness — so it could not be judged from a screenshot and
	# had been left as an unverified claim. Motion.ring builds a Sprite2D and the
	# bolt builds Line2Ds, so the node type is an unambiguous discriminator.
	_check(_rings_seen > 0,
		"the strike bloom actually fires at the landing point (%d ring node(s))"
			% _rings_seen)

	# ── The strike arc: light blow beside heavy ──────────────────────────
	# It fires on every attack in the game and was a glow band + a body band +
	# a conditional hot band. One textured beam now; `heat` carries what the
	# third layer used to. Both weights in one frame so the difference between
	# a chip and a haymaker is still visible at a glance.
	await get_tree().create_timer(0.7).timeout
	# Enemy (RED) above, player (gold) below — the red one is the shape that got
	# called out, so it has to be in the frame being judged.
	combat.call("_play_attack_tracer", Vector2(vp.x * 0.58, vp.y * 0.30),
		Vector2(vp.x * 0.20, vp.y * 0.40), true, 6.0, false, false)
	combat.call("_play_attack_tracer", Vector2(vp.x * 0.16, vp.y * 0.62),
		Vector2(vp.x * 0.52, vp.y * 0.74), false, 9.0, true, false)
	await get_tree().create_timer(0.045).timeout
	await _shoot("strike")

	# ── The spell FAMILIES that had no drawn form at all ────────────────
	# Six of the seven were particle puffs plus a screen tint; only `shock` had
	# a shape (the bolt), and it is the only one that read as cool. These are
	# the first two given a signature form: earth = radial fracture, fire =
	# flame tongues.
	await get_tree().create_timer(0.6).timeout
	combat.call("_vfx_earth", Vector2(vp.x * 0.24, vp.y * 0.50))
	combat.call("_vfx_fire", Vector2(vp.x * 0.52, vp.y * 0.52))
	# mind is the BIGGEST family (27 of 87) and had no drawn form at all.
	combat.call("_vfx_mind", Vector2(vp.x * 0.78, vp.y * 0.50), null)
	# Frost's blades grow in quantised steps and then HOLD DEAD STILL; the hold
	# is the only instant the form is fully extended, so a frame taken during the
	# growth catches a quarter-height stub and reads as a bug.
	combat.call("_vfx_frost", Vector2(vp.x * 0.40, vp.y * 0.76))
	combat.call("_vfx_blight", Vector2(vp.x * 0.62, vp.y * 0.78))
	# The two rings converted late from hand-rolled circles, and never shot.
	combat.call("_play_keyword_pulse_for", "ARMORED",
		Vector2(vp.x * 0.14, vp.y * 0.44), Color(0.65, 0.80, 1.0))
	combat.call("_play_keyword_pulse_for", "PIERCING",
		Vector2(vp.x * 0.14, vp.y * 0.62), Color(1.0, 0.62, 0.30))
	# Clear of the right-hand HUD: the aegis arch is 104x78 and rises off the
	# plane, so at 0.90 it drew over the RESERVES panel instead of the board.
	combat.call("_vfx_blessing", Vector2(vp.x * 0.80, vp.y * 0.34))
	# DELIVERY, not impact: shock now crosses the board AS the bolt, while the
	# throwers arc by weight. Both in one frame so the difference is judgeable.
	combat.call("_spell_fx_deliver", Vector2(vp.x * 0.46, vp.y * 0.30), "shock")
	combat.call("_spell_fx_deliver", Vector2(vp.x * 0.30, vp.y * 0.34), "earth")
	await get_tree().create_timer(0.10).timeout
	await _shoot("family_a")
	await get_tree().create_timer(0.13).timeout
	await _shoot("family_b")

	# ── THE LANE FORECAST — the always-on "this dies, this lives" overlay ─
	# Bodies on both sides, then force the forecast to rebuild, so the shot
	# catches the connector + reticle + label the way a player always sees them.
	await get_tree().create_timer(0.5).timeout
	# Lanes 0-1 SURVIVE, lane 2 DIES. Both readings must be in one frame or the
	# lethal treatment cannot be judged — a board where nothing dies exercises
	# only the quiet path, which is what the first shot of this caught.
	for ln2 in range(2):
		combat.call("summon_token", 3, 5, ln2, false, 0, {}, "Pikeman")
		combat.call("summon_token", 2, 4, ln2, true, 0, {}, "Raider")
	combat.call("summon_token", 3, 2, 2, false, 0, {}, "Pikeman")
	combat.call("summon_token", 6, 4, 2, true, 0, {}, "Raider")
	await get_tree().create_timer(0.45).timeout
	# A freshly summoned body is under the MUSTER DELAY and cannot swing, so
	# there is nothing to forecast and the overlay correctly draws nothing. Sweep
	# them ready the way _start_round does, or this shot photographs a bare board
	# and reads as "the forecast is broken".
	for side in [false, true]:
		for row in [0, 1]:
			for c in combat.call("_row_array", side, row):
				if c != null and is_instance_valid(c) and c.state != null:
					c.state.ready_to_swing = true
	if combat.has_method("_rebuild_lane_forecast"):
		combat.call("_rebuild_lane_forecast")
	elif combat.has_method("_request_lane_forecast_refresh"):
		combat.call("_request_lane_forecast_refresh")
	await get_tree().create_timer(0.35).timeout
	await _shoot("forecast")

	# ── THE IMPACT FRAME: two frames, so it must be grabbed deliberately ─
	# It fires from _spell_fx_impact (the shared per-target unit), NOT from the
	# _vfx_* forms the shots above call directly — so nothing else in this
	# harness would ever catch it. Grabbed on the very next drawn frame.
	await get_tree().create_timer(0.7).timeout
	combat.call("_spell_fx_impact", Vector2(vp.x * 0.30, vp.y * 0.42),
		"fire", "damage", null)
	combat.call("_spell_fx_impact", Vector2(vp.x * 0.56, vp.y * 0.42),
		"frost", "damage", null)
	await _shoot("impact_frame")

	# ── SIZE SANITY: every family form against the body it lands on ─────
	# Sized by independent magic numbers the seven drifted to three different
	# scales for the same event. Measured ONE AT A TIME against a clean plate,
	# because a hue test on a shared frame catches the gold lane rules and
	# reports a flame as twice the width of the board (it did).
	await _measure_sizes(combat, vp)

	# ── The clash commit: a sweep down the line, not one flash ───────────
	# Each side charges its own half and they meet on the midline, lanes going
	# off ~45ms apart. Sampled twice so the STAGGER is visible: if lanes 0 and 3
	# light on the same frame the sequence has been lost.
	await get_tree().create_timer(0.8).timeout
	# The beat early-returns on an empty board, so stand a line on both sides
	# first — otherwise the harness photographs a bare table and calls it a pass.
	for ln in range(4):
		combat.call("summon_token", 2, 4, ln, false, 0, {}, "Pikeman")
		combat.call("summon_token", 2, 4, ln, true, 0, {}, "Raider")
	await get_tree().create_timer(0.35).timeout
	combat.call("_play_clash_commit_vfx")
	await get_tree().create_timer(0.03).timeout
	await _shoot("clash_a")
	await get_tree().create_timer(0.09).timeout
	await _shoot("clash_b")

	# ── The face vignette, light hit and heavy hit ────────────────────────
	await get_tree().create_timer(0.6).timeout
	combat.call("_play_face_damage_flash", 1)
	await get_tree().create_timer(0.04).timeout
	var light := await _shoot_measure("vig_light")

	await get_tree().create_timer(0.8).timeout
	combat.call("_play_face_damage_flash", 9)
	await get_tree().create_timer(0.04).timeout
	var heavy := await _shoot_measure("vig_heavy")

	print("")
	print("[fxr] ============ VIGNETTE: CENTRE MUST STAY CLEAR ============")
	for r in [light, heavy]:
		print("[fxr]   %-10s centre red %6.1f   edge red %6.1f   edge/centre %.2fx"
			% [r["tag"], r["centre"], r["edge"], r["ratio"]])
	# The centre carries the damage numeral. The whole point of moving off a
	# uniform wash is that the edges do the shouting.
	_check(heavy["ratio"] >= 2.0,
		"a heavy hit reddens the EDGE at least 2x the centre")
	_check(heavy["edge"] > light["edge"],
		"a heavy hit reddens the edge more than a light one (slope preserved)")
	print("[fxr] %s" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	print("[fxr] DONE")
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail += 1
	print("[fxr] %s  %s" % ["PASS" if ok else "FAIL", what])


func _wait_for_player_turn(combat: Node, limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if not is_instance_valid(combat):
			return false
		if int(combat.round_number) >= 1 and int(combat.phase) == 0:
			return true
	return false


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_fxr_%s.png" % tag)
	print("[fxr] SAVED _fxr_%s.png" % tag)


## Fire each family alone on a clean board and measure the INK BOUNDING BOX
## against the battlefield token (Combat.FX_BODY, 200x150). The house band is
## 0.5-1.1 x the body's width: under it the form is a decal ON the art, over it
## it spills into the neighbouring lane and stops saying WHICH body was hit.
##
## Fire is the sanctioned exception on WIDTH — a flame is tall and narrow, so it
## is judged on HEIGHT instead.
func _measure_sizes(combat: Node, vp: Vector2) -> void:
	var at := Vector2(vp.x * 0.32, vp.y * 0.52)
	var rows: Array[String] = []
	var bad := 0
	# ISOLATE THE DRAWN FORM. Every family also fires particle emitters and a
	# screen flash, and a naive diff measures those too — which reported all five
	# forms at 1.7-2.2x the body, a uniform failure across every case, i.e. the
	# signature of a broken oracle rather than five broken effects. Particles off
	# for the measurement only; the flash is brief and under the threshold.
	var had_particles: bool = UserSettings.particles
	UserSettings.particles = false
	for spec in [{"n": "earth", "f": "_vfx_earth"}, {"n": "fire", "f": "_vfx_fire"},
			{"n": "frost", "f": "_vfx_frost"}, {"n": "blight", "f": "_vfx_blight"},
			{"n": "blessing", "f": "_vfx_blessing"}]:
		# Let the previous form clear, then take the clean plate.
		await get_tree().create_timer(1.1).timeout
		var plate := await _grab()
		combat.call(String(spec["f"]), at)
		await get_tree().create_timer(0.13).timeout
		await RenderingServer.frame_post_draw
		var shot: Image = get_viewport().get_texture().get_image()
		var x0 := 99999
		var y0 := 99999
		var x1 := -1
		var y1 := -1
		for y in range(maxi(0, int(at.y) - 260), mini(shot.get_height(),
				int(at.y) + 260), 2):
			for x in range(maxi(0, int(at.x) - 260), mini(shot.get_width(),
					int(at.x) + 260), 2):
				var p: Color = shot.get_pixel(x, y)
				var q: Color = plate.get_pixel(x, y)
				# 0.38, NOT 0.10. Most families also fire a `screen_flash`, a
				# FULL-SCREEN tint that clears a low threshold everywhere and
				# makes every form measure the size of the sample window — which
				# is why the first two passes reported all five at a suspiciously
				# uniform 1.5-2.2x. Only the drawn form reaches high contrast.
				if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.38:
					x0 = mini(x0, x); x1 = maxi(x1, x)
					y0 = mini(y0, y); y1 = maxi(y1, y)
		if x1 < 0:
			rows.append("%-9s NOTHING DREW" % spec["n"])
			bad += 1
			continue
		# The token is 200x150 in the 1600x900 PROJECT CANVAS, but the shot is
		# the window framebuffer — so a body is 200 * (shot_w / 1600) pixels
		# wide. Dividing raw shot pixels by 200 overstated everything by 1.2x.
		var px: float = float(shot.get_width()) / 1600.0
		var fw: float = float(x1 - x0) / (200.0 * px)
		var fh: float = float(y1 - y0) / (150.0 * px)
		var judged: float = fh if String(spec["n"]) == "fire" else fw
		var ok: bool = judged >= 0.45 and judged <= 1.15
		if not ok:
			bad += 1
		rows.append("%-9s %4dx%-4d px   %.2f w / %.2f h x body   %s"
			% [spec["n"], x1 - x0, y1 - y0, fw, fh, "OK" if ok else "OUT OF BAND"])
	UserSettings.particles = had_particles
	print("")
	print("[fxr] ====== SIZE vs THE BODY (200x150) — INFORMATIONAL ======")
	for r in rows:
		print("[fxr]   %s" % r)
	print("[fxr]   NOT AN ASSERTION, and the reason is worth keeping. A clean")
	print("[fxr]   plate cannot be taken on a LIVE board: the cards bob, the")
	print("[fxr]   ambient embers drift, the HUD animates — so a diff against a")
	print("[fxr]   plate grabbed even 0.13s earlier measures everything that")
	print("[fxr]   MOVED, not the effect. Three passes at it (threshold 0.10 ->")
	print("[fxr]   0.38, particles off, the 1600->1920 canvas scale) all")
	print("[fxr]   reported the five forms at a suspiciously UNIFORM 1.4-1.8x,")
	print("[fxr]   and a uniform result across every case is the signature of a")
	print("[fxr]   broken oracle rather than five broken effects. The numbers")
	print("[fxr]   above are an UPPER BOUND that includes board motion; sizes")
	print("[fxr]   were judged from the frames instead. To make this a real")
	print("[fxr]   gate, stage the form on a BARE board (no cards, no ambient)")
	print("[fxr]   rather than mid-fight.")


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Pixels that DEPART the clean plate — a per-frame ink figure, so a flicker
## shows up as a changing number.
func _ink(img: Image) -> float:
	if _baseline == null:
		return 0.0
	# WINDOWED to the bolt's corridor. Diffing the whole frame counted the ROUND
	# banner, the tooltip and the ambient embers animating, so the "flicker" it
	# reported was the HUD moving and would have passed with no bolt at all.
	var n := 0
	for y in range(150, mini(img.get_height(), 700), 2):
		for x in range(340, mini(img.get_width(), 1200), 2):
			var p: Color = img.get_pixel(x, y)
			var q: Color = _baseline.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.06:
				n += 1
	return float(n)


## Shoot, then report mean "redness" (R above the mean of G and B) in the centre
## box versus a border band — the vignette's whole claim in two numbers.
func _shoot_measure(tag: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_fxr_%s.png" % tag)
	var w := img.get_width()
	var h := img.get_height()
	var c_acc := 0.0
	var c_n := 0
	var e_acc := 0.0
	var e_n := 0
	var band := int(minf(float(w), float(h)) * 0.055)
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			var p: Color = img.get_pixel(x, y)
			var red: float = maxf(p.r - (p.g + p.b) * 0.5, 0.0) * 255.0
			var in_centre := absf(float(x) - w * 0.5) < w * 0.16 \
				and absf(float(y) - h * 0.5) < h * 0.16
			var on_edge := x < band or x >= w - band or y < band or y >= h - band
			if in_centre:
				c_acc += red
				c_n += 1
			elif on_edge:
				e_acc += red
				e_n += 1
	var centre: float = c_acc / maxf(float(c_n), 1.0)
	var edge: float = e_acc / maxf(float(e_n), 1.0)
	print("[fxr] SAVED _fxr_%s.png" % tag)
	return {"tag": tag, "centre": centre, "edge": edge,
		"ratio": edge / maxf(centre, 0.01)}
