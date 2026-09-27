extends SceneTree
## Focused contract probe for Combat's battlefield-creature hover forecast.
## Boots the real combat scene, seats deterministic cards, and exercises the
## public shape returned by `_predict_lane_strike` without resolving a clash.
##
## Run:
## Godot_console.exe --headless --path "D:\Godot" --log-file \
##   "D:\Godot\_codex_probe_combat_telegraph.log" \
##   --script res://tools/_probe_combat_telegraph.gd

const TURN_WAIT_TICKS := 60
const TICK := 0.1

var RS: Node
var CDB: Node
var SS: Node
var US: Node
var combat: Node
var _started := false
var _done := false
var _passed := 0
var _failed: Array[String] = []
var _next_probe_id := 1


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _run() -> void:
	print("[combat-telegraph] start")
	RS = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	SS = root.get_node_or_null("SkirmishState")
	US = root.get_node_or_null("UserSettings")
	if RS == null or CDB == null:
		print("[combat-telegraph] FATAL: required autoloads missing")
		_finish(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
		US.combat_telegraph = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	var net_match := root.get_node_or_null("NetMatch")
	if net_match != null and net_match.has_method("leave"):
		net_match.leave()

	RS.start_new_run("raider", 0, 731337)
	# No starting relic should make a synthetic attack stronger or rescue a body.
	RS.relics.clear()
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_for_player_turn():
		print("[combat-telegraph] FATAL: never reached PLAYER_TURN")
		_finish(1)
		return

	await _test_normal_targeting()
	await _test_mitigation_and_survival()
	await _test_attack_modifiers()
	await _test_disabled_and_intents()
	await _test_sniper_and_hydra()
	await _test_interpose_and_wall()
	await _test_poison_and_recoil()
	await _test_piercing_cleave_and_guardian()
	await _test_overkill_forecast()
	await _test_zero_attack_edges()
	await _test_rescue_wording()
	await _test_heal_projection_and_sniper_order()
	await _test_repeat_notices()
	await _test_pavise_chain_suppression()
	await _test_death_followup_wording()

	print("[combat-telegraph] ============ SUMMARY ============")
	print("[combat-telegraph] passed : %d" % _passed)
	print("[combat-telegraph] FAILED : %d %s" % [_failed.size(), str(_failed)])
	print("[combat-telegraph] DONE")
	_finish(0 if _failed.is_empty() else 2)


func _test_normal_targeting() -> void:
	print("[combat-telegraph] -- normal front / back / face")
	await _reset_board()
	var attacker = _seat_plain(false, 1, 3, 5)
	var front = _seat_plain(true, 1, 0, 5, [], combat.ROW_FRONT)
	_seat_plain(true, 1, 0, 7, [], combat.ROW_BACK)
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("front row has target priority",
		read.get("target") == front and int(read.get("damage", -1)) == 3 \
		and int(read.get("hp_after", -1)) == 2, str(read))

	await _reset_board()
	attacker = _seat_plain(false, 2, 3, 5)
	var back = _seat_plain(true, 2, 0, 4, [], combat.ROW_BACK)
	read = combat._predict_lane_strike(attacker)
	_check("exposed back row becomes the target",
		read.get("target") == back and int(read.get("target_row", -1)) == combat.ROW_BACK \
		and int(read.get("hp_after", -1)) == 1, str(read))

	# THE WORD FOR THE FAR SIDE WAS NEVER THIS PROBE'S CONTRACT. This asserted
	# `contains("FOE HP -3")` and failed on vocabulary alone: the plain-language
	# pass retired "FOE" from UI chrome — a road-register noun in a label costs the
	# player information (docs/COPY_STYLE.md §12) — and the chip has read
	# "ENEMY HP -3 - 17 LEFT" since. The LIVE WORDING IS THE CORRECT SIDE of that
	# disagreement. §12 settles the split as one term per concept: a board-side
	# face is the ENEMY (the HUD around it already says ENEMY DEPLOYMENT / ENEMY
	# REINFORCES / ENEMY COMMAND, KeywordEffects says ENEMY HEALS, and §3 names the
	# concept `enemy face`), while OPPONENT means the human across the wire and is
	# spoken by CombatNet's captions, not here. No live player-facing string in
	# scripts/ says FOE any more; this assertion was the last holdout.
	#
	# So it moved off the vocabulary and onto what the forecast actually promises:
	# that it strikes a FACE, WHOSE face, for how much, and what stands after. All
	# four are structured fields no wording pass can reach — and `target_is_enemy`
	# is the honest way to ask the question "FOE HP" was really asking, which is
	# whether the chip named the right side's bar.
	#
	# The text is still read, but only for the two NUMBERS it must speak aloud:
	# delete the "%s -%d - %d LEFT" line entirely and the fields alone would still
	# pass while the chip said nothing. Digits and a stat abbreviation are the one
	# part of a label COPY_STYLE fixes in place (§2: numbers are digits, the stat
	# is caps), so they are what a probe may safely hold.
	await _reset_board()
	combat.enemy_hp = 20
	attacker = _seat_plain(false, 3, 3, 5)
	read = combat._predict_lane_strike(attacker)
	var face_text := String(read.get("text", ""))
	_check("empty column forecasts enemy face damage",
		bool(read.get("face", false)) and bool(read.get("target_is_enemy", false)) \
		and int(read.get("damage", -1)) == 3 \
		and int(read.get("hp_after", -1)) == 17 \
		and face_text.contains("HP -3") and face_text.contains("17"), str(read))


func _test_mitigation_and_survival() -> void:
	print("[combat-telegraph] -- Shield / Armored / Last Stand")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 4, 5)
	var target = _seat_plain(true, 0, 0, 6, ["shield"])
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Shield forecasts a break with no HP loss",
		read.get("target") == target and bool(read.get("shield_break", false)) \
		and int(read.get("damage", -1)) == 0 and int(read.get("hp_after", -1)) == 6 \
		and String(read.get("text", "")) == "SHIELD BREAKS", str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 4, 5)
	target = _seat_plain(true, 0, 0, 6, ["armored"])
	read = combat._predict_lane_strike(attacker)
	_check("Armored removes one damage",
		read.get("target") == target and int(read.get("damage", -1)) == 3 \
		and int(read.get("hp_after", -1)) == 3, str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 4, 5)
	target = _seat_plain(true, 0, 0, 3, ["last_stand"])
	read = combat._predict_lane_strike(attacker)
	_check("unused Last Stand forecasts survival at 1 HP",
		read.get("target") == target and bool(read.get("last_stand", false)) \
		and not bool(read.get("lethal", true)) and int(read.get("hp_after", -1)) == 1 \
		and String(read.get("text", "")).begins_with("LAST STAND"), str(read))


func _test_attack_modifiers() -> void:
	print("[combat-telegraph] -- Marked / Royal Guard / Archlich")
	await _reset_board()
	var attacker = _seat_plain(false, 1, 2, 5)
	var target = _seat_plain(true, 1, 0, 8)
	target.state.marked = true
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Marked adds two damage",
		int(read.get("damage", -1)) == 4 and int(read.get("hp_after", -1)) == 4,
		str(read))

	await _reset_board()
	attacker = _seat_plain(false, 1, 3, 5)
	target = _seat_plain(true, 1, 0, 6)
	_seat_plain(true, 0, 1, 5, [], combat.ROW_FRONT, {"passive": "royal_guard"})
	read = combat._predict_lane_strike(attacker)
	_check("adjacent Royal Guard removes one damage",
		read.get("target") == target and int(read.get("damage", -1)) == 2 \
		and int(read.get("hp_after", -1)) == 4, str(read))

	await _reset_board()
	combat._encounter_passive = "archlich_immortal"
	attacker = _seat_plain(false, 2, 5, 5)
	target = _seat_plain(true, 2, 0, 3)
	read = combat._predict_lane_strike(attacker)
	_check("Archlich creature-attack floor forecasts 1 HP",
		read.get("target") == target and int(read.get("damage", -1)) == 2 \
		and int(read.get("hp_after", -1)) == 1 and not bool(read.get("lethal", true)),
		str(read))


func _test_disabled_and_intents() -> void:
	print("[combat-telegraph] -- Stunned / CHARGE / ENRAGE / HEAL")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 3, 5)
	_seat_plain(true, 0, 0, 6)
	attacker.state.stunned = true
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Stunned attacker has no forecast", read.is_empty(), str(read))

	await _reset_board()
	attacker = _seat_plain(true, 0, 2, 5)
	_seat_plain(false, 0, 0, 8)
	attacker.state.current_intent = "CHARGE"
	read = combat._predict_lane_strike(attacker)
	_check("CHARGE includes its pending +1 ATK",
		int(read.get("damage", -1)) == 3 and int(read.get("hp_after", -1)) == 5,
		str(read))

	await _reset_board()
	attacker = _seat_plain(true, 0, 2, 5)
	_seat_plain(false, 0, 0, 8)
	attacker.state.current_intent = "ENRAGE"
	read = combat._predict_lane_strike(attacker)
	_check("ENRAGE includes its pending +2 ATK",
		int(read.get("damage", -1)) == 4 and int(read.get("hp_after", -1)) == 4,
		str(read))

	await _reset_board()
	attacker = _seat_plain(true, 0, 2, 5)
	_seat_plain(false, 0, 0, 8)
	attacker.state.current_intent = "HEAL"
	read = combat._predict_lane_strike(attacker)
	_check("HEAL intent spends the attack and has no forecast", read.is_empty(), str(read))


func _test_sniper_and_hydra() -> void:
	print("[combat-telegraph] -- Sniper / Hydra summary")
	await _reset_board()
	var sniper = _seat_plain(false, 0, 2, 4, ["sniper"])
	_seat_plain(true, 0, 0, 5)
	var weakest = _seat_plain(true, 3, 0, 1)
	var read: Dictionary = combat._predict_lane_strike(sniper)
	_check("Sniper forecasts the lowest-HP creature across lanes",
		read.get("target") == weakest and bool(read.get("lethal", false)) \
		and String(read.get("text", "")).contains("CHAINS ON KILL"), str(read))

	await _reset_board()
	var hydra = _seat_id("hydra", false, 0)
	_seat_plain(true, 0, 0, 2)
	_seat_plain(true, 1, 0, 7)
	_seat_plain(true, 2, 0, 5, ["shield"])
	read = combat._predict_lane_strike(hydra)
	var hydra_text := String(read.get("text", ""))
	_check("Hydra summarizes every opposing creature",
		bool(read.get("summary", false)) and int(read.get("target_count", -1)) == 3 \
		and int(read.get("damage", -1)) == 6 \
		and hydra_text.contains("HITS ALL 3") and hydra_text.contains("1 DIE") \
		and hydra_text.contains("1 HURT") and hydra_text.contains("1 SHIELD"),
		str(read))


func _test_interpose_and_wall() -> void:
	print("[combat-telegraph] -- Interpose / face wall")
	await _reset_board()
	combat.player_hp = 20
	var attacker = _seat_plain(true, 0, 3, 5)
	var interposer = _seat_id("shieldmaiden", false, 3)
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Shieldmaiden catches an otherwise open face strike",
		read.get("target") == interposer and not bool(read.get("face", true)) \
		and int(read.get("damage", -1)) == 3 \
		and String(read.get("text", "")).begins_with("INTERPOSES"), str(read))

	# THE FACE WALL. This block used to seat `iron_bastion` and assert it blunted an
	# open face strike by one. That was its `reduce_face_damage` passive, and BOTH
	# halves of it are gone: the card was reworked into the Honor Guard rare in the
	# 2026-07-15 interest slate (`passive: "column_ward"` — an HP floor on its
	# COLUMN-MATE, nothing to do with the face), and the matching arm was deleted
	# from Combat._get_wall_reduction (see the retirement note there, and the same
	# note at _probe_skirmish_combat.gd:1935). No card in the pool carries
	# `reduce_face_damage` today, so the assertion had been describing a mechanic
	# that no longer exists and failing for that reason alone.
	#
	# What it was really guarding is worth keeping: the forecast must apply the SAME
	# wall reduction the resolver applies (_forecast_face_strike and
	# _creature_hits_face both call _get_wall_reduction), or the pre-commit read
	# promises the player face damage the wall is going to eat. So it now exercises
	# the arm that SURVIVED — `cannot_attack_wall`, which unlike the retired one is
	# LANE-SCOPED (|wall lane - struck lane| <= 1) — from both sides: in range it
	# must reduce, out of range it must not.
	await _reset_board()
	combat.player_hp = 20
	attacker = _seat_plain(true, 0, 3, 5)
	_seat_plain(false, 1, 0, 5, [], combat.ROW_BACK,
		{"passive": "cannot_attack_wall"})
	read = combat._predict_lane_strike(attacker)
	_check("a wall one lane over blunts an open face strike by one",
		bool(read.get("face", false)) and int(read.get("damage", -1)) == 2 \
		and int(read.get("hp_after", -1)) == 18, str(read))

	await _reset_board()
	combat.player_hp = 20
	attacker = _seat_plain(true, 0, 3, 5)
	_seat_plain(false, 3, 0, 5, [], combat.ROW_BACK,
		{"passive": "cannot_attack_wall"})
	read = combat._predict_lane_strike(attacker)
	_check("a wall three lanes away blunts nothing - the reduction is lane-scoped",
		bool(read.get("face", false)) and int(read.get("damage", -1)) == 3 \
		and int(read.get("hp_after", -1)) == 17, str(read))


func _test_poison_and_recoil() -> void:
	print("[combat-telegraph] -- Poison / Virulence / Thorns recoil")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 1, 4, ["poison"])
	var target = _seat_plain(true, 0, 0, 7)
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Poison forecasts lethality after a nonlethal hit",
		read.get("target") == target and bool(read.get("lethal", false)) \
		and int(read.get("damage", -1)) == 1 \
		and String(read.get("text", "")).contains("DIES - POISON"), str(read))

	# VIRULENCE THROUGH A SHIELD — THE RULE ITSELF CHANGED, so this assertion was
	# asserting the old one. It used to demand a lethal "DIES - POISON" over a
	# Shielded body, and that WAS the live answer: the resolver's poison branch was
	# gated on `atk > 0`, so a blow the Shield swallowed whole still killed. The
	# comment sitting directly above that branch had claimed "Shield absorbing the
	# hit means no damage was dealt" the entire time — the code did not do what its
	# own comment said. The strike funnel Combat._apply_creature_strike_poison
	# settled it the comment's way: poison now requires HP ACTUALLY REMOVED
	# (`damage_dealt <= 0` returns false), and _forecast_creature_impact moved onto
	# the same rule (`poison_lands = state.damage > 0`, previously `atk > 0` for
	# every kind but sniper). So the live answer flipped, and this is the new one.
	#
	# The positive control comes FIRST on purpose: "no poison" would pass for free
	# if _virulence_active were ignored outright, so prove the flag still kills an
	# unshielded body before asserting that a Shield stops it.
	await _reset_board()
	combat._virulence_active[0] = true
	attacker = _seat_plain(false, 0, 1, 4)
	target = _seat_plain(true, 0, 0, 7)
	read = combat._predict_lane_strike(attacker)
	_check("Virulence alone still forecasts a poison kill (control)",
		read.get("target") == target and bool(read.get("lethal", false)) \
		and int(read.get("damage", -1)) == 1 \
		and String(read.get("text", "")).contains("DIES - POISON"), str(read))

	await _reset_board()
	combat._virulence_active[0] = true
	attacker = _seat_plain(false, 0, 1, 4)
	target = _seat_plain(true, 0, 0, 7, ["shield"])
	read = combat._predict_lane_strike(attacker)
	_check("a Shield swallows the whole blow, so Virulence poisons nothing",
		read.get("target") == target and not bool(read.get("lethal", true)) \
		and bool(read.get("shield_break", false)) and int(read.get("damage", -1)) == 0 \
		and int(read.get("hp_after", -1)) == 7 \
		and not String(read.get("text", "")).contains("POISON"), str(read))

	# ...and the same fixture pushed through the REAL funnels the clash uses —
	# _deal_creature_strike_damage into _apply_creature_strike_poison, the two lines
	# that decide this at strike time (Combat.gd, in _creature_attacks_creature).
	# The forecast above is only honest if the board agrees, and the previous
	# wording of this check ("matches the live Shield interaction") asserted that
	# agreement without ever consulting the live side.
	var live_dealt: int = combat._deal_creature_strike_damage(target, 1)
	var live_poisoned: bool = combat._apply_creature_strike_poison(
		attacker, target, false, live_dealt)
	var live_alive: bool = is_instance_valid(target)
	_check("...and the live strike funnel agrees - Shield spent, body untouched",
		live_dealt == 0 and not live_poisoned and live_alive \
		and int(target.current_hp) == 7 and not bool(target.state.has_shield),
		"dealt=%d poisoned=%s hp=%s shield=%s" % [live_dealt, str(live_poisoned),
			str(target.current_hp) if live_alive else "freed",
			str(target.state.has_shield) if live_alive else "freed"])

	await _reset_board()
	attacker = _seat_plain(false, 0, 2, 1)
	_seat_plain(true, 0, 0, 5, ["thorns"])
	read = combat._predict_lane_strike(attacker)
	_check("Thorns forecasts the attacker's death",
		String(read.get("text", "")).contains("ATTACKER DIES ON RETURN"), str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 2, 3)
	_seat_plain(true, 0, 0, 5, ["thorns"], combat.ROW_FRONT,
		{"venom_thorns": true})
	read = combat._predict_lane_strike(attacker)
	_check("venomous Thorns forecasts its poison kill on the attacker",
		String(read.get("text", "")).contains("ATTACKER DIES ON RETURN"), str(read))


func _test_piercing_cleave_and_guardian() -> void:
	print("[combat-telegraph] -- Piercing / Cleave / Guardian")
	await _reset_board()
	var attacker = _seat_plain(false, 1, 5, 5, ["piercing"])
	_seat_plain(true, 1, 0, 2)
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Piercing reports lethal overkill",
		bool(read.get("lethal", false)) and int(read.get("overkill", -1)) == 3 \
		and String(read.get("text", "")).contains("PIERCES 3"), str(read))

	await _reset_board()
	attacker = _seat_plain(false, 1, 2, 5, [], combat.ROW_FRONT,
		{"passive": "cleave"})
	var main_target = _seat_plain(true, 1, 0, 6)
	_seat_plain(true, 0, 0, 1)
	_seat_plain(true, 2, 0, 4)
	_seat_plain(true, 1, 0, 4, ["shield"], combat.ROW_BACK)
	read = combat._predict_lane_strike(attacker)
	var cleave_text := String(read.get("text", ""))
	_check("Cleave summarizes all three canonical-adjacent riders",
		read.get("target") == main_target and cleave_text.contains("CLEAVE HITS 3") \
		and cleave_text.contains("1 DIE") and cleave_text.contains("1 SHIELD"),
		str(read))

	await _reset_board()
	attacker = _seat_plain(false, 1, 3, 5)
	var intended = _seat_plain(true, 1, 0, 6)
	var guardian = _seat_plain(true, 0, 0, 5, ["guardian"])
	read = combat._predict_lane_strike(attacker)
	_check("Guardian redirects the forecast away from the intended target",
		read.get("target") == guardian and read.get("target") != intended,
		str(read))


func _test_overkill_forecast() -> void:
	# THE FORECAST MUST NAME THE SPILL (docs/COMBAT_LEGIBILITY_20260728.md §4 #1).
	#
	# Before 2026-07-28 the forecast appended a spill line ONLY for Piercing. The
	# universal OVERKILL rule — the whole blocker economy, where a body now REDUCES
	# a blow by its own HP instead of negating a whole attack — was computed into
	# state["overkill"] and then thrown away for everyone else. The pre-commit read
	# said "SLAIN" and nothing more, at the exact moment the player is choosing
	# which body to put in front.
	#
	# The two halves of the contract, and they are easy to collapse into each other:
	#   OVERKILL spills into the body BEHIND the victim and STOPS there. The
	#            forecast may only promise it when such a body exists and is alive,
	#            or the chip advertises damage that goes nowhere.
	#   PIERCING is the keyword that reads on to the FACE. If a Piercing blow ever
	#            printed OVERKILL instead, the keyword would read as a downgrade.
	print("[combat-telegraph] -- OVERKILL spill in the pre-commit forecast")

	# 7 into a 2 HP screen with a live 9 HP body behind it: 5 excess, and it lands.
	await _reset_board()
	var attacker = _seat_plain(false, 1, 7, 9)
	var screen = _seat_plain(true, 1, 0, 2, [], combat.ROW_FRONT)
	_seat_plain(true, 1, 0, 9, [], combat.ROW_BACK)
	var read: Dictionary = combat._predict_lane_strike(attacker)
	var text := String(read.get("text", ""))
	_check("lethal spill onto a screened body forecasts OVERKILL N",
		read.get("target") == screen and bool(read.get("lethal", false)) \
		and int(read.get("overkill", -1)) == 5 and text.contains("OVERKILL 5"),
		str(read))
	_check("...and does NOT claim to pierce (that word belongs to the keyword)",
		not text.contains("PIERCES"), str(read))

	# Same blow, nothing standing behind: the spill goes nowhere, so the forecast
	# must stay silent about it. The NUMBER is still computed — it was never the
	# arithmetic that was missing, only the line — so assert both halves.
	await _reset_board()
	attacker = _seat_plain(false, 1, 7, 9)
	var lone = _seat_plain(true, 1, 0, 2, [], combat.ROW_FRONT)
	read = combat._predict_lane_strike(attacker)
	text = String(read.get("text", ""))
	_check("an unscreened lethal blow forecasts NO overkill line (the spill stops at the body)",
		read.get("target") == lone and bool(read.get("lethal", false)) \
		and not text.contains("OVERKILL") and not text.contains("PIERCES"), str(read))
	_check("...though the spill VALUE is still computed and exposed",
		int(read.get("overkill", -1)) == 5, str(read))

	# Piercing keeps its own word even with a body behind — same fixture, one keyword.
	await _reset_board()
	attacker = _seat_plain(false, 1, 7, 9, ["piercing"])
	_seat_plain(true, 1, 0, 2, [], combat.ROW_FRONT)
	_seat_plain(true, 1, 0, 9, [], combat.ROW_BACK)
	read = combat._predict_lane_strike(attacker)
	text = String(read.get("text", ""))
	_check("Piercing still prints PIERCES, never demoted to OVERKILL",
		text.contains("PIERCES 5") and not text.contains("OVERKILL"), str(read))

	# A back-row victim has nothing behind it by construction (the back rank is the
	# last rank), so the line must not print even though the excess is large.
	await _reset_board()
	attacker = _seat_plain(false, 2, 7, 9)
	var backer = _seat_plain(true, 2, 0, 2, [], combat.ROW_BACK)
	read = combat._predict_lane_strike(attacker)
	text = String(read.get("text", ""))
	_check("a lethal blow on an exposed BACK-row body forecasts no OVERKILL",
		read.get("target") == backer and not text.contains("OVERKILL"), str(read))

	# Exact lethal — zero excess. Never promise a spill of 0.
	await _reset_board()
	attacker = _seat_plain(false, 0, 2, 9)
	var exact = _seat_plain(true, 0, 0, 2, [], combat.ROW_FRONT)
	_seat_plain(true, 0, 0, 9, [], combat.ROW_BACK)
	read = combat._predict_lane_strike(attacker)
	text = String(read.get("text", ""))
	_check("an EXACT lethal blow forecasts no overkill (spill of 0 is not a promise)",
		read.get("target") == exact and bool(read.get("lethal", false)) \
		and int(read.get("overkill", 0)) == 0 and not text.contains("OVERKILL"),
		str(read))

	# Non-lethal into a screen: nothing spills at all.
	await _reset_board()
	attacker = _seat_plain(false, 0, 3, 9)
	var survivor = _seat_plain(true, 0, 0, 9, [], combat.ROW_FRONT)
	_seat_plain(true, 0, 0, 9, [], combat.ROW_BACK)
	read = combat._predict_lane_strike(attacker)
	text = String(read.get("text", ""))
	_check("a NON-lethal blow forecasts no overkill",
		read.get("target") == survivor and not bool(read.get("lethal", true)) \
		and not text.contains("OVERKILL"), str(read))

	# The body behind must be ALIVE to be promised. A 0 HP corpse still standing in
	# the back slot (defer_deaths holds them there mid-clash) is not a landing spot.
	await _reset_board()
	attacker = _seat_plain(false, 3, 7, 9)
	_seat_plain(true, 3, 0, 2, [], combat.ROW_FRONT)
	var corpse = _seat_plain(true, 3, 0, 2, [], combat.ROW_BACK)
	corpse.current_hp = 0
	corpse.update_stat_display()
	read = combat._predict_lane_strike(attacker)
	text = String(read.get("text", ""))
	_check("a downed body behind is not a landing spot — no OVERKILL promised",
		not text.contains("OVERKILL"), str(read))

	await _reset_board()


func _test_zero_attack_edges() -> void:
	print("[combat-telegraph] -- zero-ATK Shield / Armored parity")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 0, 5)
	var target = _seat_plain(true, 0, 0, 5, ["shield"])
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("zero ATK still pops Shield, matching take_damage(0)",
		read.get("target") == target and bool(read.get("shield_break", false)) \
		and int(read.get("damage", -1)) == 0 \
		and String(read.get("text", "")) == "SHIELD BREAKS", str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 0, 5)
	target = _seat_plain(true, 0, 0, 5, ["armored"])
	read = combat._predict_lane_strike(attacker)
	_check("zero ATK into Armored forecasts the resolver's minimum 1",
		read.get("target") == target and int(read.get("damage", -1)) == 1 \
		and int(read.get("hp_after", -1)) == 4, str(read))


func _test_rescue_wording() -> void:
	print("[combat-telegraph] -- Reborn / Phantom Veil wording")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 5, 5)
	var target = _seat_plain(true, 0, 0, 2, [], combat.ROW_FRONT,
		{"on_death": {"type": "reborn", "atk": 1, "hp": 1}})
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Reborn replaces a misleading DIES verdict",
		read.get("target") == target and String(read.get("rescue", "")) == "REBORN" \
		and String(read.get("text", "")) == "REBORN", str(read))

	await _reset_board()
	_equip_relic("phantom_veil")
	attacker = _seat_plain(true, 0, 5, 5)
	target = _seat_plain(false, 0, 0, 2)
	read = combat._predict_lane_strike(attacker)
	_check("Phantom Veil reports its still-available conditional rescue",
		read.get("target") == target \
		and String(read.get("rescue", "")) == "PHANTOM VEIL MAY SAVE" \
		and String(read.get("text", "")) == "PHANTOM VEIL MAY SAVE", str(read))


func _test_heal_projection_and_sniper_order() -> void:
	print("[combat-telegraph] -- pending HEAL projection / Sniper order")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 3, 5)
	var healer = _seat_plain(true, 0, 0, 5)
	healer.current_hp = 1
	healer.state.current_intent = "HEAL"
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("pending HEAL is applied before forecast damage",
		read.get("target") == healer and int(read.get("damage", -1)) == 3 \
		and int(read.get("hp_after", -1)) == 1 and not bool(read.get("lethal", true)),
		str(read))

	await _reset_board()
	var sniper = _seat_plain(false, 3, 2, 4, ["sniper"])
	healer = _seat_plain(true, 0, 0, 5)
	healer.current_hp = 1
	healer.state.current_intent = "HEAL"
	var actual_weakest = _seat_plain(true, 2, 0, 2)
	read = combat._predict_lane_strike(sniper)
	_check("Sniper compares post-HEAL HP when choosing its target",
		read.get("target") == actual_weakest and read.get("target") != healer,
		str(read))


func _test_repeat_notices() -> void:
	print("[combat-telegraph] -- Twinblade / Doubled Hour repeat notices")
	await _reset_board()
	combat.enemy_hp = 20
	var attacker = _seat_plain(false, 0, 2, 4, [], combat.ROW_FRONT,
		{"passive": "attacks_twice"})
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Twinblade face forecast includes its later flank blow",
		bool(read.get("face", false)) \
		and String(read.get("text", "")).contains("FLANK BLOW LATER"), str(read))

	await _reset_board()
	combat.enemy_hp = 20
	combat._doubled_hour[0] = true
	attacker = _seat_plain(false, 0, 2, 4)
	read = combat._predict_lane_strike(attacker)
	_check("Doubled Hour face forecast includes its later repeat",
		bool(read.get("face", false)) \
		and String(read.get("text", "")).contains("STRIKES AGAIN LATER"), str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 2, 1, [], combat.ROW_FRONT,
		{"passive": "attacks_twice"})
	_seat_plain(true, 0, 0, 5, ["thorns"])
	read = combat._predict_lane_strike(attacker)
	var twin_text := String(read.get("text", ""))
	_check("Twinblade flank blow is suppressed when Thorns kills it",
		not bool(read.get("attacker_survives", true)) \
		and twin_text.contains("ATTACKER DIES ON RETURN") \
		and not twin_text.contains("FLANK BLOW"), str(read))

	await _reset_board()
	combat._doubled_hour[0] = true
	attacker = _seat_plain(false, 0, 2, 2, [], combat.ROW_FRONT,
		{"passive": "attacks_all_lanes"})
	_seat_plain(true, 1, 3, 6)
	read = combat._predict_lane_strike(attacker)
	var doubled_text := String(read.get("text", ""))
	_check("Doubled repeat is suppressed when sweep return damage kills it",
		not bool(read.get("attacker_survives", true)) \
		and doubled_text.contains("ATTACKER DIES") \
		and not doubled_text.contains("STRIKES AGAIN"), str(read))


func _test_pavise_chain_suppression() -> void:
	print("[combat-telegraph] -- enemy Sniper / Pavise chain suppression")
	await _reset_board()
	_equip_relic("hexagonal_shield")
	var sniper = _seat_plain(true, 0, 2, 3, ["sniper"])
	var back_target = _seat_plain(false, 2, 0, 1, [], combat.ROW_BACK)
	_seat_plain(false, 1, 0, 5)
	var read: Dictionary = combat._predict_lane_strike(sniper)
	var text := String(read.get("text", ""))
	_check("Pavise kills an enemy Sniper after its back-row shot and stops the chain",
		read.get("target") == back_target and bool(read.get("lethal", false)) \
		and not bool(read.get("attacker_survives", true)) \
		and text.contains("ATTACKER DIES ON RETURN") \
		and not text.contains("CHAINS ON KILL"), str(read))


func _test_death_followup_wording() -> void:
	print("[combat-telegraph] -- Griffin / Death Card / Gravewarden's Pact")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 5, 5)
	var enemy_griffin = _seat_id("griffin", true, 0)
	enemy_griffin.current_hp = 2
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("solo enemy Griffin does not promise a return to the player's hand",
		read.get("target") == enemy_griffin \
		and String(read.get("death_followup", "")) == "" \
		and not String(read.get("text", "")).contains("RETURNS TO HAND"), str(read))

	await _reset_board()
	attacker = _seat_plain(true, 0, 5, 5)
	var friendly_griffin = _seat_id("griffin", false, 0)
	friendly_griffin.current_hp = 2
	friendly_griffin.deck_uid = 91001
	read = combat._predict_lane_strike(attacker)
	_check("friendly Griffin forecasts its once-per-fight hand return",
		read.get("target") == friendly_griffin \
		and String(read.get("death_followup", "")) == "RETURNS TO HAND" \
		and String(read.get("text", "")) == "RETURNS TO HAND", str(read))

	await _reset_board()
	_equip_relic("death_card")
	attacker = _seat_plain(true, 0, 5, 5)
	var death_card_target = _seat_plain(false, 0, 0, 2)
	death_card_target.deck_uid = 91002
	read = combat._predict_lane_strike(attacker)
	_check("Death Card forecasts a friendly non-token returning to hand",
		read.get("target") == death_card_target \
		and String(read.get("death_followup", "")) == "RETURNS TO HAND" \
		and String(read.get("text", "")) == "RETURNS TO HAND", str(read))

	await _reset_board()
	_equip_relic("gravewardens_pact")
	attacker = _seat_plain(true, 0, 5, 5)
	var pact_target = _seat_plain(false, 0, 0, 2)
	pact_target.deck_uid = 91003
	read = combat._predict_lane_strike(attacker)
	_check("Gravewarden's Pact names the 1/1 Imp rebirth after death",
		read.get("target") == pact_target \
		and String(read.get("death_followup", "")) == "REBORN AS A 1/1 IMP" \
		and String(read.get("text", "")).contains("DIES") \
		and String(read.get("text", "")).contains("REBORN AS A 1/1 IMP"), str(read))


func _reset_board() -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr: Array = combat._row_array(is_enemy, row)
			for lane in range(combat.LANES_PER_ROW):
				var card = arr[lane]
				arr[lane] = null
				if card != null and is_instance_valid(card):
					card.queue_free()
	combat._encounter_passive = ""
	combat._virulence_active = [false, false]
	combat._doubled_hour = [false, false]
	combat._gravewardens_rebirths[0] = 0
	combat._gravewardens_rebirths[1] = 0
	combat._griffin_returned_uids.clear()
	combat._death_card_returns.clear()
	combat._cards_played_this_turn = 0
	RS.relics.clear()
	combat._rebuild_relic_cache()
	if combat.has_meta("phantom_veil_used"):
		combat.remove_meta("phantom_veil_used")
	combat.enemy_hp = 30
	combat.player_hp = 30
	combat.player_max_hp = 30
	combat.phase = combat.Phase.PLAYER_TURN
	await process_frame


func _equip_relic(id: String) -> void:
	RS.relics.clear()
	RS.relics.append(id)
	combat._rebuild_relic_cache()


func _seat_id(id: String, is_enemy: bool, lane: int, row: int = 0):
	return _seat_data(CDB.get_card_data(id).duplicate(true), is_enemy, lane, row)


func _seat_plain(is_enemy: bool, lane: int, atk: int, hp: int,
		keywords: Array = [], row: int = 0, extra: Dictionary = {}):
	var data := {
		"id": "telegraph_probe_%d" % _next_probe_id,
		"name": "Forecast Probe",
		"type": "creature",
		"ctype": "soldier",
		"cost": 1,
		"atk": atk,
		"hp": hp,
		"rarity": "common",
		"keywords": keywords.duplicate(),
		"desc": "",
	}
	_next_probe_id += 1
	for key in extra:
		data[key] = extra[key]
	return _seat_data(data, is_enemy, lane, row)


func _seat_data(data: Dictionary, is_enemy: bool, lane: int, row: int):
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = String(data.get("id", "telegraph_probe"))
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.compact_mode = true
	card.card_data = data
	card.current_lane = lane
	card.current_row = row
	card.current_hp = int(data.get("hp", 1))
	card.current_atk = int(data.get("atk", 0))
	# THE MUSTER DELAY (2026-07-21) defaults ready_to_swing to FALSE on every new
	# body, and _forecast_attacker_can_strike gates on can_attack(). Seating a
	# fixture directly skips _start_round's ready-sweep, so without this every
	# _predict_lane_strike below returned {} and all 37 checks failed for one
	# reason that had nothing to do with what they test. In real play the sweep
	# does this at the top of each round; here the probe stands in for it.
	card.state.ready_to_swing = true
	combat._row_array(is_enemy, row)[lane] = card
	var slot = combat._slot_array(is_enemy, row)[lane]
	combat._slot_set_card(slot, card)
	if (data.get("keywords", []) as Array).has("shield"):
		card.state.has_shield = true
	card.destroyed.connect(combat._on_card_destroyed.bind(card))
	card.will_die.connect(combat._on_card_will_die.bind(card))
	card.update_stat_display()
	return card


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[combat-telegraph] PASS  %s" % label)
	else:
		_failed.append(label)
		print("[combat-telegraph] FAIL  %s  %s" % [label, detail])


func _wait_for_player_turn() -> bool:
	for _tick in range(TURN_WAIT_TICKS):
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.PLAYER_TURN:
			return true
		await create_timer(TICK).timeout
	return false
