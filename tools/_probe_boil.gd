extends Node
## _probe_boil.gd — the gate for ▲1, the boil (docs/TECHNIQUE_HUNT_20260902.md §5).
##
##   Godot.exe --path "D:\Godot" res://tools/_probe_boil.tscn
##   (WINDOWED on purpose — a boil is pixels, and only pixels can prove it.)
##
## Three parts, and PART A exists because the pixel test alone was not enough.
##
##   A. THE NUMBERS. Amplitude is the load-bearing quantity in this technique —
##      above ~1.2 px a boil stops being a hand and becomes a vibration — and the
##      pixel diff cannot see it. Measured: a mutant that made the displacement
##      TEN TIMES too large moved luma by only 0.2253 against a 0.55 ceiling and
##      PASSED, because the chart's ink runs at alpha 0.055–0.16 and faint ink
##      displaced hard is still a faint change. So the band is asserted directly
##      against `Motion`'s own constants and its offset function, where 10× is
##      unmissable. **A pixel oracle cannot judge a quantity it only sees through
##      alpha 0.1.**
##   B. THE PIXELS. That it runs at all, and that it moves a thin MINORITY of the
##      plate — only line work boils; the burn, the stains, the board furniture
##      and the cards must not.
##   C. REDUCE MOTION IS FROZEN, AND IS THE OLD CHART. Variant 0 is defined as the
##      undisplaced drawing, so holding it must render identical frames.
##
## THE TRAP THIS WAS WRITTEN THROUGH: a combat board is full of things that move
## on their own — ambient embers, the idle bob, banner sway, the intro ceremony.
## Diffing two raw frames of a live fight measures those, not the boil, and would
## pass with the boil deleted. So the probe shoots a BARE TablePlate on a black
## background, nothing else in the tree.

const AMP := 0.6
const W := 900
const H := 520

var _plate: Control = null
var _hits := 0


func _ready() -> void:
	# The painter is the only thing on screen: no embers, no cards, no ceremony.
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var TablePlate = load("res://scripts/ui/painters/TablePlate.gd")
	_plate = TablePlate.new()
	_plate.position = Vector2(40, 40)
	_plate.size = Vector2(W, H)
	_plate.seed_text = "boil_probe_act1"
	_plate.act = 1
	add_child(_plate)
	await get_tree().process_frame

	print("[boil] ▲1 — does the ink breathe, and only the ink?\n")

	# ── A: the numbers ────────────────────────────────────────────────────
	print("  -- A, the constants --")
	if Motion.BOIL_AMP > 1.2:
		_fail("BOIL_AMP %.2f px is past the band — that is a vibration, not a hand"
			% Motion.BOIL_AMP)
	elif Motion.BOIL_AMP < 0.3:
		_fail("BOIL_AMP %.2f px is below what LINEAR filtering resolves — invisible"
			% Motion.BOIL_AMP)
	else:
		print("  ok    amplitude %.2f px is inside the 0.3–1.2 band" % Motion.BOIL_AMP)

	var worst := 0.0
	for i in 4000:
		for v in [1, 2]:
			var o: Vector2 = Motion.boil_offset(i, v)
			worst = maxf(worst, maxf(absf(o.x), absf(o.y)))
	if worst > Motion.BOIL_AMP + 0.0001:
		_fail("an offset reached %.3f px, past BOIL_AMP %.2f" % [worst, Motion.BOIL_AMP])
	else:
		print("  ok    no offset exceeds the amplitude (worst %.3f px)" % worst)

	if Motion.boil_offset(17, 0) != Vector2.ZERO:
		_fail("drawing 0 is displaced — Reduce Motion would not render the old chart")
	else:
		print("  ok    drawing 0 is the undisplaced chart")

	# The cycle must ping-pong. A plain 0,1,2 loop reads as a 3-frame flicker
	# because the eye finds the seam where the last drawing snaps back to the first.
	var order: Array = Array(Motion.BOIL_ORDER)
	var uniq := {}
	for v in order:
		uniq[v] = true
	if uniq.size() < 3:
		_fail("the cycle uses only %d of the 3 drawings" % uniq.size())
	elif order == [0, 1, 2]:
		_fail("BOIL_ORDER is a plain loop — that reads as a flicker, not a boil")
	else:
		print("  ok    %d-step ping-pong over 3 drawings: %s" % [order.size(), str(order)])

	# And it must actually advance on twos, not on frames.
	if Motion.boil_variant(0.0) == Motion.boil_variant(1.0 / Motion.BOIL_FPS + 0.001):
		_fail("the variant does not advance across one %.0f fps step" % Motion.BOIL_FPS)
	elif Motion.boil_variant(0.0) != Motion.boil_variant(0.5 / Motion.BOIL_FPS):
		_fail("the variant advances WITHIN a step — that is animating on ones")
	else:
		print("  ok    advances once per %.0f ms and holds between" % (1000.0 / Motion.BOIL_FPS))

	# ── B + C: the pixels ─────────────────────────────────────────────────
	print("\n  -- B, the pixels --")
	UserSettings.reduce_motion = false
	_plate.set_process(true)
	_plate._boil_t = 0.0
	await get_tree().create_timer(0.30).timeout
	var a := await _grab("boil_a")
	# 125 ms is just over one 8 fps step, so the drawing MUST have changed.
	await get_tree().create_timer(0.125).timeout
	var b := await _grab("boil_b")

	var d := _diff(a, b)
	print("  moved pixels   : %.3f%% of the plate" % (d.frac * 100.0))
	print("  mean move      : %.4f (0-1 luma) over the changed pixels" % d.mean)
	print("  worst move     : %.4f" % d.peak)
	if d.frac <= 0.0005:
		_fail("the ink did not move at all — the boil is not running")
	elif d.frac > 0.12:
		_fail("%.1f%% of the plate changed — that is not a boil, that is a redraw"
			% (d.frac * 100.0))
	else:
		print("  ok    it moves, and it moves a minority of the plate")
	# Kept, but read it for what it is: a guard against something LOUD getting
	# into this layer, not against amplitude. Part A owns amplitude.
	if d.peak > 0.55:
		_fail("a changed pixel moved by %.2f — something opaque is boiling" % d.peak)
	else:
		print("  ok    every change is faint — displacement, not a repaint")

	# ── C: Reduce Motion holds drawing 0 ──────────────────────────────────
	print("\n  -- C, reduce motion --")
	UserSettings.reduce_motion = true
	await get_tree().create_timer(0.20).timeout
	var c := await _grab("boil_rm_a")
	await get_tree().create_timer(0.30).timeout
	var e := await _grab("boil_rm_b")
	var drm := _diff(c, e)
	print("  reduce motion  : %.4f%% moved" % (drm.frac * 100.0))
	if drm.frac > 0.0002:
		_fail("Reduce Motion still boils (%.3f%% of pixels moved)" % (drm.frac * 100.0))
	else:
		print("  ok    Reduce Motion is frozen")

	# ...AND IT MUST COME BACK. Holding is right; latching off is not. The first
	# version called `set_process(false)` on the hold, so a player who turned the
	# setting on and back off mid-fight got a chart that never breathed again for
	# the rest of the scene — silent, and invisible to every other check.
	UserSettings.reduce_motion = false
	await get_tree().create_timer(0.25).timeout
	var f1 := await _grab("boil_resume_a")
	await get_tree().create_timer(0.125).timeout
	var f2 := await _grab("boil_resume_b")
	var dres := _diff(f1, f2)
	print("  after resume   : %.3f%% moved" % (dres.frac * 100.0))
	if dres.frac <= 0.0005:
		_fail("the boil never resumed after Reduce Motion was turned back off")
	else:
		print("  ok    resumes when Reduce Motion is turned back off")

	# ── D: is it actually ON in a real fight? ─────────────────────────────
	#
	# Parts A–C prove the PRIMITIVE works, on a painter this probe built itself.
	# That is not the same claim as "the board boils", and the difference is
	# exactly where a feature quietly ships switched off: Combat builds its own
	# TablePlate with its own anchors and its own lifecycle, and a painter that
	# never gets `_process` — or never gets built at all — would leave every
	# assertion above green while the game showed a frozen chart.
	#
	# Asserted as STATE rather than pixels on purpose: a live board also carries
	# ambient embers, the idle bob and the intro ceremony, so a frame diff there
	# would pass with the boil deleted.
	print("\n  -- D, live in a fight --")
	UserSettings.reduce_motion = false
	_plate.queue_free()
	await get_tree().process_frame
	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_encounter_id = "goblin_scouts"
	RunState.current_node_type = "combat"
	var cb = load("res://scenes/combat.tscn").instantiate()
	add_child(cb)
	await get_tree().create_timer(5.0).timeout

	var live: Control = _find_plate(cb)
	if live == null:
		_fail("no TablePlate on the combat board at all")
	elif not live.is_processing():
		_fail("the board's TablePlate is not processing — the boil is off in-game")
	else:
		var seen := {}
		for _i in 30:
			seen[live._boil_v] = true
			await get_tree().create_timer(0.05).timeout
		if seen.size() < 2:
			_fail("the live chart held one drawing for 1.5 s — it is frozen in-game")
		else:
			print("  ok    the board's chart cycled %d drawings in 1.5 s" % seen.size())
	if is_instance_valid(cb):
		cb.queue_free()
	await get_tree().process_frame

	print("\n[boil] %s" % ("PASS" if _hits == 0 else "%d FAIL" % _hits))
	get_tree().quit(1 if _hits > 0 else 0)


## Identify the painter by its SCRIPT, not by duck-typing its properties.
## The property probe (`"seed_text" in ch and "_boil_v" in ch`) reported no plate
## on a board that demonstrably had one, and a harness that cannot find the thing
## it is judging reports the feature broken when the feature is fine. Matching the
## script path is unambiguous and was verified against the live board first.
func _find_plate(n: Node) -> Control:
	var stack: Array = [n]
	while not stack.is_empty():
		var x = stack.pop_back()
		for ch in x.get_children():
			stack.push_back(ch)
		var scr = x.get_script()
		if scr != null and String(scr.resource_path).find("TablePlate") >= 0:
			return x as Control
	return null


func _fail(msg: String) -> void:
	_hits += 1
	print("  FAIL  %s" % msg)


func _grab(tag: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/_shot_%s.png" % tag)
	return img


## Compare only the plate's own rect, and report both how much moved and how hard.
func _diff(a: Image, b: Image) -> Dictionary:
	var scale := float(a.get_width()) / 1600.0
	var r := Rect2i(int(40 * scale), int(40 * scale), int(W * scale), int(H * scale))
	r = r.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var changed := 0
	var total := 0
	var sum := 0.0
	var peak := 0.0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			total += 1
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var dl: float = absf((0.2126 * ca.r + 0.7152 * ca.g + 0.0722 * ca.b)
				- (0.2126 * cb.r + 0.7152 * cb.g + 0.0722 * cb.b))
			if dl > 0.004:
				changed += 1
				sum += dl
				peak = maxf(peak, dl)
	return {
		"frac": 0.0 if total == 0 else float(changed) / float(total),
		"mean": 0.0 if changed == 0 else sum / float(changed),
		"peak": peak,
	}
