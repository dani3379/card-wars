extends Node
## _shot_warband_ledger.gd — renders the NetDraft warband ledger (the
## Hearthstone-style row-art strips, 2026-07-07) to PNG (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_warband_ledger.tscn
## Shot: tools/screenshot/_warband_ledger.png — a mid-draft ledger with a relic,
## spells, creatures, and ×2 stacks so every row variant is on screen.

const PICKS: Array = [
	"spark", "banish", "blood_tithe", "dark_pact", "frost_bolt", "offering",
	"ratling", "plague_rat", "blood_pyre", "pikeman", "pikeman",
	"harpy", "harpy", "bloodsworn", "bloodsworn", "vampire_lord", "the_leveler",
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

	# Practice-bot session — the draft screen runs for real without a socket.
	NetMatch.start_vs_bot(SkirmishState.MatchMode.DRAFT, 1)
	var draft = load("res://scenes/net_draft.tscn").instantiate()
	get_tree().root.add_child(draft)
	await get_tree().create_timer(1.0).timeout

	# The arsenal stage (2026-07-16 API): 3 relic slates + 2 potion slates —
	# take one relic, pass the rest, so the ledger shows an arsenal row.
	draft._on_ars_pick("deep_satchel", true)
	draft._on_ars_pick("", true)
	draft._on_ars_pick("", true)
	await get_tree().create_timer(0.3).timeout
	draft._on_ars_pick("healing", false)
	draft._on_ars_pick("", false)
	await get_tree().create_timer(0.3).timeout
	for id in PICKS:
		draft._on_pick(id)
	await get_tree().create_timer(1.0).timeout

	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_warband_ledger.png")
	print("SAVED warband_ledger ", img.get_size())
	get_tree().quit()
