extends SceneTree
## Deck-vs-FIELD survival test (2026-07-13) — the complement to _probe_cardpower.
##
## Where cardpower isolates ONE card (stack 4-10 copies + filler, 2 fixed fights),
## this grades whole ARCHETYPE DECKS against the ENTIRE encounter table. It answers
## a different question: not "is card X an outlier" but "can a realistic deck built
## around the reworked/demoted cards actually clear the game's fights?" — so a card
## that reads flat in a stacked shell but pulls its weight in a real deck (Siege
## Golem's engine grant, Censer Light's zealots, King's Command's wide board) is
## finally seen in the shell it was designed for.
##
## Method: reuse cardpower's SMART pilot verbatim (creatures-first, walls opposite
## the biggest threat, snipers to back, sac-fodder/heal intents, army-wide support
## waits for an army). Each deck fights every encounter FROM FULL HP with NO relic
## (common-random-numbers isolation), MAX_ROUNDS cap. A fight is a WIN if the enemy
## is dead and the deck's hero is alive when it ends; a round-cap timeout is a loss
## (the deck couldn't close). Per deck: win% + mean HP margin; per encounter: which
## decks it beat (to spot an over-tuned fight, not just an over/under-tuned card).
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_field.gd
##   --field=all  also runs a boss sample (default 'core' = combat + elite only)

const MAX_ROUNDS := 14         # a real deck gets room to close; timeout = loss
const TURN_WAIT_TICKS := 70
const TICK := 0.1
const HERO := "raider"         # neutral shell; the deck is installed over its starter

# Same un-auto-playable set as cardpower (pick UI / special state). Decks avoid these.
const MODAL := ["familiar", "scholar", "treasure_hunter", "adaptable", "copycat",
	"doppelganger", "lost_tome", "war_council", "chaos_imp", "war_chant",
	"gambit", "recycle", "reanimate", "grave_robbery"]
const SAC_FODDER := ["dark_pact", "offering"]
const SAC_CANNON := ["fuel_the_pyre"]
const HEAL_SPELLS := ["patch_up"]

# ── Archetype decks — realistic ~12-card mixed lists, each built around a slice of
# the 2026-07-13 balance pass so the changed cards are exercised in their home shell.
const DECKS := {
	"AGGRO_SWIFT": ["goblin", "levy_rider", "skirmisher", "harpy", "lancer",
		"scavenger", "breaker", "war_cry", "slash", "flame_bolt", "doom_knight",
		"blood_tithe"],
	"WALL_CONTROL": ["palisade", "warding_stone", "ironhide_anvil", "iron_bastion",
		"siege_golem", "thornguard", "trebuchet", "torchbearer", "earthquake",
		"kings_command", "the_leveler", "smite_spell"],
	"ZEALOT_BURN": ["cinder_acolyte", "ember_warden", "bloodsworn", "hexblade",
		"emberwright", "mourner", "mending_light", "flame_bolt", "blood_tithe",
		"inferno", "concentrate", "reckless_charge"],
	"DEATH_SAC": ["mourner", "gravedigger", "tallow_doll", "husk", "blood_pyre",
		"necromancer", "carrion_priest", "thornguard", "offering", "grave_pact",
		"corpse_eater", "old_bones"],
	"MIDRANGE": ["brute", "naga", "pikeman", "duelist", "basilisk", "berserker",
		"dragon_hatchling", "patch_up", "smite_spell", "the_leveler", "cinder_whelp",
		"hex"],
}

# The field: all combat + elite across the three acts (the card-balance core), plus
# an optional boss sample under --field=all.
const FIELD_CORE := [
	"goblin_scouts", "wolf_pack", "bandit_camp", "mushroom_grove", "stone_sentinels",
	"harpy_nest", "boar_herd", "scarecrow_field", "orc_warband", "necromancer_tower",
	"cultist_enclave", "swamp_horror", "mercenary_company", "haunted_crypt",
	"fire_giants_forge", "oathbroken_knights", "ash_hounds", "outriders_hour",
	"grass_that_hunts", "borrowed_faces", "signal_glass", "demon_vanguard",
	"puppeteer", "horse_lords_toll", "mirror_temple", "elemental_nexus",
	"executioners_block", "dragons_lair", "pyre_cult", "withered_court",
	"killing_choir", "archlich", "void_walker", "corrupted_shepherd",
]
const FIELD_BOSS := [
	"rival_stalwart", "iron_warden", "dragon_lord", "collector", "hollow_king",
	"the_devil", "the_crone", "the_black_tide",
]

# ── PER-CARD mode (--mode=percard) — the "is the GAME too easy" test. Each card is
# slotted into the WEAK deck a real run actually has early: the plain raider starter
# (deliberately below pool commons) + N copies of the test card. If even this floor
# deck clears fights, the signal points at ENEMY strength, not deck strength. The
# bare starter's own win% is printed as the baseline so each card's LIFT is honest.
const RAIDER_STARTER := ["goblin", "goblin", "levy_rider", "levy_rider", "ratling",
	"ratling", "brute", "brute", "naga", "strike"]
# A difficulty-representative slice (2 combats/act spanning the curve) so a full
# ~110-card sweep stays tractable; elites/bosses excluded (dodgeable, meant hard).
const PERCARD_FIELD := [
	"goblin_scouts", "bandit_camp", "mercenary_company", "fire_giants_forge",
	"elemental_nexus", "dragons_lair",
]
# A DIFFICULTY-SPANNING field (--field=hard): 2 easy + 2 medium + 2 brutal, so a
# card's win% ranges the full 0-100% and actually SEPARATES cards (the easy field
# saturates win% at 50-100%; only margin discriminated there). Picked from the
# archetype run's per-encounter spread: easy (5/5), medium (2/5), brutal (0-1/5).
const PERCARD_FIELD_HARD := [
	"goblin_scouts", "bandit_camp", "fire_giants_forge", "harpy_nest",
	"ash_hounds", "pyre_cult",
]
# --field=buffed: the 3 act-1 combats given fight passives 2026-07-13, plus
# goblin_scouts (still plain) as the control. Used to check whether the passives
# raised the WEAK-deck floor (the bare-starter baseline is the number that matters).
const PERCARD_FIELD_BUFFED := [
	"goblin_scouts", "bandit_camp", "mushroom_grove", "stone_sentinels",
]

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var CDB: Node
var combat: Node
var _started := false
var _field: Array = []


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[field] start")
	RS = root.get_node_or_null("RunState"); EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings"); SS = root.get_node_or_null("SkirmishState")
	CDB = root.get_node_or_null("CardDB")
	if RS == null or EDB == null or CDB == null:
		print("[field] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	var mode := "archetype"
	var pc_copies := 2
	_field = FIELD_CORE.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg == "--field=all":
			_field += FIELD_BOSS
		elif arg == "--mode=percard":
			mode = "percard"
		elif arg.begins_with("--copies="):
			pc_copies = maxi(1, int(arg.substr(9)))
	if mode == "percard":
		await _run_percard(pc_copies)
		return
	# Validate deck ids up front so a typo is a clear message, not a mid-run crash.
	for dname in DECKS:
		for cid in DECKS[dname]:
			if not CDB.CARD_POOL.has(cid):
				print("[field] BAD deck id in %s: %s" % [dname, cid])

	print("[field] %d decks x %d encounters, cap %d rounds, no relic, full HP each"
		% [DECKS.size(), _field.size(), MAX_ROUNDS])

	var summary: Array = []                       # [{deck, winpct, mean_margin}]
	var enc_wins: Dictionary = {}                 # enc_id -> count of decks that won it
	for dname in DECKS:
		var deck: Array = DECKS[dname]
		var wins := 0
		var margin_sum := 0.0
		var counted := 0
		var worst: Array = []                     # [[margin, enc_id], ...]
		for enc_id in _field:
			var res = await _fight(enc_id, deck)
			if res == null:
				continue
			counted += 1
			var margin: int = int(res["margin"])
			var won: bool = bool(res["won"])
			margin_sum += float(margin)
			if won:
				wins += 1
				enc_wins[enc_id] = int(enc_wins.get(enc_id, 0)) + 1
			worst.append([margin, enc_id, won])
		worst.sort_custom(func(a, b): return a[0] < b[0])
		var winpct := 100.0 * float(wins) / float(maxi(1, counted))
		var mean_margin := margin_sum / float(maxi(1, counted))
		summary.append({"deck": dname, "winpct": winpct, "mean": mean_margin,
			"wins": wins, "n": counted})
		print("[field] %-13s  win %5.1f%% (%d/%d)   mean margin %+5.1f   worst: %s"
			% [dname, winpct, wins, counted, mean_margin, _fmt_worst(worst)])

	summary.sort_custom(func(a, b): return a["winpct"] > b["winpct"])
	print("[field] ================= DECK RANKING (win%%) =================")
	for s in summary:
		print("[field]   %5.1f%%  margin %+5.1f  %s" % [s["winpct"], s["mean"], s["deck"]])

	# Encounters no deck (or every deck) cleared — the over/under-tuned FIGHTS.
	print("[field] ================= ENCOUNTER DIFFICULTY (decks that won) =================")
	var enc_rows: Array = []
	for enc_id in _field:
		enc_rows.append([int(enc_wins.get(enc_id, 0)), enc_id])
	enc_rows.sort_custom(func(a, b): return a[0] < b[0])
	for row in enc_rows:
		var bar := ""
		for _i in row[0]: bar += "#"
		print("[field]   %d/%d %-20s %s" % [row[0], DECKS.size(), row[1], bar])
	print("[field] DONE")
	quit(0)


## PER-CARD floor test: the weak raider starter + N copies of each draftable card,
## vs a representative 6-fight field. Answers "does a REALISTIC weak deck still win?"
## — if most cards keep the floor deck winning, the enemies are under-tuned.
func _run_percard(copies: int) -> void:
	var pc_field: Array = PERCARD_FIELD
	# --only=<id,id,...> grades just those cards (2026-07-20). The full sweep is
	# ~111 cards x 6 fights; when you are validating a handful of NEW cards you
	# want the same instrument and the same baseline, not a 700-fight wait. The
	# baseline below still runs, so the lifts stay comparable to a full sweep's.
	var pc_only: Array = []
	var pc_nobase: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg == "--field=hard":
			pc_field = PERCARD_FIELD_HARD
		elif arg == "--field=buffed":
			pc_field = PERCARD_FIELD_BUFFED
		elif arg.begins_with("--only="):
			pc_only = arg.substr(7).split(",", false)
		elif arg == "--nobase":
			pc_nobase = true
	print("[field] PERCARD: raider starter + %dx <card> vs %d fights (win = kill & survive)"
		% [copies, pc_field.size()])
	# Baseline: the bare starter, no added card — the reference the lift is measured from.
	# --nobase skips it (2026-07-20): the baseline is 6 more fights, which is most of
	# a short chunk's budget, and it is FIXED for a given field — so when you are
	# grading a couple of cards against a baseline you already measured this session,
	# skipping it doubles how many cards fit in one run. Never skip it when the
	# baseline itself might have moved (encounter or starter-deck edits).
	var base_wins := 0
	var base_margin := 0.0
	var base_pct := 0.0
	if not pc_nobase:
		for enc_id in pc_field:
			var r = await _fight(enc_id, RAIDER_STARTER)
			if r != null:
				base_margin += float(r["margin"])
				if r["won"]: base_wins += 1
				print("[field]   baseline vs %-18s %s  m%+d" % [enc_id, ("WIN " if r["won"] else "LOSS"), int(r["margin"])])
		base_pct = 100.0 * float(base_wins) / float(maxi(1, pc_field.size()))
		print("[field] BASELINE bare starter: win %.1f%% (%d/%d)  mean margin %+.1f"
			% [base_pct, base_wins, pc_field.size(), base_margin / float(maxi(1, pc_field.size()))])
	else:
		print("[field] BASELINE skipped (--nobase) — lifts below read 0; compare the raw win%% against a baseline from this same session")

	# Draftable, auto-playable cards (same filter family as cardpower's MODAL skip).
	var ids: Array = CDB.CARD_POOL.keys()
	ids.sort()
	var rows: Array = []                   # [{id, cost, rarity, type, winpct, mean}]
	for id in ids:
		var sid := String(id)
		var d: Dictionary = CDB.CARD_POOL[sid]
		var t := String(d.get("type", ""))
		if t not in ["creature", "spell"]: continue
		if not pc_only.is_empty():
			# --only bypasses the draftable/modal filters the same way cardpower's
			# does, so an in-development card can be graded before it is pool-legal.
			if sid not in pc_only: continue
		else:
			if String(d.get("rarity", "")) == "enemy": continue
			if CDB.is_curse(sid): continue
			if sid in MODAL: continue
		var deck: Array = RAIDER_STARTER.duplicate()
		for _c in copies: deck.append(sid)
		var wins := 0
		var margin_sum := 0.0
		var counted := 0
		for enc_id in pc_field:
			var res = await _fight(enc_id, deck)
			if res == null: continue
			counted += 1
			margin_sum += float(res["margin"])
			if res["won"]: wins += 1
		var row := {"id": sid, "cost": int(d.get("cost", 0)),
			"rarity": String(d.get("rarity", "")), "type": t,
			"winpct": 100.0 * float(wins) / float(maxi(1, counted)),
			"mean": margin_sum / float(maxi(1, counted))}
		rows.append(row)
		# Print each card AS COMPUTED so partial results survive an interrupt and
		# progress is watchable; the sorted table below is the summary.
		print("[field] .. %-18s win %5.1f%% (%d/%d)  m%+5.1f"
			% [sid, row["winpct"], wins, counted, row["mean"]])

	rows.sort_custom(func(a, b): return a["winpct"] > b["winpct"])
	print("[field] ============ PER-CARD (weak shell) — win%% then margin ============")
	print("[field]   baseline (bare starter) = %.1f%% win, %+.1f margin  | lift vs baseline in ( )" % [base_pct, base_margin / float(maxi(1, pc_field.size()))])
	for r in rows:
		print("[field]   %5.1f%%  m%+5.1f  (%+4.1f)  %-18s [%s %dc %s]"
			% [r["winpct"], r["mean"], r["winpct"] - base_pct, r["id"], r["type"], r["cost"], r["rarity"]])
	# The verdict line: how many cards keep the FLOOR deck winning the majority.
	var over50 := 0
	for r in rows:
		if r["winpct"] >= 50.0: over50 += 1
	print("[field] VERDICT: %d/%d cards push the weak starter to >=50%% win (baseline %.1f%%). High count => enemies under-tuned."
		% [over50, rows.size(), base_pct])
	print("[field] DONE")
	quit(0)


func _fmt_worst(worst: Array) -> String:
	var out: Array = []
	for i in mini(3, worst.size()):
		out.append("%s(%+d%s)" % [worst[i][1], worst[i][0], "" if worst[i][2] else " L"])
	return ", ".join(out)


## One fight: install the deck over the hero's starter, no relic, full HP; run the
## smart pilot to a win/loss/timeout. Returns {won, margin} or null on a boot fail.
func _fight(enc_id: String, deck: Array):
	RS.start_new_run(HERO, 0, 4242)
	RS.current_encounter_id = enc_id
	var enc: Dictionary = EDB.get_encounter(enc_id)
	RS.current_node_type = String(enc.get("type", "combat"))
	RS.relics.clear()
	RS.deck.clear(); RS.deck_uids.clear()
	for cid in deck:
		RS.add_card(String(cid))
	seed(4242)
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_turn():
		await _teardown(); return null
	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER and rounds < MAX_ROUNDS:
		await _settle_hand()
		await _auto_play_turn()
		if not is_instance_valid(combat): break
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		if not await _wait_turn(): break
	if not is_instance_valid(combat):
		return null
	var php: int = maxi(0, int(combat.player_hp))
	var ehp: int = maxi(0, int(combat.enemy_hp))
	var won: bool = ehp <= 0 and php > 0
	var res := {"won": won, "margin": php - ehp}
	await _teardown()
	return res


# ═══════════ smart pilot (verbatim from _probe_cardpower.gd) ═══════════

func _wait_turn() -> bool:
	var w := 0
	while w < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		w += 1
	return false


## Poll until the hand has finished ARRIVING, not just until input is accepted.
##
## Combat._start_round STAGGERS the deal: only the first card is drawn inline,
## and every one after it lands on a `create_timer(0.08 * i)` — no headless
## branch, no reduce_motion branch, not scaled by `anim_speed` — while `phase`
## ALREADY reads PLAYER_TURN. A driver that starts there is playing a hand the
## game has not finished dealing it: on round 1 that is ONE card of five, and at
## Command 1 a single 2-drop means the whole turn plays nothing.
##
## Rounds 2+ hide it, because the hand is PERSISTENT and carries unplayed stock
## forward — so the fault is worst exactly where round-1 measurements live. It
## cost `_probe_deploy_curve` a published number before it was found; see
## CLAUDE.md's settle-until-stable note.
##
## Stability polling, NOT a computed deal window: draw_count is the ramp plus
## four relics plus two mutators, and restating that arithmetic in a probe is
## the duplicate-rule pathology. Bounded, because an unbounded `while await`
## spins to the harness timeout and reports NOTHING at all.
func _settle_hand() -> void:
	const SETTLE_TICK := 0.03    # poll interval
	const STABLE_TICKS := 5      # 0.15s unchanged, a 1.9x margin on the 0.08s gap
	const SETTLE_BUDGET := 40    # ~1.2s ceiling
	var last := -1
	var stable := 0
	var waited := 0
	while waited < SETTLE_BUDGET:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var n: int = combat._hand.size()
		if n == last:
			stable += 1
			if stable >= STABLE_TICKS:
				return
		else:
			stable = 0
			last = n
		await create_timer(SETTLE_TICK).timeout
		waited += 1


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
