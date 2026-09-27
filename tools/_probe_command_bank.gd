extends Node
## _probe_command_bank.gd — CARRYOVER IS A RELIC, and nothing else grants it.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_command_bank.tscn
##
## WHY THIS FILE EXISTS. Unspent Command carried into the next round for
## everybody, always, until 2026-09-16 — and the reasoning that was supposed to
## govern that had already been applied ONCE and then forgotten. Miser's Coffer
## (uncapped banking) was retired 2026-07-25 because "Command is a FIXED resource
## and banking is the clearest violation of that", and the universal 2-point bank
## was left standing beside the note that retired it. A rule nothing asserts is a
## rule that gets re-added by whoever is next in the file.
##
## The new rule has two halves and they fail in opposite directions, so both are
## tested here:
##   · WITHOUT the relic, a round must open on exactly this round's Command. A
##     regression here hands every run a resource it did not earn.
##   · WITH the relic, it must still bank, up to MAX_BANKED_MANA. A regression
##     HERE is the worse one: it makes an uncommon relic do nothing, silently,
##     and there is no error anywhere — the run just quietly plays as though the
##     player had never picked it up.
##
## It also pins the two things a future reader would most plausibly "tidy":
## `_bank_cap()` is the ONE gate (the numeral stays on MAX_BANKED_MANA, the
## relic decides whether any of it applies), and round 1 never banks regardless,
## because there is no previous round to bank FROM.
##
## THE CHEAP MISTAKE THIS PROBE IS BUILT AROUND: `_start_round` reads
## `player_mana` as "last round's leftover" BEFORE it reassigns it, so a test
## that sets the leftover after calling it measures nothing. Every case below
## sets the leftover, calls `_start_round`, and reads what came back.

const COMBAT_SCENE := "res://scenes/combat.tscn"

var _fails := 0


func _ready() -> void:
	# ── 1. NO RELIC: what you do not spend is gone ────────────────────────────
	var plain = await _boot([])
	if plain == null:
		_check(false, "fixture: a plain combat booted")
		_finish()
		return
	_check(plain._bank_cap() == 0,
		"no carryover relic -> _bank_cap() is 0 (got %d)" % plain._bank_cap())
	var plain_carried := await _carry_across_round(plain, 3)
	_check(plain_carried == 0,
		"no relic: 3 Command left on the seal carried NOTHING into the next round (carried %d)"
			% plain_carried)
	plain.queue_free()
	await get_tree().process_frame

	# ── 2. WITH THE RELIC: it banks, and only up to the cap ───────────────────
	# Booted through the real relic list, not by poking _bank_cap, so this also
	# covers _has_relic actually finding the id that RelicDB ships.
	var kept = await _boot([Combat_bank_relic()])
	if kept == null:
		_check(false, "fixture: a combat with the carryover relic booted")
		_finish()
		return
	var cap: int = int(kept.MAX_BANKED_MANA)
	_check(kept._bank_cap() == cap,
		"with the relic, _bank_cap() is MAX_BANKED_MANA (%d, got %d)"
			% [cap, kept._bank_cap()])
	# UNDER the cap: all of it carries, so the relic is not silently rounding.
	var under := maxi(1, cap - 1)
	var carried_under := await _carry_across_round(kept, under)
	_check(carried_under == under,
		"with the relic: %d unspent Command carried whole (carried %d)"
			% [under, carried_under])
	# OVER the cap: the surplus is lost. This is the half that keeps the numeral
	# on MAX_BANKED_MANA rather than on the relic's `value`, which three
	# implementations plus the wire fingerprint read.
	var carried_over := await _carry_across_round(kept, cap + 3)
	_check(carried_over == cap,
		"with the relic: %d unspent Command carried only the cap of %d (carried %d)"
			% [cap + 3, cap, carried_over])
	kept.queue_free()
	await get_tree().process_frame

	# ── 3. THE GATE IS THE RELIC, NOT A SECOND NUMBER ─────────────────────────
	# Read out of source, because the defect this guards against is somebody
	# restating the cap at a call site — which is how the host and its model of
	# the client came apart over relic magnitudes once already (NetPlayerState).
	# The bot's turn machine is the third implementation and it goes through
	# `bank_cap_for`, so a bare MAX_BANKED_MANA clamp anywhere but `_bank_cap` /
	# `bank_cap_for` is the finding.
	#
	# COMMENTS ARE SKIPPED AND THE TEST IS A SHAPE, NOT A COUNT. A threshold ("no
	# more than N mentions") is the wrong oracle for this: it drifts with every
	# comment somebody writes, and the way a drifting gate gets fixed is by
	# raising the number, which is the same as deleting it. Each remaining CODE
	# mention has to be one of the two funnels or the declaration itself, and the
	# failure prints the offending line so it names the restatement directly.
	var src := FileAccess.get_file_as_string("res://scripts/scenes/Combat.gd")
	var strays: Array[String] = []
	for raw in src.split("\n"):
		var line := String(raw).strip_edges()
		if not ("MAX_BANKED_MANA" in line) or line.begins_with("#"):
			continue
		if line.begins_with("const MAX_BANKED_MANA") \
				or line.begins_with("return MAX_BANKED_MANA"):
			continue
		strays.append(line)
	_check(strays.is_empty(),
		"MAX_BANKED_MANA is stated once and read only by the two cap funnels%s"
			% ("" if strays.is_empty() else " — stray: %s" % strays[0]))
	var net_src := FileAccess.get_file_as_string("res://scripts/net/CombatNet.gd")
	_check(not ("combat.MAX_BANKED_MANA" in net_src),
		"the practice bot banks through bank_cap_for, not through a clamp of its own")
	var nps := FileAccess.get_file_as_string("res://scripts/net/NetPlayerState.gd")
	_check("BANK_RELIC" in nps,
		"the host's model of the client gates carryover on the same relic id")

	_finish()


## Leave `spend_left` Command on the seal, open the next round, and report how
## much of it survived — i.e. `player_mana - player_max_mana`, clamped at 0.
##
## The subtraction is the measurement rather than a read of `banked`, because
## `banked` is a local inside _start_round: what a player experiences is the
## count on the seal being ABOVE this round's income, and that is what is
## asserted. Round is forced past 1 first — round 1 has nothing to bank from,
## and testing on it would pass for the wrong reason.
func _carry_across_round(combat, leftover: int) -> int:
	combat.round_number = maxi(2, int(combat.round_number))
	combat.player_mana = leftover
	await combat._start_round()
	return maxi(0, int(combat.player_mana) - int(combat.player_max_mana))


## The relic id, taken from RelicDB rather than spelled here — a probe that
## hardcodes the id it is testing keeps passing after a rename, against a game
## where `_has_relic` on an unknown id is simply false.
func Combat_bank_relic() -> String:
	for id in RelicDB.RELICS.keys():
		if String(RelicDB.RELICS[id].get("effect", "")) == "command_carryover":
			return String(id)
	return ""


func _boot(relics: Array):
	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	for rid in relics:
		if rid != "" and not RunState.relics.has(rid):
			RunState.relics.append(rid)
	await get_tree().process_frame
	var combat = load(COMBAT_SCENE).instantiate()
	add_child(combat)
	# Poll on round + hand, NOT on phase: Phase.PLAYER_TURN is enum 0, which is
	# also the uninitialised default (documented trap).
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			return combat
		await get_tree().create_timer(0.05).timeout
		waited += 1
	return combat if is_instance_valid(combat) else null


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _finish() -> void:
	if _fails == 0:
		print("PROBE PASS: command_bank")
	else:
		print("PROBE FAIL: command_bank (%d failures)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
