extends SceneTree
## Per-CARD power sweep (2026-07-01). Isolates each draftable card's combat impact
## by STACKING it: deck = COPIES copies of the test card + goblin filler (10 total),
## run through a fixed 3-act gauntlet with the smart auto-pilot. Score per fight =
## HP MARGIN (player_hp - enemy_hp) at game-over or a round cap — a continuous
## strength signal that separates cards even when the binary win/loss is the same.
##
## Read it as an OUTLIER detector: cards far ABOVE the pack are over-strong; cards
## near or below the 10-goblin BASELINE are under-strong (literally no better than
## filling your deck with 1/2 goblins). Confounds to keep in mind: high-cost cards
## lose a little to curve-clog; pure SYNERGY enablers read low with only goblins to
## work with; cards needing a pick UI can't be auto-played (listed separately).
##
## Run (background — ~350 fights):
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_cardpower.gd

const HERO := "raider"
# brute = a solid vanilla-ish common (2/3, on-enter 1 to opposing creature, NO face
# damage). Makes the baseline "an average common" so a card's score answers "is this
# better or worse than a fair common body?" — and avoids goblin's face-rush ceiling
# (with goblin filler EVERY card scored below baseline because 10 goblins face-rush).
const FILLER := "brute"
const COPIES := 4
const FILL := 6
# Overridable at runtime: --filler=<id> swaps the shell (brute = neutral FLOOR;
# goblin = aggressive/go-wide/death CEILING for condition-enabling cards).
var _filler: String = FILLER
# --only=<id> sims just that one card (bypasses the draftable/modal filter, so temp
# variant cards marked rarity:"enemy" can still be graded). Repeatable via commas.
var _only: Array = []
# --copies=N : how many copies of the test card to stack. Default 4 amplifies a
# CREATURE's signal, but for non-body cards (buff/utility SPELLS) 4 copies means 4
# fewer creatures than baseline + redundant draws — grade those at --copies=1 ("is
# ONE worth a card slot, given bodies to act on?").
var _copies: int = COPIES
# [encounter, rng_seed] — the seed is FIXED per encounter and reused across every
# card (common random numbers), so two cards face identical enemy draws/placement
# and the margin gap is attributable to the CARD, not luck. Combat's 98 global
# randi()/shuffle() calls are otherwise unseeded (baseline swung +8..+15 run-to-run).
const GAUNTLET := [["bandit_camp", 111], ["dragons_lair", 333]]   # act1 + act3 range
const MAX_ROUNDS := 6
const TURN_WAIT_TICKS := 70
const TICK := 0.1
# Cards the headless bot can't play (open a pick UI / need special state).
const MODAL := ["familiar", "scholar", "treasure_hunter", "adaptable", "copycat",
	"doppelganger", "lost_tome", "war_council", "chaos_imp", "war_chant",
	"gambit", "recycle", "reanimate", "grave_robbery"]

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var CDB: Node
var combat: Node
var _started := false
var _scores: Array = []   # [{id, cost, rarity, type, score}]
var _baseline := 0.0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[cardpow] start")
	RS = root.get_node_or_null("RunState"); EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings"); SS = root.get_node_or_null("SkirmishState")
	CDB = root.get_node_or_null("CardDB")
	if RS == null or EDB == null or CDB == null:
		print("[cardpow] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	# Build the testable card list: draftable creatures + spells, minus curses,
	# enemy-only, the filler itself, and modal (un-auto-playable) cards.
	var ids: Array = CDB.CARD_POOL.keys()
	ids.sort()
	var test_ids: Array = []
	var skipped_modal: Array = []
	for id in ids:
		var sid := String(id)
		var d: Dictionary = CDB.CARD_POOL[sid]
		var t := String(d.get("type", ""))
		var r := String(d.get("rarity", ""))
		if t not in ["creature", "spell"]: continue
		if r == "enemy": continue
		if CDB.is_curse(sid): continue
		if sid == FILLER: continue
		if sid in MODAL:
			skipped_modal.append(sid); continue
		test_ids.append(sid)
	# --from=N --to=M slices the test list so a foreground run fits under 10 min
	# (background runs get killed at session teardown). Chunks are combined at the end.
	var from_i := 0
	var to_i := test_ids.size()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--from="): from_i = int(arg.substr(7))
		elif arg.begins_with("--to="): to_i = int(arg.substr(5))
		elif arg.begins_with("--filler="): _filler = arg.substr(9)
		elif arg.begins_with("--only="): _only = arg.substr(7).split(",", false)
		elif arg.begins_with("--copies="): _copies = maxi(1, int(arg.substr(9)))
	from_i = clampi(from_i, 0, test_ids.size())
	to_i = clampi(to_i, from_i, test_ids.size())
	# --only wins: grade exactly the listed ids (any rarity), skipping the sweep.
	var chunk: Array = _only if _only.size() > 0 else test_ids.slice(from_i, to_i)
	print("[cardpow] shell=%s | testing %s over gauntlet %s (%d copies + %d filler, cap %d rounds)"
		% [_filler, ("only " + str(_only) if _only.size() > 0 else "[%d..%d) of %d" % [from_i, to_i, test_ids.size()]), str(GAUNTLET), COPIES, FILL, MAX_ROUNDS])

	# Baseline: a pure 10-filler deck — the reference line for THIS shell.
	_baseline = await _score_deck([])
	print("[cardpow] BASELINE (10x %s) margin = %+.1f" % [_filler, _baseline])

	var n := 0
	for sid in chunk:
		var score: float = await _score_deck([sid])
		var d: Dictionary = CDB.CARD_POOL[sid]
		_scores.append({"id": sid, "cost": int(d.get("cost", 0)),
			"rarity": String(d.get("rarity", "")), "type": String(d.get("type", "")),
			"score": score})
		n += 1
		print("[cardpow] %3d/%d  %-20s %+6.1f (base %+.1f, lift %+.1f)"
			% [n, chunk.size(), sid, score, _baseline, score - _baseline])

	# ── Report ──
	_scores.sort_custom(func(a, b): return a["score"] > b["score"])
	print("\n[cardpow] ===================== RANKING (strongest first) =====================")
	print("[cardpow] baseline (10x goblin) = %+.1f  | lift = card_score - baseline" % _baseline)
	for row in _scores:
		print("[cardpow] %+6.1f  lift %+6.1f  %-20s [%s %dcc %s]" % [
			row["score"], row["score"] - _baseline, row["id"], row["type"], row["cost"], row["rarity"]])
	# Outlier flags: top/bottom deciles + anything at or below baseline.
	var k: int = maxi(3, _scores.size() / 10)
	print("\n[cardpow] ===== TOO GOOD? (top %d) =====" % k)
	for i in range(mini(k, _scores.size())):
		print("[cardpow]   %-20s %+6.1f (lift %+.1f)" % [_scores[i]["id"], _scores[i]["score"], _scores[i]["score"] - _baseline])
	print("[cardpow] ===== TOO BAD? (bottom %d — at/under a goblin) =====" % k)
	for i in range(maxi(0, _scores.size() - k), _scores.size()):
		print("[cardpow]   %-20s %+6.1f (lift %+.1f)" % [_scores[i]["id"], _scores[i]["score"], _scores[i]["score"] - _baseline])
	print("[cardpow] not simulatable (needs a pick UI): %s" % str(skipped_modal))
	print("[cardpow] DONE")
	quit(0)


## Mean HP margin for a deck = COPIES×extra_ids + goblins to 10, across the gauntlet.
func _score_deck(extra_ids: Array) -> float:
	var total := 0.0
	var fights := 0
	for pair in GAUNTLET:
		var m = await _fight(String(pair[0]), int(pair[1]), extra_ids)
		if m != null:
			total += float(m)
			fights += 1
	return total / float(maxi(1, fights))


func _fight(enc_id: String, rng_seed: int, extra_ids: Array):
	RS.start_new_run(HERO, 0, 4242)
	RS.current_encounter_id = enc_id
	var enc: Dictionary = EDB.get_encounter(enc_id)
	RS.current_node_type = String(enc.get("type", "combat"))
	RS.relics.clear()   # neutralize the hero's signature relic — isolate the card
	# Install the controlled 10-card deck.
	RS.deck.clear(); RS.deck_uids.clear()
	for id in extra_ids:
		for _c in _copies:
			RS.add_card(String(id))
	while RS.deck.size() < 10:
		RS.add_card(_filler)

	# Common random numbers: pin combat's global RNG so this (card, encounter) is
	# reproducible and every card meets the same enemy line. Set right before the
	# scene consumes any randi() (enemy build / opening shuffle happen in _ready).
	seed(rng_seed)
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_turn():
		await _teardown(); return null
	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER and rounds < MAX_ROUNDS:
		await _auto_play_turn()
		if not is_instance_valid(combat): break
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		if not await _wait_turn(): break
	var margin = null
	if is_instance_valid(combat):
		margin = maxi(0, int(combat.player_hp)) - maxi(0, int(combat.enemy_hp))
	await _teardown()
	return margin


func _wait_turn() -> bool:
	var w := 0
	while w < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		w += 1
	return false


func _auto_play_turn() -> void:
	for _pass in 4:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN: return
		var played := false
		for card in combat._hand.duplicate():
			if not is_instance_valid(card) or not (card in combat._hand): continue
			var cd: Dictionary = card.card_data
			if String(cd.get("id", "")) in MODAL: continue
			var cost: int = int(cd.get("cost", 0))
			if int(combat.player_mana) < cost: continue
			var ctype := String(cd.get("type", ""))
			if ctype == "creature":
				var slot = _empty_slot()
				if slot == null: continue
				card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5
				combat._on_card_played(card)
				played = true
				await create_timer(0.02).timeout
			elif ctype == "spell":
				var targeting := String(cd.get("targeting", "none"))
				if targeting == "none":
					combat._on_card_played(card)
					played = true
					await create_timer(0.02).timeout
				else:
					var target = _smart_target(cd)
					if target == null or not is_instance_valid(target): continue
					var lane: int = maxi(0, int(target.current_lane))
					combat.player_mana -= cost
					combat._first_spell_this_turn = true
					combat._cards_played_this_turn += 1
					combat._hand.erase(card)
					if card.get_parent() != null: card.get_parent().remove_child(card)
					await combat._resolve_spell(card.card_data, target, lane)
					if is_instance_valid(card): combat._after_spell(card)
					played = true
					await create_timer(0.02).timeout
		if not played: return


func _smart_target(cd: Dictionary) -> Object:
	var targeting := String(cd.get("targeting", "none"))
	var spell: Dictionary = cd.get("spell", {})
	var stype := String(spell.get("type", ""))
	var supportive: bool = stype in ["buff_atk", "buff_hp", "heal", "shield", "regen", "buff_all_atk"] \
		or targeting == "friendly_creature"
	if targeting == "friendly_creature": return _best_friendly()
	if targeting == "enemy_creature": return _best_enemy(int(spell.get("value", 3)))
	if supportive:
		var f = _best_friendly()
		if f != null: return f
	var e = _best_enemy(int(spell.get("value", 3)))
	if e != null: return e
	return combat._auto_target_for(targeting)


func _best_enemy(dmg: int) -> Object:
	var best: Object = null; var best_atk := -1
	var bk: Object = null; var bk_atk := -1
	for c in combat._all_enemy_creatures():
		if not is_instance_valid(c) or c.has_keyword("structure"): continue
		var atk: int = c.effective_atk()
		if atk > best_atk: best_atk = atk; best = c
		if dmg > 0 and int(c.current_hp) <= dmg and atk > bk_atk: bk_atk = atk; bk = c
	return bk if bk != null else best


func _best_friendly() -> Object:
	var best: Object = null; var best_atk := -1
	for c in combat._all_player_creatures():
		if not is_instance_valid(c) or c.has_keyword("structure"): continue
		var atk: int = c.effective_atk()
		if atk > best_atk: best_atk = atk; best = c
	return best


func _empty_slot():
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for lane in range(combat.LANES_PER_ROW):
			if combat._row_array(false, row)[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


func _teardown() -> void:
	if is_instance_valid(combat): combat.queue_free()
	combat = null
	await create_timer(0.04).timeout
