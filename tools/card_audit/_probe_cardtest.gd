extends SceneTree
## _probe_cardtest.gd — CARD-INCLUSION TEST (2026-06-22)
## ----------------------------------------------------------------------------
## Empirically measures whether a SUSPECT card earns its slot, by INCLUSION
## DELTA. For a fixed baseline (hero starter deck + a generically-good draft
## package, fought across a representative encounter set with a SMART auto-pilot
## borrowed from _probe_balance), it runs:
##     BASELINE                : starter + DRAFT_PACKAGE
##     BASELINE + 2x <suspect> : the same, plus 2 copies of the suspect card
## ...with the SAME seed (4242), SAME heroes, SAME encounters, so the comparison
## is apples-to-apples. A card whose inclusion does NOTHING (delta ~0) or makes
## results WORSE is empirically bad-for-its-cost. Known-good controls (paladin /
## troll / harpy) calibrate the signal — they should show a >= 0 delta.
##
## METRIC (per pass, aggregated over heroes x encounters):
##   - winrate  : wins / games
##   - rounds   : avg rounds to resolution
##   - score    : a single "how did it go" number per fight, averaged:
##         win  -> +100 + player_hp_remaining   (won, and how healthy)
##         loss -> -(enemy_hp_remaining)         (lost, and how close)
##     so score rises with both winning more AND winning healthier / losing
##     closer. The DELTA in this score is the headline signal.
##
## This is DIRECTIONAL EVIDENCE, not proof: few fights => real variance, the bot
## is strong-but-not-optimal (no floop, no banking, no modal-picker cards), and
## a 2-copy dilution of a 17-card deck is a blunt instrument. Read deltas of a
## few points as noise; trust the clearly-bad (large negative) and clearly-good
## (large positive control) ends.
##
## Run:  Godot.exe --headless --path "D:\Godot" --script res://tools/card_audit/_probe_cardtest.gd
## Slice: -- --only=warchief,leyline_conduit   (test a subset of suspects)
##        -- --fast                            (stalwart only, 4 encounters)

# --- baseline composition --------------------------------------------------
const HEROES := ["stalwart", "raider"]
# A generically-strong package any deck would happily run: targeted removal,
# an enemy-only board-clear AOE, and premium bodies. Mirrors _probe_balance's
# DRAFT_PACKAGE so the baseline is a believable mid-run deck, not a bare starter.
const DRAFT_PACKAGE := ["strike", "strike", "inferno", "paladin", "paladin", "troll", "griffin"]

# Representative slice across the difficulty curve (act1 normal x2, act1
# General/elite, act1 boss, act2 normal, act3 boss). Each id is a real
# EncounterDB entry; chosen to span easy-floor -> hardest-endgame so a suspect
# that only matters in long fights still has somewhere to show it.
const ENCOUNTERS := ["goblin_scouts", "boar_herd", "orc_warband", "dragon_lord",
	"cultist_enclave", "the_devil"]
const ENCOUNTERS_FAST := ["goblin_scouts", "orc_warband", "dragon_lord", "cultist_enclave"]

# Suspects (underpowered / bland end of the efficiency analyzer) + controls.
const SUSPECTS := ["warchief", "copycat", "cinder_pup", "necromancer", "witch",
	"mule", "blood_pyre", "hound", "pikeman", "mana_sprite", "leyline_conduit",
	"battle_drummer", "bloodhound", "torchbearer", "crystal_sentry",
	"shieldbearer", "lancer", "summoner", "plague_rat",
	# known-good controls to calibrate the harness's signal:
	"paladin", "troll", "harpy"]
const CONTROLS := ["paladin", "troll", "harpy"]

# Cards whose on-play/on-enter opens a picker the headless bot can't dismiss.
# The bot draws but never plays them, so 2 copies just DILUTE the deck. A
# suspect on this list cannot be truly auto-tested (its delta reflects dilution,
# not its effect) — flagged in the report.
const MODAL_BLOCKLIST := ["familiar", "scholar", "treasure_hunter", "adaptable",
	"copycat", "doppelganger", "lost_tome", "war_council", "chaos_imp",
	"war_chant", "scrap", "gambit", "censer_light", "recycle"]

const SEED := 4242
const MAX_ROUNDS := 40
const TURN_WAIT_TICKS := 80
const TICK := 0.1

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var combat: Node
var _started := false
var _encs: Array = ENCOUNTERS
var _heroes: Array = HEROES
var _suspects: Array = SUSPECTS
var _results: Array = []     # [{card, base:{...}, plus:{...}, delta:{...}}]


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[cardtest] start")
	RS  = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US  = root.get_node_or_null("UserSettings")
	SS  = root.get_node_or_null("SkirmishState")
	if RS == null or EDB == null:
		print("[cardtest] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	var only: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr("--only=".length()).split(",", false)
		elif arg == "--fast":
			_heroes = ["stalwart"]
			_encs = ENCOUNTERS_FAST
	if only.size() > 0:
		_suspects = only
	print("[cardtest] heroes=%s  encounters=%s" % [str(_heroes), str(_encs)])
	print("[cardtest] suspects=%d  (controls: %s)" % [_suspects.size(), str(CONTROLS)])

	# 1) BASELINE pass (no suspect injected).
	var base: Dictionary = await _measure([])
	print("[cardtest] BASELINE  %s" % _fmt(base))

	# 2) Per-suspect: baseline + 2 copies.
	for card in _suspects:
		var plus: Dictionary = await _measure([card, card])
		var d := {
			"winrate": plus["winrate"] - base["winrate"],
			"rounds": plus["rounds"] - base["rounds"],
			"score": plus["score"] - base["score"],
		}
		_results.append({"card": card, "base": base, "plus": plus, "delta": d})
		print("[cardtest] +2x %-16s %s   d_score %+6.1f  d_win %+5.1f%%" % \
			[card, _fmt(plus), d["score"], d["winrate"] * 100.0])

	_report(base)
	quit(0)


## Run the full grid (heroes x encounters) once, optionally injecting `extra`
## cards into every deck. Returns aggregate winrate / avg rounds / avg score.
func _measure(extra: Array) -> Dictionary:
	var wins := 0
	var games := 0
	var round_sum := 0
	var score_sum := 0.0
	for hero in _heroes:
		for enc_id in _encs:
			var r: Dictionary = await _fight(hero, enc_id, extra)
			if not r.get("ok", false):
				continue
			games += 1
			round_sum += int(r["rounds"])
			if r["win"]:
				wins += 1
				score_sum += 100.0 + float(r["php"])
			else:
				score_sum += -float(r["ehp"])
	var g: int = maxi(1, games)
	return {
		"winrate": float(wins) / float(g),
		"wins": wins, "games": games,
		"rounds": float(round_sum) / float(g),
		"score": score_sum / float(g),
	}


func _fight(hero: String, enc_id: String, extra: Array) -> Dictionary:
	RS.start_new_run(hero, 0, SEED)
	RS.current_encounter_id = enc_id
	var enc: Dictionary = EDB.get_encounter(enc_id)
	var etype: String = String(enc.get("type", "combat"))
	RS.current_node_type = etype if etype in ["combat", "elite", "boss"] else "combat"
	for cid in DRAFT_PACKAGE:
		RS.add_card(cid)
	for cid in extra:
		RS.add_card(cid)
	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	if not await _wait_for_player_turn():
		await _teardown()
		return {"ok": false}
	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER and rounds < MAX_ROUNDS:
		await _auto_play_turn()
		if not is_instance_valid(combat): break
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		if not await _wait_for_player_turn(): break
	var res := {"ok": false}
	if is_instance_valid(combat) and combat.phase == combat.Phase.GAME_OVER:
		var win: bool = int(combat.enemy_hp) <= 0
		res = {"ok": true, "win": win, "rounds": rounds,
			"php": maxi(0, int(combat.player_hp)), "ehp": maxi(0, int(combat.enemy_hp))}
	await _teardown()
	return res


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		waited += 1
	return false


# --- smart auto-pilot (verbatim behavior from _probe_balance) ---------------
func _auto_play_turn() -> void:
	for _pass in 4:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN: return
		var played_any := false
		for card in combat._hand.duplicate():
			if not is_instance_valid(card) or not (card in combat._hand): continue
			var cd: Dictionary = card.card_data
			if String(cd.get("id", "")) in MODAL_BLOCKLIST: continue
			var cost: int = int(cd.get("cost", 0))
			if int(combat.player_mana) < cost: continue
			var ctype: String = String(cd.get("type", ""))
			if ctype == "creature":
				var slot = _find_empty_player_slot()
				if slot == null: continue
				card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5
				combat._on_card_played(card)
				played_any = true
				await create_timer(0.03).timeout
			elif ctype == "spell":
				var targeting := String(cd.get("targeting", "none"))
				if targeting == "none":
					combat._on_card_played(card)
					played_any = true
					await create_timer(0.03).timeout
				else:
					var target = _smart_target(cd)
					if target == null or not is_instance_valid(target):
						continue
					var lane: int = maxi(0, int(target.current_lane))
					combat.player_mana -= cost
					combat._first_spell_this_turn = true
					combat._cards_played_this_turn += 1
					combat._hand.erase(card)
					if card.get_parent() != null:
						card.get_parent().remove_child(card)
					await combat._resolve_spell(card.card_data, target, lane)
					if is_instance_valid(card):
						combat._after_spell(card)
					played_any = true
					await create_timer(0.03).timeout
		if not played_any: return


func _smart_target(cd: Dictionary) -> Object:
	var targeting := String(cd.get("targeting", "none"))
	var spell: Dictionary = cd.get("spell", {})
	var stype := String(spell.get("type", ""))
	var supportive := stype in ["buff_atk", "buff_hp", "heal", "shield", "regen", "buff_all_atk"]
	if targeting == "friendly_creature":
		return _best_friendly()
	if targeting == "enemy_creature":
		return _best_enemy(int(spell.get("value", 3)))
	if supportive:
		var f = _best_friendly()
		if f != null: return f
	var e = _best_enemy(int(spell.get("value", 3)))
	if e != null: return e
	return combat._auto_target_for(targeting)


func _best_enemy(dmg: int) -> Object:
	var best: Object = null
	var best_atk := -1
	var best_killable: Object = null
	var best_killable_atk := -1
	for c in combat._all_enemy_creatures():
		if not is_instance_valid(c) or c.has_keyword("structure"): continue
		var atk: int = c.effective_atk()
		if atk > best_atk:
			best_atk = atk
			best = c
		if dmg > 0 and int(c.current_hp) <= dmg and atk > best_killable_atk:
			best_killable_atk = atk
			best_killable = c
	return best_killable if best_killable != null else best


func _best_friendly() -> Object:
	var best: Object = null
	var best_atk := -1
	for c in combat._all_player_creatures():
		if not is_instance_valid(c) or c.has_keyword("structure"): continue
		var atk: int = c.effective_atk()
		if atk > best_atk:
			best_atk = atk
			best = c
	return best


func _find_empty_player_slot():
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for lane in range(combat.LANES_PER_ROW):
			if combat._row_array(false, row)[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


func _teardown() -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	combat = null
	await create_timer(0.05).timeout


func _fmt(m: Dictionary) -> String:
	return "win %d/%-2d (%4.1f%%)  rounds %4.1f  score %6.1f" % \
		[m["wins"], m["games"], m["winrate"] * 100.0, m["rounds"], m["score"]]


func _report(base: Dictionary) -> void:
	print("[cardtest] ================= REPORT (most-clearly-BAD first) =================")
	print("[cardtest] BASELINE: %s" % _fmt(base))
	print("[cardtest] (score = win:+100+playerHP, loss:-enemyHP_remaining; delta is the signal)")
	_results.sort_custom(func(a, b): return a["delta"]["score"] < b["delta"]["score"])
	print("[cardtest] %-16s %8s %9s %9s   %s" % ["card", "d_score", "d_win%", "d_rounds", "verdict"])
	for r in _results:
		var c: String = r["card"]
		var d: Dictionary = r["delta"]
		var tags := ""
		if c in CONTROLS: tags += " [CONTROL]"
		if c in MODAL_BLOCKLIST: tags += " [MODAL-untestable]"
		print("[cardtest] %-16s %+8.1f %+8.1f%% %+9.1f   %s%s" % \
			[c, d["score"], d["winrate"] * 100.0, d["rounds"], _verdict(d, c), tags])
	print("[cardtest] DONE")


## One-line empirical verdict from the score delta. Thresholds are deliberately
## wide because few-fight variance is real.
func _verdict(d: Dictionary, card: String) -> String:
	if card in MODAL_BLOCKLIST:
		return "cannot auto-test (modal picker) — judge by resolver"
	var s: float = d["score"]
	if s <= -8.0:
		return "HURTS — empirically worse for its cost"
	if s < 4.0:
		return "DOES NOTHING — no measurable contribution"
	if s < 12.0:
		return "marginal / inconclusive"
	return "HELPS — clear positive contribution"
