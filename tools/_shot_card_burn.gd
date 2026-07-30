extends Node2D
## Windowed harness for ★1 "the writ burns" (docs/ANIMATION_COOL_PITCH_20260717.md).
##
## The whole point of the effect is the frame BETWEEN alive and gone, so a
## before/after shot proves nothing — this catches the dissolve mid-burn at
## several progress values and writes them to _shot_burn_*.png.
##
## Renders a row of live battlefield tokens, sets each alight, and samples the
## sheet at staggered progress. Also asserts the shader COMPILED (a parse check
## can't see GPU compile errors — a failed shader silently renders untouched).
##
## Run WINDOWED (the editor must be closed; GL shots are session-dependent):
##   Godot.exe --path "D:\Godot" res://tools/_shot_card_burn.tscn

const CARD := preload("res://scenes/card_2d.tscn")

var _cards: Array = []


func _ready() -> void:
	# WATCHDOG. A windowed harness whose _ready throws never reaches quit() and
	# the process lives forever (this cost three orphaned Godot processes on
	# 07-16, and this harness itself hung on a bad CardDB call). An independent
	# timer guarantees the window closes whether _ready finishes or not.
	get_tree().create_timer(45.0).timeout.connect(func():
		print("[burn] WATCHDOG fired — _ready never completed")
		get_tree().quit(1))

	# This machine's saved settings have Reduce Motion ON — every shot harness
	# has to force it off or it captures the static fallback (known trap).
	if UserSettings != null:
		UserSettings.reduce_motion = false
		UserSettings.anim_speed = 1.0
	await get_tree().process_frame

	var ids := ["goblin", "brute", "pikeman", "palisade"]
	var x := 140.0
	for id in ids:
		var data: Dictionary = CardDB.get_card_data(id)
		if data.is_empty():
			print("[burn] WARN unknown card id: %s" % id)
			continue
		var c = CARD.instantiate()
		c.card_data = data.duplicate(true)
		c.card_id = id
		c.compact_mode = true
		c.is_on_battlefield = true
		c.position = Vector2(x, 220.0)
		add_child(c)
		_cards.append(c)
		x += 240.0

	# Let the battlefield bake land — the burn needs the cached face to exist,
	# and without it _play_burn_death correctly falls back (which is not what
	# we're here to photograph).
	for i in 40:
		await get_tree().process_frame

	var faced := 0
	for c in _cards:
		if c._compact_face != null and is_instance_valid(c._compact_face):
			faced += 1
	print("[burn] tokens with a baked face: %d / %d" % [faced, _cards.size()])
	if faced == 0:
		print("[burn] FAIL — no baked faces; the burn would silently fall back")
		get_tree().quit(1)
		return

	# Stagger the burn so one screenshot shows the whole arc: just-lit, mid,
	# nearly consumed. Strip the panel exactly as _play_burn_death does — the
	# card paints its own backing board behind the face, and without this the
	# capture lies (the burned region reads black instead of gone).
	for i in _cards.size():
		var c = _cards[i]
		c.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var mat := Motion.burn_material()
		c._compact_face.material = mat
		mat.set_shader_parameter("burn", 0.18 + float(i) * 0.24)

	await get_tree().process_frame
	await get_tree().process_frame

	# A shader that failed to compile renders the texture untouched, so verify
	# the material actually took and reports its parameter back.
	var ok := true
	for c in _cards:
		var m = c._compact_face.material
		if m == null or not (m is ShaderMaterial):
			ok = false
			continue
		if m.shader == null:
			ok = false
	print("[burn] shader material bound on every token: %s" % ("yes" if ok else "NO"))

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shot_burn_stages.png")
	print("[burn] wrote _shot_burn_stages.png (burn = 0.18 / 0.42 / 0.66 / 0.90)")

	# Second capture: a real _die() on a live token, caught mid-flight.
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	await get_tree().process_frame
	var d = CARD.instantiate()
	var ddata: Dictionary = CardDB.get_card_data("brute")
	d.card_data = ddata.duplicate(true)
	d.card_id = "brute"
	d.compact_mode = true
	d.is_on_battlefield = true
	d.position = Vector2(400.0, 220.0)
	add_child(d)
	for i in 40:
		await get_tree().process_frame
	d._die()
	# ~40% through a 0.52s burn.
	await get_tree().create_timer(0.21).timeout
	await RenderingServer.frame_post_draw
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("res://_shot_burn_die.png")
	print("[burn] wrote _shot_burn_die.png (a real _die, caught mid-burn)")
	if is_instance_valid(d):
		d.queue_free()
	await get_tree().process_frame

	# ── ★3 the seal cracks + ★4 ink shock ──────────────────────────────
	# Three tokens at descending HP so both crack rungs and the whole seal are
	# in one frame, and the rightmost is caught mid-flash.
	var hps := [4, 2, 1]
	var shots: Array = []
	var sx := 200.0
	for h in hps:
		var cdata: Dictionary = CardDB.get_card_data("palisade")  # 0/4 — clean rungs
		var c = CARD.instantiate()
		c.card_data = cdata.duplicate(true)
		c.card_id = "palisade"
		c.compact_mode = true
		c.is_on_battlefield = true
		c.position = Vector2(sx, 220.0)
		add_child(c)
		shots.append(c)
		sx += 260.0
	for i in 40:
		await get_tree().process_frame
	for i in shots.size():
		shots[i].current_hp = hps[i]
		shots[i].update_stat_display()
	shots[2]._flash_hit()
	var flashed: bool = shots[2]._flash_mat != null
	print("[burn] ink shock bound a flash material: %s" % ("yes" if flashed else "NO"))
	await get_tree().create_timer(0.05).timeout
	await RenderingServer.frame_post_draw
	var img3 := get_viewport().get_texture().get_image()
	img3.save_png("res://_shot_burn_seals.png")
	print("[burn] wrote _shot_burn_seals.png (HP 4 whole / 2 hairline / 1 split+flash)")

	# The seal is 38px — at 1:1 a crack is a few pixels and the capture can't
	# settle whether it reads as wax or as noise. Blow the seal row up so the
	# rungs are actually judgeable.
	#
	# Derive the crop from the real node rects scaled into image space: the
	# captured image is not the viewport's logical size (window scale +
	# supersampling), so hardcoded pixel coords miss — the first cut cropped a
	# strip of empty backdrop and proved nothing.
	var full := get_viewport().get_texture().get_image()
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var k: float = float(full.get_width()) / maxf(vp_size.x, 1.0)
	var first: Control = shots[0]
	var last: Control = shots[2]
	var y0: float = (first.global_position.y + first.size.y * 0.55) * k
	var y1: float = (first.global_position.y + first.size.y + 8.0) * k
	var x0: float = (first.global_position.x - 8.0) * k
	var x1: float = (last.global_position.x + last.size.x + 8.0) * k
	var crop := Rect2i(int(x0), int(y0), int(x1 - x0), int(y1 - y0))
	crop = crop.intersection(Rect2i(Vector2i.ZERO, full.get_size()))
	if crop.size.x > 4 and crop.size.y > 4:
		var zoom := full.get_region(crop)
		zoom.resize(zoom.get_width() * 3, zoom.get_height() * 3,
			Image.INTERPOLATE_NEAREST)
		zoom.save_png("res://_shot_burn_seals_zoom.png")
		print("[burn] wrote _shot_burn_seals_zoom.png (3x on the seal row)")
	print("[burn] DONE")
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0)
