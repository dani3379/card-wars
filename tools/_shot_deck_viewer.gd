extends Node
## _shot_deck_viewer.gd — EYES on the in-run deck viewer (MapView._show_deck_viewer).
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_deck_viewer.tscn
##
## The viewer grew a COMPANY LEDGER beside the card grid — a Command-cost curve
## and the tribe roll — and neither can be gated headless. The failure modes are
## all pictures: a bar column that runs past its panel, a ledger that pushes the
## card grid into its own scrollbar, a count that disagrees with the cards
## sitting two inches to its left, a row whose numeral collides with its bar.
##
## Frames → tools/screenshot/:
##   _deck_viewer_full   the whole overlay, a 30-card deck with every tribe in it
##   _deck_viewer_ledger a 2x zoom on the ledger column alone — bar ends, unit
##                       ticks and numerals are not decidable at 1:1
##   _deck_viewer_small  a 12-card starting deck: the ledger with a thin curve
##                       and two tribes, which is what run 1 actually looks like
##
## It also PRINTS the measured geometry (grid rect, ledger rect, scroll rect,
## overflow checks) because "does it fit" is a number, not an impression.
##
## READ THEM. A PASS here is a set of files, not a verdict.

const OUT_DIR := "res://tools/screenshot"
const HERO_ID := "raider"
const SHOT_SEED := 20260912

## A deck built to exercise every bucket of the curve and every tribe of the
## roll — the shot is worthless if the histogram it photographs is flat.
## (cost buckets 0..5+ and all six ctypes are covered between these and the
## Raider's own retinue.)
const EXTRA_CARDS := [
	"pikeman", "shieldmaiden", "warden_sergeant", "iron_bastion",  # soldier
	"brute", "troll", "bloodmoon_alpha", "dragon_hatchling",       # beast
	"mourner", "gravedigger", "the_sexton", "gravepact",           # dead
	"witch", "hedge_caster", "coven_mother",                       # warlock
	"siege_golem", "siegewright", "the_leveler",                   # bastion
	"kingpin",                                                     # stray
	"spark", "star_chart", "fireball",                             # spells
]

var _map: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# The coach owns the whole screen for its first lesson and would photograph
	# itself instead of the viewer.
	UserSettings.coaching_mode = TutorialDB.COACH_OFF
	UserSettings.anim_speed = 2.0

	await _shoot_state("full", true)
	await _shoot_state("small", false)
	print("DECK_VIEWER_SHOTS_DONE")
	get_tree().quit()


func _shoot_state(tag: String, rich: bool) -> void:
	RunState.start_new_run(HERO_ID, -1, SHOT_SEED)
	if rich:
		for cid in EXTRA_CARDS:
			RunState.add_card(cid)
		# Forged and drilled slots, so the curve is reading FOLDED costs rather
		# than what CardDB prints (several "+" entries move the cost).
		for i in [0, 2, 5, 11, 14]:
			if i < RunState.deck.size():
				RunState.upgrade_card(i, "plus")
		RunState.add_card("curse")
		RunState.add_card("war_debt")
	await get_tree().process_frame

	_map = load("res://scenes/map.tscn").instantiate()
	get_tree().root.add_child(_map)
	# HOUSE TRAP (from _shot_tutorial_manual): several helpers resolve their host
	# through get_tree().current_scene, so add_child alone is not enough.
	get_tree().current_scene = _map
	await get_tree().create_timer(3.5).timeout

	_map.call("_show_deck_viewer")
	await _settle()
	_report(tag)
	await _shoot("_deck_viewer_%s" % tag)
	if tag == "full":
		await _shoot_zoom("_deck_viewer_ledger")

	_map.queue_free()
	_map = null
	await get_tree().process_frame


## Poll until the overlay HOLDS. The viewer spawns its cards six per frame and
## each one bakes a texture, so a fixed timer measures the machine.
func _settle() -> void:
	var prev := ""
	for _i in 240:
		await get_tree().process_frame
		var now := _fingerprint(_map)
		if now == prev and now != "":
			return
		prev = now


func _fingerprint(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	var out := ""
	for child in node.get_children():
		if child is Control and (child as Control).is_visible_in_tree():
			var r: Rect2 = (child as Control).get_global_rect()
			out += "%d,%d,%d,%d;" % [roundi(r.position.x), roundi(r.position.y),
				roundi(r.size.x), roundi(r.size.y)]
		out += _fingerprint(child)
	return out


## The numbers behind the picture. Every one of these is a fit question the eye
## answers badly at 1600x900.
func _report(tag: String) -> void:
	var ov: Node = _map.get_node_or_null("DeckOverlay")
	if ov == null:
		print("[deck_shot] %s FAIL — no DeckOverlay" % tag)
		return
	print("[deck_shot] --- %s --- deck %d cards, canvas %s"
		% [tag, RunState.deck.size(), str(get_viewport().get_visible_rect().size)])
	var scroll: ScrollContainer = _find(ov, "ScrollContainer")
	var grid: GridContainer = _find(ov, "GridContainer")
	if scroll != null:
		print("    scroll   %s" % str(scroll.get_global_rect()))
	if grid != null:
		print("    grid     %s  (columns %d)"
			% [str(grid.get_global_rect()), grid.columns])
		if scroll != null and grid.size.x > scroll.size.x:
			print("    OVERFLOW grid is %.0f px wider than its scroll"
				% (grid.size.x - scroll.size.x))
	var ledger: Node = _by_name(ov, "DeckLedger")
	if ledger != null and ledger is Control:
		var lr: Rect2 = (ledger as Control).get_global_rect()
		print("    ledger   %s" % str(lr))
		var canvas: Vector2 = get_viewport().get_visible_rect().size
		if lr.end.x > canvas.x or lr.end.y > canvas.y:
			print("    OVERFLOW ledger runs off the canvas")
		if scroll != null and lr.intersects(scroll.get_global_rect()):
			print("    OVERLAP  ledger sits on the card scroll")
	else:
		print("    ledger   (absent)")


func _find(root: Node, cls: String) -> Node:
	if root.get_class() == cls:
		return root
	for child in root.get_children():
		var found := _find(child, cls)
		if found != null:
			return found
	return null


func _by_name(root: Node, nm: String) -> Node:
	if root.name == nm:
		return root
	for child in root.get_children():
		var found := _by_name(child, nm)
		if found != null:
			return found
	return null


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, tag])
	print("SAVED ", tag, " ", img.get_size())


## The ledger at 2x. A 2px hairline rule and an 8px unit tick are not decidable
## in a 1600-wide frame — same reasoning as _shot_coach_devices' zooms.
func _shoot_zoom(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var ov: Node = _map.get_node_or_null("DeckOverlay")
	var ledger: Node = _by_name(ov, "DeckLedger") if ov != null else null
	if ledger == null or not (ledger is Control):
		print("SKIP ", tag, " — no ledger to zoom")
		return
	var r: Rect2 = (ledger as Control).get_global_rect().grow(12.0)
	r = r.intersection(Rect2(Vector2.ZERO, Vector2(img.get_size())))
	if r.size.x < 4.0 or r.size.y < 4.0:
		print("SKIP ", tag, " — ledger rect is empty")
		return
	var crop: Image = img.get_region(Rect2i(r))
	crop.resize(int(r.size.x * 2.0), int(r.size.y * 2.0), Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [OUT_DIR, tag])
	print("SAVED ", tag, " ", crop.get_size())
