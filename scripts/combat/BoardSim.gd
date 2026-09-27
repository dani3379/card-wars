extends RefCounted
## BoardSim — a fast, node-free FORWARD MODEL of the clash: "if nobody played
## another card, how would this board resolve over the next few rounds?"
##
## `BoardEval` answers what a play is worth by looking at the board as it stands.
## That is a ONE-PLY judgement, and one ply is where every hand-tuned scorer is
## weakest: it cannot see that the 4/1 it just valued for its ATK dies to the
## first blow, or that the wall it undervalued survives three rounds and denies
## twenty damage. This file is the deeper look — the thing a post-game analysis
## compares the shallow judgement AGAINST (Veness et al., NeurIPS 2009,
## "Bootstrapping from Game Tree Search": train the cheap evaluator toward what
## the expensive search says).
##
## ── WHY IT EXISTS AT ALL: THE REAL CLASH CANNOT BE USED ──────────────────
## `Combat._clash_lane_pass` IS the authority on these rules, and it is
## unusable as a search primitive: it is a coroutine that awaits animation
## beats, mutates Card2D nodes, fires audio, writes the battle log and ships
## net events. A rollout needs to resolve a board thousands of times per second
## with no scene at all. So this is a SECOND implementation of the clash, and
## the honest name for that is an APPROXIMATION.
##
## ── WHAT IT MODELS, AND WHAT IT DOES NOT ─────────────────────────────────
## Modelled, because these are the rules that decide ordinary trades:
##   · both rows strike every round; front strikes first and is struck first
##   · target = opposing front in the column, else opposing back, else the face
##   · the MUSTER DELAY — a body does not swing in the clash ending its arrival
##     round; Swift is the exemption, and Swift may not reach the face that round
##   · OVERKILL — a killing blow's excess carries into the body behind, then stops
##   · PIERCING — the same spill, but it reads on to the face
##   · Armored (-1, min 1), Thorns (1 back), Last Stand (survive once at 1),
##     Regenerate/Wither at the top of a round, Lifelink, Sniper (culls lowest HP)
##   · deferred deaths, so a mutual trade resolves BOTH ways
## NOT modelled, deliberately, and every one of these is a known bias:
##   · cards drawn or played after this instant — a rollout here assumes both
##     sides stop playing. That is why the horizon is SHORT (3 rounds): it is
##     the window where "no further plays" is least wrong.
##   · on-enter / on-death / floop triggers, encounter passives, relics, spells
##   · Guardian/redirect, structures beyond "inert scenery does not block"
## A rollout is therefore a BOARD-RESOLUTION estimate, not a game solver. It is
## used only to RANK plays against each other, where a shared bias mostly cancels.
##
## ── THE AUTOLOAD TRAP (same as BoardEval's) ──────────────────────────────
## A plain RefCounted that `--script` probes preload: its dependencies compile
## BEFORE the autoloads register, so a bare `CardDB` / `RunState` identifier here
## is a hard compile error there while `_probe_parsecheck` stays green. Nothing
## in this file may name an autoload. Card data arrives as plain Dictionaries.

const BoardEval = preload("res://scripts/combat/BoardEval.gd")

const ROW_FRONT := 0
const ROW_BACK := 1
const LANES := 4
## Side indices. 0 is the "player" side of a Combat board, 1 the "enemy" side —
## the same convention `_row_array(is_enemy, row)` uses, so `side == 1` ⇔ is_enemy.
const SIDE_PLAYER := 0
const SIDE_ENEMY := 1

## How far a rollout looks. Three rounds is not a tuning taste: it is the point
## where the "nobody plays another card" assumption above stops being defensible.
const DEFAULT_HORIZON := 3
## A simulated game that has not ended by here is a stall, not a game. Used by
## the self-play driver, never by a rollout.
const MAX_SIM_ROUNDS := 40


# =========================================================================
#  THE SNAPSHOT — plain data, cloneable, no nodes
# =========================================================================

## One body on a simulated board. It is a RefCounted rather than a Dictionary
## for one reason that matters: `BoardEval` reads bodies through `effective_atk()`
## / `current_hp` / `card_data` / `can_attack()` / `is_inert_structure()`, and a
## RefCounted answering those is scored by the REAL scorer with no special case.
## That is what lets a post-game analysis re-score a decision offline, months
## after the Combat scene that produced it was freed.
class SimBody extends RefCounted:
	var atk: int = 0
	var current_hp: int = 1
	## The PRINTED hp — the ceiling a heal or Regenerate may restore to. The game
	## caps creature healing at `card_data.hp`, so that is the cap here too.
	var cap_hp: int = 1
	var kw: Array = []
	## The muster delay. FALSE by default, exactly as `CreatureInstance.ready_to_swing`
	## is, so every arrival path in this file gets the delay for free.
	var ready: bool = false
	var struck_this_round: bool = false
	var last_stand_spent: bool = false
	## A mustering defender trades on the COUNTER, once per clash. See `_strike`.
	var counter_spent: bool = false
	var card_data: Dictionary = {}
	## CARRIED THROUGH FROM THE LIVE BODY THIS WAS CAPTURED FROM, and it is load-
	## bearing rather than bookkeeping: the bot scores its turn against a snapshot,
	## so the target a spell picks IS one of these — and every net play path
	## addresses a creature by `entity_id`. Without it the bot would name no
	## target at all and every targeted spell would resolve on the wrong thing.
	## -1 means "not a body on the real board" (one the bot seated this turn, or a
	## body that only exists inside a rollout), which is the game's own value for
	## an untargeted play.
	var entity_id: int = -1

	func effective_atk() -> int:
		return atk

	## IT DOES NOT READ HP, AND THAT IS THE RULE RATHER THAN AN OVERSIGHT.
	## `Card2D.can_attack()` does not read HP either, and `Card2D.defer_deaths`
	## holds a dead body standing until the end of the pass — together that is
	## what makes a mutual trade mutual. Guarding on `current_hp > 0` here read
	## perfectly sensible and broke exactly one thing: the side that struck
	## SECOND in a 2/2-into-2/2 trade found a corpse that could no longer swing,
	## so every simultaneous kill resolved one-sided and the rollout would have
	## taught the scorer that trading up is free. Corpses are swept by `_sweep`
	## at the end of the pass, which is the only place it is safe to do it.
	func can_attack() -> bool:
		if struck_this_round:
			return false
		if "structure" in kw:
			return false
		return ready or "swift" in kw

	func is_inert_structure() -> bool:
		return "structure" in kw and not bool(card_data.get("attackable", false))

	func has(k: String) -> bool:
		return k in kw

	func clone() -> SimBody:
		var b := SimBody.new()
		b.atk = atk
		b.current_hp = current_hp
		b.cap_hp = cap_hp
		b.kw = kw.duplicate()
		b.ready = ready
		b.struck_this_round = struck_this_round
		b.last_stand_spent = last_stand_spent
		b.counter_spent = counter_spent
		b.card_data = card_data
		b.entity_id = entity_id
		return b


## A whole board, duck-typed so `BoardEval` scores it as if it were a live
## Combat instance. Nothing here knows it is a simulation.
class SimCtx extends RefCounted:
	var player_hp: int = 30
	var player_max_hp: int = 30
	var enemy_hp: int = 30
	var enemy_max_hp: int = 30
	## [side][row] → Array of LANES slots holding SimBody or null.
	var grid: Array = []

	func _init() -> void:
		grid = []
		for _s in 2:
			var rows: Array = []
			for _r in 2:
				rows.append([null, null, null, null])
			grid.append(rows)

	func _row_array(is_enemy: bool, row: int) -> Array:
		return grid[SIDE_ENEMY if is_enemy else SIDE_PLAYER][row]

	func at(side: int, row: int, lane: int) -> SimBody:
		if lane < 0 or lane >= LANES:
			return null
		var n: Variant = grid[side][row][lane]
		return n if n is SimBody else null

	func put(side: int, row: int, lane: int, b: SimBody) -> void:
		grid[side][row][lane] = b

	func hero(side: int) -> int:
		return enemy_hp if side == SIDE_ENEMY else player_hp

	func set_hero(side: int, v: int) -> void:
		if side == SIDE_ENEMY:
			enemy_hp = v
		else:
			player_hp = v

	func bodies(side: int) -> Array:
		var out: Array = []
		for row in [ROW_FRONT, ROW_BACK]:
			for lane in LANES:
				var b := at(side, row, lane)
				if b != null and b.current_hp > 0:
					out.append(b)
		return out

	func first_empty(side: int) -> Vector2i:
		for row in [ROW_FRONT, ROW_BACK]:
			for lane in LANES:
				if at(side, row, lane) == null:
					return Vector2i(lane, row)
		return Vector2i(-1, -1)

	func clone() -> SimCtx:
		var c := SimCtx.new()
		c.player_hp = player_hp
		c.player_max_hp = player_max_hp
		c.enemy_hp = enemy_hp
		c.enemy_max_hp = enemy_max_hp
		for side in 2:
			for row in 2:
				for lane in LANES:
					var b: SimBody = at(side, row, lane)
					c.grid[side][row][lane] = null if b == null else b.clone()
		return c


# =========================================================================
#  CAPTURE — read a live board (or any duck-typed stand-in) into a snapshot
# =========================================================================

## Build a SimBody from a card-data Dictionary. `arrived` false means the body
## has been standing a while and swings this round.
static func body_from_data(data: Dictionary, arrived: bool = true) -> SimBody:
	var b := SimBody.new()
	b.atk = int(data.get("atk", 0))
	b.current_hp = int(data.get("hp", 1))
	b.cap_hp = b.current_hp
	var k: Variant = data.get("keywords", [])
	b.kw = (k as Array).duplicate() if k is Array else []
	b.ready = not arrived
	b.card_data = data
	return b


## Snapshot a live `Combat` (or the probes' stub) into a SimCtx.
##
## READINESS IS READ THROUGH `can_attack()`, which is the game's own gate on the
## muster delay — and that is a deliberate approximation with one named cost:
## `can_attack()` is also false for a body that has already swung this round.
## Every caller here captures during a PLAYER/BOT TURN, before the clash, where
## `has_attacked_this_turn` is false for everything — so the two agree. Capturing
## mid-clash would read a board that has spent its swings as a board that cannot
## swing at all, which is not the same claim.
static func capture(ctx) -> SimCtx:
	var c := SimCtx.new()
	if ctx == null:
		return c
	c.player_hp = int(ctx.get("player_hp"))
	c.enemy_hp = int(ctx.get("enemy_hp"))
	var pmax: Variant = ctx.get("player_max_hp")
	var emax: Variant = ctx.get("enemy_max_hp")
	c.player_max_hp = int(pmax) if pmax != null else c.player_hp
	c.enemy_max_hp = int(emax) if emax != null else c.enemy_hp
	if not ctx.has_method("_row_array"):
		return c
	for side in 2:
		for row in 2:
			var arr: Variant = ctx.call("_row_array", side == SIDE_ENEMY, row)
			if not (arr is Array):
				continue
			var a: Array = arr
			for lane in mini(LANES, a.size()):
				var n: Variant = a[lane]
				if n == null or not is_instance_valid(n):
					continue
				var b := SimBody.new()
				var d: Variant = n.get("card_data")
				b.card_data = d if d is Dictionary else {}
				b.atk = BoardEval.atk_of(n)
				b.current_hp = BoardEval.hp_of(n)
				b.cap_hp = maxi(BoardEval.hp_cap_of(n), b.current_hp)
				b.kw = BoardEval.keywords_of(n).duplicate()
				# READINESS IS `ready_to_swing`, NOT `can_attack()`. They agree on
				# an ordinary body and disagree on exactly the one that matters: a
				# SWIFT creature that arrived this round answers can_attack() TRUE
				# (Swift is the muster-delay exemption) while its `ready_to_swing`
				# is still false — and the Rush rule, which bars Swift from the
				# FACE on its arrival round, keys off the latter. Capturing
				# can_attack() marked such a body as formed up, and every rollout
				# then let it hit the face on the turn it landed.
				var st: Variant = n.get("state")
				if st != null and st.get("ready_to_swing") != null:
					b.ready = bool(st.get("ready_to_swing"))
				else:
					b.ready = n.has_method("can_attack") and bool(n.call("can_attack"))
				var eid: Variant = n.get("entity_id")
				b.entity_id = int(eid) if eid != null else -1
				c.put(side, row, lane, b)
	return c


# =========================================================================
#  RESOLUTION — one round of the clash
# =========================================================================

## Land `dmg` on `target`, honouring Armored and Last Stand, and return the
## EXCESS (damage past the last point of HP) so the caller can spill it.
static func _land(target: SimBody, dmg: int) -> int:
	if target == null or dmg <= 0 or target.current_hp <= 0:
		return 0
	var d := dmg
	if target.has("armored"):
		d = maxi(1, d - 1)
	if d >= target.current_hp and target.has("last_stand") and not target.last_stand_spent:
		target.last_stand_spent = true
		target.current_hp = 1
		return 0
	target.current_hp -= d
	if target.current_hp < 0:
		var excess := -target.current_hp
		target.current_hp = 0
		return excess
	return 0


## One creature strikes into one column. `atk_side` owns the attacker.
##
## THE SPILL IS THE 2026-07-28 BLOCKER ECONOMY, and getting it wrong here would
## make the rollout disagree with the game about the single thing that decides
## whether a cheap wall is a good buy: overkill carries into the body BEHIND the
## victim and then STOPS; only Piercing reads on to the face.
static func _strike(c: SimCtx, atk_side: int, row: int, lane: int) -> void:
	var a := c.at(atk_side, row, lane)
	if a == null or not a.can_attack():
		return
	a.struck_this_round = true
	var def_side: int = SIDE_PLAYER if atk_side == SIDE_ENEMY else SIDE_ENEMY
	# A 0-ATK BODY STILL ENGAGES. It lands nothing, but the engine still resolves
	# the strike — so a mustering defender still gets its counter off it. Bailing
	# here (which this did) meant a 0/7 wall could be walked into by a 1-ATK
	# attacker for free, and the fidelity probe caught it as a one-point
	# disagreement that had no other explanation.
	var power := maxi(a.atk, 0)

	# SNIPER skips its own column and culls the weakest thing standing. It is the
	# one targeting rule here that is not lane-based.
	if a.has("sniper"):
		var quarry: SimBody = null
		for b in c.bodies(def_side):
			if b.is_inert_structure():
				continue
			if quarry == null or b.current_hp < quarry.current_hp:
				quarry = b
		if quarry != null:
			_land(quarry, power)
			_retaliate(a, quarry)
			_lifelink(c, atk_side, a, power)
		return

	var front := c.at(def_side, ROW_FRONT, lane)
	var back := c.at(def_side, ROW_BACK, lane)
	# A corpse does not block: the engine's own target test is `current_hp > 0`,
	# and an inert structure is treated as an empty seat everywhere else too.
	var victim: SimBody = null
	var victim_is_front := true
	if front != null and front.current_hp > 0 and not front.is_inert_structure():
		victim = front
	elif back != null and back.current_hp > 0 and not back.is_inert_structure():
		victim = back
		victim_is_front = false

	if victim == null:
		# NOTHING STANDING → the face. Swift is exempt from the muster delay but
		# may NOT reach the face on its arrival round (the Rush rule), which is
		# what stops it doubling as a burst finisher.
		if not a.ready and a.has("swift"):
			return
		c.set_hero(def_side, c.hero(def_side) - power)
		_lifelink(c, atk_side, a, power)
		return

	var victim_was_alive: bool = victim.current_hp > 0
	var excess := _land(victim, power)
	_retaliate(a, victim)
	_counter(a, victim, victim_was_alive)
	_lifelink(c, atk_side, a, power)
	if excess <= 0:
		return
	# OVERKILL: into the body behind, then stop.
	if victim_is_front and back != null and back.current_hp > 0 and not back.is_inert_structure():
		_land(back, excess)
		return
	# PIERCING is the only thing that reads on to the face.
	if a.has("piercing"):
		c.set_hero(def_side, c.hero(def_side) - excess)


static func _retaliate(attacker: SimBody, victim: SimBody) -> void:
	if victim != null and victim.has("thorns") and attacker != null:
		_land(attacker, 1)


## THE MUSTERING DEFENDER'S COUNTER — `Combat._defender_is_mustering` +
## `_apply_mutual_retaliation`. This was MISSING from the model until the
## fidelity probe found it, and it is not a detail: the muster delay stops a body
## INITIATING, never DEFENDING. A creature that arrived this round gets no swing
## of its own, so the clash gives it its trade on the counter instead — otherwise
## "cannot attack" decays into "cannot fight back" and playing a body would mean
## offering a free kill.
##
## Missing it biased the learner in a specific direction: every rollout treated a
## freshly-played blocker as something the enemy eats for nothing, so the scorer
## was being taught to undervalue exactly the play the front row is for.
##
## Once per clash, against the first thing to engage it (`counter_spent`), and
## only if the attacker is still standing — a counter from a body that died to
## Thorns on the way in is not a thing the engine does either.
static func _counter(attacker: SimBody, victim: SimBody, victim_was_alive: bool) -> void:
	if attacker == null or victim == null or not victim_was_alive:
		return
	if victim.counter_spent or victim.atk <= 0:
		return
	# A defender that CAN swing gets its own pass instead — no double count.
	if victim.ready or victim.has("swift"):
		return
	# SWIFT TAKES NOTHING BACK. It is Legends of Runeterra's QUICK ATTACK: strike
	# before the other body, and the counter does not answer it. Measured rather
	# than assumed — on a board where a Swift body and an ordinary one both
	# engaged the same mustering 7/7, the engine spent the counter on the ORDINARY
	# attacker and left the Swift one untouched.
	if attacker.has("swift"):
		return
	if attacker.current_hp <= 0:
		return
	victim.counter_spent = true
	_land(attacker, victim.atk)


static func _lifelink(c: SimCtx, side: int, a: SimBody, dealt: int) -> void:
	if a != null and a.has("lifelink") and dealt > 0:
		var cap: int = c.enemy_max_hp if side == SIDE_ENEMY else c.player_max_hp
		c.set_hero(side, mini(c.hero(side) + dealt, cap))


## Sweep corpses off the board. Called at the END of a row pass, never during
## one — `Card2D.defer_deaths` holds a dead body standing so a simultaneous
## trade resolves both ways, and removing it early turns every mutual kill into
## a one-sided one.
static func _sweep(c: SimCtx) -> void:
	for side in 2:
		for row in 2:
			for lane in LANES:
				var b := c.at(side, row, lane)
				if b != null and b.current_hp <= 0:
					c.put(side, row, lane, null)


## Resolve one full round: top-of-round ticks → Swift pre-phase → the clash →
## corpses swept → the muster sweep that readies everything for the NEXT round.
##
## THE MUSTER SWEEP IS LAST, and that ordering is the whole rule. In the game,
## `_start_round` readies the board and THEN the player seats new bodies, so a
## body placed in round N is still unready for round N's clash and swings from
## N+1. Readying at the top here would hand every freshly played creature a
## swing it does not have, which is precisely the defect BoardEval was built to
## stop the bot committing.
static func step_round(c: SimCtx) -> void:
	round_open(c)
	clash(c)
	muster(c)


## THE THREE PHASES ARE SPLIT so that each can be compared against the engine
## beat it corresponds to. `Combat._do_combat` is the CLASH ALONE — the
## start-of-round ticks and the muster sweep happen elsewhere in the round
## ladder — and `tools/_probe_sim_fidelity.gd` diffs the two clashes directly.
## Comparing a whole simulated round against the engine's clash charges the model
## for a regenerate tick the engine had not run yet, which reads as a modelling
## error and is a phase mismatch in the test.

## Start-of-round ticks: Regenerate and Wither, and everyone's swing refreshed.
static func round_open(c: SimCtx) -> void:
	for side in 2:
		for b in c.bodies(side):
			b.struck_this_round = false
			if b.has("regenerate"):
				b.current_hp = mini(b.current_hp + 1, b.cap_hp)
			if b.has("wither"):
				b.current_hp -= 1
	_sweep(c)


## The clash: Swift pre-phase, then both rows of every lane, then the dead swept.
static func clash(c: SimCtx) -> void:
	# The counter is spent ONCE PER CLASH, not once per round — reset it here
	# rather than in `round_open`, so a caller running a bare clash (the fidelity
	# probe does) gets the same rule a full round does.
	for side in 2:
		for row in 2:
			for lane in LANES:
				var cb := c.at(side, row, lane)
				if cb != null:
					cb.counter_spent = false
	# SWIFT ORDERING MIRRORS THE ENGINE: the whole FRONT row of both sides across
	# every lane, and only then the whole back row. Interleaving front and back
	# per lane (which this did first) resolves a back-row Swift before a front-row
	# one in a later lane, and the two orders disagree whenever a Swift kill in
	# one lane changes what a Swift strike in another finds standing.
	for row in [ROW_FRONT, ROW_BACK]:
		for lane in LANES:
			for side in [SIDE_PLAYER, SIDE_ENEMY]:
				var b := c.at(side, row, lane)
				if b != null and b.has("swift"):
					_strike(c, side, row, lane)
	# A body slain in the Swift pre-phase is barred from swinging but is NOT
	# removed here — `SWIFT_HOLDS_THE_LANE` (Combat.gd, 2026-09-15) holds it
	# standing until the post-clash sweep. `_strike`'s targeting already ignores
	# anything at zero HP, so leaving it in the slot changes nothing about who
	# gets hit; what it must NOT do is swing, and `_land` dropping it to zero
	# plus this flag is what stops that.
	for side in 2:
		for row in 2:
			for lane in LANES:
				var b := c.at(side, row, lane)
				if b != null and b.current_hp <= 0:
					b.struck_this_round = true

	# Front row first on both sides, then back — "front goes first and is
	# attacked first" is an ORDERING, not a separate combat tier.
	for lane in LANES:
		for row in [ROW_FRONT, ROW_BACK]:
			_strike(c, SIDE_PLAYER, row, lane)
			_strike(c, SIDE_ENEMY, row, lane)
		_sweep(c)
	_sweep(c)


## Everything still standing has formed up and swings from here on.
static func muster(c: SimCtx) -> void:
	for side in 2:
		for b in c.bodies(side):
			b.ready = true


# =========================================================================
#  VALUATION — in BoardEval's currency, so the two can be compared at all
# =========================================================================

## What a body on the board is worth. Deliberately the same shape as
## `BoardEval.body_value`, and it reads the SAME weights, because the entire
## point of a rollout is to produce a number the static scorer can be trained
## toward. Two different currencies would make the comparison meaningless.
static func body_worth(b: SimBody) -> float:
	if b == null or b.current_hp <= 0:
		return 0.0
	var v := float(b.atk) * BoardEval.W_ATK + float(b.current_hp) * BoardEval.W_HP
	v += BoardEval.keyword_value(b.kw, b.atk, b.current_hp, false)
	return v


static func material(c: SimCtx, side: int) -> float:
	var total := 0.0
	for b in c.bodies(side):
		if not b.is_inert_structure():
			total += body_worth(b)
	return total


## The value of a whole position from `side`'s point of view, in stat points.
## A dead hero is not on the same scale as a bad board, so it is not scored on
## one — the same reasoning as BoardEval.LETHAL.
static func evaluate(c: SimCtx, side: int) -> float:
	var foe: int = SIDE_PLAYER if side == SIDE_ENEMY else SIDE_ENEMY
	if c.hero(foe) <= 0:
		return BoardEval.LETHAL
	if c.hero(side) <= 0:
		return -BoardEval.LETHAL
	var v := material(c, side) - material(c, foe)
	v += float(c.hero(side) - c.hero(foe)) * BoardEval.W_FACE
	return v


## THE DEEPER LOOK. Resolve `horizon` rounds and report what the position is
## worth then. This is the signal a post-game analysis trains the static scorer
## toward — it is not "the truth", it is a strictly better-informed opinion,
## which is all RootStrap ever claimed for it either.
static func rollout(c: SimCtx, side: int, horizon: int = DEFAULT_HORIZON) -> float:
	var w := c.clone()
	for _i in maxi(1, horizon):
		step_round(w)
		if w.hero(SIDE_PLAYER) <= 0 or w.hero(SIDE_ENEMY) <= 0:
			break
	return evaluate(w, side)


# =========================================================================
#  APPLYING A CANDIDATE PLAY TO A SNAPSHOT
# =========================================================================

## Seat a creature / resolve a spell on a COPY of `c`, and return that copy.
## `play` is the shape BoardEval returns, plus the card data:
##   {kind:"creature"|"spell", data:Dictionary, lane:int, row:int, target:Vector3i}
## A spell's target is carried as (side, row, lane) rather than a node, because
## the node it was scored against is long gone by the time this runs.
##
## ONLY THE EFFECT TYPES `BoardEval.score_spell` CLAIMS TO KNOW ARE APPLIED, and
## an unknown one is left as a no-op on purpose: inventing a resolution for an
## effect this file does not model would teach the learner that the spell did
## nothing, which is a stronger and more wrong claim than "unmeasured".
static func apply_play(c: SimCtx, side: int, play: Dictionary) -> SimCtx:
	var w := c.clone()
	var data: Dictionary = play.get("data", {})
	if String(play.get("kind", "creature")) == "creature":
		var lane := int(play.get("lane", -1))
		var row := int(play.get("row", ROW_FRONT))
		if lane < 0:
			var slot := w.first_empty(side)
			lane = slot.x
			row = slot.y
		if lane >= 0 and w.at(side, row, lane) == null:
			w.put(side, row, lane, body_from_data(data, true))
		return w

	var foe: int = SIDE_PLAYER if side == SIDE_ENEMY else SIDE_ENEMY
	var spell_v: Variant = data.get("spell", {})
	var spell: Dictionary = spell_v if spell_v is Dictionary else {}
	var val := int(spell.get("value", 0))
	var tgt_v: Variant = play.get("target", null)
	var tgt: SimBody = null
	if tgt_v is Vector3i:
		var t: Vector3i = tgt_v
		tgt = w.at(t.x, t.y, t.z)

	match String(spell.get("type", "")):
		"damage":
			if tgt != null:
				_land(tgt, val)
		"damage_face":
			w.set_hero(foe, w.hero(foe) - val)
		"damage_all_enemies", "damage_all":
			for b in w.bodies(foe):
				_land(b, val)
		"heal":
			var cap: int = w.enemy_max_hp if side == SIDE_ENEMY else w.player_max_hp
			w.set_hero(side, mini(w.hero(side) + val, cap))
		"heal_creature":
			if tgt != null:
				tgt.current_hp = mini(tgt.current_hp + val, tgt.cap_hp)
		"buff_atk":
			if tgt != null:
				tgt.atk += val
		"buff_hp":
			if tgt != null:
				tgt.current_hp += val
				tgt.cap_hp += val
		"buff_all_atk":
			for b in w.bodies(side):
				b.atk += val
		"buff_all_hp":
			for b in w.bodies(side):
				b.current_hp += val
				b.cap_hp += val
		_:
			pass   # unmodelled: see the note above — a no-op, not a claim
	_sweep(w)
	return w
