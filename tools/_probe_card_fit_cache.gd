extends SceneTree
## Verifies that Card2D's cached rules-text fit produces exactly the same
## font size, leading, and measured content height as the first full layout.

const SAMPLE_SIZE := 80

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _find_rules_rt(node: Node) -> RichTextLabel:
	if node is RichTextLabel:
		return node as RichTextLabel
	for child in node.get_children():
		var found := _find_rules_rt(child)
		if found != null:
			return found
	return null


func _measure(card_scene: PackedScene, host: Control,
		data: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var card = card_scene.instantiate()
	card.card_data = data.duplicate(true)
	card.card_id = String(data.get("id", ""))
	card.is_on_battlefield = true
	card.static_display = true
	host.add_child(card)
	await process_frame
	await process_frame
	await process_frame
	var rt := _find_rules_rt(card)
	var result := {
		"font": int(rt.get_theme_font_size("normal_font_size")),
		"bold": int(rt.get_theme_font_size("bold_font_size")),
		"leading": int(rt.get_theme_constant("line_separation")),
		"height": float(rt.get_content_height()),
		"ms": float(Time.get_ticks_usec() - started) / 1000.0,
	}
	card.free()
	await process_frame
	return result


func _run() -> void:
	var card_db := root.get_node_or_null("CardDB")
	if card_db == null:
		print("[fit-cache] FATAL: CardDB missing")
		_done = true
		quit(1)
		return
	var card_scene := load("res://scenes/card_2d.tscn") as PackedScene
	var host := Control.new()
	root.add_child(host)
	var faces: Array[Dictionary] = []
	var seen: Dictionary = {}
	for id_variant in card_db.CARD_POOL.keys():
		var id := String(id_variant)
		var base: Dictionary = card_db.CARD_POOL[id]
		if String(base.get("type", "")) not in ["creature", "spell", "armament"]:
			continue
		if String(base.get("rarity", "")) == "enemy":
			continue
		var variants: Array[Dictionary] = [base.duplicate(true)]
		var upgrade: Dictionary = card_db.UPGRADES.get(id, {})
		if upgrade.has("desc"):
			var plus := base.duplicate(true)
			plus["desc"] = String(upgrade["desc"])
			variants.append(plus)
		for data in variants:
			var desc := String(data.get("desc", "")).strip_edges()
			if desc == "":
				continue
			var identity := "%s\u001f%s" % [String(data.get("type", "")), desc]
			if seen.has(identity):
				continue
			seen[identity] = true
			faces.append(data)
	faces.sort_custom(func(a, b):
		return String(a.get("desc", "")).length() \
			> String(b.get("desc", "")).length())
	if faces.size() > SAMPLE_SIZE:
		faces.resize(SAMPLE_SIZE)

	var mismatches: Array = []
	var first_total := 0.0
	var repeat_total := 0.0
	for data in faces:
		var first: Dictionary = await _measure(card_scene, host, data)
		var repeat: Dictionary = await _measure(card_scene, host, data)
		first_total += float(first.ms)
		repeat_total += float(repeat.ms)
		if int(first.font) != int(repeat.font) \
				or int(first.bold) != int(repeat.bold) \
				or int(first.leading) != int(repeat.leading) \
				or absf(float(first.height) - float(repeat.height)) > 0.01:
			mismatches.append({
				"id": String(data.get("id", "?")),
				"first": first,
				"repeat": repeat,
			})

	host.free()
	print("[fit-cache] compared %d long unique card faces" % faces.size())
	print("[fit-cache] first=%.2fms repeat=%.2fms delta=%.2fms" % [
		first_total, repeat_total, first_total - repeat_total])
	if not mismatches.is_empty():
		print("[fit-cache] FAIL mismatches=%d %s" % [mismatches.size(), mismatches])
		_done = true
		quit(1)
		return
	print("[fit-cache] PASS exact font/leading/height matches")
	_done = true
	quit(0)
