extends Node
## PlayLog — structured, per-action telemetry of what the player actually does,
## written as JSONL (one JSON object per line) to user://playlogs/. Companion to
## the run-level user://runs.csv. Intended for offline study of real games and as
## a training corpus for imitation-learning bots later. Local-only; nothing is
## ever sent anywhere.
##
## One file per run ("session"). Event types:
##   session        — header (hero, deck, relics, seed, mode)
##   combat_start   — a fight begins (encounter, act, mutator)
##   play_creature  — player seats a creature   {card, lane, row, cost, state}
##   play_spell     — player casts a spell       {card, cost, target, state}
##   potion         — player drinks a potion     {potion, state}
##   sacrifice      — a friendly is sacrificed    {card, lane, row, state}
##   end_turn       — player ends their turn      {state}
##   combat_end     — fight resolves             {result, round, hp}
##   map_visit      — player picks a map node     {row, col, type, encounter}
##   deck_add       — a card enters the deck       {id}
##   relic_add      — a relic is acquired          {id}
##   run_end        — run finishes                 {result}
##
## Every gameplay event carries `state` — a compact board/hand/resource snapshot
## taken at DECISION time — so each record is a usable state→action pair.
##
## To disable: set PlayLog.enabled = false (e.g. from a settings toggle) before a
## run starts. Logs live next to saves in the Godot user data dir; find the exact
## path via PlayLog.current_path().

const DIR := "user://playlogs"
const VERSION := 1

var enabled: bool = true

var _f: FileAccess = null
var _session_id: String = ""
var _path: String = ""
var _t0: int = 0
var _seq: int = 0


## Opens a fresh session file. `meta` is merged into the header (hero, deck, etc.).
func start_session(meta: Dictionary = {}) -> void:
	end_session()  # close any prior session first
	if not enabled:
		return
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	_session_id = "%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
	_path = "%s/session_%s.jsonl" % [DIR, _session_id]
	_f = FileAccess.open(_path, FileAccess.WRITE)
	if _f == null:
		push_warning("PlayLog: could not open %s (err %d)" % [_path, FileAccess.get_open_error()])
		return
	_t0 = Time.get_ticks_msec()
	_seq = 0
	var header := {
		"v": VERSION,
		"session": _session_id,
		"started_at": Time.get_datetime_string_from_system(),
		"mode": ("headless" if DisplayServer.get_name() == "headless" else "interactive"),
	}
	header.merge(meta, true)
	log_event("session", header)


## Appends one event line. No-op if no session is open, so callers never guard.
func log_event(type: String, payload: Dictionary = {}) -> void:
	if _f == null:
		return
	# Copy the payload first, then stamp the envelope fields LAST so a colliding
	# payload key (e.g. a map node's own "type") can never clobber the record's
	# seq / t_ms / type.
	var rec: Dictionary = {}
	for k in payload:
		rec[k] = payload[k]
	rec["seq"] = _seq
	rec["t_ms"] = Time.get_ticks_msec() - _t0
	rec["type"] = type
	_seq += 1
	_f.store_line(JSON.stringify(rec))
	_f.flush()  # turn-based pacing — flush so a crash never loses the last play


## Closes the current session. Optional `final` is logged as a run_end event.
func end_session(final: Dictionary = {}) -> void:
	if _f == null:
		return
	if not final.is_empty():
		log_event("run_end", final)
	_f.flush()
	_f.close()
	_f = null
	_path = ""


func is_active() -> bool:
	return _f != null


## Absolute on-disk path of the current session file (for surfacing to the user).
func current_path() -> String:
	return ProjectSettings.globalize_path(_path) if _path != "" else ""


## Absolute on-disk path of the playlogs directory.
func dir_path() -> String:
	return ProjectSettings.globalize_path(DIR)
