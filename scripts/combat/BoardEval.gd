extends RefCounted
## BoardEval — what is this play WORTH, right now, on this board?
##
## Shared by `SkirmishBot` (the practice opponent) and `tools/_probe_pilot.gd`
## (the input pilot). It holds no state, touches no autoload and mutates nothing:
## every function is static and takes the Combat instance plus a card dict.
##
## ── WHY IT IS SHARED, AND WHY THAT IS NOT TIDINESS ───────────────────────
## Both callers need the same judgement ("is this the best card to play?") from
## opposite sides of the same board. Written twice, they are two implementations
## of one rule with nothing comparing them — which is the exact pathology this
## codebase has already paid for once: `NetPlayerState` restated every relic's
## magnitude as a literal instead of reading RelicDB, the two agreed on the day
## they were written, and a single retune would have moved one and left the other
## behind silently, on one player's Command pool, for one relic. So WHOSE SIDE IS
## MINE is a PARAMETER here (`mine_is_enemy`), not an assumption baked into a
## copy. The bot plays the `is_enemy` side; the pilot plays the player side.
##
## ── THE AUTOLOAD TRAP ────────────────────────────────────────────────────
## This is a plain RefCounted that tools `preload`, so its dependencies compile
## BEFORE the autoloads register — a bare `CardDB` / `RunState` identifier here
## is a hard compile error in a `--script` probe while `_probe_parsecheck` stays
## green, and it takes the whole depending probe down. Nothing in this file may
## name an autoload. Everything it needs arrives as an argument.
##
## ── ONE CURRENCY ─────────────────────────────────────────────────────────
## Every number below is denominated in STAT POINTS: one point is one point of
## ATK on a body that can swing. That single rule is what makes a heal comparable
## to a draw comparable to a removal spell — the scorer this replaced multiplied
## by 1.0, 0.6, 1.2, 1.3, 0.9 and 0.6 in different branches with no shared unit,
## so its numbers could be ordered within a branch and meant nothing across them.

const ROW_FRONT := 0
const ROW_BACK := 1
const LANES := 4

## ── THE SHIPPED DEFAULTS ─────────────────────────────────────────────────
## These `PT_*` consts are what the game ships with and what every assertion in
## `tools/_probe_board_eval.gd` is written against. They are NOT what the scorer
## reads — see the `W_*` block below.
##
## ATK is the unit. HP is worth less than ATK because it only ever defends,
## while ATK both threatens and wins trades — the usual card-game ratio is
## around 3:4 and that is what this is.
const PT_ATK := 1.0
const PT_HP := 0.75
## A card in hand. Two stat points is the long-standing design convention (a
## 1-cost vanilla is roughly a 2/2), and it is what makes "draw 2" comparable
## to "+2/+2".
const PT_CARD := 2.0
## One Command. Slightly better than a card: it is the thing that makes cards
## playable, and this game banks at most 2.
const PT_COMMAND := 2.0
## One damage to the enemy hero. Worth MORE than a stat point, because it is the
## only resource that actually wins — stats just contest the board.
const PT_FACE := 1.6
## Taking a body off the board is worth more than the HP it took to do it: you
## also delete every swing that body would ever have made again.
const PT_KILL := 2.0
## Placement terms, previously written inline as bare numbers. They are named
## here for one reason: a weight with no name cannot be learned, and these five
## are where a one-ply scorer is most often wrong.
const PT_BLOCK := 1.0          # multiplier on "how much damage this body stops"
const PT_OPEN_LANE := 0.8      # unblocked pressure, when the body can swing
const PT_CHUMP := 1.5          # penalty for a body that trades down and dies
const PT_SHELTER := 1.2        # a fragile hitter tucked behind a wall
const PT_BACK_EXPOSED := 1.0   # back row with nothing in front of it
const PT_TRADE_PARTIAL := 0.6  # a blow that wounds but does not kill
## WHAT KEEPING THE HERO'S SKIN IS WORTH, as a fraction of the face damage the
## block denies (2026-09-19). Named rather than folded into `W_FACE` because the
## two are genuinely different judgements — `face` is what damage to THEIR hero
## is worth, `deny` is what damage not taken by MINE is worth — and a player can
## rate them differently without being incoherent. A racer discounts its own
## skin; a grinder buys it.
##
## IT IS BELOW 1.0 FOR TWO REASONS A ONE-PLY SCORER CANNOT SEE. A wall closes a
## lane only while it stands, and the attacker behind it does not go away. And
## the block term beside it (`min(fa, hp) * W_HP * W_BLOCK`) already pays for
## part of the same event, so charging full face value here counts the blow
## twice.
##
## THE CEILING IS MEASURED, NOT CHOSEN. At parity with face damage, blocking
## swamped every other consideration: `tools/_probe_personas.gd` caught `curve`
## (the shipped vector) and `control` (the grinder) collapsing onto the SAME play
## on all three of its boards. Two named playstyles becoming one is the signal
## that a term has stopped being a preference and become a rule. Swept against
## that gate, the divergence returns at 0.35 and is gone by 0.45 — so this sits
## at the boundary, which is the strongest statement available: as much weight as
## the correction can carry without the default bot turning into the grinder.
const PT_DENY := 0.35
## One dial over the whole keyword table. Per-keyword weights were considered
## and rejected: the published work on evolving CCG evaluators is consistent
## that a modest parameter count converges on the sample sizes a practice bot
## can actually collect, and twenty keyword weights fitted on a few hundred
## games is noise wearing a number.
const PT_KEYWORD := 1.0
## What one ROUND of delayed face damage is worth against stopping the stream
## outright. A blocker that dies to the blow has not closed the lane — the same
## attacker bills the hero again next round — so it buys one instalment of a
## debt that runs the length of the fight. Fights here run 7-10 rounds measured,
## and this is deliberately at the pessimistic end of 1/7: a scorer that pays
## full price for a chump block will chump every lane it can reach, which is how
## a bot spends its whole hand delaying a loss instead of winning.
## NOT tunable by the learner: it is a statement about the clash rule, and the
## thing the learner is allowed to discover is how much blocking is worth, which
## is `W_BLOCK` sitting beside it.
const DENIAL_DELAY := 0.12
## A play that ends the game is not on the same scale as a play that does not.
## NOT tunable: this is a sentinel, not a valuation. Learning is not permitted
## to discover that winning is worth 940 points.
const LETHAL := 1000.0


## ── THE LIVE WEIGHTS — what the scorer actually reads ────────────────────
## `BotBrain` writes these between games. They start at the shipped defaults, so
## a build with no brain file on disk behaves EXACTLY as it did before any of
## this existed — that is the property that makes the learning safe to ship.
##
## THE GAUGE IS FIXED AT `W_ATK = 1.0` AND MUST STAY THAT WAY. Every score here
## is a sum of weighted terms, so multiplying the whole vector by a constant
## changes no ordering at all — the scorer is invariant under it and a learner
## is therefore free to wander off along that direction forever, growing without
## ever playing differently. Pinning one weight removes the degeneracy. ATK is
## the natural choice because the file's stated contract is already "ATK is the
## unit"; `BotBrain.normalise` re-imposes it after every update.
static var W_ATK := PT_ATK
static var W_HP := PT_HP
static var W_CARD := PT_CARD
static var W_COMMAND := PT_COMMAND
static var W_FACE := PT_FACE
static var W_KILL := PT_KILL
static var W_BLOCK := PT_BLOCK
static var W_OPEN_LANE := PT_OPEN_LANE
static var W_CHUMP := PT_CHUMP
static var W_SHELTER := PT_SHELTER
static var W_BACK_EXPOSED := PT_BACK_EXPOSED
static var W_TRADE_PARTIAL := PT_TRADE_PARTIAL
static var W_DENY := PT_DENY
static var W_KEYWORD := PT_KEYWORD

## The learnable vector, by name. This is the ONE place the set is declared —
## `export_weights` / `apply_weights` / the brain's gradient loop all read it,
## so adding a weight is a one-line change and cannot leave a consumer behind.
const WEIGHT_NAMES: Array = ["atk", "hp", "card", "command", "face", "kill",
	"block", "open_lane", "chump", "shelter", "back_exposed", "trade_partial",
	"keyword", "deny"]


static func default_weights() -> Dictionary:
	return {"atk": PT_ATK, "hp": PT_HP, "card": PT_CARD, "command": PT_COMMAND,
		"face": PT_FACE, "kill": PT_KILL, "block": PT_BLOCK,
		"open_lane": PT_OPEN_LANE, "chump": PT_CHUMP, "shelter": PT_SHELTER,
		"back_exposed": PT_BACK_EXPOSED, "trade_partial": PT_TRADE_PARTIAL,
		"keyword": PT_KEYWORD, "deny": PT_DENY}


static func export_weights() -> Dictionary:
	return {"atk": W_ATK, "hp": W_HP, "card": W_CARD, "command": W_COMMAND,
		"face": W_FACE, "kill": W_KILL, "block": W_BLOCK,
		"open_lane": W_OPEN_LANE, "chump": W_CHUMP, "shelter": W_SHELTER,
		"back_exposed": W_BACK_EXPOSED, "trade_partial": W_TRADE_PARTIAL,
		"keyword": W_KEYWORD, "deny": W_DENY}


## Install a weight vector. Missing keys keep their current value, so a brain
## file written before a weight existed still loads instead of zeroing it —
## a zero here is not a neutral default, it is "this consideration does not
## exist", which is how a save-format change silently lobotomises a bot.
static func apply_weights(w: Dictionary) -> void:
	W_ATK = float(w.get("atk", W_ATK))
	W_HP = float(w.get("hp", W_HP))
	W_CARD = float(w.get("card", W_CARD))
	W_COMMAND = float(w.get("command", W_COMMAND))
	W_FACE = float(w.get("face", W_FACE))
	W_KILL = float(w.get("kill", W_KILL))
	W_BLOCK = float(w.get("block", W_BLOCK))
	W_OPEN_LANE = float(w.get("open_lane", W_OPEN_LANE))
	W_CHUMP = float(w.get("chump", W_CHUMP))
	W_SHELTER = float(w.get("shelter", W_SHELTER))
	W_BACK_EXPOSED = float(w.get("back_exposed", W_BACK_EXPOSED))
	W_TRADE_PARTIAL = float(w.get("trade_partial", W_TRADE_PARTIAL))
	W_KEYWORD = float(w.get("keyword", W_KEYWORD))
	W_DENY = float(w.get("deny", W_DENY))


static func reset_weights() -> void:
	apply_weights(default_weights())


# =========================================================================
#  BOARD READS — side-aware, so one implementation serves both players
# =========================================================================

static func row_of(ctx, is_enemy: bool, row: int) -> Array:
	if ctx == null or not ctx.has_method("_row_array"):
		return []
	var a: Variant = ctx.call("_row_array", is_enemy, row)
	return a if a is Array else []


static func body_at(ctx, is_enemy: bool, row: int, lane: int) -> Variant:
	var arr := row_of(ctx, is_enemy, row)
	if lane < 0 or lane >= arr.size():
		return null
	var n: Variant = arr[lane]
	return n if n != null and is_instance_valid(n) else null


## Every live body on a side. Inert scenery is excluded: a `structure` that the
## clash cannot target is not a creature for valuation purposes, and counting it
## made board-wide spells look better than they are.
static func all_bodies(ctx, is_enemy: bool) -> Array:
	var out: Array = []
	for row in [ROW_FRONT, ROW_BACK]:
		for n in row_of(ctx, is_enemy, row):
			if n == null or not is_instance_valid(n):
				continue
			if n.has_method("is_inert_structure") and bool(n.call("is_inert_structure")):
				continue
			out.append(n)
	return out


static func occupancy(ctx, is_enemy: bool) -> Array:
	var grid: Array = [[false, false, false, false], [false, false, false, false]]
	for row in [ROW_FRONT, ROW_BACK]:
		for lane in LANES:
			grid[row][lane] = body_at(ctx, is_enemy, row, lane) != null
	return grid


static func hero_hp(ctx, is_enemy: bool) -> int:
	return int(ctx.get("enemy_hp") if is_enemy else ctx.get("player_hp"))


static func hero_max_hp(ctx, is_enemy: bool) -> int:
	return int(ctx.get("enemy_max_hp") if is_enemy else ctx.get("player_max_hp"))


static func atk_of(n: Variant) -> int:
	if n == null or not is_instance_valid(n):
		return 0
	if n.has_method("effective_atk"):
		return int(n.call("effective_atk"))
	return int(n.get("current_atk"))


static func hp_of(n: Variant) -> int:
	return 0 if n == null or not is_instance_valid(n) else int(n.get("current_hp"))


## A creature's HP ceiling. There is no `max_hp` anywhere on Card2D or
## CreatureInstance — the game caps a creature heal at the PRINTED value
## (`mini(current_hp + amount, card_data.hp)`), so that is the ceiling here too.
static func hp_cap_of(n: Variant) -> int:
	if n == null or not is_instance_valid(n):
		return 0
	var d: Variant = n.get("card_data")
	if d is Dictionary:
		return int((d as Dictionary).get("hp", 0))
	return 0


static func keywords_of(n: Variant) -> Array:
	if n == null or not is_instance_valid(n):
		return []
	var d: Variant = n.get("card_data")
	if d is Dictionary:
		var k: Variant = (d as Dictionary).get("keywords", [])
		return k if k is Array else []
	return []


# =========================================================================
#  EFFECT VALUES — every one measured against the LIVE board
# =========================================================================

## THE RULE THAT MATTERS MOST IN THIS FILE: a card is not worth what it says, it
## is worth what it would DO here. "Heal 1 to all friendlies" is worth nothing on
## a healthy board and four points on a battered one — same card, same text. The
## scorer this replaces read printed values, which is why it would throw a
## 6-damage spell at a 2/1 and call it a good play.
static func damage_value(target: Variant, dmg: int) -> float:
	if target == null or not is_instance_valid(target) or dmg <= 0:
		return 0.0
	var hp := hp_of(target)
	if hp <= 0:
		return 0.0
	# OVERKILL IS WASTED. Damage past the last point of HP buys nothing, so a
	# 6-damage spell on a 2/1 is worth exactly what a 1-damage spell would be
	# (plus the kill). Without this cap, removal is spent on the cheapest body
	# on the board.
	var landed := mini(dmg, hp)
	var v := float(landed) * W_HP
	if dmg >= hp:
		# The kill deletes the body: its remaining HP is already counted above,
		# so what is added here is everything it would have DONE.
		v += float(atk_of(target)) * W_ATK + W_KILL
		# Killing something that strikes back harder is worth more.
		if "thorns" in keywords_of(target):
			v += 1.0
	return v


static func heal_value(target: Variant, amount: int) -> float:
	if target == null or not is_instance_valid(target) or amount <= 0:
		return 0.0
	var missing := maxi(0, hp_cap_of(target) - hp_of(target))
	return float(mini(amount, missing)) * W_HP


## A hero heal, capped at what is actually missing — and worth more the closer
## the hero is to dying, because the last few points are the run.
static func hero_heal_value(ctx, mine_is_enemy: bool, amount: int) -> float:
	var cur := hero_hp(ctx, mine_is_enemy)
	var cap := hero_max_hp(ctx, mine_is_enemy)
	var missing := maxi(0, cap - cur)
	var landed := float(mini(amount, missing))
	if cap <= 0:
		return landed * W_HP
	var pressure: float = 1.0 + clampf(1.0 - float(cur) / float(cap), 0.0, 1.0)
	return landed * W_HP * pressure


## A buff on a body that is about to die is worth very little, and +ATK on a body
## that cannot swing this round is worth less than on one that can.
static func buff_value(target: Variant, d_atk: int, d_hp: int) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	var v := float(d_hp) * W_HP
	var swings := true
	if target.has_method("can_attack"):
		swings = bool(target.call("can_attack"))
	v += float(d_atk) * W_ATK * (1.0 if swings else 0.55)
	return v


## Face damage, and the one thing the old scorer had no concept of at all: a play
## that ENDS THE GAME is not on the same scale as a play that chips. It valued a
## 3-damage burn identically at 30 foe HP and at 3, so it could hold exact lethal
## in hand and play a 2/2 instead.
static func face_damage_value(ctx, mine_is_enemy: bool, dmg: int) -> float:
	if dmg <= 0:
		return 0.0
	var foe_hp := hero_hp(ctx, not mine_is_enemy)
	if dmg >= foe_hp:
		return LETHAL
	return float(dmg) * W_FACE


## What a keyword is worth ON THIS BODY, in stat points. Several of these scale
## with the body's own numbers — Piercing on a 1-ATK creature is nearly nothing
## and on a 7-ATK creature is most of a second attack.
static func keyword_value(kws: Array, atk: int, hp: int, arriving: bool) -> float:
	var v := 0.0
	for k in kws:
		match String(k):
			"swift":
				# Swift is the ONE exemption from the muster delay, so on the
				# arrival round it is worth a whole extra swing.
				v += float(atk) * (W_ATK if arriving else 0.35)
			"piercing":
				v += float(atk) * 0.45
			"armored":
				v += 1.5          # roughly +1 HP against every blow it takes
			"thorns":
				v += 1.0
			"last_stand":
				v += float(hp) * 0.4
			"regenerate":
				v += 1.2
			"lifelink":
				v += float(atk) * 0.35
			"guardian":
				v += 1.0
			"sniper":
				v += float(atk) * 0.5   # picks its target instead of its column
			"rampage", "overrun":
				v += float(atk) * 0.3
			"wither":
				v -= float(hp) * 0.3    # it is on a clock
			"doom":
				v -= float(hp) * 0.35   # so is this
	# ONE DIAL OVER THE WHOLE TABLE. See PT_KEYWORD: per-keyword weights are more
	# expressive and need more games than this bot will ever play to fit.
	return v * W_KEYWORD


## The raw worth of a body, ignoring where it stands.
static func body_value(data: Dictionary, arriving: bool) -> float:
	var atk := int(data.get("atk", 0))
	var hp := int(data.get("hp", 0))
	var kws: Variant = data.get("keywords", [])
	var v := float(atk) * W_ATK + float(hp) * W_HP
	v += keyword_value(kws if kws is Array else [], atk, hp, arriving)
	return v


# =========================================================================
#  SCORING A PLAY
# =========================================================================

## Where to put a creature, and what that placement is worth.
##
## TWO CORRECTIONS THE OLD SCORER NEEDED, both of them rules this game has had
## for over a year:
##
## 1. THE MUSTER DELAY (2026-07-21). A creature does NOT swing in the clash that
##    ends the round it arrived in. The old scorer credited `atk * 0.8` for
##    "unblocked pressure" and `+2.0` for "we can kill it" — both describing a
##    swing that cannot happen — so it consistently overvalued dropping a big
##    body into an open lane and undervalued the wall that survives to use it.
##    Only SWIFT is exempt, and `ignores_muster_delay()` is the game's own test.
##
## 2. THE BACK ROW IS PLAY SPACE. The old scorer carried a flat `-2.0` with the
##    comment "back row: no immediate combat". That is not this game: BOTH rows
##    strike every round, front simply attacks first and is attacked first. The
##    back row's real cost is that it is second in line for a lane, and its real
##    benefit is that a body there is shielded by the one in front — so the
##    preference is small, and it INVERTS for something fragile worth protecting.
## `occ_override` — A CALLER MAY KNOW MORE THAN THE BOARD DOES, and one of them
## does. `SkirmishBot.decide_turn` picks several plays in a single pass and
## returns them as INTENTS; nothing is applied until Combat resolves them, so the
## board still reads empty for every slot the bot has already committed to this
## turn. Reading occupancy live would put every creature it plays into the same
## lane. The bot therefore keeps its own running grid and hands it in. The pilot
## passes nothing: it drags one card at a time and the board is already true.
static func score_creature(ctx, mine_is_enemy: bool, data: Dictionary,
		occ_override: Array = []) -> Dictionary:
	var occ: Array = occ_override if occ_override.size() == 2 \
		else occupancy(ctx, mine_is_enemy)
	var atk := int(data.get("atk", 0))
	var hp := int(data.get("hp", 0))
	var kws_v: Variant = data.get("keywords", [])
	var kws: Array = kws_v if kws_v is Array else []
	var swift: bool = "swift" in kws
	# On the round it lands, a non-Swift body's ATK does nothing at all.
	var will_swing := swift

	var best := {}
	var best_score := -1.0e9
	for lane in LANES:
		for row in [ROW_FRONT, ROW_BACK]:
			if row < occ.size() and lane < occ[row].size() and occ[row][lane]:
				continue
			var score := score_creature_at(ctx, mine_is_enemy, data, lane, row)
			if score > best_score:
				best_score = score
				best = {"score": score, "lane": lane, "row": row}
	return best


## What this exact body in this exact SLOT is worth. Split out of the loop above
## on 2026-09-15, and the reason is not tidiness either.
##
## `score_creature` answers "where should this go, and what is that worth" — it
## returns only its WINNER. A post-game analysis needs the opposite: the score of
## a placement someone already chose, including the ones the scorer rejected, so
## that the choice can be compared against what a rollout says actually happened.
## And `BotBrain`'s gradient step re-scores the SAME two plays under perturbed
## weights, which is only meaningful if the placement is held fixed — re-running
## the search would let the argmax move between the two evaluations and measure
## the wrong difference entirely.
static func score_creature_at(ctx, mine_is_enemy: bool, data: Dictionary,
		lane: int, row: int) -> float:
	var atk := int(data.get("atk", 0))
	var hp := int(data.get("hp", 0))
	var kws_v: Variant = data.get("keywords", [])
	var kws: Array = kws_v if kws_v is Array else []
	# On the round it lands, a non-Swift body's ATK does nothing at all.
	var will_swing: bool = "swift" in kws

	var score := body_value(data, true)
	# Explicitly `Variant`, never `:=` — a board slot holds a Card2D or null, and
	# this project treats "inferred from a Variant value" as a build error.
	var foe_front: Variant = body_at(ctx, not mine_is_enemy, ROW_FRONT, lane)
	var foe_back: Variant = body_at(ctx, not mine_is_enemy, ROW_BACK, lane)
	var foe: Variant = foe_front if foe_front != null else foe_back
	var mine_front: Variant = body_at(ctx, mine_is_enemy, ROW_FRONT, lane)

	if row == ROW_FRONT:
		if foe != null:
			var fa := atk_of(foe)
			var fh := hp_of(foe)
			# BLOCKING IS THE POINT OF A FRONT BODY. What it is worth is the
			# damage it stops, and that is capped by what the blow would
			# actually have done — plus, since 2026-07-28, the excess carries
			# THROUGH into whatever stands behind, so a paper wall in front of
			# a big swing is not a full block.
			score += float(mini(fa, hp)) * W_HP * W_BLOCK
			# ...AND A BODY IN A COLUMN DENIES THE FACE ENTIRELY, WHICH IS A
			# DIFFERENT QUANTITY AND WAS WORTH NOTHING HERE (2026-09-19).
			#
			# `_clash_lane_pass` resolves "opposing front in this column, else
			# opposing back, else FACE". So an empty column is not a column the
			# hero is partly exposed in — it is a column the hero takes the blow
			# in, in full. Overkill spills into the body behind and STOPS; only
			# Piercing reads on to the face.
			#
			# The old line credited a block with the damage its own HP absorbed,
			# capping a 1/2 wall against a 6-ATK attacker at 1.5 points. What
			# that wall actually buys is SIX points of face damage denied, and
			# face damage is the only resource that ends the run. The measured
			# consequence was the whole difficulty finding: 93-96% of all damage
			# the hero took arrived through lanes the bot left open, while the
			# pilot placed for trades it could win rather than for the hero it
			# was supposed to be keeping alive.
			#
			# Only counted where the blow WOULD have reached the hero — with a
			# body already in the back of this column the foe was never hitting
			# the face, so there is nothing to deny and the trade terms above are
			# the whole story.
			# A CHUMP DELAYS; A WALL STOPS. That distinction is the whole of it,
			# and leaving it out is what made the first version of this term
			# wrong: an unblocked lane bills the hero `fa` EVERY round, so a
			# body that dies to the blow has not stopped the stream, it has
			# moved one instalment back by a round. A body that SURVIVES the
			# blow is still standing next round, and that is what buys the
			# stream off. `DENIAL_DELAY` is one round's worth against a fight
			# that runs 7-10 (measured); `W_CHUMP` below prices the corpse.
			var mine_back: Variant = body_at(ctx, mine_is_enemy, ROW_BACK, lane)
			if mine_back == null:
				var denied := float(fa)
				if "piercing" in keywords_of(foe):
					# Piercing reads THROUGH the blocker, so the wall only
					# denies what it absorbs.
					denied = float(mini(fa, hp))
				score += denied * W_FACE * W_DENY * (
					1.0 if hp > fa else DENIAL_DELAY)
			if will_swing and atk >= fh:
				score += damage_value(foe, atk)
			elif will_swing:
				score += float(mini(atk, fh)) * W_HP * W_TRADE_PARTIAL
			if hp <= fa and atk < fh:
				score -= W_CHUMP        # chump: trades down and dies
		else:
			# An open lane is pressure, but only from the round it can actually
			# swing.
			score += float(atk) * W_FACE * (W_OPEN_LANE if will_swing else 0.25)
	else:
		# Back row. Strikes like anything else; it is simply behind.
		#
		# AND IT REACHES THE FACE THROUGH A CLEAR COLUMN, which this branch did
		# not credit at all (2026-09-19). The front-row arm has always scored
		# `atk * W_FACE * OPEN_LANE` for an unopposed lane; the back-row arm
		# scored a flat +0.3 for the same body in the same empty column. That is
		# not a preference for the front row, it is the back row's offence
		# being invisible — and it is the same omission, in the same function,
		# that DEFECT 4 was written about: this game's back row strikes every
		# round and the scorer kept finding reasons not to notice.
		if foe == null:
			score += float(atk) * W_FACE * (W_OPEN_LANE if will_swing else 0.25)
		if mine_front == null:
			# Nothing in front means it is the one being hit — the front row's
			# exposure with none of the front row's initiative.
			score -= W_BACK_EXPOSED
			# BUT IT IS STILL IN THE COLUMN, so it still denies the face. The
			# clash reads front, then back, then the hero: a body in either row
			# is the difference between a blow landing on a creature and a blow
			# landing on the run. Leaving this out made the back row look like
			# pure exposure, which is the opposite of the house rule that the
			# back row is play space.
			#
			# Same chump-versus-wall rule as the front arm, and it is not
			# optional here either: without it the scorer preferred an EXPOSED
			# back slot in a threatened lane to a sheltered one in a safe lane,
			# because a full-price denial outweighed its own exposure penalty.
			if foe != null:
				var fa_b := atk_of(foe)
				var denied_b := float(fa_b)
				if "piercing" in keywords_of(foe):
					denied_b = float(mini(fa_b, hp))
				score += denied_b * W_FACE * W_DENY * (
					1.0 if hp > fa_b else DENIAL_DELAY)
		else:
			# Shielded. Worth most for something that hits hard and dies easily,
			# which is exactly what the flat -2.0 punished.
			if hp <= 3 and atk >= 3:
				score += W_SHELTER
			else:
				score += 0.3
	return score


## What a spell is worth, and what it should hit.
##
## `known` is the half the pilot needs and the bot does not. The bot should HOLD
## a spell it cannot evaluate — dumping it for nothing is how a bot throws a game
## away. The pilot must still CAST it, because an unscored spell is an unexercised
## resolver, and there are 52 effect types here against the dozen below: a pilot
## that only played what this function understands would quietly stop covering
## three quarters of the spell surface. So the judgement is returned, and the
## caller decides what to do with an unknown.
static func score_spell(ctx, mine_is_enemy: bool, data: Dictionary) -> Dictionary:
	var spell_v: Variant = data.get("spell", {})
	var spell: Dictionary = spell_v if spell_v is Dictionary else {}
	var stype := String(spell.get("type", ""))
	var val := int(spell.get("value", 0))
	var foes := all_bodies(ctx, not mine_is_enemy)
	var mine := all_bodies(ctx, mine_is_enemy)

	match stype:
		"damage":
			var best: Variant = null
			var best_v := 0.0
			for n in foes:
				var v := damage_value(n, val)
				if v > best_v:
					best_v = v
					best = n
			if best == null:
				return {"known": true, "score": 0.0, "target": null}
			return {"known": true, "score": best_v, "target": best}
		"damage_face":
			return {"known": true,
				"score": face_damage_value(ctx, mine_is_enemy, val), "target": null}
		"damage_all_enemies", "damage_all":
			var total := 0.0
			for n in foes:
				total += damage_value(n, val)
			return {"known": true, "score": total, "target": null}
		"heal":
			return {"known": true,
				"score": hero_heal_value(ctx, mine_is_enemy, val), "target": null}
		"heal_creature":
			var bh: Variant = null
			var bhv := 0.0
			for n in mine:
				var v := heal_value(n, val)
				if v > bhv:
					bhv = v
					bh = n
			return {"known": true, "score": bhv, "target": bh}
		"buff_atk", "buff_hp":
			var d_atk := val if stype == "buff_atk" else 0
			var d_hp := val if stype == "buff_hp" else 0
			var bb: Variant = null
			var bbv := 0.0
			for n in mine:
				var v := buff_value(n, d_atk, d_hp)
				if v > bbv:
					bbv = v
					bb = n
			if bb == null:
				return {"known": true, "score": 0.0, "target": null}
			return {"known": true, "score": bbv, "target": bb}
		"buff_all_atk", "buff_all_hp":
			var d_atk2 := val if stype == "buff_all_atk" else 0
			var d_hp2 := val if stype == "buff_all_hp" else 0
			var tot := 0.0
			for n in mine:
				tot += buff_value(n, d_atk2, d_hp2)
			return {"known": true, "score": tot, "target": null}
		"draw":
			return {"known": true, "score": float(maxi(val, 1)) * W_CARD,
				"target": null}
		"gain_mana":
			return {"known": true,
				"score": float(maxi(val, 1)) * W_COMMAND * _command_scarcity(ctx),
				"target": null}
		_:
			# Unknown. NOT zero — zero is a claim, and this is an absence of one.
			return {"known": false, "score": 0.0, "target": null}


## What one extra Command is worth RIGHT NOW, as a multiple of W_COMMAND.
##
## Under the flat-3 economy a Command was a Command and a constant was correct.
## The ramp made it a scarce resource early and an abundant one late: at round 1
## you hold ONE, so a spare Command doubles the turn; by the cap you hold six and
## it is a seventh of it. Marginal value is therefore ~1/pool, normalised so the
## weight keeps its calibrated meaning at the cap and only ever rises below it.
## Clamped at 3x because a scorer that values one Command above any board play is
## a scorer that never plays a card.
##
## READ THE CTX DEFENSIVELY. `ctx` is duck-typed — it is a live Combat for the
## bot and the pilot, but a BoardSim.SimCtx during a rollout, and that has no
## round at all. `Object.get` on a missing property answers null, so an absent
## round reads 0 and falls through to the neutral late-game assumption, which is
## the right default for a rollout that does not know when it is happening.
##
## SCOPE, so nobody measures this and reports nothing: CLAUDE.md's sensitivity
## sweep found `command` to be one of FOUR weights that never change a single
## decision in skirmish — `gain_mana` is its only consumer and few decks hold
## one. This is a correctness fix to a weight that was silently wrong, not a
## lever anyone should expect to move a win rate.
static func _command_scarcity(ctx) -> float:
	var r := 0
	if ctx != null:
		var v: Variant = ctx.get("round_number")
		if v is int or v is float:
			r = int(v)
	if r <= 0:
		return 1.0
	var pool: int = clampi(r, 1, RAMP_CAP_ASSUMED)
	return clampf(float(RAMP_CAP_ASSUMED) / float(pool), 1.0, 3.0)


## Combat.COMMAND_RAMP_CAP, restated because this file deliberately names no
## autoload and takes no Combat reference — that is what lets its gate run with
## stubs and no scene. Kept in step by `tools/_probe_board_eval.gd`.
const RAMP_CAP_ASSUMED := 6


# =========================================================================
#  DRAFT VALUE — what is this card worth IN A DECK?
# =========================================================================
##
## `score_play` answers "is this the best card to play on THIS board". Drafting
## asks a different question, and the difference is not academic: the best card
## to play right now is whatever the position wants, while the best card to OWN
## is the one that will be the right answer most often over the twenty fights
## still to come. A board-conditioned scorer is the wrong instrument for that —
## on an empty board it would rate a wall at nothing.
##
## THIS IS THE LEVER THAT WAS MISSING. The pilot took a card from the muster at
## UNIFORM RANDOM (`ready[_rng.randi_range(...)]`), bought a random affordable
## ware, forged a random card and — worst of the four — answered the shop's
## REMOVAL picker at random, so a run could pay 60 gold to delete its own rare.
## Every other lever in a deckbuilder is downstream of the deck, so a bot that
## drafts by coin-flip cannot be used to measure difficulty at all: it is
## measuring a deck nobody would ever build.
##
## SAME CURRENCY AS THE REST OF THE FILE — stat points — so a draft value and a
## play score are commensurable, which is what lets one policy decide between
## "take the card" and "take the gold".

## How much of a card's worth its COST eats. The ramp makes Command scarce early
## and free late, so a cheap card is worth more than its body says — it is the
## one that can be cast on the turn it matters. Denominated in stat points per
## Command, from the design convention a 1-cost vanilla is about a 2/2.
const DRAFT_COST_WEIGHT := 1.35
## What a deck's Nth copy of the same cost band is worth relative to its first.
## A deck of six-drops cannot act before round 6 and loses on the board while it
## waits; a deck of one-drops has no ceiling. Neither is a card's own fault,
## which is why this is a DECK term and not a card term.
const DRAFT_CURVE_PENALTY := 0.9
## Extra worth for a card that shares a tribe with what the deck already holds.
## Deliberately SMALL. The tribe keystones are real, but a draft policy that
## chases a tribe hard enough to take a weak card for it is how a bot builds a
## themed deck that loses — and the published work on drafting agrees that raw
## card quality dominates synergy at these deck sizes.
const DRAFT_SYNERGY := 0.45


## A card's standalone worth, before any deck considers it. Creatures are read
## off the statline the same way `body_value` does; a spell is read off the
## board-independent half of `score_spell`, which is its printed magnitude.
##
## `arriving` is FALSE here on purpose: a draft is not an arrival, and crediting
## every Swift body with a free extra swing would make Swift the only keyword the
## policy could see.
static func card_power(data: Dictionary) -> float:
	var ctype := String(data.get("type", "creature"))
	if ctype == "creature":
		var v := body_value(data, false)
		# An effect dict is worth roughly a stat point of body, and the same
		# rule `_probe_cost_rescale._power` learned applies: a dict that BILLS
		# the player is not a bonus. `hero_pay` is why Bloodsworn can print a
		# 4/4 Lifesteal at common, and counting it as upside is a double error.
		for key in ["on_enter", "on_death", "floop", "adj_buff", "passive"]:
			if data.has(key):
				v += 1.0
		var oe: Variant = data.get("on_enter", {})
		if oe is Dictionary and String((oe as Dictionary).get("type", "")) == "hero_pay":
			v -= 2.0
		return v
	# A spell's worth is its printed magnitude times how many times it fires.
	# `exhaust` is the common case and it is ONE use, which is the single
	# largest correction available on the spell half of a pool this size.
	var sp: Variant = data.get("spell", {})
	var mag := 0.0
	if sp is Dictionary:
		mag = float(int((sp as Dictionary).get("value", 0)))
	# AN UNREADABLE SPELL IS ASSUMED TO BE FAIRLY PRICED, and the alternative was
	# measured to be badly wrong. 78 of the 87 spells carry `type: "custom"` and
	# state what they do only in their rules text, so `spell.value` is 0 for most
	# of the pool. A FLAT floor was the first version of this and it made the
	# prior independent of cost — which, once the cost is subtracted below, meant
	# every expensive spell scored strongly negative and the policy declined all
	# of them: `holy_smite` at cost 4 came out at -2.90 against a 4-cost creature
	# at +3.10, for no reason except that the model could not read it.
	#
	# The honest prior for a card you cannot evaluate is that it costs what it is
	# worth. Denominated from the pool's own average body (mean 1.55 ATK / 2.34
	# HP at mean cost 2.40 after the 2026-09-16 rescale, i.e. ~1.2 stat points per
	# Command over a base), so an unreadable spell lands near zero net and
	# competes on the deck's curve rather than on the model's ignorance.
	var cost_f := float(int(data.get("cost", 0)))
	var v_spell := maxf(mag * 1.1, 1.2 * cost_f + 1.0)
	var kws_v: Variant = data.get("keywords", [])
	var kws: Array = kws_v if kws_v is Array else []
	if "retain" in kws:
		v_spell *= 1.3
	return v_spell


## What this card is worth to THIS deck. `profile` is what the caller knows about
## the deck it is building:
##   {costs: {cost:count}, ctypes: {ctype:count}, size: int}
## All optional — an empty profile degrades to standalone power, which is the
## right answer when the caller has no deck (a skirmish draft from nothing).
static func draft_value(data: Dictionary, profile: Dictionary = {}) -> float:
	var cost := int(data.get("cost", 0))
	var v := card_power(data)
	# CURVE. One cheap play is worth more than the fifth copy of it, and the
	# ramp is what makes that true: at Command 1 a 6-drop is a blank card.
	var costs: Variant = profile.get("costs", {})
	if costs is Dictionary:
		var band: int = clampi(cost, 0, 6)
		var have := int((costs as Dictionary).get(band, 0))
		if have > 0:
			v *= pow(DRAFT_CURVE_PENALTY, minf(float(have), 4.0))
		# A deck with nothing castable on round 1-2 loses the opening exchange
		# regardless of what it holds, and the opening exchange is where this
		# game is decided (measured: ahead until round 1.4 of 10.4).
		var cheap := int((costs as Dictionary).get(1, 0)) \
			+ int((costs as Dictionary).get(0, 0))
		if cost <= 2 and cheap < 4:
			v += 1.5
	# SYNERGY, small on purpose. See DRAFT_SYNERGY.
	var ct := String(data.get("ctype", ""))
	var ctypes: Variant = profile.get("ctypes", {})
	if ct != "" and ctypes is Dictionary:
		v += DRAFT_SYNERGY * float(mini(int((ctypes as Dictionary).get(ct, 0)), 4))
	# COST IS PAID EVERY TIME THE CARD IS DRAWN, not once at the draft. This is
	# the term that stops the policy taking the biggest body on every slate.
	v -= float(cost) * DRAFT_COST_WEIGHT
	return v


## The deck profile `draft_value` wants, built from a list of card dicts. Kept
## here rather than in the caller so the two cannot disagree about what a
## "cost band" is.
static func deck_profile(cards: Array) -> Dictionary:
	var costs: Dictionary = {}
	var ctypes: Dictionary = {}
	for d in cards:
		if not (d is Dictionary):
			continue
		var band: int = clampi(int((d as Dictionary).get("cost", 0)), 0, 6)
		costs[band] = int(costs.get(band, 0)) + 1
		var ct := String((d as Dictionary).get("ctype", ""))
		if ct != "":
			ctypes[ct] = int(ctypes.get(ct, 0)) + 1
	return {"costs": costs, "ctypes": ctypes, "size": cards.size()}


## The single entry point both callers use: what is playing THIS card worth, and
## how would it be played? Returns {} for a card that cannot be played at all.
##   {kind: "creature"|"spell", score: float, lane, row, target, known}
static func score_play(ctx, mine_is_enemy: bool, data: Dictionary,
		occ_override: Array = []) -> Dictionary:
	var ctype := String(data.get("type", "creature"))
	if ctype == "creature":
		var c := score_creature(ctx, mine_is_enemy, data, occ_override)
		if c.is_empty():
			return {}
		c["kind"] = "creature"
		c["known"] = true
		c["target"] = null
		return c
	var s := score_spell(ctx, mine_is_enemy, data)
	s["kind"] = "spell"
	s["lane"] = -1
	s["row"] = -1
	return s
