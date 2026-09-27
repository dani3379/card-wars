extends Node
## _shot_writ_amend.gd — eyes for the "the writ is amended" beat
## (Motion.writ_amend), windowed, editor closed:
##   Godot.exe --path "D:\Godot" res://tools/_shot_writ_amend.tscn
##
## The beat is what every PERMANENT change to a deck card now plays. Two
## surfaces are shot because they exercise the two shapes of it:
##   drill_*        — the drill yard, stamping "+1/+1" on the recruit standing
##                    on the yard (the card PERSISTS across the rebuild, so the
##                    stamp lands on a writ the player was already watching)
##   bearer_*       — the standard-bearer, stamping the pinned keyword onto the
##                    taker's tile with the rest of the slate still on screen
## Each is shot mid-beat (the stamp still oversized / the shine mid-sweep) and
## settled. Outputs tools/screenshot/_writ_*.png

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	RunState.start_new_run("stalwart", 0, 4242)
	await get_tree().process_frame

	await _shoot_drill()
	await _shoot_bearer()
	await _shoot_arsenal()
	await _shoot_event_forge()
	await _shoot_war_school()
	await _shoot_rare_foil()

	print("WRIT_SHOTS_DONE")
	get_tree().quit()


func _shoot_drill() -> void:
	RunState.current_wayside_id = "drill_yard"
	var ws: Node = load("res://scenes/wayside.tscn").instantiate()
	get_tree().root.add_child(ws)
	await get_tree().create_timer(0.90).timeout
	await _shoot("drill_picker")

	# Take the first eligible recruit the way a click would.
	var eligible: Array = ws._drill_eligible()
	if eligible.is_empty():
		print("SKIP drill — nothing eligible")
		ws.queue_free()
		return
	ws._on_drill_pick(int(eligible[0]))
	# Deal-in 0.26 + anticipation/shine 0.24 = contact. Catch the IMPACT FRAME
	# first (it lives ~0.13s from contact), then the landed stamp.
	await get_tree().create_timer(0.54).timeout
	await _shoot("drill_flash")
	await get_tree().create_timer(0.14).timeout
	await _shoot("drill_stamp")
	await get_tree().create_timer(1.10).timeout
	await _shoot("drill_settled")

	# THE CLAIM OF THE RESTRUCTURE: a second pass rebuilds the header and the
	# tiles around the SAME card node. If this ever prints CHANGED, the recruit
	# is blinking out and back between passes and the stamp is landing on a
	# stranger. Also checks the busy latch reopened for the new tiles.
	var before_id: int = ws._drill_card.get_instance_id()
	var before_stacks: int = ws._drill_stacks
	_seed_heads()
	ws._on_drill_again()
	await get_tree().create_timer(0.44).timeout
	await _shoot("drill_stamp2")
	await get_tree().create_timer(1.10).timeout
	var same: bool = ws._drill_card != null and is_instance_valid(ws._drill_card) \
		and ws._drill_card.get_instance_id() == before_id
	print("CHECK drill card across passes: ", "SAME" if same else "CHANGED",
		"  stacks ", before_stacks, "->", ws._drill_stacks,
		"  busy=", ws._drill_busy)
	ws.queue_free()
	await get_tree().process_frame


## Reseed so the next randi() in _on_drill_again lands heads (a banked pass),
## otherwise the coin decides whether this check runs at all.
func _seed_heads() -> void:
	for s in 128:
		seed(s)
		if randi() % 2 == 0:
			seed(s)
			return
	seed(0)


func _shoot_bearer() -> void:
	RunState.current_wayside_id = "standard_bearer"
	var ws: Node = load("res://scenes/wayside.tscn").instantiate()
	get_tree().root.add_child(ws)
	await get_tree().create_timer(0.90).timeout
	await _shoot("bearer_donors")

	# Walk the trade: donor → (keyword, if it had a choice) → taker.
	var donors: Array = ws._banner_donors()
	if donors.is_empty():
		print("SKIP bearer — no donor carries a movable keyword")
		ws.queue_free()
		return
	ws._on_banner_donor_pick(int(donors[0]))
	await get_tree().create_timer(0.40).timeout
	if ws._banner_kw == "":
		print("SKIP bearer — stopped on the keyword fork")
		ws.queue_free()
		return
	var takers: Array = ws._banner_receivers(ws._banner_from, ws._banner_kw)
	if takers.is_empty():
		print("SKIP bearer — no taker")
		ws.queue_free()
		return
	# Through the grid's own click path so the picked tile is the stamped one.
	var slot: Control = _find_grid_slot(ws, 0)
	ws._last_pick_slot = slot
	ws._on_banner_receiver_pick(int(takers[0]))
	await get_tree().create_timer(0.44).timeout
	await _shoot("bearer_stamp")
	await get_tree().create_timer(1.10).timeout
	await _shoot("bearer_settled")
	ws.queue_free()
	await get_tree().process_frame


## The Arsenal's forge — it used to mutate the card and change scene in the same
## frame, so this shoots the preview + forge_strike that now stands between.
func _shoot_arsenal() -> void:
	var tr: Node = load("res://scenes/treasure.tscn").instantiate()
	get_tree().root.add_child(tr)
	await get_tree().create_timer(0.60).timeout
	var target: int = -1
	for i in RunState.deck.size():
		if not RunState.has_upgrade_path(i, "plus") \
				and CardDB.is_upgradeable(RunState.deck[i]):
			target = i
			break
	if target < 0:
		print("SKIP arsenal — nothing forgeable")
		tr.queue_free()
		return
	RunState.upgrade_card(target, "plus")
	tr._show_forged_card(target)
	# Deal-in 0.36 + anticipation 0.10 = contact. First frame catches the impact
	# frame, second the squash held through the anvil's hitstop.
	await get_tree().create_timer(0.50).timeout
	await _shoot("arsenal_flash")
	# +0.06 lands inside the anvil's hitstop, where the squash is still HELD.
	# The cool tween is BACK-out over 0.30s and is ~85% home by +0.16, so a
	# later frame just photographs a normal card and proves nothing.
	await get_tree().create_timer(0.06).timeout
	await _shoot("arsenal_forge")
	await get_tree().create_timer(1.00).timeout
	await _shoot("arsenal_settled")
	tr.queue_free()
	await get_tree().process_frame


## Event's forge picker — the stamp lands on the clicked tile before the result
## page, so the change happens where the player is looking.
func _shoot_event_forge() -> void:
	var ev: Node = load("res://scenes/event.tscn").instantiate()
	get_tree().root.add_child(ev)
	await get_tree().create_timer(0.70).timeout
	ev._upgrade_choice_remaining = 1
	ev._upgrade_choice_names = []
	ev._start_upgrade_mode(1)
	await get_tree().create_timer(0.60).timeout
	await _shoot("event_forge_picker")
	var slot: Control = _find_grid_slot(ev, 0)
	if slot == null:
		print("SKIP event forge — no picker tile")
		ev.queue_free()
		return
	# Through the real click path, so _last_pick_tile is set the way it is in play.
	var click: Button = slot.find_children("*", "Button", true, false)[0]
	click.pressed.emit()
	await get_tree().create_timer(0.44).timeout
	await _shoot("event_forge_stamp")
	await get_tree().create_timer(1.30).timeout
	ev.queue_free()
	await get_tree().process_frame


## The war-school rung modal. It used to name the veteran in a title and show
## nothing but two keyword tiles — the card is now standing in it, and the
## chosen lesson is struck onto that card before the modal closes.
func _shoot_war_school() -> void:
	RunState.current_act_idx = 0
	RunState.current_node_type = "combat"
	var cb: Node = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(cb)
	get_tree().current_scene = cb
	await get_tree().create_timer(2.20).timeout

	var veteran: Dictionary = RunState.get_upgraded_card_data(0)
	var schools: Array = cb.get_script().get_script_constant_map()["WAR_SCHOOLS"]
	# Fire and forget — the overlay is a coroutine that runs until it is clicked.
	cb._war_school_overlay(String(veteran.get("name", "The veteran")),
		veteran, schools)
	await get_tree().create_timer(0.45).timeout
	await _shoot("school_modal")

	var tile: Node = null
	for n in cb.find_children("Click", "", true, false):
		if n is BaseButton:
			tile = n
			break
	if tile == null:
		print("SKIP war school — no pick tile found")
		cb.queue_free()
		return
	tile.pressed.emit()
	await get_tree().create_timer(0.44).timeout
	await _shoot("school_stamp")
	await get_tree().create_timer(1.30).timeout
	await _shoot("school_closed")
	cb.queue_free()
	await get_tree().process_frame


## The RARE pull's foil. rarity_reveal's halo says "the slate rolled well" from
## outside the card; the sweep says it about the card itself. Staged bare so the
## shader is judged on its own rather than through a slate's staggered entrance.
func _shoot_rare_foil() -> void:
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(stage)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.07, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(bg)

	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(225, 300)
	wrapper.size = Vector2(225, 300)
	wrapper.position = Vector2(688, 300)
	wrapper.pivot_offset = Vector2(112.5, 150.0)
	stage.add_child(wrapper)
	# CARD_POOL is keyed by id, so iterating it yields Strings, not card dicts.
	var rare_id := ""
	for cid in CardDB.CARD_POOL.keys():
		var cd: Dictionary = CardDB.get_card_data(String(cid))
		if String(cd.get("rarity", "")) == "rare" 				and String(cd.get("type", "")) == "creature":
			rare_id = String(cid)
			break
	var data: Dictionary = CardDB.get_card_data(rare_id)
	var card = load("res://scenes/card_2d.tscn").instantiate()
	card.static_display = true
	card.card_data = data
	card.card_id = rare_id
	card.live_baked_mode = true
	CardTextureCache.bake(data)
	wrapper.add_child(card)
	await get_tree().create_timer(0.40).timeout

	GameTheme.rarity_reveal(wrapper, "rare", 0.0)
	await get_tree().create_timer(0.20).timeout
	await _shoot("rare_foil")
	await get_tree().create_timer(0.22).timeout
	await _shoot("rare_foil_late")
	stage.queue_free()
	await get_tree().process_frame


## First card tile in whatever grid the screen is currently showing.
func _find_grid_slot(root: Node, idx: int) -> Control:
	for n in root.find_children("*", "GridContainer", true, false):
		var g: GridContainer = n
		if g.get_child_count() > idx:
			return g.get_child(idx) as Control
	return null


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_writ_%s.png" % tag)
	print("SAVED writ_", tag, " ", img.get_size())
