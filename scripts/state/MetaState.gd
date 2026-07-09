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

# Campaign ledger — per-hero records shown on the run-setup screen.
# hero_id → {"wins": int, "losses": int, "best_asc": int} (best_asc = highest
# ascension WON at; -1 until the hero's first victory).
var hero_stats: Dictionary = {}

# Daily March record — one entry, today only (yesterday's march is history the
# moment the date turns): {"date": "YYYY-MM-DD", "hero": id,
# "result": "marching" | "won" | "lost"}.
var daily_record: Dictionary = {}

# Transient flags for the GameOver screen (NOT saved): record_victory runs
# before game_over.tscn loads, so the screen reads these to announce what the
# win just changed instead of the bump happening silently.
var last_victory_unlocked_tier: int = -1
var last_victory_was_fastest: bool = false


func _ready() -> void:
	load_save()


static func today_str() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


func record_daily_start(hero: String) -> void:
	daily_record = {"date": today_str(), "hero": hero, "result": "marching"}
	save()


## Today's daily entry, or {} if the player hasn't marched today.
func todays_daily() -> Dictionary:
	if String(daily_record.get("date", "")) == today_str():
		return daily_record
	return {}


func _hero_entry(hero: String) -> Dictionary:
	if not hero_stats.has(hero):
		hero_stats[hero] = {"wins": 0, "losses": 0, "best_asc": -1}
	return hero_stats[hero]


## Read-only ledger queries for the cross-run muster unlocks (run-setup pane).
## Deliberately don't call _hero_entry — a query must never create a row.
func hero_wins(hero: String) -> int:
	return int(hero_stats.get(hero, {}).get("wins", 0))


## Highest ascension this hero has WON at (-1 = no victory yet).
func hero_best_asc(hero: String) -> int:
	return int(hero_stats.get(hero, {}).get("best_asc", -1))


func record_victory() -> void:
	total_runs += 1
	total_victories += 1
	last_victory_unlocked_tier = -1
	last_victory_was_fastest = false
	if fastest_victory_floors < 0 or RunState.current_floor < fastest_victory_floors:
		# The very first victory sets a baseline, not a "record".
		last_victory_was_fastest = fastest_victory_floors >= 0
		fastest_victory_floors = RunState.current_floor
	# Bump unlocked tier if they beat the current one.
	if RunState.current_ascension >= unlocked_ascension and unlocked_ascension < MAX_ASCENSION:
		unlocked_ascension = mini(RunState.current_ascension + 1, MAX_ASCENSION)
		last_victory_unlocked_tier = unlocked_ascension
	var h := _hero_entry(RunState.current_hero_id)
	h["wins"] = int(h.get("wins", 0)) + 1
	h["best_asc"] = maxi(int(h.get("best_asc", -1)), RunState.current_ascension)
	if RunState.is_daily_run and not todays_daily().is_empty():
		daily_record["result"] = "won"
	save()


func record_defeat() -> void:
	total_runs += 1
	total_defeats += 1
	var h := _hero_entry(RunState.current_hero_id)
	h["losses"] = int(h.get("losses", 0)) + 1
	if RunState.is_daily_run and not todays_daily().is_empty():
		daily_record["result"] = "lost"
	save()


func save() -> void:
	var data := {
		"total_runs": total_runs,
		"total_victories": total_victories,
		"total_defeats": total_defeats,
		"fastest_victory_floors": fastest_victory_floors,
		"unlocked_ascension": unlocked_ascension,
		"hero_stats": hero_stats,
		"daily_record": daily_record,
	}
	SaveIO.write_text(SAVE_PATH, JSON.stringify(data))


func load_save() -> void:
	var raw := SaveIO.read_text(SAVE_PATH)
	if raw == "":
		return
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		# Main file corrupt (crash mid-write left garbage): fall back to the
		# .bak generation — losing one save's delta beats wiping the ledger,
		# and the next save() will re-establish a good main file.
		parsed = JSON.parse_string(SaveIO.read_backup_text(SAVE_PATH))
	if parsed is Dictionary:
		total_runs = parsed.get("total_runs", 0)
		total_victories = parsed.get("total_victories", 0)
		total_defeats = parsed.get("total_defeats", 0)
		fastest_victory_floors = parsed.get("fastest_victory_floors", -1)
		unlocked_ascension = int(parsed.get("unlocked_ascension", 0))
		hero_stats = {}
		var hs = parsed.get("hero_stats", {})
		if hs is Dictionary:
			for k in hs:
				if hs[k] is Dictionary:
					hero_stats[String(k)] = {
						"wins": int(hs[k].get("wins", 0)),
						"losses": int(hs[k].get("losses", 0)),
						"best_asc": int(hs[k].get("best_asc", -1)),
					}
		daily_record = {}
		var dr = parsed.get("daily_record", {})
		if dr is Dictionary and dr.has("date"):
			daily_record = {
				"date": String(dr.get("date", "")),
				"hero": String(dr.get("hero", "")),
				"result": String(dr.get("result", "")),
			}
