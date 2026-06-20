extends SceneTree
## Auto-play combat harness — stability hardening (2026-06-17).
##
## Boots the REAL campaign combat scene headless and auto-plays each EncounterDB
## fight to a win/loss, catching runtime crashes and softlocks that the parse-check
## and logic probes can't. Uses a rotating hero per fight so every starter deck is
## exercised. The auto-pilot is deliberately dumb: each turn it plays every
## affordable creature into an empty slot and every non-targeted spell, then ends
## the turn — which hammers on-enter/on-play effects, the clash resolver, keywords,
## passives, deaths/on-death, reinforcements, escalation, and boss/reactive passives
## across the whole encounter table.
##
## Headless notes:
##   - Combat._prebake_hand_textures() now early-returns headless, so _ready runs to
##     _start_round() instead of parking on the texture bake.
##   - anim_speed is forced to max so _short_pause collapses to one frame (fast runs);
##     end-turn warning is disabled so _on_end_turn never opens a modal.
##   - Starter decks contain no Discover/Choose/Copy cards, so no on-play modal can
##     stall the auto-pilot. (Reward-drafted cards are NOT added in this probe.)
##
## Detection: a per-fight marker is printed before/after each fight. Capture stdout+
## stderr and scan for "SCRIPT ERROR"/"Invalid call" between markers to attribute a
## crash to its fight. The probe itself reports softlocks (a fight that never ends).
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_autorun.gd

const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const MAX_ROUNDS := 40          # a fight that runs past this is treated as a softlock
const TURN_WAIT_TICKS := 80     # ~8s of 0.1s polls waiting for the next player turn
const TICK := 0.1
# Cards whose on-enter/on-play opens a modal picker (Discover / Choose / Copy) or
# casts into one — playing these headless would stall waiting for a click, so the
# auto-pilot draws them (exercising the deck path) but never plays them.
const MODAL_BLOCKLIST := ["familiar", "scholar", "treasure_hunter", "adaptable",
	"copycat", "doppelganger", "lost_tome", "war_council", "chaos_imp"]
# Relics that open a picker/modal the headless auto-pilot can't dismiss (legit in a
# real game — there's a player to click). Mime opens an end-of-turn battlecry picker.
const RELIC_BLOCKLIST := ["mime"]
const POOL_WINDOW := 16         # how many pool cards to inject per fight (rotates)

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var NM: Node
var CDB: Node
var RDB: Node
var combat: Node
var _pool: Array = []
var _relic_ids: Array = []

var _started := false
var _done := false
var _fights := 0
var _wins := 0
var _losses := 0
var _stuck: Array = []
var _bail := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	print("[autorun] start")
	RS  = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US  = root.get_node_or_null("UserSettings")
	SS  = root.get_node_or_null("SkirmishState")
	NM  = root.get_node_or_null("NetMatch")
	if RS == null or EDB == null:
		print("[autorun] FATAL: autoloads missing (RunState/EncounterDB)")
		_finish(1)
		return
	# Speed pauses to ~0 and never pop the end-turn warning modal.
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	# Make sure no stale skirmish state routes combat into a net path.
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	if NM != null and NM.has_method("leave"):
		NM.leave()
	# Build the full draftable card pool + relic id list for stress coverage.
	CDB = root.get_node_or_null("CardDB")
	RDB = root.get_node_or_null("RelicDB")
	if CDB != null:
		for id in CDB.CARD_POOL.keys():
			var d: Dictionary = CDB.CARD_POOL[id]
			if String(d.get("type", "")) in ["creature", "spell"] \
					and String(d.get("rarity", "")) != "enemy" and not CDB.is_curse(String(id)):
				_pool.append(String(id))
		_pool.sort()
	if RDB != null:
		for rid in RDB.RELICS.keys():
			_relic_ids.append(String(rid))
		_relic_ids.sort()
	print("[autorun] pool=%d draftable cards, %d relics" % [_pool.size(), _relic_ids.size()])

	var enc_ids: Array = []
	for id in EDB.ENCOUNTERS.keys():
		enc_ids.append(String(id))
	enc_ids.sort()
	print("[autorun] %d encounters to fight" % enc_ids.size())

	for i in enc_ids.size():
		if _bail:
			break
		var hero: String = HEROES[i % HEROES.size()]
		await _fight(i + 1, enc_ids.size(), hero, enc_ids[i])

	print("[autorun] ============ SUMMARY ============")
	print("[autorun] fights run : %d" % _fights)
	print("[autorun] wins/losses: %d / %d" % [_wins, _losses])
	print("[autorun] softlocks  : %d %s" % [_stuck.size(), str(_stuck)])
	print("[autorun] (scan the log above for SCRIPT ERROR / Invalid call to attribute crashes)")
	print("[autorun] DONE")
	_finish(1 if _stuck.size() > 0 else 0)


func _fight(n: int, total: int, hero: String, enc_id: String) -> void:
	var enc: Dictionary = EDB.get_encounter(enc_id)
	var etype: String = String(enc.get("type", "combat"))
	print("[autorun] >>> FIGHT %d/%d hero=%s enc=%s type=%s" % [n, total, hero, enc_id, etype])
	RS.start_new_run(hero, 0, 4242)
	RS.current_encounter_id = enc_id
	RS.current_node_type = etype if etype in ["combat", "elite", "boss"] else "combat"

	# Stress coverage on top of the hero's starter deck: guarantee the board-verb
	# cards in the first couple of fights, then a rotating window of the whole
	# draftable pool so every card gets drawn/played across the run; plus a few
	# rotating relics each fight to exercise relic hooks (reset per start_new_run).
	if n <= 2:
		for cid in ["pikeman", "pikeman", "harpy", "harpy", "lookout", "raven"]:
			RS.add_card(cid)
	for k in POOL_WINDOW:
		if _pool.size() > 0:
			RS.add_card(_pool[((n - 1) * POOL_WINDOW + k) % _pool.size()])
	for r in 3:
		if _relic_ids.size() > 0:
			var rid: String = _relic_ids[((n - 1) * 3 + r) % _relic_ids.size()]
			if not (rid in RELIC_BLOCKLIST):
				RS.add_relic(rid)

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	_fights += 1

	# Wait for _ready to reach the first player turn (or an instant game-over).
	if not await _wait_for_player_turn():
		# never reached a player turn and not over -> stuck during boot/round 1
		_record_stuck(enc_id, "boot")
		await _teardown()
		return

	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER and rounds < MAX_ROUNDS:
		await _auto_play_turn()
		if not is_instance_valid(combat):
			break
		# End the turn (bypass the warning; it's disabled anyway).
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		# Wait for the resolve/enemy/next-round chain to hand control back.
		if not await _wait_for_player_turn():
			break  # either game-over (loop cond catches it) or stuck (handled below)

	if is_instance_valid(combat) and combat.phase == combat.Phase.GAME_OVER:
		if int(combat.enemy_hp) <= 0:
			_wins += 1
			print("[autorun] <<< result=WIN  rounds=%d" % rounds)
		else:
			_losses += 1
			print("[autorun] <<< result=LOSS rounds=%d" % rounds)
	elif rounds >= MAX_ROUNDS:
		_record_stuck(enc_id, "max_rounds")
	elif is_instance_valid(combat):
		_record_stuck(enc_id, "no_player_turn")
	await _teardown()


## Poll until the scene is in PLAYER_TURN (ready for input) or GAME_OVER.
## Returns false only if it timed out in some other phase (potential softlock).
func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.GAME_OVER:
			return true
		if combat.phase == combat.Phase.PLAYER_TURN:
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false


func _auto_play_turn() -> void:
	# Several passes, since playing a card can grant Command (ramp) and open more plays.
	for _pass in 4:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var played_any := false
		for card in combat._hand.duplicate():
			if not is_instance_valid(card) or not (card in combat._hand):
				continue
			var cd: Dictionary = card.card_data
			# (Curses are harmless to "play" — a none-spell that wastes itself — so
			# we don't special-case them; playing one just exercises that path.)
			if String(cd.get("id", "")) in MODAL_BLOCKLIST:
				continue   # would open a picker and stall headless
			var cost: int = int(cd.get("cost", 0))
			if int(combat.player_mana) < cost:
				continue
			var ctype: String = String(cd.get("type", ""))
			if ctype == "creature":
				var slot = _find_empty_player_slot()
				if slot == null:
					continue
				card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5
				combat._on_card_played(card)
				played_any = true
				await create_timer(0.03).timeout
			elif ctype == "spell":
				# Only self-resolving spells — targeted ones need _input clicks.
				if String(cd.get("targeting", "none")) == "none":
					combat._on_card_played(card)
					played_any = true
					await create_timer(0.03).timeout
		if not played_any:
			return


func _find_empty_player_slot():
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for lane in range(combat.LANES_PER_ROW):
			if combat._row_array(false, row)[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


func _record_stuck(enc_id: String, why: String) -> void:
	print("[autorun] <<< result=STUCK (%s) enc=%s" % [why, enc_id])
	_stuck.append("%s:%s" % [enc_id, why])


func _teardown() -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	combat = null
	# Let the freed scene's timers/tweens settle before the next boot.
	await create_timer(0.1).timeout


func _finish(code: int) -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	_done = true
	quit(code)
