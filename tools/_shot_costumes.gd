extends Node2D
## Windowed harness for the KEYWORD COSTUMES (docs/RULE_FX_PASS_20260728.md §7).
##
## Questions a parse check cannot answer:
##  1. Does the Shield wax seal read as a SEAL on a 200x150 token, or does it
##     read as a third stat orb next to ATK and HP?
##  2. Does it occlude the art the player uses to recognise the creature?
##  3. Is the Last Stand candle legible at 26x42, and does guttering read?
##  4. Do the two coexist without colliding with the status rail or the seals?
##
## Run WINDOWED (editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_costumes.tscn

const CARD := preload("res://scenes/card_2d.tscn")

var _built: Array = []


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func():
		print("[costume] WATCHDOG fired — _ready never completed")
		get_tree().quit(1))
	if UserSettings != null:
		UserSettings.reduce_motion = false
	await get_tree().process_frame

	# A real creature with real art, so occlusion is judged against the thing the
	# player actually reads — not against a grey rectangle.
	var ids: Array = CardDB.cards_of_rarity("common")
	if ids.is_empty():
		print("[costume] FAIL — no commons in the pool")
		get_tree().quit(1)
		return
	var cid := ""
	for i in ids:
		var d: Dictionary = CardDB.get_card_data(String(i))
		if String(d.get("type", "")) == "creature":
			cid = String(i)
			break
	if cid == "":
		print("[costume] FAIL — no creature common found")
		get_tree().quit(1)
		return
	print("[costume] using card: %s" % cid)

	# bare · shield only · last stand only · both
	var cases := [
		{"shield": false, "ls": false, "tag": "bare"},
		{"shield": true, "ls": false, "tag": "shield"},
		{"shield": true, "ls": true, "tag": "shield+ls"},
	]
	for i in cases.size():
		var cfg: Dictionary = cases[i]
		var data: Dictionary = CardDB.get_card_data(cid).duplicate(true)
		var kws: Array = (data.get("keywords", []) as Array).duplicate()
		if bool(cfg["ls"]) and not kws.has("last_stand"):
			kws.append("last_stand")
		data["keywords"] = kws
		var c = CARD.instantiate()
		c.card_data = data
		c.card_id = cid
		# The 200x150 token layout is gated on compact_mode, NOT on
		# is_on_battlefield — setting only the latter builds the HAND card and
		# leaves _compact_root null, so every costume silently no-ops.
		c.compact_mode = true
		c.is_on_battlefield = true
		c.position = Vector2(40 + float(i % 2) * 420, 40 + float(i / 2) * 260)
		add_child(c)
		if bool(cfg["shield"]):
			c.state.has_shield = true
		_built.append({"card": c, "tag": cfg["tag"]})

	for i in 24:
		await get_tree().process_frame

	# Force the poll so the costumes build without waiting on the shared clock.
	for b in _built:
		b["card"]._refresh_status_rail(true)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	for b in _built:
		var c = b["card"]
		print("[costume] %-11s seal=%s candle=%s" % [
			b["tag"],
			c._shield_seal != null and is_instance_valid(c._shield_seal),
			false])
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shot_costumes.png")
	print("[costume] wrote _shot_costumes.png")

	# Now fire BOTH reactions on the "both" token and shoot mid-break.
	var both = _built[_built.size() - 1]["card"]
	both.state.has_shield = false
	both.last_stand_used = true
	both._refresh_status_rail(true)
	# Catch the break MID-BEAT: the whole thing is ~0.20s, so a long settle would
	# shoot an empty scrim and prove nothing.
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_shot_costumes_break.png")
	print("[costume] wrote _shot_costumes_break.png (seal mid-break, candle guttering)")
	print("[costume] DONE")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)
