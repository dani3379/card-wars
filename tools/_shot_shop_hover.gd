extends Node
## Shoots the Shop's shelf with a relic tile HOVERED — the rule text moved into
## the rich-hover tip, so the tip is now load-bearing and has to be verified
## visually, not assumed.

const SHOP_SCENE := "res://scenes/shop.tscn"


func _ready() -> void:
	RunState.start_new_run("stalwart")
	RunState.gold = 214
	await get_tree().process_frame
	var shop = load(SHOP_SCENE).instantiate()
	add_child(shop)
	await get_tree().create_timer(1.1).timeout

	# The shelf row: first relic tile.
	# The shelf row is the HBox whose direct children are the tile Buttons.
	var row: Node = null
	for child in shop.get_children():
		if not (child is HBoxContainer):
			continue
		var buttons := 0
		for g in child.get_children():
			if g is Button:
				buttons += 1
		if buttons >= 3:
			row = child
			break
	if row == null:
		push_error("[shop-hover] no shelf row found")
		get_tree().quit(1)
		return
	var tile: Control = row.get_child(0)
	print("[shop-hover] hovering %s" % tile)
	# Fire the same signal the mouse would.
	print("[shop-hover] mouse_entered connections: %d" % tile.mouse_entered.get_connections().size())
	tile.mouse_entered.emit()
	await get_tree().create_timer(0.55).timeout
	print("[shop-hover] has _rh_tip meta: %s" % tile.has_meta("_rh_tip"))
	if tile.has_meta("_rh_tip"):
		var tip: Control = tile.get_meta("_rh_tip")
		print("[shop-hover] tip parent=%s pos=%s size=%s vis=%s a=%s z=%s"
			% [tip.get_parent(), tip.position, tip.size, tip.visible,
				tip.modulate.a, tip.z_index])
		print("[shop-hover] tile global_rect=%s" % tile.get_global_rect())
	await _capture("shop_hover")

	# And a tile whose rule is long, to check the tip wraps rather than clips.
	var last: Control = row.get_child(row.get_child_count() - 1)
	tile.mouse_exited.emit()
	last.mouse_entered.emit()
	await get_tree().create_timer(0.55).timeout
	await _capture("shop_hover_last")
	# Let the PNG writes flush — quitting straight after save_png truncates them.
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)


func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	# ROOT viewport, not get_viewport(). Supersample pulls the running scene into
	# a SubViewport, so get_viewport() here returns that SubViewport — and the
	# rich-hover tip is parented to SupersampleLayer OUTSIDE it (attach_rich_hover
	# hosts tips in the nearest CanvasLayer ancestor). Capturing the SubViewport
	# therefore renders a frame the tip can never appear in.
	var image := get_tree().root.get_texture().get_image()
	# Halve it: the 2x viewport lands at 3200x1800, past what review tooling reads.
	image.resize(image.get_width() / 2, image.get_height() / 2,
		Image.INTERPOLATE_LANCZOS)
	image.save_png("res://tools/screenshot/_%s.png" % tag)
	print("  SAVED  ", tag, " ", image.get_size())
