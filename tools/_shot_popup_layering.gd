extends Node
## _shot_popup_layering.gd — eyes for the buried hover inspector (2026-09-02).
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_popup_layering.tscn
##
## Opens the discard-pile viewer in a real fight, hovers a card in it, and shoots
## the frame. If the inspector is buried the frame shows a lifted, gilded card
## with no rules panel anywhere.

func _ready() -> void:
	UserSettings.anim_speed = 3.0
	UserSettings.tooltip_delay = 0.0
	UserSettings.end_turn_warning = false
	seed(4242)
	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_encounter_id = "goblin_scouts"
	RunState.current_node_type = "combat"
	var cb = load("res://scenes/combat.tscn").instantiate()
	add_child(cb)
	await get_tree().create_timer(6.0).timeout

	if cb._player_discard_pile.is_empty():
		for i in mini(6, RunState.deck.size()):
			cb._player_discard_pile.append(RunState.deck[i])
	cb._show_pile_viewer(1)
	await get_tree().create_timer(1.4).timeout

	var cards: Array = []
	_find_cards(cb._pile_viewer_layer, cards)
	print("[shot] %d cards in viewer" % cards.size())
	if not cards.is_empty():
		var t = cards[mini(2, cards.size() - 1)]
		t._on_mouse_entered()
		print("[shot] hovering \"%s\"" % String(t.card_data.get("name", "?")))
	await get_tree().create_timer(1.6).timeout

	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/_shot_popup_buried.png")
	print("[shot] saved (%s)" % str(img.get_size()))
	get_tree().quit()


func _find_cards(n: Node, out: Array) -> void:
	if n == null:
		return
	for ch in n.get_children():
		if ch.get_class() == "PanelContainer" and "card_data" in ch:
			out.append(ch)
		_find_cards(ch, out)
