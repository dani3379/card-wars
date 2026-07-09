extends SceneTree
## Targeted-spell combat probe (2026-06-18). The autorun flood-bot only plays
## NON-targeted spells (targeted ones need _input clicks), so every
## enemy_creature / friendly_creature / any_creature / any spell resolver was
## unexercised. This boots real combat, stands up friendly + enemy targets, then
## calls _resolve_spell(data, target, lane) directly for each targeted spell
## (target picked via the game's own _auto_target_for) — exercising _resolve_spell
## + _resolve_custom_spell across the whole pool without needing clicks.
## Picker-opening spells are skipped (they'd stall headless).
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_spells.gd

const TURN_WAIT_TICKS := 80
const TICK := 0.1
# Spells whose resolver opens a discard/Discover/keyword picker (await input).
const PICKER_BLOCKLIST := ["war_chant", "lost_tome", "war_council",
	"gambit", "censer_light", "recycle"]

var RS: Node
var CDB: Node
var EDB: Node
var US: Node
var SS: Node
var combat: Node
var _started := false
var _tested := 0
var _skipped := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[spells] start")
	RS = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	if RS == null or CDB == null or EDB == null:
		print("[spells] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	# Collect every draftable TARGETED spell (the untested surface).
	var spells: Array = []
	for id in CDB.CARD_POOL.keys():
		var d: Dictionary = CDB.CARD_POOL[id]
		if String(d.get("type", "")) != "spell":
			continue
		if String(d.get("rarity", "")) == "enemy" or CDB.is_curse(String(id)):
			continue
		var tgt := String(d.get("targeting", "none"))
		if tgt == "none":
			continue   # autorun already covers self-resolving spells
		if String(id) in PICKER_BLOCKLIST:
			continue
		spells.append(String(id))
	spells.sort()
	print("[spells] %d targeted spells to resolve: %s" % [spells.size(), str(spells)])

	RS.start_new_run("raider", 0, 4242)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	if not await _wait_for_player_turn():
		print("[spells] FATAL: never reached player turn"); quit(1); return

	# Stand up a few friendly bodies (so friendly_creature spells have targets).
	await _ensure_friendlies(3)

	for id in spells:
		await _exercise_spell(id)

	print("[spells] ============ SUMMARY ============")
	print("[spells] resolved : %d" % _tested)
	print("[spells] skipped  : %d (no valid target available)" % _skipped)
	print("[spells] (scan log for SCRIPT ERROR / Invalid to find a crashing resolver)")
	print("[spells] DONE")
	quit(0)


func _exercise_spell(id: String) -> void:
	var data: Dictionary = CDB.CARD_POOL[id].duplicate(true)
	var targeting := String(data.get("targeting", "none"))
	# Top up the board so a target exists.
	_ensure_enemies(2)
	if targeting == "friendly_creature":
		await _ensure_friendlies(1)
	var target = combat._auto_target_for(targeting)
	if target == null or not is_instance_valid(target):
		print("[spells] SKIP %s (no %s target)" % [id, targeting])
		_skipped += 1
		return
	var lane: int = maxi(0, int(target.current_lane))
	print("[spells] cast %s -> %s (lane %d)" % [id, targeting, lane])
	await combat._resolve_spell(data, target, lane)
	_tested += 1
	await create_timer(0.04).timeout


func _ensure_enemies(n: int) -> void:
	var live: Array = combat._all_enemy_creatures().filter(
		func(c): return is_instance_valid(c) and not c.has_keyword("structure"))
	var lane := 0
	while live.size() < n and lane < combat.LANES_PER_ROW:
		if combat._row_array(true, combat.ROW_FRONT)[lane] == null:
			combat._place_enemy_card(EDB.make_card_data({"name": "Dummy", "atk": 1, "hp": 8}), lane, combat.ROW_FRONT)
			live = combat._all_enemy_creatures().filter(
				func(c): return is_instance_valid(c) and not c.has_keyword("structure"))
		lane += 1


func _ensure_friendlies(n: int) -> void:
	# Play creatures from hand into empty front lanes until we have n friendlies.
	for _pass in 4:
		var live: Array = combat._all_player_creatures().filter(
			func(c): return is_instance_valid(c))
		if live.size() >= n:
			return
		# Refill the hand with a creature if we have none to play.
		var have_creature := false
		for c in combat._hand:
			if is_instance_valid(c) and c.is_creature():
				have_creature = true; break
		if not have_creature:
			for _draw in 6:
				if combat.has_method("draw_one"):
					combat.draw_one()
				for c in combat._hand:
					if is_instance_valid(c) and c.is_creature():
						have_creature = true; break
				if have_creature:
					break
		var played := false
		for card in combat._hand.duplicate():
			if not is_instance_valid(card) or not card.is_creature():
				continue
			var slot = _empty_player_front()
			if slot == null:
				return
			# Force affordability so placement always succeeds.
			combat.player_mana = 9
			card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5
			combat._on_card_played(card)
			played = true
			await create_timer(0.03).timeout
			break
		if not played:
			return


func _empty_player_front():
	for lane in range(combat.LANES_PER_ROW):
		if combat._row_array(false, combat.ROW_FRONT)[lane] == null:
			return combat._slot_array(false, combat.ROW_FRONT)[lane]
	return null


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		waited += 1
	return false
