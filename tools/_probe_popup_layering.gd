extends SceneTree
## _probe_popup_layering.gd — C28 follow-up: the hover inspector inside a modal.
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_popup_layering.gd
##
## Card2D parents its hover detail popup to a shared CanvasLayer at **layer 90**,
## and the comment at that site states the trade deliberately: "above the HUD (12)
## and frame-grade (40) but BELOW the modal pile / glossary viewers (100)".
##
## That reasoning holds for a popup raised from a card on the board. It stops
## holding the moment a **layer-100 modal is itself full of cards** — and the pile
## viewer builds a six-column grid of real `Card2D` instances, `static_display`
## true. `_on_mouse_entered` carries no `static_display` guard, so those cards
## hover, lift, and call `_show_detail_panel()` like any other. The popup is then
## created ten layers BENEATH the viewer that owns the card being pointed at.
##
## z_index cannot reach across a CanvasLayer — the lesson the veterancy rung
## modals already taught this codebase from the other direction.
##
## So: open the viewer, hover a card in it, and ask two questions the player would
## ask. Is the popup there? And can anything be seen of it?

var _started := false
var _done := false
var _hits := 0

var RS: Node
var US: Node
var EDB: Node


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _settle(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		await create_timer(0.02).timeout
		t += 0.02


func _find_cards(n: Node, out: Array) -> void:
	for ch in n.get_children():
		if ch.get_class() == "PanelContainer" and "card_data" in ch:
			out.append(ch)
		_find_cards(ch, out)


func _layer_of(n: Node) -> int:
	var w: Node = n
	while w != null:
		if w is CanvasLayer:
			return (w as CanvasLayer).layer
		w = w.get_parent()
	return 0


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	EDB = root.get_node_or_null("EncounterDB")
	if RS == null or US == null:
		print("[popup] FATAL: autoloads missing"); _done = true; quit(1); return
	US.anim_speed = 3.0
	US.tooltip_delay = 0.0          # show the inspector on contact, no dwell
	US.end_turn_warning = false

	print("[popup] the hover inspector, raised from inside a layer-100 modal\n")

	seed(4242)
	RS.start_new_run("stalwart", 0, 4242)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	var cb = load("res://scenes/combat.tscn").instantiate()
	root.add_child(cb)
	await _settle(6.0)

	# Stock a pile so the viewer has something to show, then open it.
	if cb._player_discard_pile.is_empty():
		for i in mini(6, RS.deck.size()):
			cb._player_discard_pile.append(RS.deck[i])
	cb._show_pile_viewer(1)
	await _settle(1.2)

	var viewer: CanvasLayer = cb._pile_viewer_layer
	if viewer == null or not is_instance_valid(viewer):
		print("[popup] FATAL: the pile viewer did not open"); _done = true; quit(1); return
	print("[popup] pile viewer is on layer %d" % viewer.layer)

	var cards: Array = []
	_find_cards(viewer, cards)
	print("[popup] %d card(s) standing inside the viewer" % cards.size())
	if cards.is_empty():
		print("[popup] FATAL: no cards in the viewer — nothing to hover")
		_done = true; quit(1); return

	# Hover one, exactly as the mouse would.
	var target = cards[0]
	print("[popup] hovering \"%s\"" % String(target.card_data.get("name", "?")))
	target._on_mouse_entered()
	await _settle(1.0)

	var popup = target._detail_popup
	if popup == null or not is_instance_valid(popup):
		print("[popup] HIT  hovering a card in the viewer raised NO inspector at all")
		_hits += 1
	else:
		var plyr := _layer_of(popup)
		print("[popup] inspector raised on layer %d, visible=%s" % [
			plyr, str(popup.visible)])
		if popup.visible and plyr < viewer.layer:
			_hits += 1
			print("[popup] HIT  THE INSPECTOR IS BURIED.")
			print("        The card being pointed at lives on layer %d; the panel"
				% viewer.layer)
			print("        describing it is built on layer %d, so the viewer's own"
				% plyr)
			print("        backdrop and card grid paint straight over it. The")
			print("        player hovers a card, the card lifts and gilds — and no")
			print("        rules text ever appears.")

	# The same question for every OTHER layer-100 surface that stands a card.
	print("\n[popup] other modal surfaces that hold cards:")
	for pair in [["glossary", 100], ["rung modal", 100]]:
		print("  %-12s layer %d vs inspector layer 90 — same arithmetic"
			% [pair[0], pair[1]])

	cb.free()
	await process_frame
	print("\n[popup] %s" % ("PASS" if _hits == 0 else "%d HIT(S)" % _hits))
	_done = true
	quit(1 if _hits > 0 else 0)
