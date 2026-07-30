extends Node
## _probe_status_riders.gd — the ROUND-SCOPED RIDERS on the battlefield status
## rail (2026-07-28).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_status_riders.gd
##
## A rider is a spell or passive that rewrites what a body DOES for a round —
## strike in the Swift pre-phase, hit every opposing lane, swing twice, soak an
## ally's blow, shrug off every effect in the game. Until this pass none of them
## touched the token: the rule changed and the card said nothing.
##
## The failure mode this exists to catch is SILENT. Card2D._refresh_status_rail
## filters out any entry whose texture is null, so a rider that names a device
## GameTheme never registered does not error, does not warn, and simply never
## appears — which is indistinguishable from the bug it was added to fix. Every
## check below therefore asserts the entry exists AND carries a real texture AND
## brings a worded description to its hover.
##
## It also pins the two truths that made the rail LIE rather than stay quiet:
## Venom Tip's one-round grant must not print as a permanent keyword, and a body
## that prints Swift must not collect a second "granted Swift" orb on top of it.

const CARD_SCENE := preload("res://scenes/card_2d.tscn")

var _fails := 0
var _checks := 0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL  %s" % label)


## Every rider: the state flag to raise, the rail id it must produce, and the
## device it borrows. Kept in step with Card2D._active_effect_entries — a rider
## added there without a row here ships untested.
const RIDERS := [
	{"flag": "war_cry_swift", "id": "granted_swift"},
	{"flag": "drummer_swift", "id": "granted_swift"},
	{"flag": "charges_this_turn", "id": "charging"},
	{"flag": "battle_order_second_strike", "id": "double_strike"},
	{"flag": "redirecting", "id": "redirecting"},
	{"flag": "challenge_any_lane", "id": "challenging"},
	{"flag": "hp_floor", "id": "warded"},
	{"flag": "effect_immune", "id": "effect_immune"},
]


## Marks that are not plain booleans on `state` and need their own fixture.
func _check_guarded() -> void:
	# ward_by is hp_floor's sibling (Oathbound Squire's bodyguard vs Honor
	# Guard's column ward). Marking one and not the other teaches the player to
	# read a missing orb as "unprotected", which would be wrong half the time.
	var body := _make_body()
	_check(_entry_for(body, "guarded").is_empty(), "guarded: present with no bodyguard")
	var guard := _make_body()
	body.ward_by = guard
	_check(not _entry_for(body, "guarded").is_empty(),
		"guarded: no mark while a living bodyguard covers the column")
	# A dead bodyguard guards nothing — the mark must drop with it.
	guard.current_hp = 0
	_check(_entry_for(body, "guarded").is_empty(),
		"guarded: mark survived its bodyguard's death")
	body.queue_free()
	guard.queue_free()


func _check_debt() -> void:
	var body := _make_body()
	_check(_entry_for(body, "debt_due").is_empty(), "debt_due: present with no debt")
	body.state.credit_due_round = 4
	_check(not _entry_for(body, "debt_due").is_empty(),
		"debt_due: no mark while a reckoning is booked")
	body.state.credit_due_round = 999999   # the sentinel Combat writes when paid
	_check(_entry_for(body, "debt_due").is_empty(),
		"debt_due: mark survived the bill being settled")
	body.queue_free()


func _check_spent_reborn() -> void:
	# Reborn is a once-per-body on_death TYPE, not a keyword, so the dict stays
	# on the card after it fires. The mark must not go on promising a revive.
	var body := _make_body()
	body.card_data["keywords"] = []
	body.card_data["on_death"] = {"type": "reborn", "value": 1}
	_check(not _entry_for(body, "trig_on_death").is_empty(),
		"reborn: no death mark before it has fired")
	body.state.reborn_used = true
	_check(_entry_for(body, "trig_on_death").is_empty(),
		"reborn: SPENT reborn still advertises an On-Death that cannot fire")
	# A normal death rider is not once-per-body and must be unaffected.
	var other := _make_body()
	other.card_data["keywords"] = []
	other.card_data["on_death"] = {"type": "damage_face", "value": 2}
	other.state.reborn_used = true
	_check(not _entry_for(other, "trig_on_death").is_empty(),
		"reborn: the spent-reborn guard suppressed an unrelated On-Death")
	body.queue_free()
	other.queue_free()


## THE FIGHT'S OWN RULE (2026-07-29). An encounter passive can lend the enemy line
## Piercing or Thorns; the grant is resolved by LOOKUP at strike time, so it never
## touches `card_data.keywords` and the only thing that can show it is the rail.
## Combat mirrors the live answer into `card_data.encounter_grants` — deliberately
## its own key, because `keywords` is looted, copied, deserted and stripped by half
## a dozen other systems and a field rule parked there would leak onto the player's
## board. This pins the three ways that mirror can go wrong.
func _check_encounter_grants() -> void:
	var foe := _make_body()
	foe.is_opponent = true
	_check(_entry_for(foe, "granted_piercing").is_empty(),
		"granted_piercing: present with no grant")
	foe.card_data["encounter_grants"] = ["piercing", "thorns"]
	for id in ["granted_piercing", "granted_thorns"]:
		var e := _entry_for(foe, id)
		_check(not e.is_empty(), "%s: no rail entry for an encounter grant" % id)
		if not e.is_empty():
			_check(e.get("tex") != null,
				"%s: entry has NO texture (the rail drops it silently)" % id)
			_check(String(e.get("desc", "")) != "", "%s: hover would read blank" % id)
	foe.queue_free()

	# A body that PRINTS the keyword takes its own gilt device from the keyword
	# loop — two orbs for one rule reads as two rules.
	var printer := _make_body()
	printer.is_opponent = true
	printer.card_data["keywords"] = ["piercing"]
	printer.card_data["encounter_grants"] = ["piercing"]
	_check(_entry_for(printer, "granted_piercing").is_empty(),
		"granted_piercing: double-stamped on a creature that already prints it")
	printer.queue_free()

	# The deserter case: _desert_enemy_to_player hands the whole card_data across
	# to YOUR banner, where the encounter's rule no longer applies. An orb still
	# promising it would be the same lie pointed the other way.
	var mine := _make_body()
	mine.is_opponent = false
	mine.card_data["encounter_grants"] = ["piercing"]
	_check(_entry_for(mine, "granted_piercing").is_empty(),
		"granted_piercing: an encounter grant leaked onto a player-side body")
	mine.queue_free()


func _make_body() -> Control:
	var c = CARD_SCENE.instantiate()
	c.card_id = "pikeman"
	c.card_data = CardDB.get_card_data("pikeman")
	if c.card_data.is_empty():
		c.card_data = {"id": "probe_body", "name": "Probe Body", "type": "creature",
			"cost": 1, "atk": 2, "hp": 3, "keywords": [], "rarity": "common", "desc": ""}
	c.is_on_battlefield = true
	c.compact_mode = true
	add_child(c)
	c.current_hp = int(c.card_data.get("hp", 3))
	c.current_atk = int(c.card_data.get("atk", 2))
	# The muster mark is its own rider and would ride along in every result set,
	# so stand the body up as a formed-up soldier and test one rider at a time.
	c.state.ready_to_swing = true
	return c


func _entry_for(body: Control, id: String) -> Dictionary:
	for e in body._active_effect_entries(false):
		if String(e.get("id", "")) == id:
			return e
	return {}


func _ready() -> void:
	print("[riders] === ROUND-SCOPED RIDER RAIL ===")

	for r in RIDERS:
		var flag := String(r["flag"])
		var id := String(r["id"])
		var body := _make_body()
		# Baseline: a plain formed-up body wears none of these.
		_check(_entry_for(body, id).is_empty(), "%s: present before the flag was raised" % id)
		body.state.set(flag, true)
		var e := _entry_for(body, id)
		_check(not e.is_empty(), "%s: no rail entry when state.%s is true" % [id, flag])
		if not e.is_empty():
			# The silent killer — a null texture is dropped by the rail with no
			# error, so the rider would never appear on a real token.
			_check(e.get("tex") != null,
				"%s: entry has NO texture (the rail drops it silently)" % id)
			_check(String(e.get("display", "")) != "", "%s: entry has no display name" % id)
			_check(String(e.get("desc", "")) != "",
				"%s: entry has no description — the hover would read blank" % id)
		body.queue_free()

	_check_guarded()
	_check_debt()
	_check_spent_reborn()
	_check_encounter_grants()

	# Venom Tip's grant is ONE ROUND. It reached the rail through the printed-
	# keyword loop, so it used to render as a permanent rule — the rail claiming
	# a card is something it isn't is worse than the rail staying quiet.
	var vt := _make_body()
	vt.card_data["keywords"] = ["poison"]
	vt.state.temp_poison = true
	var pe := _entry_for(vt, "poison")
	_check(not pe.is_empty(), "temp_poison: no poison entry at all")
	if not pe.is_empty():
		_check(String(pe.get("display", "")).findn("this round") != -1,
			"temp_poison: rail prints the grant as PERMANENT (display=%s)" \
				% String(pe.get("display", "")))
	vt.queue_free()

	# A body that PRINTS Swift must not collect a granted-Swift orb on top of its
	# own keyword — two devices for one rule reads as two rules.
	var sw := _make_body()
	sw.card_data["keywords"] = ["swift"]
	sw.state.war_cry_swift = true
	_check(_entry_for(sw, "granted_swift").is_empty(),
		"granted_swift: double-stamped on a creature that already prints Swift")
	sw.queue_free()

	# A rider is a BATTLEFIELD rule. A hand card prints its full rules text and
	# has no board state to describe, so none of these belong on one.
	var hand := _make_body()
	hand.is_on_battlefield = false
	hand.state.charges_this_turn = true
	_check(_entry_for(hand, "charging").is_empty(),
		"charging: rider leaked onto a card that is not on the battlefield")
	hand.queue_free()

	# The moment-of-change half. Every rider callout must resolve to a real device
	# too, or the flash is a bare word while the orb it leaves behind carries an
	# icon — the same rule arriving and then standing still, in two visual
	# languages. Read straight off Combat.gd's constant map so this never needs
	# the scene booted.
	# This doubles as the project's cheapest REAL COMPILE GATE. `--check-only
	# --script` runs an earlier pass than identifier resolution, so it has
	# green-lit a Combat.gd that could not be load()ed at all (a stray `var` in
	# the wrong match arm, 2026-07-28). A constant count of 0 here means the
	# script did not compile and the game will not boot — see CLAUDE.md.
	var combat_script = load("res://scripts/scenes/Combat.gd")
	var combat_consts: Dictionary = {}
	if combat_script == null:
		print("  [diag] Combat.gd FAILED TO LOAD")
	else:
		combat_consts = combat_script.get_script_constant_map()
		print("  [diag] Combat.gd constants visible: %d %s" % [combat_consts.size(),
			"" if combat_consts.size() > 0 else "  <<< DID NOT COMPILE"])
	_check(combat_consts.size() > 0, "Combat.gd does not compile (game will not boot)")
	var styles: Dictionary = combat_consts.get("_CALLOUT_STYLE", {})
	var aliases: Dictionary = combat_consts.get("_CALLOUT_ICON_ALIAS", {})
	print("  [diag] _CALLOUT_STYLE=%d  _CALLOUT_ICON_ALIAS=%d" % [styles.size(), aliases.size()])
	for rider_id in ["granted_swift", "charging", "double_strike", "challenging",
			"redirecting", "warded",
			# The encounter's lent keywords, and the arrival chip that replaced
			# EncounterEffects' before/after board-size captions.
			"granted_piercing", "granted_thorns", "summoned"]:
		_check(styles.has(rider_id),
			"%s: no _CALLOUT_STYLE entry — the callout would print the raw id" % rider_id)
		var device := String(aliases.get(rider_id, rider_id))
		_check(GameTheme.get_keyword_icon(device) != null,
			"%s: callout device '%s' is not a registered keyword icon" % [rider_id, device])

	print("[riders] %d checks, %d failures" % [_checks, _fails])
	print("[riders] %s" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(1 if _fails > 0 else 0)
