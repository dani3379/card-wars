extends SceneTree
## _probe_encwin.gd — PER-ENCOUNTER win/loss measurement (2026-07-26).
##
## Why this exists: `_probe_autorun` fights every encounter EXACTLY ONCE with a
## rotating hero and a rotating slice of the card pool, and reports only a global
## W/L total. That answers "does the engine crash?" — it cannot answer "which
## encounters are unwinnable?", because one fight is one sample and the injected
## deck is a random pool window rather than a deck a player would actually have.
##
## Two fidelity fixes over the existing harnesses (both `_probe_autorun` and
## `_probe_cardpower` have this bug):
##   * They never set `RunState.current_act_idx`, so `RunState.get_act()` returns
##     1 for every fight. Combat feeds that to `EncounterDB.get_face_hp()` and
##     `build_enemy_deck()` as the TARGET act — which rescales every act-2/act-3
##     encounter DOWN to act-1 strength (face HP by the band norms, and -1 ATK/-1
##     HP per body per act step). Act-3 fights were being measured at act-1 power.
##     This probe sets the act to the encounter's authored act.
##   * They fight with a starter deck + noise. This probe builds an ACT-APPROPRIATE
##     loadout by rolling real rewards through `CardDB.roll_card_reward` and
##     `RelicDB.roll_relic_reward`, so an act-3 encounter is met by an act-3 deck.
##
## The pilot is the `_probe_cardpower` policy (creatures placed by a lane heuristic,
## then targeted + untargeted spells, then a second creature pass). It is a decent
## floor, NOT a good player: no discards, no potions, no banking, no modal cards,
## no upgrades. See the LIMITATIONS block printed at the end of a run.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_encwin.gd -- --samples=6
##
## Flags (after a bare `--`):
##   --samples=N     fights per encounter (default 6)
##   --from=N --to=M shard the sorted encounter list (for chunked background runs)
##   --act=N         only encounters authored at act N
##   --type=T        only encounters of type T (combat/elite/boss)
##   --maxrounds=N   stalemate cap (default 30)
##   --starter       fight with the bare hero deck (no drafts, no extra relics)
##   --hp=N          player starting HP override (default 30 = full)
##   --tag=NAME      label printed on every row (for combining shard logs)
##   --forceact=N    fight every encounter as if the run were in act N. This is the
##                   CONTROL for the act-scaling bug above: `--act=3 --type=combat
##                   --forceact=1` reproduces what the older probes were measuring,
##                   with deck, pilot and seeds held identical. Measured 2026-07-26:
##                   act-3 combats score 23/70 correctly scaled vs 53/70 at
##                   --forceact=1 — i.e. the old numbers were roughly twice as easy.

const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const TURN_WAIT_TICKS := 90
const TICK := 0.1

# Cards the headless pilot cannot play (they open a pick UI). Kept out of the
# drafted deck so the bot is not handed dead cards.
const MODAL := ["familiar", "scholar", "treasure_hunter", "adaptable", "copycat",
	"doppelganger", "lost_tome", "war_council", "chaos_imp", "war_chant",
	"gambit", "recycle", "reanimate", "grave_robbery", "quartermaster",
	"the_understudy", "rat_piper", "muster_the_fallen"]
const RELIC_BLOCKLIST := ["mime"]

# How much a player has drafted by the time they reach a fight in each act.
# 7 combats per act route; ~1 card kept per victory, plus shop/recruit picks.
const DRAFTS_PER_ACT := [4, 10, 16]
const RELICS_PER_ACT := [1, 3, 5]

# Pilot policy (lifted verbatim from _probe_cardpower so the two are comparable).
const SAC_FODDER := ["dark_pact", "offering"]
const SAC_CANNON := ["fuel_the_pyre"]
const HEAL_SPELLS := ["patch_up"]

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var NM: Node
var CDB: Node
var RDB: Node
var combat: Node

var _started := false
var _samples := 6
var _max_rounds := 30
var _from := 0
var _to := 100000
var _act_filter := 0
var _type_filter := ""
var _starter_only := false
var _hp_override := 0
var _tag := "-"
var _force_act := 0
var _rows: Array = []          # per-encounter aggregate dicts
var _draft_pool: Array = []    # ids the pilot can actually play


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var arg := String(a)
		if arg.begins_with("--samples="): _samples = maxi(1, int(arg.substr(10)))
		elif arg.begins_with("--from="): _from = int(arg.substr(7))
		elif arg.begins_with("--to="): _to = int(arg.substr(5))
		elif arg.begins_with("--act="): _act_filter = int(arg.substr(6))
		elif arg.begins_with("--type="): _type_filter = arg.substr(7)
		elif arg.begins_with("--maxrounds="): _max_rounds = int(arg.substr(12))
		elif arg.begins_with("--hp="): _hp_override = int(arg.substr(5))
		elif arg.begins_with("--tag="): _tag = arg.substr(6)
		elif arg.begins_with("--forceact="): _force_act = int(arg.substr(11))
		elif arg == "--starter": _starter_only = true

	RS = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	CDB = root.get_node_or_null("CardDB")
	RDB = root.get_node_or_null("RelicDB")
	if RS == null or EDB == null or CDB == null or RDB == null:
		printerr("[encwin] FATAL: autoloads missing")
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

	for id in CDB.CARD_POOL.keys():
		var sid := String(id)
		var d: Dictionary = CDB.CARD_POOL[sid]
		if String(d.get("type", "")) not in ["creature", "spell"]: continue
		if String(d.get("rarity", "")) == "enemy": continue
		if CDB.is_curse(sid): continue
		if sid in MODAL: continue
		_draft_pool.append(sid)

	var enc_ids: Array = []
	for id in EDB.ENCOUNTERS.keys():
		var sid := String(id)
		var e: Dictionary = EDB.ENCOUNTERS[sid]
		if _act_filter > 0 and int(e.get("act", 1)) != _act_filter: continue
		if _type_filter != "" and String(e.get("type", "combat")) != _type_filter: continue
		enc_ids.append(sid)
	enc_ids.sort()
	_from = clampi(_from, 0, enc_ids.size())
	_to = clampi(_to, _from, enc_ids.size())
	var chunk: Array = enc_ids.slice(_from, _to)

	print("[encwin] tag=%s encounters=%d (slice %d..%d of %d) samples=%d maxrounds=%d starter_only=%s"
		% [_tag, chunk.size(), _from, _to, enc_ids.size(), _samples, _max_rounds, str(_starter_only)])
	print("[encwin] playable draft pool = %d cards" % _draft_pool.size())

	for ei in chunk.size():
		var enc_id: String = chunk[ei]
		var enc: Dictionary = EDB.ENCOUNTERS[enc_id]
		var act: int = clampi(int(enc.get("act", 1)), 1, 3)
		var etype: String = String(enc.get("type", "combat"))
		var row := {
			"id": enc_id, "name": String(enc.get("name", enc_id)), "act": act,
			"type": etype, "n": 0, "wins": 0, "losses": 0, "stuck": 0,
			"rounds_sum": 0, "win_hp_sum": 0, "loss_bodies_sum": 0,
			"loss_ehp_sum": 0, "loss_ehp_max_sum": 0, "boot_fail": 0,
		}
		for s in _samples:
			var hero: String = HEROES[(ei + s) % HEROES.size()]
			var rng_seed: int = 90210 + s * 7919 + enc_id.hash()
			var r: Dictionary = await _fight(enc_id, enc, act, etype, hero, rng_seed)
			row.n += 1
			row.rounds_sum += int(r.get("rounds", 0))
			match String(r.get("result", "STUCK")):
				"WIN":
					row.wins += 1
					row.win_hp_sum += int(r.get("php", 0))
				"LOSS":
					row.losses += 1
					row.loss_bodies_sum += int(r.get("ebodies", 0))
					row.loss_ehp_sum += int(r.get("ehp", 0))
					row.loss_ehp_max_sum += int(r.get("ehp_max", 0))
				"BOOT":
					row.boot_fail += 1
				_:
					row.stuck += 1
					row.loss_bodies_sum += int(r.get("ebodies", 0))
			print("[encwin] FIGHT tag=%s enc=%s act=%d type=%s hero=%s s=%d result=%s rounds=%d php=%d ehp=%d/%d ebodies=%d"
				% [_tag, enc_id, act, etype, hero, s, String(r.get("result", "?")),
					int(r.get("rounds", 0)), int(r.get("php", 0)), int(r.get("ehp", 0)),
					int(r.get("ehp_max", 0)), int(r.get("ebodies", 0))])
		_rows.append(row)
		var decided: int = row.wins + row.losses
		print("[encwin] ENC tag=%s %-26s act=%d %-6s n=%d W=%d L=%d stuck=%d wr=%s"
			% [_tag, enc_id, act, etype, row.n, row.wins, row.losses, row.stuck,
				("%.0f%%" % (100.0 * row.wins / decided)) if decided > 0 else "n/a"])

	_report()
	quit(0)


func _report() -> void:
	print("")
	print("[encwin] ================= PER-ENCOUNTER TABLE (tag=%s) =================" % _tag)
	print("[encwin] %-26s %-3s %-6s %4s %4s %4s %5s %8s %8s %8s"
		% ["encounter", "act", "type", "n", "W", "L", "wr%", "avgRound", "winHPrem", "lossBody"])
	_rows.sort_custom(func(a, b):
		var aw: float = float(a.wins) / maxf(1.0, float(a.wins + a.losses))
		var bw: float = float(b.wins) / maxf(1.0, float(b.wins + b.losses))
		if is_equal_approx(aw, bw):
			return "%d%s" % [a.act, a.id] < "%d%s" % [b.act, b.id]
		return aw < bw)
	var tw := 0
	var tl := 0
	var ts := 0
	for r in _rows:
		var dec: int = r.wins + r.losses
		tw += r.wins
		tl += r.losses
		ts += r.stuck
		print("[encwin] %-26s %-3d %-6s %4d %4d %4d %5s %8.1f %8s %8s" % [
			r.id, r.act, r.type, r.n, r.wins, r.losses,
			("%.0f" % (100.0 * r.wins / dec)) if dec > 0 else "n/a",
			float(r.rounds_sum) / maxf(1.0, float(r.n)),
			("%.1f" % (float(r.win_hp_sum) / float(r.wins))) if r.wins > 0 else "-",
			("%.1f" % (float(r.loss_bodies_sum) / float(r.losses + r.stuck))) if (r.losses + r.stuck) > 0 else "-",
		])
	print("[encwin] TOTALS W=%d L=%d stuck=%d  overall wr=%.1f%%"
		% [tw, tl, ts, 100.0 * tw / maxf(1.0, float(tw + tl))])
	print("")
	print("[encwin] LIMITATIONS — the pilot is a floor, not a player:")
	print("[encwin]   * no potions, no discards (right-click mark), no Command banking")
	print("[encwin]   * never plays a card needing a pick UI (%d ids blocked)" % MODAL.size())
	print("[encwin]   * no card upgrades (+ forges) or veterancy carried in")
	print("[encwin]   * placement is a one-ply lane heuristic; no multi-round planning")
	print("[encwin]   * deck is a RANDOM roll of act-appropriate rewards, not a built deck")
	print("[encwin]   * every fight starts at full HP with a fresh deck (best case)")
	print("[encwin] DONE")


func _fight(enc_id: String, enc: Dictionary, act: int, etype: String, hero: String,
		rng_seed: int) -> Dictionary:
	seed(rng_seed)
	RS.start_new_run(hero, 0, 4242)
	# THE FIX the older harnesses miss: put the run in the encounter's own act so
	# Combat does not rescale an act-3 kit down to act-1 strength.
	RS.current_act_idx = (_force_act - 1) if _force_act > 0 else (act - 1)
	RS.current_encounter_id = enc_id
	RS.current_node_type = etype if etype in ["combat", "elite", "boss"] else "combat"
	if _hp_override > 0:
		RS.hero_hp = _hp_override

	if not _starter_only:
		var n_draft: int = DRAFTS_PER_ACT[act - 1]
		for _i in n_draft:
			var offer: Array = CDB.roll_card_reward(act, etype == "elite", false, 3)
			var legal: Array = []
			for c in offer:
				if String(c) in _draft_pool:
					legal.append(String(c))
			if legal.is_empty():
				legal = [_draft_pool[randi() % _draft_pool.size()]]
			RS.add_card(legal[randi() % legal.size()])
		var n_relic: int = RELICS_PER_ACT[act - 1]
		for _i in n_relic:
			var held: Array[String] = []
			for h in RS.relics:
				held.append(String(h))
			var roffer: Array = RDB.roll_relic_reward("combat", held, hero, 3)
			var rlegal: Array = []
			for rid in roffer:
				if not (String(rid) in RELIC_BLOCKLIST) and not (String(rid) in RS.relics):
					rlegal.append(String(rid))
			if not rlegal.is_empty():
				RS.add_relic(rlegal[randi() % rlegal.size()])

	seed(rng_seed)
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_turn():
		var boot := {"result": "BOOT", "rounds": 0, "php": 0, "ehp": 0, "ehp_max": 0, "ebodies": 0}
		if is_instance_valid(combat) and combat.phase == combat.Phase.GAME_OVER:
			boot = _snapshot(0)
		await _teardown()
		return boot

	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER and rounds < _max_rounds:
		await _auto_play_turn()
		if not is_instance_valid(combat): break
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		if not await _wait_turn(): break

	var out := _snapshot(rounds)
	await _teardown()
	return out


func _snapshot(rounds: int) -> Dictionary:
	var res := "STUCK"
	var php := 0
	var ehp := 0
	var ehp_max := 0
	var bodies := 0
	if is_instance_valid(combat):
		php = int(combat.player_hp)
		ehp = int(combat.enemy_hp)
		ehp_max = int(combat.enemy_max_hp)
		bodies = combat._all_enemy_creatures().size()
		if int(combat.round_number) > 0:
			rounds = int(combat.round_number)
		if combat.phase == combat.Phase.GAME_OVER:
			res = "WIN" if ehp <= 0 else "LOSS"
	return {"result": res, "rounds": rounds, "php": php, "ehp": ehp,
		"ehp_max": ehp_max, "ebodies": bodies}


func _wait_turn() -> bool:
	var w := 0
	while w < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		w += 1
	return false


# ── Pilot (same policy as _probe_cardpower) ────────────────────────────────

func _auto_play_turn() -> void:
	await _play_creatures()
	await _play_spells()
	await _play_creatures()


func _play_creatures() -> void:
	for _pass in 4:
		if not _turn_live(): return
		var played := false
		for card in combat._hand.duplicate():
			if not _card_live(card): continue
			var cd: Dictionary = card.card_data
			if String(cd.get("id", "")) in MODAL: continue
			if String(cd.get("type", "")) != "creature": continue
			if int(combat.player_mana) < int(cd.get("cost", 0)): continue
			var slot = _pick_slot(cd)
			if slot == null: continue
			card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5
			combat._on_card_played(card)
			played = true
			await create_timer(0.02).timeout
		if not played: return


func _play_spells() -> void:
	for _pass in 4:
		if not _turn_live(): return
		var played := false
		for card in combat._hand.duplicate():
			if not _card_live(card): continue
			var cd: Dictionary = card.card_data
			if String(cd.get("id", "")) in MODAL: continue
			if String(cd.get("type", "")) != "spell": continue
			var cost: int = int(cd.get("cost", 0))
			if int(combat.player_mana) < cost: continue
			var targeting := String(cd.get("targeting", "none"))
			if targeting == "none":
				if String(cd.get("scope", "")) == "YOUR ARMY" \
						and combat._all_player_creatures().is_empty():
					continue
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


func _turn_live() -> bool:
	return is_instance_valid(combat) and combat.phase == combat.Phase.PLAYER_TURN


func _card_live(card) -> bool:
	return is_instance_valid(card) and (card in combat._hand)


func _smart_target(cd: Dictionary) -> Object:
	var id := String(cd.get("id", ""))
	var targeting := String(cd.get("targeting", "none"))
	var spell: Dictionary = cd.get("spell", {})
	if id in SAC_FODDER: return _sac_fodder()
	if id in SAC_CANNON: return _sac_cannon()
	if id in HEAL_SPELLS: return _wounded_veteran()
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


func _sac_fodder() -> Object:
	var mine: Array = combat._all_player_creatures()
	if mine.size() < 2: return null
	var best: Object = null
	var best_v := 9999
	for c in mine:
		if not is_instance_valid(c): continue
		var v: int = c.effective_atk() * 2 + int(c.current_hp)
		if v < best_v: best_v = v; best = c
	return best


func _sac_cannon() -> Object:
	var mine: Array = combat._all_player_creatures()
	if mine.size() < 2: return null
	var best: Object = null
	var best_a := -1
	for c in mine:
		if not is_instance_valid(c): continue
		if int(c.current_hp) <= 2 and c.effective_atk() > best_a:
			best_a = c.effective_atk(); best = c
	return best if best != null else _sac_fodder()


func _wounded_veteran() -> Object:
	var best: Object = null
	var best_s := 0
	for c in combat._all_player_creatures():
		if not is_instance_valid(c): continue
		var missing: int = int(c.card_data.get("hp", c.current_hp)) - int(c.current_hp)
		var s: int = missing * 2 + c.effective_atk()
		if missing > 0 and s > best_s: best_s = s; best = c
	return best


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


func _pick_slot(cd: Dictionary):
	var kws: Array = cd.get("keywords", [])
	var atk := int(cd.get("atk", 0))
	var hp := int(cd.get("hp", 1))
	var is_wall: bool = ("guardian" in kws) or (atk <= 1 and hp >= 4)
	var wants_back: bool = ("sniper" in kws) \
		or String(cd.get("passive", "")) == "trebuchet_volley" \
		or (atk == 0 and not ("guardian" in kws))
	var front_free: Array = []
	var back_free: Array = []
	for lane in range(combat.LANES_PER_ROW):
		if combat._row_array(false, combat.ROW_FRONT)[lane] == null: front_free.append(lane)
		if combat._row_array(false, combat.ROW_BACK)[lane] == null: back_free.append(lane)
	if wants_back and back_free.size() > 0:
		var pick_b: int = back_free[0]
		for l in back_free:
			if combat._row_array(false, combat.ROW_FRONT)[l] != null:
				pick_b = l
				break
		return combat._slot_array(false, combat.ROW_BACK)[pick_b]
	if front_free.size() > 0:
		var pick: int = front_free[0]
		if is_wall:
			var best_t := -1
			for l in front_free:
				var t := _lane_threat(l)
				if t > best_t: best_t = t; pick = l
		else:
			var best_s := -999
			for l in front_free:
				var e = combat._row_array(true, combat.ROW_FRONT)[l]
				var s := 0
				if e != null and is_instance_valid(e):
					if int(e.current_hp) <= atk: s = 100 + e.effective_atk()
					else: s = _lane_threat(l) - int(e.current_hp)
				else:
					s = 50
				if s > best_s: best_s = s; pick = l
		return combat._slot_array(false, combat.ROW_FRONT)[pick]
	if back_free.size() > 0:
		return combat._slot_array(false, combat.ROW_BACK)[back_free[0]]
	return null


func _lane_threat(lane: int) -> int:
	var t := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var e = combat._row_array(true, row)[lane]
		if e != null and is_instance_valid(e):
			t += e.effective_atk()
	return t


func _teardown() -> void:
	if is_instance_valid(combat): combat.queue_free()
	combat = null
	await create_timer(0.04).timeout
