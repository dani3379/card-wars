extends SceneTree
## RUN SIMULATOR — balance measured under the conditions a real run actually has.
##
## Why this exists (2026-07-27): `_probe_balance` calls `start_new_run` PER FIGHT,
## so every encounter is measured at full HP with a bare 10-card starter deck, no
## relics, no upgrades, and no accumulated damage. Its own header calls that a
## FLOOR, not a run — and it is the right tool for spotting a single overtuned
## encounter. It is the wrong tool for asking "did my balance change help?",
## because nothing it measures resembles the state a player is actually in.
##
## This probe carries a run FORWARD, the way the campaign does:
##   * ONE start_new_run per run; HP persists between fights (Combat writes
##     RunState.hero_hp back on the way out).
##   * The act skeleton from CLAUDE.md: 7 combats per act — 4 holds, 2 Generals,
##     1 boss (FIGHT_ROWS + ELITE_ROWS + BOSS_ROW).
##   * current_act_idx is set per act, so act-2/3 kits fight at their real
##     strength instead of being scaled down to act 1 (the defect that made all
##     historical balance data ~2x too easy).
##   * The deck GROWS: a card reward after every fight, drawn from the real
##     CardDB.roll_card_reward rarity tables for that act/tier.
##   * Relics accumulate on Generals and bosses via RDB.roll_relic_reward.
##   * A camp rest before the keep heals, like REST_ROW does.
##
## Read it as: how far does a run get, and where does it die?
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_runsim.gd
##   ... -- --runs=3 --hero=raider --asc=0
##
## NOTE: like every run-level probe this writes RunState; back up user://run_0.save
## if you care about it.

const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const MAX_ROUNDS := 40
const TURN_WAIT_TICKS := 80
const TICK := 0.1
## Cards whose on-play opens a picker a headless bot cannot dismiss. The bot may
## DRAW them (exercising the deck path) but never plays them — and, critically,
## never DRAFTS them, or the deck silently fills with cards it refuses to cast.
const MODAL_BLOCKLIST := ["familiar", "scholar", "treasure_hunter", "adaptable",
	"copycat", "doppelganger", "lost_tome", "war_council", "chaos_imp",
	"war_chant", "gambit", "censer_light", "recycle"]
const RELIC_BLOCKLIST := ["mime"]
## 4 holds + 2 Generals + the keep, per act — the real per-route fight count.
const ACT_SHAPE := ["combat", "combat", "elite", "combat", "combat", "elite", "boss"]

var RS: Node
var EDB: Node
var CDB: Node
var RDB: Node
var US: Node
var SS: Node
var NM: Node
var combat: Node
var _started := false
var _done := false
var _rng := RandomNumberGenerator.new()

var _runs := 2
var _only_hero := ""
var _asc := 0
var _dry := false          # --dry: no between-fight recovery (pure floor)
var _road_heal := 0.12     # stand-in for the two roadside stops + potions


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--runs="):
			_runs = maxi(1, int(s.substr(7)))
		elif s.begins_with("--hero="):
			_only_hero = s.substr(7)
		elif s.begins_with("--asc="):
			_asc = maxi(0, int(s.substr(6)))
		elif s == "--dry":
			_dry = true
		elif s.begins_with("--roadheal="):
			_road_heal = clampf(float(s.substr(11)), 0.0, 1.0)
	RS = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	CDB = root.get_node_or_null("CardDB")
	RDB = root.get_node_or_null("RelicDB")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	if RS == null or EDB == null or CDB == null or RDB == null:
		print("[runsim] FATAL: autoloads missing")
		_done = true
		quit(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	if NM != null and NM.has_method("leave"):
		NM.leave()

	# Encounter pools by act and tier, taken from the live table.
	var pools := {}
	for eid in EDB.ENCOUNTERS.keys():
		var enc: Dictionary = EDB.ENCOUNTERS[eid]
		var act := int(enc.get("act", 1))
		var t := String(enc.get("type", "combat"))
		if not t in ["combat", "elite", "boss"]:
			continue
		var key := "%d_%s" % [act, t]
		if not pools.has(key):
			pools[key] = []
		pools[key].append(eid)

	var heroes: Array = [_only_hero] if _only_hero != "" else HEROES
	var results: Array = []
	print("[runsim] %d run(s) per hero, ascension %d" % [_runs, _asc])
	for hi in range(heroes.size()):
		var hero = heroes[hi]
		for r in range(_runs):
			# The seed must vary by HERO as well as by run. The first version used
			# `1000 + r * 77` for everyone, so all five heroes walked the SAME
			# encounter sequence — the effective sample was the number of runs, not
			# runs x heroes, and every hero "independently" died to the same fight,
			# which reads as a damning cluster when it is really one data point.
			var seed_v: int = 1000 + hi * 9173 + r * 77
			var res: Dictionary = await _simulate_run(String(hero), seed_v, pools)
			results.append(res)
			print("  %-11s seed %-5d -> %-22s  deck %2d  relics %d  hp %d/%d" % [
				hero, seed_v, String(res.get("outcome", "?")),
				int(res.get("deck", 0)), int(res.get("relics", 0)),
				int(res.get("hp", 0)), int(res.get("max_hp", 0))])

	_summarise(results)
	_done = true
	quit(0)


func _simulate_run(hero: String, seed_v: int, pools: Dictionary) -> Dictionary:
	_rng.seed = seed_v
	RS.start_new_run(hero, _asc, seed_v)
	var fights_won := 0
	for act in [1, 2, 3]:
		RS.current_act_idx = act - 1
		for i in range(ACT_SHAPE.size()):
			var tier: String = ACT_SHAPE[i]
			var key := "%d_%s" % [act, tier]
			var pool: Array = pools.get(key, [])
			if pool.is_empty():
				pool = pools.get("%d_combat" % act, [])
			if pool.is_empty():
				continue
			# THE ROAD'S RECOVERY ECONOMY. Modelling this matters more than it
			# looks: the first version healed only 30% of missing once per act and
			# reported 0/15 runs, which flattered nothing and blamed the game for
			# an omission in the harness.
			#   * The camp before the keep heals to FULL below Ascension 2 —
			#     that is the literal rule in Rest._rest_heal_target, not a model.
			#   * Between EVERY fight the map deals two non-fight stops (event /
			#     wayside / shop / recruit / treasure, per CLAUDE.md), and fights
			#     drop potions at 40% + 10% per dry fight. A real player arrives at
			#     the first General with more HP than a bot that never stops.
			#     `road_heal` is an explicit, conservative STAND-IN for that
			#     economy — not a measured value. `--dry` turns it off for a pure
			#     floor reading.
			if tier == "boss":
				if _asc >= 2:
					var missing: int = int(RS.hero_max_hp) - int(RS.hero_hp)
					RS.hero_hp = mini(int(RS.hero_max_hp),
						int(RS.hero_hp) + int(ceil(float(missing) * 0.6)))
				else:
					RS.hero_hp = int(RS.hero_max_hp)
			elif not _dry and (i > 0 or act > 1):
				RS.hero_hp = mini(int(RS.hero_max_hp),
					int(RS.hero_hp) + int(round(float(RS.hero_max_hp) * _road_heal)))
			var eid: String = String(pool[_rng.randi_range(0, pool.size() - 1)])
			var out: Dictionary = await _fight(eid, tier)
			if not bool(out.get("ok", false)):
				return _snapshot("ERROR in %s (a%d)" % [eid, act], fights_won)
			if not bool(out.get("win", false)):
				# HOW CLOSE did the run get? "fights won" alone is far too coarse:
				# a run ends at its FIRST loss, so a fight that goes from a
				# 5-round rout to a 9-round near-win scores exactly the same zero.
				# The fraction of the lord's health actually removed is the
				# sensitive measure, and it moves without needing the bot to win.
				var snap := _snapshot("DIED act %d %s (%s)" % [act, tier, eid], fights_won)
				snap["last_rounds"] = int(out.get("rounds", 0))
				snap["foe_pct"] = 100.0 * (1.0 - float(out.get("foe_left", 1))
					/ float(out.get("foe_max", 1)))
				return snap
			fights_won += 1
			_grant_rewards(act, tier)
	return _snapshot("WON THE RUN", fights_won)


func _snapshot(outcome: String, fights: int) -> Dictionary:
	return {
		"outcome": outcome, "fights": fights,
		"deck": (RS.deck as Array).size() if RS.deck != null else 0,
		"relics": (RS.relics as Array).size() if RS.relics != null else 0,
		"hp": int(RS.hero_hp), "max_hp": int(RS.hero_max_hp),
	}


func _grant_rewards(act: int, tier: String) -> void:
	## A card after every fight (the reward screen's 1-of-3, taking the priciest
	## castable option — a rough stand-in for a player drafting for impact), plus
	## a relic on Generals and bosses.
	var offers: Array = CDB.roll_card_reward(act, tier == "elite", tier == "boss", 3)
	var best := ""
	var best_cost := -1
	for cid in offers:
		var s := String(cid)
		if s in MODAL_BLOCKLIST:
			continue
		var cd: Dictionary = CDB.get_card_data(s)
		if cd.is_empty():
			continue
		var c := int(cd.get("cost", 0))
		if c > best_cost:
			best_cost = c
			best = s
	if best != "":
		RS.add_card(best)
	if tier == "elite" or tier == "boss":
		var held: Array[String] = []
		for rid in RS.relics:
			held.append(String(rid))
		# roll_relic_reward returns the 1-of-N SLATE; a player picks one.
		var slate: Array = RDB.roll_relic_reward("combat", held, "", 3)
		for rid in slate:
			var s := String(rid)
			if s != "" and not (s in RELIC_BLOCKLIST) and not (s in held):
				RS.relics.append(s)
				break


func _fight(enc_id: String, tier: String) -> Dictionary:
	## NOTE: deliberately NO start_new_run here — that is the whole point. HP,
	## deck, relics and upgrades all carry in from the previous fight.
	RS.current_encounter_id = enc_id
	RS.current_setpiece_id = ""
	RS.current_mutator_id = ""
	RS.current_node_type = tier
	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	if not await _wait_for_player_turn():
		await _teardown()
		return {"ok": false}
	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER \
			and rounds < MAX_ROUNDS:
		await _auto_play_turn()
		if not is_instance_valid(combat):
			break
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		if not await _wait_for_player_turn():
			break
	var res := {"ok": false}
	if is_instance_valid(combat) and combat.phase == combat.Phase.GAME_OVER:
		res = {"ok": true, "win": int(combat.enemy_hp) <= 0, "rounds": rounds,
			"foe_left": maxi(0, int(combat.enemy_hp)),
			"foe_max": maxi(1, int(combat.enemy_max_hp))}
	elif is_instance_valid(combat) and rounds >= MAX_ROUNDS:
		# A fight that never resolves is a REAL finding, not an error — report it
		# as a loss so the run ends and the caller can see where.
		res = {"ok": true, "win": false, "rounds": rounds, "stalled": true}
	await _teardown()
	return res


func _wait_for_player_turn() -> bool:
	## `phase == PLAYER_TURN` ALONE IS NOT A READINESS TEST. PLAYER_TURN is enum
	## value 0 and the member's default, so it reads true on the very first tick —
	## before _build_hud has run and before _end_turn_btn exists, which is exactly
	## how the first version of this probe ended up assigning `.disabled` on null
	## every round. `round_number` only leaves 0 inside _start_round, which is
	## strictly after the HUD is built, so it is the honest gate.
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.GAME_OVER:
			return true
		if combat.phase == combat.Phase.PLAYER_TURN and int(combat.round_number) >= 1:
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false


func _auto_play_turn() -> void:
	# THE HAND ARRIVES ON TIMERS. _start_round draws one card immediately and
	# staggers the rest on 0.08s timers, so `phase == PLAYER_TURN` is true while
	# the hand is still being dealt. A bot that acts at once plays a ONE-CARD
	# hand every turn — which is what every measurement in this session was
	# actually testing, and why four unrelated levers all moved nothing.
	# Wait for the hand to stop growing before deciding anything.
	var stable := 0
	var last_n: int = -1
	while stable < 3:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var n: int = combat._hand.size()
		if n == last_n:
			stable += 1
		else:
			stable = 0
			last_n = n
		await create_timer(0.05).timeout
	for _pass in 4:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var played_any := false
		for card in combat._hand.duplicate():
			if not is_instance_valid(card) or not (card in combat._hand):
				continue
			var cd: Dictionary = card.card_data
			if String(cd.get("id", "")) in MODAL_BLOCKLIST:
				continue
			var cost: int = int(cd.get("cost", 0))
			if int(combat.player_mana) < cost:
				continue
			var ctype: String = String(cd.get("type", ""))
			# Creature: drop it over an empty slot and let the real play path run,
			# exactly as _probe_balance does. (_play_creature takes (card, cost)
			# and is NOT the drop handler — calling it directly is what made the
			# first version of this bot never field anything and lose every fight.)
			if ctype == "creature":
				var slot = _find_empty_player_slot()
				if slot == null:
					continue
				card.global_position = slot.global_position + slot.size * 0.5 \
					- card.size * 0.5
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
					# Hold removal rather than burn it on nothing — the hand
					# persists, so wasting it is worse play than waiting.
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
			if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
				return
		if not played_any:
			return


func _smart_target(cd: Dictionary):
	var sp: Dictionary = cd.get("spell", {})
	var t := String(cd.get("targeting", "none"))
	var dmg := int(sp.get("value", 0))
	if t == "enemy_creature" or t == "any" or t == "any_creature":
		var e = _best_enemy(dmg)
		if e != null:
			return e
	if t == "friendly_creature" or t == "any_creature" or t == "any":
		return _best_friendly()
	return null


func _best_enemy(dmg: int):
	var best = null
	var best_score := -999
	for c in combat._all_enemy_creatures():
		if c == null or not is_instance_valid(c) or c.current_hp <= 0:
			continue
		var score: int = int(c.effective_atk()) * 2
		if dmg > 0 and int(c.current_hp) <= dmg:
			score += 50
		if score > best_score:
			best_score = score
			best = c
	return best


func _best_friendly():
	var best = null
	var best_atk := -1
	for c in combat._all_player_creatures():
		if c == null or not is_instance_valid(c) or c.current_hp <= 0:
			continue
		if int(c.effective_atk()) > best_atk:
			best_atk = int(c.effective_atk())
			best = c
	return best


func _find_empty_player_slot():
	## Returns the SLOT NODE the bot should drop into.
	##
	## POSITIONING IS THE GAME. This used to return the first empty slot, front
	## row, lane 0 outward — which ignores the one skill a 4x4 lane game asks for.
	## An UNBLOCKED lane sends its enemy straight to your face, so where a body
	## stands decides how much damage you take; the old bot was effectively
	## choosing at random. With it, -25% enemy HP and +50% player HP both moved
	## the win rate by nothing, because play quality — not tuning — was the
	## binding constraint.
	##
	## Priority: block the lane whose opposing creature hits HARDEST, then any
	## threatened lane, then fill out the front, then the back row.
	var best = null
	var best_threat := -1
	for lane in range(combat.LANES_PER_ROW):
		if combat._row_array(false, combat.ROW_FRONT)[lane] != null:
			continue
		var threat := 0
		for erow in [combat.ROW_FRONT, combat.ROW_BACK]:
			var e = combat._row_array(true, erow)[lane]
			if e != null and is_instance_valid(e) and e.current_hp > 0:
				threat = maxi(threat, int(e.effective_atk()))
		if threat > best_threat:
			best_threat = threat
			best = combat._slot_array(false, combat.ROW_FRONT)[lane]
	if best != null:
		return best
	for lane in range(combat.LANES_PER_ROW):
		if combat._row_array(false, combat.ROW_BACK)[lane] == null:
			return combat._slot_array(false, combat.ROW_BACK)[lane]
	return null


func _teardown() -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	combat = null
	await create_timer(TICK).timeout


func _summarise(results: Array) -> void:
	print("")
	print("=== RUN OUTCOMES (%d runs) ===" % results.size())
	var wins := 0
	var by_act := {1: 0, 2: 0, 3: 0}
	var total_fights := 0
	var hp_sum := 0
	var deck_sum := 0
	for r in results:
		total_fights += int(r.get("fights", 0))
		hp_sum += int(r.get("hp", 0))
		deck_sum += int(r.get("deck", 0))
		var o := String(r.get("outcome", ""))
		if o == "WON THE RUN":
			wins += 1
		elif o.begins_with("DIED act "):
			var a := int(o.substr(9, 1))
			if by_act.has(a):
				by_act[a] += 1
	print("  runs won        : %d / %d  (%.0f%%)" % [
		wins, results.size(), 100.0 * float(wins) / maxf(1.0, float(results.size()))])
	print("  avg fights won  : %.1f  (a full run is 21)" % [
		float(total_fights) / maxf(1.0, float(results.size()))])
	print("  avg final deck  : %.1f cards" % [
		float(deck_sum) / maxf(1.0, float(results.size()))])
	print("  deaths by act   : act1 %d · act2 %d · act3 %d" % [
		by_act[1], by_act[2], by_act[3]])
	var fp := 0.0
	var fr := 0.0
	var fn := 0
	for r2 in results:
		if r2.has("foe_pct"):
			fp += float(r2["foe_pct"])
			fr += float(r2.get("last_rounds", 0))
			fn += 1
	if fn > 0:
		print("  on the losing fight: %.0f%% of the foe's health removed, %.1f rounds survived"
			% [fp / float(fn), fr / float(fn)])
	print("")
	print("  NOTE: the bot never banks Command, never repositions, and never")
	print("  plays a modal card. Treat this as a FLOOR that is now measured under")
	print("  run conditions — compare deltas before/after a change, not absolutes.")
