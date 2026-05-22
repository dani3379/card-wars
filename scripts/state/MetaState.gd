extends Node
## MetaState.gd — autoload. Tracks data that persists across runs.
## Saved to disk as user://meta.save.
##
## Add to autoload as "MetaState" in Project Settings.

const SAVE_PATH := "user://meta.save"

var total_runs: int = 0
var total_victories: int = 0
var total_defeats: int = 0
var fastest_victory_floors: int = -1
# Highest ascension the player has unlocked by winning at level N. Each victory
# bumps this by 1 (capped at MAX_ASCENSION). The player still picks which
# ascension to play in MainMenu — they're not forced to climb.
var unlocked_ascension: int = 0
const MAX_ASCENSION: int = 5


func _ready() -> void:
	load_save()


func record_victory() -> void:
	total_runs += 1
	total_victories += 1
	if fastest_victory_floors < 0 or RunState.current_floor < fastest_victory_floors:
		fastest_victory_floors = RunState.current_floor
	# Bump unlocked tier if they beat the current one.
	if RunState.current_ascension >= unlocked_ascension and unlocked_ascension < MAX_ASCENSION:
		unlocked_ascension = mini(RunState.current_ascension + 1, MAX_ASCENSION)
	save()


func record_defeat() -> void:
	total_runs += 1
	total_defeats += 1
	save()


func save() -> void:
	var data := {
		"total_runs": total_runs,
		"total_victories": total_victories,
		"total_defeats": total_defeats,
		"fastest_victory_floors": fastest_victory_floors,
		"unlocked_ascension": unlocked_ascension,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var raw = f.get_as_text()
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		total_runs = parsed.get("total_runs", 0)
		total_victories = parsed.get("total_victories", 0)
		total_defeats = parsed.get("total_defeats", 0)
		fastest_victory_floors = parsed.get("fastest_victory_floors", -1)
		unlocked_ascension = int(parsed.get("unlocked_ascension", 0))
