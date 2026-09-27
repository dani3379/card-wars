extends Node
## _probe_tribe_live.gd — the four Part C tribe MOMENTS, on a real board.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_tribe_live.tscn
##
## Its sibling `_probe_tribe_moments.gd` is a STRUCTURAL gate: it greps Combat.gd
## to prove the four moments were wired the way the design doc describes, and
## that the durable flags are not reset at round open. That is worth having, but
## it cannot tell you whether any of it FIRES — and `_probe_autorun` runs starter
## decks, so none of these four rares has ever been on a board.
##
## Each block below targets a failure this repo has actually shipped before, or
## a rule the design doc calls load-bearing:
##   VOLLEY    — the once-fired latch must survive a wipe, and the Piercing grant
##               must not strip PRINTED Piercing at round end (the Venom Tip bug,
##               shipped once already).
##   THE WORKS — the arming must survive the keystone's own death, and one blow
##               must never be paid for twice.
##   THE LEDGER— must pay on the round's SECOND working, at most once, and must
##               not burn its once-per-round flag on an empty board.
##   STAMPEDE  — must FIZZLE on an empty column and must never reach the face.
##               Beasts hitting the face on arrival is a shape this project
##               explicitly rejected; a passive smuggling it back would be that
##               rejected card with extra steps.

const COMBAT_SCENE := "res://scenes/combat.tscn"

var _fails := 0
var _combat = null


func _ready() -> void:
	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = _find_act1_combat()
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	await get_tree().process_frame

	_combat = load(COMBAT_SCENE).instantiate()
	add_child(_combat)
	# Poll on round + hand, NOT on phase: Phase.PLAYER_TURN is enum 0, which is
	# also the uninitialised default (documented trap).
	var waited := 0
	while waited < 400:
		if is_instance_valid(_combat) and _combat.round_number >= 1 \
				and not _combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	_check(_combat.round_number >= 1, "combat reached round 1")

	await _test_swift_sniper()
	await _test_volley()
	await _test_works()
	await _test_ledger()
	await _test_stampede()

	print("[tribe-live] %s" % ("ALL PASS" if _fails == 0 else "%d FAILURE(S)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


# ── SWIFT + SNIPER (the veterancy ladder's dead-reward trap) ────────────────

## Not a tribe moment, but it lives or dies by the same table: the war school
## grants SWIFT at 3 kills and the tribe doctrine grants SNIPER at 10, so a Stray
## veteran taking the obvious pick order ends up with both. Until 2026-07-30 that
## combination silently deleted the snipe — the Swift pre-phase column-attacked and
## spent has_attacked_this_turn, then the clash skipped the body (sniper) and the
## ranged phase skipped it (already attacked). A 10-kill reward that does nothing,
## with no feedback, is the NO-DEAD-REWARDS rule broken by the ladder itself.
func _test_swift_sniper() -> void:
	print("— SWIFT + SNIPER (dead-reward trap)")
	var c = _combat
	_reset(c)
	var both = _put(c, false, c.ROW_FRONT, 0, 4, 6, ["swift", "sniper"])
	var quarry = _put(c, true, c.ROW_FRONT, 0, 1, 30)
	var q_hp: int = int(quarry.current_hp)
	await c._resolve_swift_attack(0, c.ROW_FRONT, false)
	_check(quarry.current_hp == q_hp,
		"a sniper does NOT column-attack in the Swift pre-phase (%d)" % quarry.current_hp)
	_check(not both.has_attacked_this_turn,
		"...and keeps its shot for the ranged phase, unspent")

	# And it really does fire there — the guard must save the snipe, not cancel it.
	await c._resolve_ranged_attacks(0)
	_check(quarry.current_hp < q_hp,
		"the snipe then landed in the ranged phase (%d -> %d)" % [q_hp, quarry.current_hp])

	# A plain Swift body is untouched by the guard.
	_reset(c)
	var plain_swift = _put(c, false, c.ROW_FRONT, 1, 4, 6, ["swift"])
	var target = _put(c, true, c.ROW_FRONT, 1, 1, 30)
	var t_hp: int = int(target.current_hp)
	await c._resolve_swift_attack(1, c.ROW_FRONT, false)
	_check(target.current_hp < t_hp,
		"a plain Swift body still strikes in the pre-phase (%d -> %d)"
			% [t_hp, target.current_hp])
	_check(plain_swift.has_attacked_this_turn,
		"...and spends its swing as before")


# ── SOLDIER · VOLLEY ────────────────────────────────────────────────────────

func _test_volley() -> void:
	print("— SOLDIER · VOLLEY")
	var c = _combat
	_reset(c)
	# A full front line of Soldiers plus the keystone in reserve.
	var line: Array = []
	for lane in range(c.LANES_PER_ROW):
		var s = _put(c, false, c.ROW_FRONT, lane, 2, 4)
		s.card_data["ctype"] = "soldier"
		line.append(s)
	var captain = _put(c, false, c.ROW_BACK, 0, 3, 5)
	captain.card_data["ctype"] = "soldier"
	captain.card_data["passive"] = "volley"

	var atk_before: int = line[0].effective_atk()
	c._apply_start_round_passives(false)
	_check(line[0].effective_atk() == atk_before + 1,
		"a full front line levels pikes: +1 ATK (%d -> %d)"
			% [atk_before, line[0].effective_atk()])
	_check(line[0].has_keyword("piercing"), "...and gains Piercing for the clash")
	_check(bool(c._volley_fired[0]), "the latch is set")

	# ONCE PER FIGHT. A second round with the line still full grants nothing.
	var atk_after: int = line[1].effective_atk()
	c._apply_start_round_passives(false)
	_check(line[1].effective_atk() == atk_after,
		"a second round with the line still full grants nothing more (%d)"
			% line[1].effective_atk())

	# THE LATCH SURVIVES A WIPE — the entire claim of the once-fired device. Wipe
	# every body including the keystone, rebuild a full line, and it must stay
	# fired. A tribe whose identity a wipe can switch back on is not durable.
	_clear_board(c)
	var line2: Array = []
	for lane in range(c.LANES_PER_ROW):
		var s2 = _put(c, false, c.ROW_FRONT, lane, 2, 4)
		s2.card_data["ctype"] = "soldier"
		line2.append(s2)
	var cap2 = _put(c, false, c.ROW_BACK, 0, 3, 5)
	cap2.card_data["ctype"] = "soldier"
	cap2.card_data["passive"] = "volley"
	var atk2: int = line2[0].effective_atk()
	c._apply_start_round_passives(false)
	_check(line2[0].effective_atk() == atk2,
		"after a full wipe the Volley STAYS fired (%d)" % line2[0].effective_atk())

	# A short line must not fire it at all.
	_reset(c)
	var short_line: Array = []
	for lane in range(c.LANES_PER_ROW - 1):
		var s3 = _put(c, false, c.ROW_FRONT, lane, 2, 4)
		s3.card_data["ctype"] = "soldier"
		short_line.append(s3)
	var cap3 = _put(c, false, c.ROW_BACK, 0, 3, 5)
	cap3.card_data["ctype"] = "soldier"
	cap3.card_data["passive"] = "volley"
	var atk3: int = short_line[0].effective_atk()
	c._apply_start_round_passives(false)
	_check(short_line[0].effective_atk() == atk3,
		"a line one body short does NOT fire it (%d)" % short_line[0].effective_atk())
	_check(not bool(c._volley_fired[0]), "...and the latch stays unset")

	# THE VENOM TIP BUG. A Soldier that PRINTS Piercing must still have it after
	# round-end cleanup — the grant may only mark bodies it actually granted.
	_reset(c)
	var printed: Array = []
	for lane in range(c.LANES_PER_ROW):
		var p = _put(c, false, c.ROW_FRONT, lane, 2, 4, ["piercing"])
		p.card_data["ctype"] = "soldier"
		printed.append(p)
	var cap4 = _put(c, false, c.ROW_BACK, 0, 3, 5)
	cap4.card_data["ctype"] = "soldier"
	cap4.card_data["passive"] = "volley"
	c._apply_start_round_passives(false)
	_check(not bool(printed[0].state.temp_piercing),
		"a Soldier that PRINTS Piercing is not marked as a temp grant")
	c._post_combat_cleanup()
	_check(printed[0].has_keyword("piercing"),
		"...so round-end cleanup does NOT strip its printed Piercing")

	# And the granted case is genuinely round-scoped, both halves.
	_reset(c)
	var granted: Array = []
	for lane in range(c.LANES_PER_ROW):
		var g = _put(c, false, c.ROW_FRONT, lane, 2, 4)
		g.card_data["ctype"] = "soldier"
		granted.append(g)
	var cap5 = _put(c, false, c.ROW_BACK, 0, 3, 5)
	cap5.card_data["ctype"] = "soldier"
	cap5.card_data["passive"] = "volley"
	var base_atk: int = granted[0].effective_atk()
	c._apply_start_round_passives(false)
	# The two halves of the grant are cleaned at DIFFERENT beats, which is worth
	# spelling out because it is easy to test the wrong one: the temp KEYWORD is
	# erased by _post_combat_cleanup, while temp_atk_buff is zeroed in
	# _discard_hand's end-of-turn creature upkeep (Combat.gd:14224). Both must
	# happen or the "for that clash" promise on the card is false.
	_check(int(granted[0].temp_atk_buff) == 1,
		"the +1 rode temp_atk_buff, not persistent_atk_buff")
	_check(int(granted[0].persistent_atk_buff) == 0,
		"...so it cannot survive the fight")
	c._post_combat_cleanup()
	_check(not granted[0].has_keyword("piercing"),
		"a GRANTED Piercing is stripped at round end")
	await c._discard_hand()
	_check(granted[0].effective_atk() == base_atk,
		"and end-of-turn upkeep took the +1 back (%d)" % granted[0].effective_atk())


# ── BASTION · THE WORKS ─────────────────────────────────────────────────────

func _test_works() -> void:
	print("— BASTION · THE WORKS")
	var c = _combat
	_reset(c)
	# Arm through the REAL on-enter rather than by poking the flag, so the arming
	# path itself is under test.
	var keystone = _put(c, false, c.ROW_BACK, 0, 2, 7)
	keystone.card_data["ctype"] = "bastion"
	keystone.card_data["on_enter"] = {"type": "arm_works"}
	KeywordEffects.dispatch_on_enter(keystone, 0, false, c)
	_check(c._works_fortified[0] > 0, "the on-enter fortified the works")

	var wall = _put(c, false, c.ROW_FRONT, 1, 0, 20)
	wall.card_data["ctype"] = "bastion"
	var attacker = _put(c, true, c.ROW_FRONT, 1, 5, 30)
	var atk_hp: int = int(attacker.current_hp)
	wall.take_damage(4)
	c._apply_struck_passives(wall, attacker, false, 4)
	_check(atk_hp - attacker.current_hp == 4,
		"the wall reflected the 4 HP it lost (%d -> %d)" % [atk_hp, attacker.current_hp])

	# HP ACTUALLY LOST, not the attacker's printed ATK. An Armored wall that lost
	# 2 from a 3-damage blow must reflect 2 — that is what makes the rule
	# self-balancing rather than free damage for existing.
	var armored = _put(c, false, c.ROW_FRONT, 2, 0, 20, ["armored"])
	armored.card_data["ctype"] = "bastion"
	var atk2 = _put(c, true, c.ROW_FRONT, 2, 3, 30)
	var hp_before: int = int(armored.current_hp)
	var atk2_hp: int = int(atk2.current_hp)
	armored.take_damage(3)
	var really_lost: int = hp_before - int(armored.current_hp)
	c._apply_struck_passives(armored, atk2, false, really_lost)
	_check(atk2_hp - atk2.current_hp == really_lost,
		"an Armored wall reflects HP LOST (%d), not the printed blow" % really_lost)

	# IT FIRES ON THE WAY DOWN — the tribe's claim is that hitting the wall costs
	# you even when the wall falls.
	var dying = _put(c, false, c.ROW_FRONT, 3, 0, 3)
	dying.card_data["ctype"] = "bastion"
	var atk3 = _put(c, true, c.ROW_FRONT, 3, 9, 30)
	var atk3_hp: int = int(atk3.current_hp)
	dying.take_damage(9)
	_check(dying.current_hp <= 0, "fixture: the wall took a killing blow")
	c._apply_struck_passives(dying, atk3, false, 3)
	_check(atk3_hp - atk3.current_hp == 3,
		"a dying wall still bit back for the 3 it had (%d -> %d)"
			% [atk3_hp, atk3.current_hp])

	# THE ARMING SURVIVES THE KEYSTONE'S DEATH.
	keystone.queue_free()
	await get_tree().process_frame
	_reset_bodies_only(c)
	var wall2 = _put(c, false, c.ROW_FRONT, 0, 0, 20)
	wall2.card_data["ctype"] = "bastion"
	var atk4 = _put(c, true, c.ROW_FRONT, 0, 5, 30)
	var atk4_hp: int = int(atk4.current_hp)
	wall2.take_damage(5)
	c._apply_struck_passives(wall2, atk4, false, 5)
	_check(atk4_hp - atk4.current_hp == 5,
		"the works keep biting after the keystone fell (%d -> %d)"
			% [atk4_hp, atk4.current_hp])

	# ONE BLOW IS NEVER PAID FOR TWICE — a reflect_strike body is excluded.
	var rampart = _put(c, false, c.ROW_FRONT, 1, 0, 20)
	rampart.card_data["ctype"] = "bastion"
	rampart.card_data["passive"] = "reflect_strike"
	var atk5 = _put(c, true, c.ROW_FRONT, 1, 4, 30)
	var atk5_hp: int = int(atk5.current_hp)
	rampart.take_damage(4)
	c._apply_struck_passives(rampart, atk5, false, 4)
	_check(atk5_hp - atk5.current_hp == 4,
		"Iron Rampart reflects ONCE, not twice (%d -> %d)" % [atk5_hp, atk5.current_hp])

	# A WALL THAT KILLS HAS KILLED. Without this the Bastion doctrine at 10 kills
	# is unreachable by the tribe it was written for: `record_kill`'s only other
	# call site credits a killing SWING, and most pool Bastions are atk 0.
	var ledger_wall = _put(c, false, c.ROW_FRONT, 3, 0, 20)
	ledger_wall.card_data["ctype"] = "bastion"
	# _put rides summon_token, which stamps is_token — and the ledger correctly
	# refuses tokens (they have no identity, uid -1). Present this one as the real
	# deck creature it is standing in for.
	ledger_wall.is_token = false
	ledger_wall.deck_uid = 4242
	var doomed_atk = _put(c, true, c.ROW_FRONT, 3, 5, 3)
	var kills_before: int = RunState.get_kills(4242)
	ledger_wall.take_damage(5)
	c._apply_struck_passives(ledger_wall, doomed_atk, false, 5)
	_check(doomed_atk.current_hp <= 0, "fixture: the recoil killed the attacker")
	_check(RunState.get_kills(4242) == kills_before + 1,
		"a 0-ATK wall banked the kill its recoil made (%d -> %d)"
			% [kills_before, RunState.get_kills(4242)])

	# ...but only when the recoil actually finished it.
	var live_wall = _put(c, false, c.ROW_BACK, 3, 0, 20)
	live_wall.card_data["ctype"] = "bastion"
	live_wall.is_token = false
	live_wall.deck_uid = 4243
	var survivor = _put(c, true, c.ROW_BACK, 3, 2, 40)
	live_wall.take_damage(2)
	c._apply_struck_passives(live_wall, survivor, false, 2)
	_check(RunState.get_kills(4243) == 0,
		"a survived reflect banks nothing (%d)" % RunState.get_kills(4243))

	# A non-Bastion friendly must not reflect at all.
	var soldier = _put(c, false, c.ROW_FRONT, 2, 1, 20)
	soldier.card_data["ctype"] = "soldier"
	var atk6 = _put(c, true, c.ROW_FRONT, 2, 4, 30)
	var atk6_hp: int = int(atk6.current_hp)
	soldier.take_damage(4)
	c._apply_struck_passives(soldier, atk6, false, 4)
	_check(atk6.current_hp == atk6_hp,
		"a non-Bastion reflects nothing (%d)" % atk6.current_hp)


# ── WARLOCK · THE LEDGER ────────────────────────────────────────────────────

func _test_ledger() -> void:
	print("— WARLOCK · THE LEDGER")
	var c = _combat
	_reset(c)
	var magister = _put(c, false, c.ROW_BACK, 0, 3, 4)
	magister.card_data["ctype"] = "warlock"
	magister.card_data["on_enter"] = {"type": "arm_ledger"}
	KeywordEffects.dispatch_on_enter(magister, 0, false, c)
	_check(c._ledger_open[0] > 0, "the on-enter opened the Ledger")

	var caster = _put(c, false, c.ROW_FRONT, 1, 1, 9)
	caster.card_data["ctype"] = "warlock"
	var mark = _put(c, true, c.ROW_FRONT, 1, 1, 30)
	var mark_hp: int = int(mark.current_hp)

	# The round's FIRST working pays nothing.
	c._maybe_pay_ledger(false, 0)
	_check(mark.current_hp == mark_hp,
		"the round's first working pays nothing (%d)" % mark.current_hp)

	# The SECOND pays, 2 per Warlock, on the body across from each.
	c._maybe_pay_ledger(false, 1)
	_check(mark_hp - mark.current_hp == 2,
		"the second working strikes across for 2 (%d -> %d)" % [mark_hp, mark.current_hp])

	# At most once per round however many further spells are cast.
	var after: int = int(mark.current_hp)
	c._maybe_pay_ledger(false, 2)
	c._maybe_pay_ledger(false, 3)
	_check(mark.current_hp == after,
		"further workings in the same round pay nothing more (%d)" % mark.current_hp)

	# It must NOT burn its once-per-round flag on an empty board — the coven
	# simply had nothing to aim at, and the payoff should still be owed.
	_reset_bodies_only(c)
	c._ledger_paid_this_round.assign([false, false])
	var lonely = _put(c, false, c.ROW_FRONT, 2, 1, 9)
	lonely.card_data["ctype"] = "warlock"
	c._maybe_pay_ledger(false, 1)
	_check(not bool(c._ledger_paid_this_round[0]),
		"an empty column does not spend the Ledger's round")
	var target2 = _put(c, true, c.ROW_FRONT, 2, 1, 30)
	var t2_hp: int = int(target2.current_hp)
	c._maybe_pay_ledger(false, 1)
	_check(t2_hp - target2.current_hp == 2,
		"...so the next working with a target still pays (%d -> %d)"
			% [t2_hp, target2.current_hp])

	# The ROUND half resets; the ARMING half does not.
	var open_before: int = int(c._ledger_open[0])
	await c._start_round()
	_check(not bool(c._ledger_paid_this_round[0]),
		"a new round re-arms the once-per-round flag")
	_check(int(c._ledger_open[0]) == open_before,
		"...but the arming itself survives the round (%d)" % c._ledger_open[0])

	# And survives the Magister's own death.
	magister.queue_free()
	await get_tree().process_frame
	_check(int(c._ledger_open[0]) > 0,
		"the Ledger stays open after the Magister falls")


# ── BEAST · STAMPEDE ────────────────────────────────────────────────────────

func _test_stampede() -> void:
	print("— BEAST · STAMPEDE")
	var c = _combat
	_reset(c)
	var alpha = _put(c, false, c.ROW_BACK, 0, 4, 4)
	alpha.card_data["ctype"] = "beast"
	alpha.card_data["passive"] = "stampede"

	var quarry = _put(c, true, c.ROW_FRONT, 1, 1, 30)
	var first = _put(c, false, c.ROW_FRONT, 1, 3, 3)
	first.card_data["ctype"] = "beast"
	var q_hp: int = int(quarry.current_hp)

	# The round's FIRST Beast arrival charges nothing.
	c._maybe_stampede(first, false)
	_check(quarry.current_hp == q_hp,
		"the first Beast arrival of the round strikes nothing (%d)" % quarry.current_hp)

	# The SECOND charges the creature across from it, for its own ATK.
	var second = _put(c, false, c.ROW_FRONT, 2, 5, 3)
	second.card_data["ctype"] = "beast"
	var quarry2 = _put(c, true, c.ROW_FRONT, 2, 1, 30)
	var q2_hp: int = int(quarry2.current_hp)
	c._maybe_stampede(second, false)
	_check(q2_hp - quarry2.current_hp == 5,
		"the second Beast charges for its own 5 ATK (%d -> %d)"
			% [q2_hp, quarry2.current_hp])

	# IT FIZZLES ON AN EMPTY COLUMN, AND THE FACE TAKES NOTHING. Load-bearing:
	# Beasts reaching the face on their arrival round is the rejected shape.
	var face_before: int = int(c.enemy_hp)
	var third = _put(c, false, c.ROW_FRONT, 3, 6, 3)
	third.card_data["ctype"] = "beast"
	c._maybe_stampede(third, false)
	_check(c.enemy_hp == face_before,
		"an empty column FIZZLES — the face takes nothing (%d)" % c.enemy_hp)

	# The counter is round-scoped, so next round's second arrival fires again.
	await c._start_round()
	_check(int(c._beasts_arrived_this_round[0]) == 0,
		"the arrival counter reset at round open")

	# THE CHARGE IS A STRIKE. It reports to the shared on-kill funnel, so a
	# Stampede kill grows Rampage exactly as a clash kill would. Without this the
	# card's own word "charges" is a lie, and The Interpreter — a card that pays
	# off kills — would silently ignore the whole mechanic.
	_reset(c)
	var alpha2 = _put(c, false, c.ROW_BACK, 0, 4, 4)
	alpha2.card_data["ctype"] = "beast"
	alpha2.card_data["passive"] = "stampede"
	var b1 = _put(c, false, c.ROW_FRONT, 0, 1, 3)
	b1.card_data["ctype"] = "beast"
	c._maybe_stampede(b1, false)          # first arrival, no charge
	var rager = _put(c, false, c.ROW_FRONT, 1, 6, 3, ["rampage"])
	rager.card_data["ctype"] = "beast"
	rager.card_data["rampage"] = 1
	var doomed = _put(c, true, c.ROW_FRONT, 1, 1, 2)
	var rage_before: int = int(rager.persistent_atk_buff)
	c._maybe_stampede(rager, false)
	_check(doomed.current_hp <= 0, "fixture: the charge killed its quarry")
	_check(int(rager.persistent_atk_buff) == rage_before + 1,
		"a Stampede KILL grew Rampage, so the charge is a real strike (%d -> %d)"
			% [rage_before, rager.persistent_atk_buff])

	# No keystone standing — no charge, ever.
	_reset(c)
	var lone_beast = _put(c, false, c.ROW_FRONT, 0, 5, 3)
	lone_beast.card_data["ctype"] = "beast"
	var beast2 = _put(c, false, c.ROW_FRONT, 1, 5, 3)
	beast2.card_data["ctype"] = "beast"
	var safe = _put(c, true, c.ROW_FRONT, 1, 1, 30)
	var safe_hp: int = int(safe.current_hp)
	c._maybe_stampede(lone_beast, false)
	c._maybe_stampede(beast2, false)
	_check(safe.current_hp == safe_hp,
		"without the Dire Alpha nothing charges (%d)" % safe.current_hp)


# ── helpers ─────────────────────────────────────────────────────────────────

func _find_act1_combat() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat":
			return String(id)
	return ""


## Full reset between tribes: board cleared AND every tribe flag zeroed, so one
## tribe's latch cannot leak into the next tribe's assertions.
## NOTE the .assign() calls. These are typed `Array[bool]` / `Array[int]`
## properties, and assigning an untyped literal to one from outside raises
## "Invalid assignment ... with value of type 'Array'" — which in GDScript ABORTS
## THE ENCLOSING FUNCTION. The first draft of this file did exactly that, so the
## flags silently never cleared and a later block inherited the previous block's
## latch. Array.assign() is the house workaround.
func _reset(combat) -> void:
	_clear_board(combat)
	combat._volley_fired.assign([false, false])
	combat._works_fortified.assign([0, 0])
	combat._ledger_open.assign([0, 0])
	combat._ledger_paid_this_round.assign([false, false])
	combat._beasts_arrived_this_round.assign([0, 0])


## Clear bodies but KEEP the tribe flags — used where the point of the block is
## that an arming outlives the board it was made on.
func _reset_bodies_only(combat) -> void:
	_clear_board(combat)


func _clear_board(combat) -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(combat.LANES_PER_ROW):
				if arr[i] != null and is_instance_valid(arr[i]):
					arr[i].queue_free()
				arr[i] = null


func _put(combat, is_enemy: bool, row: int, lane: int, atk: int, hp: int,
		kw: Array = []):
	combat.summon_token(atk, hp, lane, is_enemy, row, {}, "Probe Body", kw)
	var card = combat._row_array(is_enemy, row)[lane]
	if card == null:
		return null
	card.state.ready_to_swing = true
	card.has_attacked_this_turn = false
	return card


func _check(ok: bool, label: String) -> bool:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		printerr("  FAIL  " + label)
	return ok
