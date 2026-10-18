extends SceneTree
## Contract probe for the typed creature runtime state.
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_creature_instance.gd

const CreatureState = preload("res://scripts/state/CreatureInstance.gd")
var _failed: bool = false


func _initialize() -> void:
	var source = CreatureState.new()
	source.current_hp = 7
	source.current_atk = 4
	source.lane = 3
	source.row = 1
	source.is_opponent = true
	source.temp_atk_buff = 2
	source.persistent_atk_buff = 1
	source.stunned = true
	source.free_move_used = true
	source.has_shield = true
	source.temp_armored = true
	source.bonus_thorns = 2
	source.mummified_zero = true
	source.current_intent = "ENRAGE"
	source.intent_consecutive = 2

	var full: Dictionary = source.to_snapshot()
	var restored = CreatureState.new()
	restored.apply_snapshot(full)
	_check(full.get("v", 0) == CreatureState.SNAPSHOT_VERSION,
		"snapshot carries its schema version")
	_check(restored.current_hp == 7 and restored.current_atk == 4,
		"base stats round-trip")
	_check(restored.lane == 3 and restored.row == 1 and restored.is_opponent,
		"board identity round-trips")
	_check(restored.stunned and restored.has_shield and restored.temp_armored and restored.free_move_used,
		"combat flags round-trip")
	_check(restored.bonus_thorns == 2 and restored.mummified_zero,
		"typed former-metadata fields round-trip")
	_check(restored.current_intent == "ENRAGE" and restored.intent_consecutive == 2,
		"intent state round-trips")

	var replica: Dictionary = source.to_replication_snapshot()
	_check(not replica.has("atk") and not replica.has("temp_atk") \
		and not replica.has("lane") and not replica.has("opp"),
		"replication snapshot cannot double folded attack or viewer-relative identity")
	var target = CreatureState.new()
	target.current_atk = 9
	target.lane = 1
	target.is_opponent = false
	target.apply_snapshot(replica)
	_check(target.current_atk == 9 and target.lane == 1 and not target.is_opponent,
		"replication snapshot preserves locally-owned fields")
	_check(target.has_shield and target.stunned and target.free_move_used and target.current_intent == "ENRAGE",
		"replication snapshot applies authoritative runtime flags")

	print("[creature-instance] %s" % ("FAILED" if _failed else "all checks passed"))
	quit(1 if _failed else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
		return
	_failed = true
	push_error("[creature-instance] FAIL: %s" % label)
