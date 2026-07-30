extends Node2D
## Windowed harness for ★2 "gilt catches the light"
## (docs/ANIMATION_COOL_PITCH_20260717.md).
##
## Two questions a parse check cannot answer:
##  1. Does the luminance+warmth mask actually FIND the gilt, or does it just
##     wash the whole parchment (which is also warm)?
##  2. Does the highlight MOVE with tilt, and does a common stay untouched?
##
## Shoots one rare at three tilt angles beside a common at the same angles.
## Run WINDOWED (editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_card_gilt.tscn

const CARD := preload("res://scenes/card_2d.tscn")


func _ready() -> void:
	# Watchdog: a windowed harness whose _ready throws never reaches quit() and
	# the process lives forever (cost three orphans on 07-16).
	get_tree().create_timer(45.0).timeout.connect(func():
		print("[gilt] WATCHDOG fired — _ready never completed")
		get_tree().quit(1))

	if UserSettings != null:
		UserSettings.reduce_motion = false
	await get_tree().process_frame

	# Pick a real rare and a real common out of the pool rather than hardcoding
	# ids that may have been reworked out from under the harness.
	var rares: Array = CardDB.cards_of_rarity("rare")
	var commons: Array = CardDB.cards_of_rarity("common")
	if rares.is_empty() or commons.is_empty():
		print("[gilt] FAIL — no rare/common in the pool")
		get_tree().quit(1)
		return
	var rare_id := String(rares[0])
	var common_id := String(commons[0])
	print("[gilt] rare=%s  common=%s" % [rare_id, common_id])

	# The foil rides _build_baked_overlay_layout, which only runs on a cache HIT
	# (CardTextureCache.has) — an unbaked card falls back to the live chart_proto
	# renderer, which is a TREE of painters and therefore can't be shaded at all.
	# So: bake first, or the harness measures the fallback and reports 0/3.
	await CardTextureCache.bake(CardDB.get_card_data(rare_id))
	await CardTextureCache.bake(CardDB.get_card_data(common_id))
	print("[gilt] baked: rare=%s common=%s" % [
		CardTextureCache.has(CardDB.get_card_data(rare_id)),
		CardTextureCache.has(CardDB.get_card_data(common_id))])

	var tilts := [-0.28, 0.0, 0.28]
	var built: Array = []
	for row in 2:
		var id := rare_id if row == 0 else common_id
		for i in tilts.size():
			var c = CARD.instantiate()
			c.card_data = CardDB.get_card_data(id).duplicate(true)
			c.card_id = id
			c.live_baked_mode = true
			c.position = Vector2(120.0 + float(i) * 320.0, 40.0 + float(row) * 340.0)
			c.scale = Vector2(0.95, 0.95)
			add_child(c)
			built.append({"card": c, "tilt": tilts[i], "row": row})

	# The bake must land or _baked_face is null and the foil silently no-ops.
	for i in 60:
		await get_tree().process_frame

	var rare_foiled := 0
	var common_foiled := 0
	for b in built:
		var c = b["card"]
		if c._gilt_mat != null:
			if b["row"] == 0:
				rare_foiled += 1
			else:
				common_foiled += 1
		# Drive the sweep directly — the lean driver would need a live cursor.
		c._sweep_gilt(b["tilt"])
	print("[gilt] rares carrying foil  : %d / 3 (expect 3)" % rare_foiled)
	print("[gilt] commons carrying foil: %d / 3 (expect 0 — shine is INFORMATION)"
		% common_foiled)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shot_gilt.png")
	print("[gilt] wrote _shot_gilt.png (top = rare @ tilt -0.28/0/+0.28, bottom = common)")
	print("[gilt] DONE")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)
