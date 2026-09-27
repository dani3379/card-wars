extends Node
## _probe_resolver_sweep.gd — CLASS C33: EVERY SPELL RESOLVER, ACTUALLY RUN.
##
## WHY THIS EXISTS, in the words of the pass that named the hole. `_probe_coverage`
## (C26) measures what ONE random-deck skirmish driver reaches and closes with:
##
##     "32 further spell effect types are CAMPAIGN-ONLY and outside this driver's
##      reach. `_probe_autorun` soaks campaign combat, so some are likely covered
##      there — but no pass MEASURES that, so it is UNKNOWN rather than uncovered.
##      A campaign-side twin of this pass would say."
##
## and, one line earlier, the reason it matters: "an effect type no random-deck
## match ever triggered is surface where the other gates have nothing to say, and
## that is where a bug hides behind green."
##
## Measured on 2026-09-19 it was 22 skirmish-unreached spell types PLUS 32
## campaign-only ones — up to 54 resolvers with no evidence of ever having run.
## This pass does not measure coverage, it MANUFACTURES it: every spell in
## CARD_POOL is resolved on a real board, in a real Combat scene, once.
##
## ── THE ORACLE, AND WHY IT IS NOT AN ASSERTION ABOUT THE EFFECT ──────────────
##
## What SHOULD `custom:apocalypse` do? Answering that needs an oracle the engine
## itself is — the problem that stopped the text-vs-data pass dead and produced
## C10's metamorphic relations instead. So this pass deliberately asserts NOTHING
## about an effect's meaning. It asserts the two things that are checkable without
## a second implementation:
##
##   A. THE GAME SAID NOTHING. A GDScript runtime error does not raise, does not
##      stop the game and does not change the exit code — it prints and ABORTS the
##      function where it stands. So a resolver can half-run forever and every
##      existing gate stays green. Detected OUTSIDE, by scoring stderr.
##   B. THE BOARD SURVIVED. After each resolution: no freed node left standing in
##      a row, no NaN/inf in any stat, no negative Command, no duplicate uid in
##      hand. This is C14's continuous-invariant idea applied PER EFFECT, and it
##      is the half that works from inside the probe.
##
## ── THE PART THAT MAKES (A) USABLE: ATTRIBUTION ──────────────────────────────
##
## Godot's error output is UNATTRIBUTED — a bare "Invalid access" in a 4,000-line
## log names a line in Combat.gd, not the content that reached it. A dump nobody
## can attribute gets skimmed and then ignored, which is how a real error survives
## a log somebody "checked". So every resolution prints
##
##     [resolver] TRY <card_id> (<type>) target=<kind>
##
## BEFORE the call. Any error line therefore lands immediately after the id that
## caused it, and `tools/_score_resolver_sweep.sh` walks the log in order and
## attributes each error to the last TRY seen. That ordering is the whole
## mechanism; do not buffer these prints or batch them.
##
## ── VACUITY GUARD, because a probe that skips everything prints a clean pass ──
##
## "Resolved 0 of 90, no errors" is a green light for an untested surface — the
## exact false pass C20's census shipped three times. So a SKIP is a first-class
## outcome here: every skip is printed with its reason and counted, and the pass
## FAILS if the resolved count falls under RESOLVE_FLOOR. Read the tallies before
## believing the verdict.
##
## Run (as a SCENE — it needs Combat, and Combat needs autoloads):
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_resolver_sweep.tscn
## Score it (attribution lives here, not in the probe):
##   bash tools/_score_resolver_sweep.sh /tmp/resolver.log

const COMBAT_SCENE := "res://scenes/combat.tscn"

## A resolver reached is a resolver tested; below this the pass is vacuous and
## says so. 90 spells ship today and a handful legitimately decline (see
## `_skips`), so the floor is deliberately well under the census.
const RESOLVE_FLOOR := 60

## Creature-trigger channels, each with a real dispatcher this pass can call.
##
## `floop` IS DELIBERATELY ABSENT. It has no standalone resolver — floop effects
## are resolved inline in the round flow, and `_resolve_on_play_ability` reads
## `on_play` only (its `blood_sacrifice` arm is an on-play type that merely shares
## a name with the floop concept). Firing floops here would mean re-implementing
## the round, i.e. a second implementation of a rule — so the honest move is to
## leave it out and say so rather than ship a channel that looks covered.
const TRIGGER_CHANNELS := ["on_enter", "on_death", "on_play"]

## Same argument as RESOLVE_FLOOR, per channel: a channel that resolved almost
## nothing must not read as a clean sweep of it.
const TRIGGER_FLOOR := {"on_enter": 20, "on_death": 15, "on_play": 15}

var combat
var _fails := 0
var _resolved := 0
var _skips: Array[String] = []
var _invariant_hits: Array[String] = []
var _trigger_counts: Dictionary = {}


func _ready() -> void:
	RunState.start_new_run("raider", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = _find_act1_combat()
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	# Huge pools on both faces: several of these effects are board wipes or face
	# burn, and a fight that ENDS mid-sweep takes the rest of the inventory with
	# it. This is a resolver test, not a balance test.
	RunState.hero_max_hp = 9000
	RunState.hero_hp = 9000
	await get_tree().process_frame

	combat = load(COMBAT_SCENE).instantiate()
	add_child(combat)
	# Poll on round + hand, never on `phase`: Phase.PLAYER_TURN is enum 0, which
	# is also the uninitialised default — the documented readiness trap.
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	if not _check(combat.round_number >= 1, "combat reached round 1"):
		_finish()
		return
	combat.enemy_hp = 9000
	combat.enemy_max_hp = 9000

	var ids := _spell_ids()
	print("[resolver] inventory: %d spells in CARD_POOL" % ids.size())
	for id in ids:
		await _try_spell(id)

	# ── PHASE B: CREATURE TRIGGERS ───────────────────────────────────────────
	# C26's unreached list is not only spells: 8 on-enter types, 3 on-death types
	# and a long tail of on-play abilities were never fired by its driver either.
	# The existing gates that DO touch these (newcards, newslate, retinue_hooks,
	# sexton, boardverbs) each assert a specific behaviour for a specific card —
	# valuable, and not the same thing as an exhaustive crash-and-invariant net
	# over every authored trigger. `atk_hp_per_unspent_mana` is named by no tool
	# at all.
	for chan in TRIGGER_CHANNELS:
		var tids := _trigger_ids(chan)
		print("[resolver] inventory: %d cards with %s" % [tids.size(), chan])
		for id in tids:
			await _try_trigger(id, chan)

	_finish()


## Every spell in the pool, draftable or not — the campaign-only half is the
## whole point, so this must NOT filter on rarity or `draftable`.
func _spell_ids() -> Array:
	var out: Array = []
	for id in CardDB.CARD_POOL.keys():
		var d: Dictionary = CardDB.CARD_POOL[id]
		if String(d.get("type", "")) == "spell":
			out.append(id)
	out.sort()
	return out


func _try_spell(id: String) -> void:
	var data: Dictionary = CardDB.CARD_POOL[id].duplicate(true)
	var spell: Dictionary = data.get("spell", {})
	var stype := String(spell.get("type", ""))
	if stype == "custom":
		stype = "custom:" + String(spell.get("id", "?"))
	var targeting := String(data.get("targeting", "none"))

	# Fresh ground per spell. A previous wipe leaves empty rows, and an effect
	# that needs a body would then SKIP for a reason belonging to its predecessor.
	await _reset_board()

	var target: Control = null
	var lane := -1
	var want_enemy := false
	match targeting:
		"none":
			pass
		"friendly_creature", "friendly_lane":
			want_enemy = false
		"enemy_creature", "two_enemies":
			want_enemy = true
		"any_creature", "any", "lane", "friendly_then_enemy":
			want_enemy = false
		_:
			_skips.append("%s: unknown targeting '%s'" % [id, targeting])
			return
	if targeting != "none":
		var seat := _seat_anywhere(want_enemy)
		target = seat[0]
		lane = seat[1]

	if targeting != "none" and target == null:
		_skips.append("%s: could not seat a %s target" % [id, targeting])
		return

	# THE ATTRIBUTION MARKER. Printed before the call, unbuffered, one line, so a
	# stderr error lands directly beneath the id that produced it.
	print("[resolver] TRY %s (%s) target=%s" % [id, stype, targeting])

	await combat._resolve_spell(data, target, lane)
	_resolved += 1
	await get_tree().process_frame
	_invariants(id, stype)


## Clear both sides and restore the resources an effect may have drained, so each
## spell meets the same board.  Deaths are resolved by the engine's own sweep
## rather than by freeing nodes here — freeing a body behind Combat's back is how
## a probe manufactures the stale-registry fault it is meant to detect.
func _reset_board() -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr: Array = combat._row_array(is_enemy, row)
			for lane in range(arr.size()):
				var c = arr[lane]
				if c != null and is_instance_valid(c):
					c.current_hp = 0
					if c.has_method("_die"):
						c._die()
	await get_tree().process_frame
	combat.enemy_hp = 9000
	RunState.hero_hp = 9000
	combat.player_mana = 99
	combat.player_max_mana = 99


func _invariants(id: String, stype: String) -> void:
	# Freed node left standing in a row — the shape C14 caught when Combat never
	# called unregister_entity.
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr: Array = combat._row_array(is_enemy, row)
			for lane in range(arr.size()):
				var c = arr[lane]
				if c != null and not is_instance_valid(c):
					_flag(id, stype, "freed node standing at %s row%d lane%d"
						% ["foe" if is_enemy else "ours", row, lane])
				elif c != null:
					var a := float(c.effective_atk())
					var h := float(c.current_hp)
					if is_nan(a) or is_inf(a) or is_nan(h) or is_inf(h):
						# A non-finite stat is silent until it reaches a tween,
						# where it becomes a repeating error with no backtrace.
						_flag(id, stype, "non-finite stat atk=%s hp=%s" % [a, h])
	if combat.player_mana < 0:
		_flag(id, stype, "Command went negative (%d)" % combat.player_mana)
	var seen := {}
	for c in combat._hand:
		if c == null or not is_instance_valid(c):
			_flag(id, stype, "freed card in hand")
			continue
		# deck_uid lives on Card2D, NOT on CreatureInstance. Reading it off
		# `state` throws on every card, which made the first run of this probe
		# report 86 identical "bugs" — a uniform failure across every case is
		# almost always a broken oracle, and this one was.
		var uid := int(c.deck_uid)
		if uid > 0 and seen.has(uid):
			_flag(id, stype, "duplicate uid %d in hand" % uid)
		seen[uid] = true


func _flag(id: String, stype: String, what: String) -> void:
	var line := "%s (%s): %s" % [id, stype, what]
	if _invariant_hits.has(line):
		return
	_invariant_hits.append(line)
	print("[resolver] INVARIANT %s" % line)
	_fails += 1


## Every card carrying a trigger on this channel, draftable or not.
func _trigger_ids(chan: String) -> Array:
	var out: Array = []
	for id in CardDB.CARD_POOL.keys():
		var d: Dictionary = CardDB.CARD_POOL[id]
		var t = d.get(chan, {})
		if t is Dictionary and not t.is_empty():
			out.append(id)
	out.sort()
	return out


## Fire one card's trigger on one channel, on a board that gives it something to
## act on: the subject in our front row, a friendly neighbour beside it, and an
## enemy opposite. Several of these effects buff adjacents, copy a neighbour,
## strike the opposing body or summon — with a bare board they would resolve down
## a do-nothing branch and this pass would report coverage it had not got.
func _try_trigger(id: String, chan: String) -> void:
	await _reset_board()
	var data: Dictionary = CardDB.CARD_POOL[id].duplicate(true)
	var ttype := String((data.get(chan, {}) as Dictionary).get("type", "?"))

	var subject = combat._net_spawn_creature(data, 90000 + _resolved, 1,
		combat.ROW_FRONT, false, false)
	if subject == null or not is_instance_valid(subject):
		_skips.append("%s [%s]: could not seat the subject" % [id, chan])
		return
	subject.state.ready_to_swing = true
	# A neighbour and an opponent, so adjacency / copy / opposing-strike arms have
	# real material instead of silently taking their empty-board branch.
	_put(false, combat.ROW_FRONT, 2, 2, 6)
	_put(true, combat.ROW_FRONT, 1, 2, 6)

	print("[resolver] TRY %s (%s:%s) target=board" % [id, chan, ttype])
	match chan:
		"on_enter":
			KeywordEffects.dispatch_on_enter(subject, 1, false, combat)
		"on_death":
			KeywordEffects.dispatch_on_death(subject, 1, false, combat,
				combat.ROW_FRONT)
		"on_play":
			await combat._resolve_on_play_ability(subject, 1, false)
	_resolved += 1
	_trigger_counts[chan] = int(_trigger_counts.get(chan, 0)) + 1
	await get_tree().process_frame
	_invariants(id, "%s:%s" % [chan, ttype])


## Seat a body ANYWHERE on the requested side, trying every slot.
##
## Fixing lane 0 looked obviously fine and was not: an earlier lane can be DENIED
## for the rest of the fight, and the denial is legitimate. `summon_token`'s own
## header records it — Salted Ground "must bind every enemy" summon — so resolving
## `salted_ground` salts the lane the probe kept reusing, and the four
## enemy-target spells that sort after it (sappers_charge, shove, slash,
## soul_swap) were reported as unseatable against a game behaving exactly as
## specified. Closed ground (set-pieces) denies seats the same way. Walking the
## slots is robust to both without the probe restating either rule.
func _seat_anywhere(is_enemy: bool) -> Array:
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for lane in range(4):
			if combat._row_array(is_enemy, row)[lane] != null:
				continue
			var c = _put(is_enemy, row, lane, 2, 6)
			if c != null:
				return [c, lane]
	return [null, -1]


func _put(is_enemy: bool, row: int, lane: int, atk: int, hp: int):
	combat.summon_token(atk, hp, lane, is_enemy, row, {}, "Probe Body", [])
	var card = combat._row_array(is_enemy, row)[lane]
	if card == null:
		return null
	# The muster delay defaults ready_to_swing FALSE, so a hand-seated body that
	# is not stamped fails on its own precondition and reports it as a fault in
	# whatever was actually being tested.
	card.state.ready_to_swing = true
	card.has_attacked_this_turn = false
	return card


func _find_act1_combat() -> String:
	for eid in EncounterDB.ENCOUNTERS.keys():
		var e: Dictionary = EncounterDB.ENCOUNTERS[eid]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat":
			return eid
	return EncounterDB.ENCOUNTERS.keys()[0]


func _check(ok: bool, label: String) -> bool:
	if not ok:
		_fails += 1
		print("[resolver] FAIL %s" % label)
	return ok


func _finish() -> void:
	print("")
	print("[resolver] ============ SUMMARY ============")
	print("[resolver] resolved      : %d" % _resolved)
	print("[resolver] skipped       : %d" % _skips.size())
	for s in _skips:
		print("[resolver]   SKIP %s" % s)
	print("[resolver] invariant hits: %d" % _invariant_hits.size())
	# Vacuity: a clean report over an untested surface is worse than a red one,
	# because it reads as coverage.
	if _resolved < RESOLVE_FLOOR:
		_fails += 1
		print("[resolver] FAIL vacuous — resolved %d < floor %d; this pass tested"
			% [_resolved, RESOLVE_FLOOR]
			+ " far less than it appears to have")
	# Per channel, for the same reason: a healthy spell total must not paper over
	# a trigger channel that fired almost nothing.
	for chan in TRIGGER_CHANNELS:
		var got := int(_trigger_counts.get(chan, 0))
		var floor_n := int(TRIGGER_FLOOR.get(chan, 0))
		print("[resolver] %-9s fired : %d" % [chan, got])
		if got < floor_n:
			_fails += 1
			print("[resolver] FAIL vacuous channel — %s fired %d < floor %d"
				% [chan, got, floor_n])
	print("[resolver] %d failures" % _fails)
	print("[resolver] " + ("PASS" if _fails == 0 else "FAIL"))
	print("[resolver] NOTE: runtime errors are scored OUTSIDE this probe —"
		+ " a GDScript error neither raises nor changes the exit code."
		+ " Run tools/_score_resolver_sweep.sh over the log.")
	get_tree().quit(1 if _fails > 0 else 0)
