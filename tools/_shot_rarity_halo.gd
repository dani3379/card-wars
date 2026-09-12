extends Node
## _shot_rarity_halo.gd — eyes on the card-offer rarity shine (2026-09-10).
##
##   Godot_v4.6.2-stable_win64.exe --path "D:\Godot" res://tools/_shot_rarity_halo.tscn
##
## WHY IT EXISTS. `Motion.rarity_reveal` drew a 2.5px `draw_polyline` ellipse
## right round the card and ROTATED it — the flat-hairline-circle defect in a
## third spelling, on a card-choice screen, which made it the most-looked-at
## circle in the game. It was reported as both ugly AND meaningless, and the
## second half is the interesting one: a wire loop travelling around a card says
## "selected" far louder than it says "uncommon".
##
## It is a soft bloom with tapered rays now, and no rotation. Nothing in tools/
## photographed it, which is exactly how it survived: every shot harness here
## covers combat, and this fires on Recruit / Shop / Reward / Treasure /
## NetDraft.
##
## Shoots COMMON, UNCOMMON and RARE in one frame — the tiers have to be
## DISTINGUISHABLE from each other, not merely attractive alone, and a common
## must show nothing at all (the shine is information, not decoration).

const CARD := preload("res://scenes/card_2d.tscn")

var _fail := 0
var _wraps: Dictionary = {}


## rarity_reveal parents its burst to the wrapper, so the wrapper's non-card
## children ARE the shine.
func _shine_nodes(rarity: String) -> int:
	var w = _wraps.get(rarity)
	if w == null or not is_instance_valid(w):
		return -1
	var n := 0
	for c in w.get_children():
		if c.get_class() == "PanelContainer":
			continue   # the Card2D itself
		n += 1
	return n


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[halo] WATCHDOG fired")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 620))
	DisplayServer.window_move_to_foreground()
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0

	# The warm table the shine has to survive against — a pale halo tested on a
	# neutral grey would pass and then vanish in the game.
	var bg := ColorRect.new()
	bg.color = Color(0.118, 0.094, 0.074)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var font := ThemeDB.fallback_font
	var tiers := ["common", "uncommon", "rare"]
	for i in tiers.size():
		var rarity: String = tiers[i]
		var wrap := Control.new()
		wrap.custom_minimum_size = Vector2(225, 300)
		wrap.size = Vector2(225, 300)
		wrap.position = Vector2(150.0 + float(i) * 340.0, 150.0)
		add_child(wrap)

		var lbl := Label.new()
		lbl.text = rarity.to_upper()
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.add_theme_color_override("font_color", Color(0.74, 0.70, 0.62))
		lbl.position = Vector2(wrap.position.x + 60.0, 96.0)
		add_child(lbl)

		var cd := _pick_of(rarity)
		if cd.is_empty():
			continue
		var card = CARD.instantiate()
		card.static_display = true
		card.card_data = cd
		wrap.add_child(card)
		await get_tree().process_frame
		GameTheme.rarity_reveal(wrap, rarity, 0.02)
		_wraps[rarity] = wrap

	# Past the 0.12 fade-in and the 0.36 settle, so the shine is at full.
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_halo_tiers.png")
	print("[halo] SAVED _halo_tiers.png")

	# The COMMON cell must be untouched: the shine is information, so a card that
	# rolled nothing must show nothing. Measured against the bare table colour.
	# STRUCTURAL, NOT PIXEL, for the "a common shows nothing" claim. Three
	# pixel attempts failed it while the shot was plainly correct: the card's
	# own drop shadow, then its cost orb and stat seals — all of which sit
	# OUTSIDE the card rect — kept landing in whatever box or threshold was
	# chosen. Counting the shine NODE cannot be fooled by the card's art, and
	# rarity_reveal's contract is exactly "commons add nothing".
	var n_c := _shine_nodes("common")
	var n_u := _shine_nodes("uncommon")
	var n_r := _shine_nodes("rare")
	print("[halo] shine nodes — common %d · uncommon %d · rare %d"
		% [n_c, n_u, n_r])
	_check(n_c == 0, "a COMMON gets no shine at all (it is information)")
	# UNCOMMON 1, RARE 2 — and the extra one is the point, not a leak. A rare
	# also gets `foil_sweep` across the card face: the bloom says "this slate
	# rolled well" from OUTSIDE the card, the foil says it about the card
	# itself. Uncommons deliberately do not get it, because two tiers of shine
	# is one tier of noise (Motion's own note). Asserting "exactly one each"
	# was me guessing at the contract instead of reading it.
	_check(n_u == 1, "an uncommon gets the bloom")
	_check(n_r == 2, "a rare gets the bloom AND the foil — its second tier")
	# The ink figures stay as an INFORMATIONAL read of loudness. They cannot be
	# an assertion for the reason above — the baseline is the card, not the table.
	var lit := _lit_around(img, 262, 300, 150)
	var lit_u := _lit_around(img, 602, 300, 150)
	var lit_r := _lit_around(img, 942, 300, 150)
	print("[halo] lit px (informational; includes card furniture) — "
		+ "common %d · uncommon %d · rare %d" % [lit, lit_u, lit_r])
	_check(lit_r > lit_u, "a rare reads louder than an uncommon")
	print("[halo] %s" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail += 1
	print("[halo] %s  %s" % ["PASS" if ok else "FAIL", what])


## Ink OUTSIDE the card rect only — the shine lives behind and around the card,
## and counting the card's own art would drown it.
func _lit_around(img: Image, cx: int, cy: int, rad: int) -> int:
	var n := 0
	for y in range(maxi(0, cy - rad), mini(img.get_height(), cy + rad), 2):
		for x in range(maxi(0, cx - rad), mini(img.get_width(), cx + rad), 2):
			# Skip the card AND the tight drop shadow it casts. Without the
			# margin the shadow dominates the count: it is the same few hundred
			# pixels in every cell, so a common "scored" 1511 and a genuine
			# uncommon bloom could never reach a 2x multiple of it.
			if absf(float(x - cx)) < 132.0 and absf(float(y - cy)) < 168.0:
				continue
			var p: Color = img.get_pixel(x, y)
			# 0.62, not 0.40. The bare table already sums to 0.286, so a 0.40
			# threshold counts the table's own mottling and any shadow edge —
			# it was measuring the board, not the shine.
			if p.r + p.g + p.b > 0.62:
				n += 1
	return n


## CARD_POOL is a DICTIONARY keyed by id, so `for cd in CARD_POOL` walks the
## KEYS — plain Strings. `String.get("rarity", "")` does not error, it just
## yields nothing, so every card was silently skipped and the shot came back as
## three labels on an empty table. Iterate .values().
func _pick_of(rarity: String) -> Dictionary:
	for cd in CardDB.CARD_POOL.values():
		if String(cd.get("rarity", "")) == rarity \
				and String(cd.get("type", "")) == "creature" \
				and cd.get("draftable", true):
			return cd
	return {}
