extends Node
## _shot_shell_screens.gd — renders the main shell screens to PNG for a
## gold-overuse / text-density audit (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_shell_screens.tscn
## Outputs tools/screenshot/_shell_<name>.png

const SCENES := {
	"shop": "res://scenes/shop.tscn",
	"rest": "res://scenes/rest.tscn",
	"reward": "res://scenes/reward.tscn",
	"treasure": "res://scenes/treasure.tscn",
	"recruit": "res://scenes/recruit.tscn",
	"collection": "res://scenes/collection.tscn",
	"gameover": "res://scenes/game_over.tscn",
}

var _scene: Node = null


func _ready() -> void:
	# Same prelude the map harness needs: let settings boot, then force window
	# state + SSAA off so the root-window capture isn't empty/black.
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	RunState.start_new_run("raider")
	RunState.gold = 214
	RunState.hero_hp = 16
	# Give a couple relics + potions so counters/strips render populated.
	RunState.add_relic("whetstone")
	RunState.add_relic("war_horn")
	RunState.add_potion("healing")
	RunState.add_potion("bottled_fury")
	await get_tree().process_frame

	# Reward needs its elite-relic choices staged before _ready builds UI.
	for key in SCENES:
		await _shoot(key, SCENES[key])

	# Defeat variant of game over — the charred chronicle page, plus staged
	# campaign memory so NAMED VETERANS and THE ROLL OF THE FALLEN render.
	RunState.hero_hp = 0
	RunState.cause_of_death = "the Kindler"
	RunState.fallen = [
		{"uid": 9001, "name": "Pikeman the Grim", "enc": "the Bone Pit", "act": 1},
		{"uid": 9002, "name": "Outrider", "enc": "the Kindler", "act": 2},
	]
	RunState.creature_kills = {9001: 7}
	await _shoot("gameover_defeat", SCENES["gameover"])

	print("SHELL_SHOTS_DONE")
	get_tree().quit()


func _shoot(name: String, path: String) -> void:
	if name == "reward":
		RunState.current_node_type = "elite"
	_scene = load(path).instantiate()
	if name == "reward" and _scene.has_method("set"):
		_scene.set("_is_elite_reward", true)
		_scene.set("_relic_choices", ["ice_cream", "sozu", "lantern"])
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(3.2).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_shell_%s.png" % name)
	print("SAVED ", name, " ", img.get_size())
	_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
