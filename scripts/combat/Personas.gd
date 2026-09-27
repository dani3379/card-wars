extends RefCounted
## Personas.gd — PROCEDURAL PERSONAS: several ways to play, one scorer (2026-09-16).
##
## WHY THIS EXISTS. Every driver in this harness plays the same way — a greedy
## descending-cost pass with no board evaluation — so every balance number we have
## describes ONE policy. The published method for automated playtesting does not
## work that way: it evolves *procedural personas*, a set of agents with different
## utility functions (and different skill), and reads difficulty as the ENVELOPE
## across them rather than a single figure. The reason is not thoroughness, it is
## validity: a difficulty conclusion is only ever true *relative to the agent that
## produced it*, so one agent can only ever answer "is this hard for that agent?"
##
## We have paid for that twice in one session. `_probe_encwin` scores every act-3
## boss at 0% whether or not the fight was just changed, so the §3b A/B was
## unmeasurable; and `bandit_camp` read 13% before AND after a face-HP cut that
## demonstrably worked (the enemy face at the player's death moved 18-20/20 to
## 2-12/12 — the pilot simply dies before it can convert). Neither is a balance
## fact. Both are the instrument's ceiling reported as one.
##
## ── A PERSONA IS A WEIGHT VECTOR, NOT A SECOND SCORER ────────────────────────
## The obvious build is a policy per persona: an aggro brain, a control brain.
## That is the pathology this codebase has already paid for twice — `NetPlayerState`
## restating every relic's magnitude as a literal, and `SkirmishBot` carrying its
## own `_best_creature_slot` beside `BoardEval`. Two implementations of one
## judgement are equal on the day they are written and silently diverge on the
## first retune. So a persona is DATA: a vector over `BoardEval.WEIGHT_NAMES` plus
## a few behavioural traits. Every persona plays through the same gated scorer, and
## a rules change reaches all of them at once.
##
## ── `atk` IS THE GAUGE AND IS PINNED AT 1.0 IN EVERY PERSONA ─────────────────
## BoardEval's score is a sum of weighted terms, so multiplying the whole vector
## by a constant changes NO ordering — the scorer is invariant under it. Two
## personas differing only by a scale factor are therefore the same persona wearing
## two names, and a persona built by "make everything bigger" is a no-op that looks
## like a playstyle. Pinning `atk` removes the degeneracy and has a second payoff:
## every weight here is denominated in ATK units, so the vectors are readable and
## directly comparable. `_probe_personas` asserts the pin.
##
## ── FOUR OF THE THIRTEEN WEIGHTS ARE INERT, AND THAT IS A TRAP ───────────────
## The sensitivity sweep recorded in CLAUDE.md pushed each weight to its band edge
## over the real pool and found `card`, `command`, `kill` and `back_exposed` never
## changed a single decision in skirmish, while `hp` and `block` moved the win rate
## several points. A persona differentiated only on the inert four is a name with
## no behaviour behind it — it would print in the report, produce a plausible
## number, and be measuring the baseline. Hence the personas below move the weights
## that demonstrably decide plays, and the gate REQUIRES them to diverge on real
## boards rather than trusting that they do.
##
## ── STYLE AND SKILL ARE DIFFERENT AXES ───────────────────────────────────────
## Weights say what a player WANTS; they cannot say how well it executes. A novice
## is not a player with strange preferences, it is a player with ordinary
## preferences that misplays — so skill lives in `traits` (`blunder_rate`, whether
## it reaches for the belt, whether it banks Command). That split is what lets
## "aggro at expert skill" and "aggro at novice skill" both exist without writing
## two vectors.
##
## EVERY TRAIT DECLARED HERE HAS A CONSUMER, and that is a rule rather than a
## description. A config key nothing reads is the dead-content class this codebase
## gates against elsewhere (C1 reachability, both directions): it prints in the
## roster, looks like behaviour, and quietly measures the default. A first draft of
## this file declared `mark_discards` that nothing read; it was removed rather than
## left as a promise. The discard dig is a genuine next axis and is NOT built.
##
## ── THE SHARED-STATE HAZARD, stated plainly ──────────────────────────────────
## `BoardEval`'s weights are STATIC vars, and `BotBrain` writes them between
## skirmish games. Installing a persona therefore mutates process-wide state that
## the practice bot also reads. `choose()` installs and restores around each call
## so a persona can never leak into a later fight; `install()`/`restore()` are
## exposed for a caller that wants to hold one across a whole match, and that
## caller OWNS the restore. Never leave a persona installed at teardown.
##
## THIS FILE NAMES NO AUTOLOAD, deliberately and for the same reason BoardEval
## does not: it is `preload`ed by `--script` probes, where a bare `CardDB` is a
## hard compile error resolved BEFORE the autoloads register while parsecheck
## stays green. It also takes the board as an argument, which is what lets its
## gate run against stubs with no Combat scene at all.

const BoardEval = preload("res://scripts/combat/BoardEval.gd")

## Default traits. A persona's `traits` dict overrides only what it names, so
## adding a trait here cannot silently change an existing persona's behaviour.
const DEFAULT_TRAITS: Dictionary = {
	# Probability of taking a DIFFERENT legal play than the best-scoring one.
	# This is the skill dial. It is not noise added to the score: a scoring jitter
	# mostly reorders plays that were nearly equal anyway, which is what a good
	# player also does. Picking a genuinely non-best play is what a weak player
	# actually does, and it is the behaviour worth modelling.
	"blunder_rate": 0.0,
	# Does it drink? The belt is a real resource every driver here has ignored
	# outright, which is part of why they die in fights a player survives.
	# Consumed by the caller, not by `choose()` — see `should_drink()`.
	"use_potions": true,
	# Fraction of max HP at or below which a drinker reaches for the belt.
	"drink_below_hp": 0.5,
	# Command deliberately held back rather than spent. MAX_BANKED_MANA is 2, so
	# anything above that is simply wasted and the personas below never exceed it.
	"reserve_command": 0,
}

## THE ROSTER. Weights are RELATIVE TO `atk = 1.0` (the gauge, see the header).
## Anything omitted keeps BoardEval's shipped default, so each entry reads as a
## diff from the baseline rather than as a wall of numbers to check by eye.
const PERSONAS: Dictionary = {
	# ── THE CONTROL ARM ──────────────────────────────────────────────────────
	# The shipped weights, unchanged. It exists so every persona run carries its
	# own baseline in the same batch, under the same seeds: a difficulty envelope
	# whose floor was measured last week against a since-retuned pool is not an
	# envelope. Do not "improve" this vector — its whole job is to be the default.
	"curve": {
		"name": "On-curve",
		"desc": "The shipped BoardEval weights. The control arm, and the closest "
			+ "thing to the single policy every earlier measurement used.",
		"weights": {},
		"traits": {},
	},

	# ── STYLE: RACE THE FACE ─────────────────────────────────────────────────
	# Wants the game over before the board matters. Values face damage and open
	# lanes, and is happy to trade down (low `chump`) because a body that dies
	# having pushed damage did its job. Low `hp`/`block`: it is not buying walls.
	# This is the persona that should find a fight winnable that the grinder
	# cannot — bandit_camp, where the enemy out-bodies you forever, is the shape.
	"aggro": {
		"name": "Aggro",
		"desc": "Races the face. Trades down happily, ignores walls, spends "
			+ "everything. Finds the fights that are won before they are held.",
		"weights": {
			"face": 3.2, "open_lane": 1.6, "kill": 1.4,
			"hp": 0.35, "block": 0.4, "chump": 0.6, "shelter": 0.5,
			"trade_partial": 0.3,
			# It discounts its own skin. A racer accepts the incoming damage
			# because the fight is supposed to be over before the sum matters.
			"deny": 0.2,
		},
		"traits": {},
	},

	# ── STYLE: HOLD THE BOARD ────────────────────────────────────────────────
	# The mirror. High `block` and `chump` mean it refuses bad trades and buys
	# walls; low `face` means it will not race. `hp` and `block` are the two
	# weights the sensitivity sweep found actually move the win rate, so this is
	# the persona most likely to diverge hardest from `aggro` — which is the point
	# of having both.
	"control": {
		"name": "Control",
		"desc": "Holds the board and grinds. Refuses bad trades, buys walls, "
			+ "never races. Finds the fights that are survived rather than won.",
		"weights": {
			"hp": 1.5, "block": 2.2, "chump": 2.6, "shelter": 2.0,
			"trade_partial": 1.0, "keyword": 1.4,
			"face": 0.6, "open_lane": 0.4,
			# The mirror of aggro's line: a grinder's whole plan is to still be
			# there later, so a closed lane is the thing it is buying.
			"deny": 1.1,
		},
		"traits": {"reserve_command": 1},
	},

	# ── STYLE: KILL THINGS ───────────────────────────────────────────────────
	# Removal-first. `kill` is one of the four weights measured inert in SKIRMISH
	# creature placement — but it is NOT inert here, because the campaign pool is
	# where the damage spells live and `score_spell` reads it directly. That is
	# exactly why the gate measures divergence instead of assuming it.
	"trader": {
		"name": "Trader",
		"desc": "Removal and two-for-ones. Answers the board a card at a time "
			+ "and leans on spells, so it exercises resolvers the others skip.",
		"weights": {
			"kill": 3.2, "trade_partial": 1.4, "card": 3.0, "keyword": 1.6,
			"chump": 2.0, "face": 1.0,
			# Answers the body rather than the lane, so it neither races past
			# the block nor pays over the odds for one.
			"deny": 0.7,
		},
		"traits": {},
	},

	# ── SKILL, NOT STYLE ─────────────────────────────────────────────────────
	# Ordinary preferences, played badly: the shipped vector with a third of its
	# plays deliberately not the best one, no potions and no discard dig. This is
	# the FLOOR of the difficulty envelope and the persona a first-time player
	# most resembles. A fight only `expert` can win is not tuned; a fight `novice`
	# cannot lose is not either.
	"novice": {
		"name": "Novice",
		"desc": "The default preferences, executed badly: a third of its plays "
			+ "are not the best one, and it never reaches for the belt.",
		"weights": {},
		"traits": {"blunder_rate": 0.34, "use_potions": false},
	},
}


static func ids() -> Array:
	return PERSONAS.keys()


static func exists(pid: String) -> bool:
	return PERSONAS.has(pid)


static func display_name(pid: String) -> String:
	return String(PERSONAS.get(pid, {}).get("name", pid))


## The persona's FULL weight vector — its diff folded onto BoardEval's defaults,
## with `atk` pinned to the gauge. Complete by construction, so a caller can never
## install a partial vector and leave a weight reading whatever the last persona
## set it to.
static func weights_of(pid: String) -> Dictionary:
	var w: Dictionary = BoardEval.default_weights()
	var over: Dictionary = PERSONAS.get(pid, {}).get("weights", {})
	for k in over.keys():
		if w.has(k):
			w[k] = float(over[k])
	w["atk"] = 1.0   # the gauge — see the header; never overridable by a persona
	return w


static func trait_of(pid: String, key: String, fallback = null):
	var t: Dictionary = PERSONAS.get(pid, {}).get("traits", {})
	if t.has(key):
		return t[key]
	if DEFAULT_TRAITS.has(key):
		return DEFAULT_TRAITS[key]
	return fallback


## Should this persona reach for the belt right now?
##
## The belt is the resource every driver in this harness has ignored outright, and
## "the pilot dies in fights a player survives" is the symptom. It lives here as a
## PREDICATE rather than inside `choose()` because drinking is not a card play: it
## costs no Command, competes with nothing, and the caller owns the belt UI.
##
## WHICH bottle to drink is deliberately NOT scored. `BoardEval` models cards, not
## potions, so a scored choice would need a second judgement of the same kind —
## the exact duplication this file's header refuses. A persona therefore decides
## only WHETHER, on hero HP, and the caller drinks the first thing it can safely
## resolve. That is a floor over "never drinks", not a policy, and it is written
## down here so nobody later reads the roster as modelling potion skill.
static func should_drink(ctx, pid: String) -> bool:
	if ctx == null or not bool(trait_of(pid, "use_potions", true)):
		return false
	var cap: float = float(ctx.player_max_hp)
	if cap <= 0.0:
		return false
	return float(ctx.player_hp) / cap <= float(trait_of(pid, "drink_below_hp", 0.5))


## Install a persona's weights and hand back the PREVIOUS vector. The caller owns
## the restore — see the shared-state note in the header. Returns a full vector,
## so `restore()` on it always puts back exactly what was there.
static func install(pid: String) -> Dictionary:
	var prev: Dictionary = BoardEval.export_weights()
	BoardEval.apply_weights(weights_of(pid))
	return prev


static func restore(prev: Dictionary) -> void:
	BoardEval.apply_weights(prev)


## THE DECISION. What would this persona play right now, given this hand?
##
## Returns {} for "pass" — no affordable, non-blocked card scores a play. Otherwise
## {card, kind, lane, row, target, score, known, blundered, considered}.
##
## IT DECIDES AND DOES NOT ACT, deliberately. Executing a play means positioning a
## node, pushing it through `_on_card_played`, and for a targeted spell firing
## `_finish_targeted_spell` un-awaited against a tick budget so a resolver parked
## on a modal cannot hang the run with no diagnostic. That machinery already exists
## in the probes, is hard-won, and differs between them. Duplicating it here to own
## the whole turn would be the same mistake this file's header warns about, one
## level up — so the persona owns the POLICY and the caller keeps the actuation.
##
## `occ_override` forwards to BoardEval for callers that pick several plays before
## any of them reach the board: the live board still reads empty for every slot
## already committed this turn, and without it every creature goes to one lane.
static func choose(ctx, pid: String, hand: Array, rng: RandomNumberGenerator = null,
		blocklist: Array = [], occ_override: Array = []) -> Dictionary:
	if ctx == null or hand.is_empty() or not PERSONAS.has(pid):
		return {}

	var reserve: int = int(trait_of(pid, "reserve_command", 0))
	var spendable: int = int(ctx.player_mana) - reserve
	# A reserve must never make a turn impossible to act in. Holding Command back
	# is a preference; holding it back when it is ALL you have is a dead turn, and
	# a persona that passes every round measures nothing at all.
	if spendable <= 0:
		spendable = int(ctx.player_mana)

	var prev: Dictionary = install(pid)
	var scored: Array = []
	for card in hand:
		if card == null or not is_instance_valid(card):
			continue
		var data: Dictionary = card.card_data
		if String(data.get("id", "")) in blocklist:
			continue
		if int(data.get("cost", 0)) > spendable:
			continue
		var play: Dictionary = BoardEval.score_play(ctx, false, data, occ_override)
		if play.is_empty():
			continue
		play["card"] = card
		scored.append(play)
	restore(prev)

	if scored.is_empty():
		return {}

	scored.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))

	var pick: Dictionary = scored[0]
	var blundered := false
	var rate: float = float(trait_of(pid, "blunder_rate", 0.0))
	if rate > 0.0 and scored.size() > 1 and rng != null and rng.randf() < rate:
		# Uniform over the plays that were NOT the best one. Deliberately excludes
		# index 0: a "blunder" that can land on the best play is just a weaker
		# blunder rate, which makes the dial mean something other than it says.
		pick = scored[1 + (rng.randi() % (scored.size() - 1))]
		blundered = true

	var out: Dictionary = pick.duplicate()
	out["blundered"] = blundered
	out["considered"] = scored.size()
	return out
