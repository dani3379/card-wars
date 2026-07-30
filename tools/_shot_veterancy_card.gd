extends SceneTree
## Windowed shot probe: render one hand card with campaign-memory tallies at
## three service records (2 kills / 4 kills / 7 kills + forged) and screenshot
## to tools/screenshot/_veterancy_cards.png. Run WINDOWED (editor closed):
##   Godot.exe --path . --script res://tools/_shot_veterancy_card.gd

# load() lazily inside _process — a class-level preload would compile Card2D
# BEFORE the autoloads register and fail on its CardDB references.
var _frames := 0


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 1:
		var rs: Node = root.get_node_or_null("RunState")
		rs.start_new_run("raider")
		var bg := ColorRect.new()
		bg.color = Color(0.10, 0.085, 0.07)
		bg.size = Vector2(900, 420)
		root.add_child(bg)
		# Find a creature in the starter deck; stage three kill counts.
		var c_idx := -1
		for i in rs.deck.size():
			if String(CardDB_get(rs, i).get("type", "")) == "creature":
				c_idx = i
				break
		var card_scene: PackedScene = load("res://scenes/card_2d.tscn")
		var kills_cases := [2, 4, 7]
		for k in kills_cases.size():
			var uid: int = rs.deck_uids[c_idx]
			rs.creature_kills[uid] = kills_cases[k]
			if kills_cases[k] >= 7:
				rs.upgrade_card(c_idx, "plus")
			var data: Dictionary = rs.get_upgraded_card_data(c_idx)
			var card = card_scene.instantiate()
			card.card_id = String(data.get("id", ""))
			card.card_data = data
			card.position = Vector2(40 + k * 280, 50)
			root.add_child(card)
		return false
	if _frames < 25:
		return false
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_veterancy_cards.png")
	print("[shot] saved tools/screenshot/_veterancy_cards.png")
	quit(0)
	return true


func CardDB_get(rs: Node, i: int) -> Dictionary:
	var cdb: Node = root.get_node_or_null("CardDB")
	return cdb.get_card_data(rs.deck[i])
