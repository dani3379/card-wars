extends SceneTree
## Balance telemetry sweep (2026-06-18, smart-bot rev). Plays EVERY EncounterDB
## fight with ALL FIVE heroes using a SMARTER auto-pilot than the old flood-bot:
##   - plays every affordable creature into an empty slot (front row first),
##   - casts non-targeted spells,
##   - AND casts TARGETED damage/buff spells (Strike, Immolate, ...) with basic
##     target priority — offensive spells hit the highest-ATK enemy that the
##     spell can kill (else the biggest threat); buffs land on the player's
##     biggest attacker. (The old bot dropped every Strike unplayed, so the
##     stalwart/acolyte/pyromancer starter decks were silently throwing away
##     their removal — their floor numbers were artificially low.)
##
## Still no floop (dead-coded) and no banking — so it's a strong-but-not-optimal
## FLOOR. Read it as an OUTLIER detector, WITHIN a tier:
##   - a NORMAL fight the bot loses often            => genuine difficulty spike
##   - a NORMAL fight won 5/5 in <=3 rounds full HP  => trivially easy
##   - a General/boss the bot wins easily            => undertuned for its tier
##
## Per-encounter it reports: wins/5, avg rounds, avg player HP remaining on wins.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_balance.gd
## Slice it: -- --only=id,id  /  -- --prefix=amalgam_  (full table times out ~595s).
## (each fight uses the hero's pure STARTER deck — no injected pool/relics — so
## the numbers reflect baseline encounter difficulty, not a stacked deck.)

const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const MAX_ROUNDS := 40
const TURN_WAIT_TICKS := 80
const TICK := 0.1
# On-play / on-resolve cards that open a picker the headless bot can't dismiss
# (Discover / Choose / Copy on-enter, plus spells whose resolver awaits a
# discard/keyword/Discover pick). The bot draws them but never plays them.
const MODAL_BLOCKLIST := ["familiar", "scholar", "treasure_hunter", "adaptable",
	"copycat", "doppelganger", "lost_tome", "war_council", "chaos_imp",
	"war_chant", "scrap", "gambit", "censer_light", "recycle"]
# `--draft`: simulate a DEVELOPED deck (not the bare starter) so the boss tier
# becomes actionable rather than a "bare-deck floor, not readable" caveat. A
# generically-strong package any deck would be glad to have: removal + an
# enemy-only AOE board clear + premium bodies. inferno (NOT earthquake — that's
# damage_all and would nuke the bot's own board); strike is targeted (the smart
# bot now casts it). 7 cards on top of the 10-card starter ≈ a mid-run deck.
const DRAFT_PACKAGE := ["strike", "strike", "inferno", "paladin", "paladin", "troll", "griffin"]

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var combat: Node
var _started := false
var _draft := false        # --draft: give every hero the DRAFT_PACKAGE
var _rows: Array = []      # per-encounter aggregate strings for sorting
var _targeted_casts := 0   # tally of targeted spells the smart bot actually cast


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[bal] start")
	RS  = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US  = root.get_node_or_null("UserSettings")
	SS  = root.get_node_or_null("SkirmishState")
	if RS == null or EDB == null:
		print("[bal] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	# Optional focus filter: --only=id1,id2 / --prefix=amalgam_ to re-test a slice.
	# --draft gives every hero the DRAFT_PACKAGE (developed-deck lens).
	var only: Array = []
	var prefix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr("--only=".length()).split(",", false)
		elif arg.begins_with("--prefix="):
			prefix = arg.substr("--prefix=".length())
		elif arg == "--draft":
			_draft = true
	print("[bal] deck mode: %s" % ("DRAFT (developed)" if _draft else "bare starter"))

	var enc_ids: Array = []
	for id in EDB.ENCOUNTERS.keys():
		var sid := String(id)
		if only.size() > 0 and not (sid in only):
			continue
		if prefix != "" and not sid.begins_with(prefix):
			continue
		enc_ids.append(sid)
	enc_ids.sort()

	for enc_id in enc_ids:
		var enc: Dictionary = EDB.get_encounter(enc_id)
		var etype: String = String(enc.get("type", "combat"))
		var act: int = int(enc.get("act", 0))
		var wins := 0
		var round_sum := 0
		var hp_sum := 0
		var games := 0
		for hero in HEROES:
			var r: Dictionary = await _fight(hero, enc_id, etype)
			if r.get("ok", false):
				games += 1
				round_sum += int(r["rounds"])
				if r["win"]:
					wins += 1
					hp_sum += int(r["php"])
		var avg_rounds: float = float(round_sum) / float(maxi(1, games))
		var avg_hp: float = float(hp_sum) / float(maxi(1, wins))
		var line := "%-5s a%d  win %d/%-2d  avg_rounds %4.1f  avg_hp_on_win %4.1f  %s" \
			% [etype, act, wins, games, avg_rounds, avg_hp, enc_id]
		_rows.append({"win": wins, "type": etype, "act": act, "rounds": avg_rounds, "line": line})
		print("[bal] done ", line)

	# Sorted report: normal fights by win-rate ascending (spikes first), then a
	# trivial-fights list.
	print("[bal] ============ REPORT (normal fights, hardest first for the floor-bot) ============")
	var normals := _rows.filter(func(r): return r["type"] == "combat")
	normals.sort_custom(func(a, b): return a["win"] < b["win"])
	for r in normals:
		print("[bal] ", r["line"])
	print("[bal] ============ GENERALS / BOSSES (should be hard) ============")
	for r in _rows:
		if r["type"] != "combat":
			print("[bal] ", r["line"])
	print("[bal] ============ TRIVIAL normal fights (won 5/5 in <=3 rounds) ============")
	for r in normals:
		if r["win"] >= 5 and r["rounds"] <= 3.0:
			print("[bal] ", r["line"])
	print("[bal] (smart-bot targeted spells cast this sweep: %d)" % _targeted_casts)
	print("[bal] DONE")
	quit(0)


func _fight(hero: String, enc_id: String, etype: String) -> Dictionary:
	RS.start_new_run(hero, 0, 4242)
	RS.current_encounter_id = enc_id
	RS.current_node_type = etype if etype in ["combat", "elite", "boss"] else "combat"
	if _draft:
		for cid in DRAFT_PACKAGE:
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
					# Targeted spell: pick a sensible target and resolve it the
					# same way a player click would (pay Command, drop from hand,
					# _resolve_spell + _after_spell). Skip (hold the card) when
					# there's no good target — wasting removal on an empty board
					# is worse play than holding it (hand persists across turns).
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
					_targeted_casts += 1
					played_any = true
					await create_timer(0.03).timeout
		if not played_any: return


## Pick a target for a targeted spell: offensive spells hit the strongest enemy
## the spell can kill (else the biggest threat); supportive spells land on the
## player's biggest attacker. Falls back to the game's own _auto_target_for.
func _smart_target(cd: Dictionary) -> Object:
	var targeting := String(cd.get("targeting", "none"))
	var spell: Dictionary = cd.get("spell", {})
	var stype := String(spell.get("type", ""))
	# Supportive spell types want a friendly body; everything else (damage,
	# debuff, most customs) wants an enemy.
	var supportive := stype in ["buff_atk", "buff_hp", "heal", "shield", "regen", "buff_all_atk"]
	if targeting == "friendly_creature":
		return _best_friendly()
	if targeting == "enemy_creature":
		return _best_enemy(int(spell.get("value", 3)))
	# any_creature / any: route by intent, fall back to the other side.
	if supportive:
		var f = _best_friendly()
		if f != null: return f
	var e = _best_enemy(int(spell.get("value", 3)))
	if e != null: return e
	return combat._auto_target_for(targeting)


## Highest-ATK enemy creature; prefers one the given damage can kill outright.
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


## The player's biggest live attacker (a buff lands best on the biggest body).
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
