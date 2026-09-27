extends Node
## _shot_dossier.gd — the title screen's CURRENT RUN plate, ACROSS RUN STATES
## (2026-09-18), windowed, editor closed:
##
##     Godot.exe --path "D:\Godot" res://tools/_shot_dossier.tscn
##
## WHY A DEDICATED TOOL. `_shot_menu` renders whatever save happens to be on
## disk, and the plate's two new figures are POSITIONAL — a road with a standard
## on it and a channel with wax in it. Judging either from one data point says
## nothing about the rest of its range: the profile that reads correctly at
## Act I Province 1 (an almost empty road) is the one that has to read at the
## keep's gate too, and a HEALTH band is a different picture full, half and
## nearly out. This is the COVERAGE rule the pilot's report block exists for —
## a clean look at one state is a clean look at one state.
##
## It injects summaries into `_slot_summary_cache` rather than writing saves. A
## shot harness must never touch the player's save files.
##
## Outputs tools/screenshot/_dossier_<state>.png plus a 3x zoom of the marks,
## and PRINTS A SCANLINE across each — a 15px channel carrying a 1px rim is a
## few pixels of argument at any zoom, and one printed column of luminance
## settles what two renders of staring will not.

var _scene: Node = null

const STATES := [
	{"id": "opening", "act": 1, "floor": 0, "hp": 30, "max_hp": 30, "gold": 100,
		"hero": "raider", "asc": 0},
	{"id": "midact1", "act": 1, "floor": 9, "hp": 22, "max_hp": 30, "gold": 245,
		"hero": "stalwart", "asc": 2},
	{"id": "act2", "act": 2, "floor": 12, "hp": 17, "max_hp": 34, "gold": 61,
		"hero": "acolyte", "asc": 4},
	{"id": "nearboss", "act": 3, "floor": 16, "hp": 6, "max_hp": 30, "gold": 412,
		"hero": "pyromancer", "asc": 7},
	{"id": "atgate", "act": 3, "floor": 17, "hp": 29, "max_hp": 30, "gold": 0,
		"hero": "kindler", "asc": 1},
]


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	_scene = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(1.4).timeout

	for st in STATES:
		_inject(st)
		_scene.call("_build_command_dossier", true)
		await get_tree().create_timer(0.45).timeout
		await _snap(String(st["id"]))

	# The no-save face still has to work — it is the first thing a new player
	# ever sees, and it takes a different branch through the whole builder.
	var empty: Array[Dictionary] = []
	_scene.set("_slot_summary_cache", empty)
	_scene.call("_build_command_dossier", false)
	await get_tree().create_timer(0.45).timeout
	await _snap("nosave")

	print("DOSSIER_SHOTS_DONE")
	get_tree().quit()


## Stand a fabricated run in the menu's own summary cache. `_most_recent_slot`
## picks by `saved_at`, so one filled entry is enough — and `saved_at` is walked
## back per state so the footer's "Set down ..." line is exercised too.
## THE ARRAY MUST BE TYPED. `_slot_summary_cache` is declared
## `Array[Dictionary]`, and `Object.set()` handed an UNTYPED array fails — with
## no error, no warning and no return value — leaving the cache exactly as it
## was. First run of this harness rendered six frames of the real save on disk
## and reported them as six different run states, which is the worst kind of
## clean result: a measurement of something else entirely. Same family as the
## chaos-save probe's `Array[String]`-vs-null trap.
func _inject(st: Dictionary) -> void:
	var days := int(STATES.find(st)) * 3
	var cache: Array[Dictionary] = []
	cache.append({
		"has_save": true, "unreadable": false,
		"act": int(st["act"]), "floor": int(st["floor"]),
		"hp": int(st["hp"]), "max_hp": int(st["max_hp"]),
		"gold": int(st["gold"]), "ascension": int(st["asc"]),
		"hero": String(st["hero"]), "is_daily_run": false, "daily_date": "",
		"saved_at": int(Time.get_unix_time_from_system()) - days * 86400,
	})
	# Pad to SAVE_SLOTS: `_most_recent_slot` walks every slot and `_slot_summary`
	# falls through to the REAL save on disk for any index the cache does not
	# cover, so a one-entry cache lets a genuine slot-1 run win on `saved_at`.
	while cache.size() < RunState.SAVE_SLOTS:
		cache.append({"has_save": false, "unreadable": false})
	_scene.set("_slot_summary_cache", cache)


func _snap(state: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	# THE CANVAS IS 1600x900 AND THE FRAMEBUFFER IS NOT. Derive the ratio from
	# the captured image — a crop centred on a logical coordinate is off by that
	# factor otherwise, and a wide crop still CONTAINS the feature, which is
	# exactly why the mistake survives review (reference_screenshot_probe_limits).
	var rt := float(img.get_size().x) / get_viewport().get_visible_rect().size.x
	var l := int(1100.0 * rt)
	var r := int(1488.0 * rt)
	var t := int(170.0 * rt)
	var h := int(440.0 * rt)
	img.save_png("res://tools/screenshot/_dossier_%s_full.png" % state)
	var crop := img.get_region(Rect2i(l - 40, t - 40, (r - l) + 80, h))
	crop.save_png("res://tools/screenshot/_dossier_%s.png" % state)
	_scanline(state, img, rt)


## Print the plate's vertical value profile: the ladder (ground -> plate -> ink)
## and the two channels' cross-sections, as numbers.
func _scanline(state: String, img: Image, rt: float) -> void:
	var x := int(1294.0 * rt)
	var out := PackedStringArray()
	# ASK THE NODE FOR ITS RECT. Every pixel-side attempt to locate this plate
	# failed once the redesign landed: the old detector looked for rows that were
	# mostly one bright colour, which is exactly the uniform border the molding
	# replaced, and a differential fill test either walked past the bottom edge
	# onto unrelated art or stopped early inside the plate. Both produced
	# confident, wrong geometry — and an INVERSION reading taken between a real
	# top edge and an imaginary bottom one is a number about nothing.
	var plate := _scene.get_node_or_null("CommandDossier") as Control
	if plate != null:
		var rc := plate.get_global_rect()
		out.append("[dossier] %s  RECT canvas x %.0f..%.0f  y %.0f..%.0f" % [
			state, rc.position.x, rc.position.x + rc.size.x,
			rc.position.y, rc.position.y + rc.size.y])
	out.append("[dossier] %s  scanline x=%d (canvas 1294)" % [state, x])
	var ground := _lum(img, int(1040.0 * rt), int(300.0 * rt))
	out.append("  ground(art) %.3f" % ground)
	var lo := 1.0
	var hi := 0.0
	for cy in range(176, 600):
		var y := int(float(cy) * rt)
		if y >= img.get_height():
			break
		var l := _lum(img, x, y)
		lo = minf(lo, l)
		hi = maxf(hi, l)
	out.append("  plate column: min %.3f  max %.3f" % [lo, hi])
	print("\n".join(out))


func _lum(img: Image, x: int, y: int) -> float:
	var c := img.get_pixel(clampi(x, 0, img.get_width() - 1),
		clampi(y, 0, img.get_height() - 1))
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
