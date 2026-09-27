extends Node
# THE DEAL HARNESS (2026-09-10). Shoots `Motion.deal_card`'s flight as a strip,
# because an entrance is the one thing a settled screenshot cannot show — every
# existing shell shot waits for the screen to stop moving, which is exactly when
# this effect is over.
#
#   Godot.exe --path "D:\Godot" res://tools/_shot_card_deal.tscn
#
# IT STAGES ITS OWN CARD RATHER THAN BOOTING A SCREEN, and that is the whole
# reason it works. Two earlier cuts tried to photograph the real Recruit slate:
#   1. sampling a real clock — ONE capture (`frame_post_draw` + `get_image()` +
#      a PNG encode) costs ~0.9s of wall time, so the first frame landed at
#      t=1.02 for a shot requested at t=0.10 and the deal was long over.
#   2. slowing `Engine.time_scale` — ten back-to-back captures then advanced the
#      animation by only 0.17s in total, which does not even reach the deal's
#      own start delay.
# Both were measuring the machine. Driving the verb directly with a deliberately
# long flight makes the sampling rate irrelevant: at `FLIGHT` seconds a ~0.9s
# capture is a readable step, and the frames are of a KNOWN parameter value
# rather than of whenever the harness happened to get scheduled.
#
# What the strip is evidence for, in order:
#   · the card is somewhere ELSE early. If frame 0 already has it in its slot,
#     the travel is not happening and only a scale tween survived.
#   · it is NARROW early and full-width late (the turn), and NEVER translucent.
#   · the shadow is wide/pale/offset in the air and tight/dark on contact. An
#     identical shadow in every frame means the height cue is dead.

const FLIGHT := 3.2
const FRAMES := 14
const CARD_SCENE := preload("res://scenes/card_2d.tscn")

var _wrap: Control = null


func _ready() -> void:
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	RunState.start_new_run("raider", -1, 20260910)
	await get_tree().process_frame

	# A plain dark stage: the shadow is the thing under test and it needs ground
	# to fall on, not a painted campfire background to hide in.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# A MID-VALUE stage, not a dark one. The shadow is black; on the near-black
	# first cut it had nothing to darken and the cue could not be judged at all.
	bg.color = Color(0.52, 0.44, 0.34)
	add_child(bg)

	# A real starter id. NOT `CARD_POOL[0]` as a fallback — CARD_POOL is a const
	# DICTIONARY, so an integer index on it is folded at compile time and takes
	# the whole script down with a parse error rather than failing at runtime.
	var data: Dictionary = CardDB.get_card_data("brute")
	CardTextureCache.bake(data)

	_wrap = Control.new()
	_wrap.custom_minimum_size = Vector2(Card2D.CARD_W, Card2D.CARD_H)
	_wrap.size = _wrap.custom_minimum_size
	_wrap.position = Vector2(690, 290)
	_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrap.draw.connect(_draw_shadow)
	add_child(_wrap)

	var card = CARD_SCENE.instantiate()
	card.card_data = data.duplicate(true)
	card.card_id = String(data.get("id", ""))
	card.is_on_battlefield = true
	card.live_baked_mode = true
	_wrap.add_child(card)
	# Let the face bake and lay itself out before it is thrown, or the strip
	# photographs an unbuilt card and says nothing about the flight.
	for _f in range(6):
		await get_tree().process_frame

	Motion.deal_card(_wrap, 0.0, {
		"from": Vector2(-130.0, 340.0), "spin": 0.44, "dur": FLIGHT,
	})
	for i in FRAMES:
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var fname := "_shot_deal_%d.png" % i
		img.save_png("res://" + fname)
		print("SAVED %s  lift=%.2f" % [fname,
			float(_wrap.get_meta("deal_lift", -1.0))])

	if is_instance_valid(_wrap):
		_wrap.queue_free()
	await get_tree().process_frame

	# PHASE 2 — the real screens, SETTLED. The strip above proves the verb; this
	# proves the WIRING, and it is the half that actually goes wrong: a flight
	# that ends anywhere but exactly (0,0) leaves every card permanently offset in
	# its slot, and that is invisible in a mid-flight frame.
	# Reward and Treasure carry the CONTAINER-CHILD path (`drop_item` moves a tile
	# that an HBox owns), which is the one that can land wrong: the resting
	# position is read at take-off, and Reward re-sorts its row after building it
	# to equalise tile heights. A settled shot is exactly the check for that — a
	# tile stranded off its slot shows up here and nowhere else.
	for spec in [["res://scenes/recruit.tscn", "recruit", "recruit"],
			["res://scenes/shop.tscn", "shop", "shop"],
			["res://scenes/reward.tscn", "reward", "elite"],
			["res://scenes/treasure.tscn", "treasure", "reliquary"]]:
		# THE NODE TYPE GATES THE ROW UNDER TEST. Reward only builds its relic
		# choices for an elite/boss stop; booted cold it shows a gold-and-cards
		# screen with no spoils on it at all, and the shot would have "passed"
		# while photographing nothing.
		RunState.current_node_type = String(spec[2])
		var scn: Node = load(String(spec[0])).instantiate()
		get_tree().root.add_child(scn)
		# Settle by POLLING until the frame stops changing, not on a fixed timer —
		# a timed wait on an animated screen measures the machine.
		var prev := PackedByteArray()
		var stable := 0
		var guard := 0
		while stable < 3 and guard < 220:
			guard += 1
			await RenderingServer.frame_post_draw
			var cur: PackedByteArray = get_viewport().get_texture() \
				.get_image().get_data()
			stable = stable + 1 if cur == prev else 0
			prev = cur
		var img2: Image = get_viewport().get_texture().get_image()
		img2.save_png("res://_shot_deal_%s_settled.png" % String(spec[1]))
		print("SAVED _shot_deal_%s_settled.png (settled after %d frames)"
			% [String(spec[1]), guard])
		scn.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	# PHASE 3 — the Collection's hydration beat. The gallery swaps a ghost writ
	# for a real baked card, and the beat marking that swap is a 0.34s specular.
	# A settled shot is useless for it (by then every sweep is over), so this
	# takes CONSECUTIVE frames from the moment the grid starts filling and the
	# check is the DIFF: moving bright bands across card faces. A static grid
	# between two frames means the beat is not firing.
	var col: Node = load("res://scenes/collection.tscn").instantiate()
	get_tree().root.add_child(col)
	for _f in range(10):
		await get_tree().process_frame
	for i in 4:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image() \
			.save_png("res://_shot_illum_%d.png" % i)
		print("SAVED _shot_illum_%d.png" % i)
	col.queue_free()
	await get_tree().process_frame

	print("SHOTS_DONE")
	get_tree().quit()


func _draw_shadow() -> void:
	Motion.card_shadow(_wrap,
		Vector2(Card2D.CARD_W * 0.5, Card2D.CARD_H + 8.0),
		float(_wrap.get_meta("deal_lift", 0.0)), 96.0,
		_wrap.get_meta("deal_off", Vector2.ZERO))
