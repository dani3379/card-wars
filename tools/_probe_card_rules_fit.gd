extends SceneTree
## _probe_card_rules_fit.gd — DOES EVERY CARD'S RULES TEXT ACTUALLY FIT ITS BOX?
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_card_rules_fit.gd
##
## `Card2D._fit_desc_to_box` spends two budgets to make long copy fit — it tightens
## leading from -2 to -5, then takes ONE font step from 18 to 17 — and then, by its
## own explicit decision, stops and lets the card clip. That is the right call: the
## 18px reading floor is worth more than a fifth line, and the function's comment
## says so outright ("anything still overflowing after both is genuinely
## over-written and wants a copy editor, not a smaller font").
##
## But nothing ever CHECKED which cards land past that line. A clipped card ends
## mid-sentence on the shop shelf, in the Collection, and on the skirmish draft
## slate, where three cards are shown side by side and one of them is missing its
## last clause — and the player has no way to know a rule was cut off rather than
## simply absent. This probe is the missing check: it builds the real hand face for
## every playable card, lets the deferred fitter run, and reports every rules box
## whose content is taller than the box.
##
## It reports and does not fail: the remedy is a copy edit, which is a judgement
## call, and a red gate on prose would just get waived. The COUNT is the signal —
## it should go down and stay down.

const SLACK := 2.0        # px of rounding noise before an overrun counts

var CDB: Node
var _started := false
var _done := false
var _over: Array = []
var _tested := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


## The deepest RichTextLabel holding the card's rules prose. The face also carries
## a name cartouche and a footer, but those are plain Labels — the rules box is the
## only RichTextLabel on a built card face (it needs one for the gilded keywords).
func _find_rules_rt(n: Node) -> RichTextLabel:
	if n is RichTextLabel:
		return n as RichTextLabel
	for c in n.get_children():
		var found := _find_rules_rt(c)
		if found != null:
			return found
	return null


func _run() -> void:
	CDB = root.get_node_or_null("CardDB")
	if CDB == null:
		print("[rules-fit] FATAL: CardDB missing"); _done = true; quit(1); return
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var CardScene = load("res://scenes/card_2d.tscn")

	# BOTH FACES. A "+" entry may override the desc with a longer sentence, and
	# the forged card is shown at exactly the same size in the Collection, at the
	# camp forge preview and on the reward slate — so it clips in exactly the same
	# places. Measuring only the base face would have cleared half the pool blind.
	var faces: Array = []
	var ids: Array = CDB.CARD_POOL.keys()
	ids.sort()
	for id_v in ids:
		var id := String(id_v)
		var d: Dictionary = CDB.CARD_POOL[id]
		if String(d.get("type", "")) not in ["creature", "spell", "armament"]:
			continue
		if String(d.get("rarity", "")) == "enemy":
			continue
		if String(d.get("desc", "")).strip_edges() != "":
			faces.append([id, d.duplicate(true)])
		var up: Dictionary = CDB.UPGRADES.get(id, {})
		if up.has("desc") and String(up["desc"]).strip_edges() != "":
			var plus: Dictionary = d.duplicate(true)
			plus["desc"] = String(up["desc"])
			faces.append([id + " +", plus])

	for face in faces:
		var id := String(face[0])
		var d: Dictionary = face[1]
		var card = CardScene.instantiate()
		card.card_data = d.duplicate(true)
		card.card_id = String(d.get("id", id))
		host.add_child(card)
		# The fitter runs via call_deferred and then loops on get_content_height,
		# which validates the line cache — give it its frames before measuring.
		await process_frame
		await process_frame
		await process_frame
		var rt := _find_rules_rt(card)
		if rt != null and is_instance_valid(rt):
			_tested += 1
			# MEASURE AGAINST THE FITTER'S OWN BUDGET, not the label's box. The
			# rules RichTextLabel self-sizes, so `get_content_height()` and
			# `size.y` come back identical on every card and comparing them can
			# only ever report "fits" — the first cut of this probe did exactly
			# that and cleared a card the screenshot plainly showed clipping. The
			# real ceiling is the `max_h` `_fit_desc_to_box` is handed (80 for a
			# creature, 87 otherwise); past it the label simply grows out of the
			# parent's clip rect and the last line is cut.
			var budget: float = 80.0 if String(d.get("type", "")) == "creature" else 87.0
			var content := rt.get_content_height()
			if content > budget + SLACK:
				_over.append({
					"id": id,
					"name": String(d.get("name", id)),
					"over": content - budget,
					"fs": int(rt.get_theme_font_size("normal_font_size")),
					"chars": String(d.get("desc", "")).length(),
					"desc": String(d.get("desc", "")),
				})
		card.free()
		await process_frame
	host.free()

	print("\n[rules-fit] %d card faces measured" % _tested)
	if _over.is_empty():
		print("[rules-fit] every rules box fits — nothing clipped")
	else:
		_over.sort_custom(func(a, b): return float(a["over"]) > float(b["over"]))
		print("[rules-fit] %d CLIP past the fitter's last step:" % _over.size())
		for e in _over:
			print("   %-22s +%.0fpx  fs=%d  (%d chars)  %s" % [
				e["id"], e["over"], e["fs"], e["chars"], e["desc"]])
	_done = true
	quit(0)
