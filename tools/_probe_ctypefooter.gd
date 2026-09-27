extends Node

# THROWAWAY diagnostic. Proves whether the ctype letterpress footer survives the
# baked-overlay path. Builds the SAME card twice: once with a cold texture cache
# (Card2D._build_layout falls through to _build_chart_proto) and once after the
# bake has landed (_build_baked_overlay_layout). Writes to a file because stdout
# from a windowed run is not reliably captured.

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const OUT := "res://tools/_ctypefooter.txt"

var _lines: Array[String] = []


func _log(s: String) -> void:
	_lines.append(s)
	print(s)


func _labels_of(n: Node, acc: Array) -> void:
	if n is Label:
		var t: String = (n as Label).text.strip_edges()
		if t != "":
			acc.append(t)
	for c in n.get_children():
		_labels_of(c, acc)


func _footer_text_for(ct: String) -> String:
	# _build_chart_proto letterspaces the tag: "beast" -> "B E A S T".
	var up := ct.to_upper()
	var out := ""
	for i in range(up.length()):
		out += up[i]
		if i < up.length() - 1:
			out += " "
	return out


func _probe_card(id: String, tag: String) -> bool:
	var data: Dictionary = CardDB.get_card_data(id)
	var ct := String(data.get("ctype", ""))
	var want := _footer_text_for(ct)
	var card = CARD_SCENE.instantiate()
	card.card_data = data.duplicate(true)
	card.card_id = id
	card.is_on_battlefield = true
	card.live_baked_mode = true
	add_child(card)
	await get_tree().process_frame
	await get_tree().process_frame
	var acc: Array = []
	_labels_of(card, acc)
	var found := acc.has(want)
	_log("  [%s] %s  ctype=%s  cache_has=%s  footer(%s)=%s"
		% [tag, id, ct, str(CardTextureCache.has(data)), want,
			"PRESENT" if found else "MISSING"])
	_log("      labels: %s" % str(acc))
	card.queue_free()
	await get_tree().process_frame
	return found


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_log("=== ctype footer A/B (cold cache vs warm cache) ===")
	var ids := ["goblin", "ratling", "brute", "mourner", "cinder_pup"]
	var cold_ok := 0
	var warm_ok := 0
	for id in ids:
		var data: Dictionary = CardDB.get_card_data(id)
		_log("--- %s ---" % id)
		# COLD: make sure nothing is cached for this card yet.
		_log("  pre-bake cache_has=%s" % str(CardTextureCache.has(data)))
		if await _probe_card(id, "COLD"):
			cold_ok += 1
		# Now bake it and rebuild.
		await CardTextureCache.bake(data)
		if await _probe_card(id, "WARM"):
			warm_ok += 1
	_log("")
	_log("COLD (live _build_chart_proto): %d/%d showed the footer" % [cold_ok, ids.size()])
	_log("WARM (_build_baked_overlay_layout): %d/%d showed the footer" % [warm_ok, ids.size()])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit()
