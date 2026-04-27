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
var unlocked_cards: Array[String] = []
var unlocked_relics: Array[String] = []

# Transient — set by record_victory if a card was unlocked. Read by GameOver.
var last_unlocked_card: String = ""


func _ready() -> void:
	load_save()


func record_victory() -> void:
	total_runs += 1
	total_victories += 1
	if fastest_victory_floors < 0 or RunState.current_floor < fastest_victory_floors:
		fastest_victory_floors = RunState.current_floor
	last_unlocked_card = _unlock_random_locked_card()
	save()


# Pick one still-locked card from CardDB and unlock it. Returns the id,
# or "" if everything is already unlocked.
func _unlock_random_locked_card() -> String:
	var locked: Array[String] = CardDB.locked_card_ids()
	if locked.is_empty():
		return ""
	var pick = locked[randi() % locked.size()]
	unlock_card(pick)
	return pick


func record_defeat() -> void:
	total_runs += 1
	total_defeats += 1
	save()


func unlock_card(id: String) -> void:
	if not unlocked_cards.has(id):
		unlocked_cards.append(id)
		save()


func unlock_relic(id: String) -> void:
	if not unlocked_relics.has(id):
		unlocked_relics.append(id)
		save()


func save() -> void:
	var data := {
		"total_runs": total_runs,
		"total_victories": total_victories,
		"total_defeats": total_defeats,
		"fastest_victory_floors": fastest_victory_floors,
		"unlocked_cards": unlocked_cards,
		"unlocked_relics": unlocked_relics,
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
		# Arrays come back as untyped Array; copy element-by-element.
		unlocked_cards.clear()
		for c in parsed.get("unlocked_cards", []):
			unlocked_cards.append(c)
		unlocked_relics.clear()
		for r in parsed.get("unlocked_relics", []):
			unlocked_relics.append(r)
