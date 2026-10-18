class_name TutorialDB
extends RefCounted
## THE LESSON REGISTRY — every rule the game teaches, in one dictionary.
##
## WHY A REGISTRY AND NOT SIX MORE `_maybe_show_*` FUNCTIONS. The teaching used
## to be six hand-rolled functions in Combat.gd, each carrying its own copy, its
## own `UserSettings` flag and its own gate. That shape has three faults and the
## player pays for all of them:
##   · THE COPY IS UNREACHABLE. A lesson that lives inside an `if` in a 25,000
##     line file cannot be listed, cannot be searched, and cannot be shown to a
##     player who wants it back. "How do I see that again?" had no answer but
##     "start a new profile".
##   · A FLAG IS SPENT THE MOMENT IT FIRES, once ever, per profile. There was no
##     way to un-spend one without resetting all of them.
##   · NOTHING COULD COUNT THEM. Six lessons covered the first fight and nothing
##     else — no spell, no potion, no relic, no map, no shop, no camp — and the
##     omission was invisible because there was no list to compare against.
##
## So: one entry per lesson, and everything else is derived. `tools/_probe_tutorial.gd`
## diffs these ids against the call sites in BOTH directions (the C1 reachability
## shape), the Field Manual renders the list, and the copy sits where a person can
## read it end to end and hear whether it sounds like one voice.
##
## THIS FILE REFERENCES NO AUTOLOAD, deliberately. It is a plain `RefCounted` that
## tools `preload`, and a preloaded helper has its dependencies compiled BEFORE the
## autoloads register — a bare `UserSettings` identifier in here would be a hard
## compile error in every `--script` probe while `_probe_parsecheck` (which runs as
## a SCENE) stayed green. See CLAUDE.md, "parsecheck's ONE blind spot". Seen-state
## lives in UserSettings and is reached through it, never from here.

## Where a lesson is taught — the Field Manual's grouping, and the probe's map of
## which screen must emit it.
const GROUP_FIGHT := "fight"
const GROUP_ROAD := "road"
const GROUP_STOP := "stop"

const GROUP_TITLES := {
	GROUP_FIGHT: "IN A FIGHT",
	GROUP_ROAD: "ON THE ROAD",
	GROUP_STOP: "BETWEEN FIGHTS",
}
const GROUP_ORDER: Array[String] = [GROUP_FIGHT, GROUP_ROAD, GROUP_STOP]

## HOW MUCH COACHING THE PLAYER WANTS. Three settings rather than a checkbox,
## because "I have played this genre but not this game" is the commonest state a
## returning player is in and a boolean cannot express it.
##   FULL  — the guided first fight, then the tips as they become relevant.
##   TIPS  — no walkthrough; you are left alone but still told the rules that are
##           particular to this game (the muster, banking, overkill).
##   OFF   — nothing fires. The Field Manual still has every word of it.
const COACH_FULL := 0
const COACH_TIPS := 1
const COACH_OFF := 2

const COACH_MODE_LABELS := {
	COACH_FULL: "Full",
	COACH_TIPS: "Tips Only",
	COACH_OFF: "Off",
}

## `kind` — what the entry IS, which decides how it is delivered and how the
## manual prints it.
##   STEP — a beat of the guided first fight. Blocking-ish: a spotlight, a panel,
##          and the player has to act. Only ever fires in COACH_FULL.
##   TIP  — one line in the combat info channel, with an optional arrow. Never
##          interrupts; if the channel is busy it waits for a later round.
##   CARD — a small panel on a screen that has no info channel of its own (the
##          map, the shop, the camp). Dismissed with GOT IT.
const KIND_STEP := "step"
const KIND_TIP := "tip"
const KIND_CARD := "card"

## `{n}` in a body is substituted by the caller — see `body()`. It exists for
## exactly one lesson (the discard cap is read live from `_max_discard_marks()`,
## because a relic may raise it and the sentence must not go stale).
##
## COPY RULES THESE OBEY (docs/COPY_STYLE.md): a title is a caps micro-label of
## two or more words (§12's lint fails a LONE capped word); a body is standard
## product language, verb first, naming the control — NOT the road register, which
## governs event prose and card flavour only (§12). Bodies stay under ~28 words:
## this is the one paragraph in the game written for someone who has never played
## it, and it is read while a fight is waiting.
const LESSONS := {
	# ── The guided first fight ─────────────────────────────────────────
	# All three carry the SAME legacy flag, and that is the right semantics rather
	# than a shortcut: a walkthrough is one thing. You cannot have seen step 3 and
	# not step 1, and "replay this step" would mean replaying the walkthrough
	# anyway — so the manual offers the three as one entry with one tick.
	"walk_play": {
		"title": "PLAY A CREATURE",
		"body": "Drag the lit card onto any lit slot on your side. It costs Command — the seal on the left is what you have this turn.",
		"group": GROUP_FIGHT, "kind": KIND_STEP, "order": 10,
		"legacy": "first_battle_tutorial_complete",
	},
	"walk_commit": {
		"title": "END THE TURN",
		"body": "Your creature is forming up — nothing swings on the round it arrives. End the turn and the enemy takes the field across from you.",
		"group": GROUP_FIGHT, "kind": KIND_STEP, "order": 20,
		"legacy": "first_battle_tutorial_complete",
	},
	# "the back row waits behind it" was the old wording and it taught the wrong
	# rule. BOTH ROWS STRIKE EVERY ROUND — the back row is play space, not a
	# reserve and not a lesser tier (CLAUDE.md: "back row is queue space, not a
	# separate combat tier"). A player who reads "waits" builds a front line and
	# treats four of their eight slots as a bench.
	"walk_lane": {
		"title": "READ THE LANE",
		"body": "Creatures fight the lane they stand in. Both rows strike every round — the front row simply strikes first, and is struck first.",
		"group": GROUP_FIGHT, "kind": KIND_STEP, "order": 30,
		"legacy": "first_battle_tutorial_complete",
	},

	# ── Combat tips, in the order a fight reaches them ─────────────────
	# `legacy` names the pre-registry UserSettings property. It is not decoration:
	# those flags are already `true` on every existing profile, so a lesson that
	# forgot its mapping would re-teach a rule the player was taught weeks ago.
	# "Nothing swings on the round it arrives" had no subject — the sentence
	# names no actor, so a first-time player has to guess what "it" is while a
	# fight waits. Both halves of the surprise are stated instead: the delay is a
	# property of the CREATURE you just played, and the reason round 1 looks empty
	# is that the enemy's line lands at the end of it.
	"muster": {
		# "THE MUSTER" was jargon and the lint says so: `muster` is in
		# `_probe_copy_lint.OPAQUE_TERMS`, i.e. a word the player is never told
		# the meaning of. It also disagreed with the game's OWN name for the
		# state — `KeywordEffects` displays it as **Forming Up**, which is what
		# the keyword glossary, the card status rail and the primer all print.
		# One concept, one term (COPY_STYLE §12).
		"title": "FORMING UP",
		"body": "A creature cannot attack on the round you play it — it forms up first. End the turn: the enemy takes the field, and the fighting starts next round.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 40,
		"legacy": "muster_tutorial_seen",
	},
	"combat_model": {
		"title": "BOTH SIDES ATTACK",
		"body": "Both lines swing every round. Swift attacks first, then the front row, then the back row.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 50,
		"legacy": "combat_model_tutorial_seen",
	},
	# ONE SUBJECT. This used to open "Front-row creatures protect the back row"
	# and then change the subject to forecast chips — two rules in one line, and
	# the first of them is the bench model that `walk_lane` and `back_row` exist
	# to correct. Rows are now stated three times elsewhere; this fires on the
	# first round with an enemy line, so its subject is reading that line.
	"intents": {
		"title": "READ THE BOARD",
		"body": "Forecast chips preview what each enemy will do. Read them before you commit your line.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 60,
		"legacy": "intents_tutorial_seen",
	},
	"keywords": {
		"title": "GOLD WORDS",
		"body": "The gold words on a card are keywords. Hover one to read exactly what it does.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 70,
	},
	# NOT "spells are spent once cast" — a spell's footer prints EXHAUST or
	# RETAIN and both exist, so that sentence would be false on half the pool.
	# What IS universal is the two-beat verb, which is the thing that reads as a
	# bug when nobody explains it: the card leaves your hand and the game appears
	# to wait for nothing.
	"spells": {
		"title": "CAST A SPELL",
		"body": "Drag a spell out to play it, then click what it should hit. Untargeted spells resolve at once.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 80,
	},
	# Taught at the DECISION, not in the walkthrough: the moment the front row is
	# full is the first moment the back row is a choice rather than a fact, and by
	# then the guided fight is several fights behind. The house design rule is
	# that the back row is play space with no front/back tradeoff levers — so the
	# failure this prevents is a player benching four of their eight slots.
	"back_row": {
		"title": "THE BACK ROW",
		# ROWS, NEVER RANKS (COPY_STYLE §12's settled vocabulary). This line said
		# "the front rank", which is the one word the plain-language pass retired
		# for combat rows — and in a lesson whose whole job is to correct a wrong
		# model of the rows, a second name for them is the last thing it needs.
		"body": "The back row is not a reserve. Both rows strike every round — the front row simply takes the blows first.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 35,
	},
	# The single most important rule a new player has to learn, and until
	# 2026-09-16 nothing taught it. Command used to be a flat 3 every round —
	# there was no rule, so there was no lesson — and the economy redesign made
	# it grow without anything on screen saying so. A resource that changes
	# under you and is never explained reads as a bug, and the cost curve is
	# built entirely on top of it: a 5-cost card is a round-5 card, which is
	# information the player cannot deduce from a board.
	#
	# Taught at the top of ROUND 2 rather than round 1 — that is the first
	# moment the seal has actually moved, and a rule you can watch happen is
	# worth more than one asserted at you a turn early. {cap} is read live so a
	# retune of COMMAND_RAMP_CAP cannot leave this sentence lying; the lesson is
	# stamped seen the instant it fires, so there is no second chance at it.
	"command_ramp": {
		"title": "COMMAND GROWS",
		"body": "You start on 1 Command and gain one more every round, up to {cap}. Cheap cards win the early rounds; the heavy ones are worth waiting for.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 25,
	},
	# CARRYOVER IS A RELIC, so this lesson states the DEFAULT first and the
	# exception second. It only fires on a turn that actually banked (i.e. a run
	# holding the relic), but the Field Manual prints every lesson to everyone —
	# and a manual that teaches "carry up to 2" as a standing rule would have the
	# player holding Command back in the ~95% of runs where that simply loses it.
	"banking": {
		"title": "COMMAND CARRIES",
		"body": "Unspent Command is normally lost when your turn ends. Your relic keeps up to {bank} of it for the next turn.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 90,
		"legacy": "banking_tutorial_seen",
	},
	"dismiss": {
		"title": "CLEAR YOUR HAND",
		"body": "Right-click up to {n} hand cards to discard them when your turn ends.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 100,
		"legacy": "dismiss_tutorial_seen",
	},
	# "Either pile" counted two, and there are three: the EXHAUST stack is built
	# hidden and appears the first time a card leaves play for good (Combat's
	# _build_pile_panel_diegetic, kind 2). A lesson that names a fixed number of
	# piles goes stale the first time someone plays an Exhaust card.
	"piles": {
		"title": "COUNT THE PILES",
		"body": "Click any pile to see every card in it.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 110,
		"legacy": "pile_tutorial_seen",
	},
	"relics": {
		"title": "YOUR RELICS",
		"body": "Relics work for the whole run and never need playing. Hover one to read what it does.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 120,
	},
	"potions": {
		"title": "THE BELT",
		"body": "Click a potion to drink it. Potions cost no Command and are gone once used.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 130,
	},
	# Overkill stops at the body behind; PIERCING is the keyword that reads on to
	# the face. Stating both in one line is the only way the distinction lands —
	# and getting it backwards would teach that chump-blocking does nothing.
	"overkill": {
		"title": "OVERKILL CARRIES",
		"body": "A killing blow spills what it did not need into the body standing behind. Piercing carries on to the face.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 140,
	},
	# "A lane with nobody in it strikes you" was ambiguous about WHOSE lane, and
	# the answer is the one that matters: an enemy opposite a gap in YOUR line.
	"hero_hp": {
		"title": "YOUR OWN LIFE",
		"body": "An enemy facing a gap in your line strikes you directly. Your health carries between fights — at zero the run ends.",
		"group": GROUP_FIGHT, "kind": KIND_TIP, "order": 150,
	},

	# ── The road ───────────────────────────────────────────────────────
	"map_road": {
		"title": "CHOOSE THE ROAD",
		"body": "Pick the next site along the road. Every route reaches the keep — what you meet on the way is your choice.",
		"group": GROUP_ROAD, "kind": KIND_CARD, "order": 200,
	},
	"map_gate": {
		"title": "THE KEEP IS SHUT",
		"body": "The lord's keep opens once you have broken enough Holds. The banner at the top counts what is left.",
		"group": GROUP_ROAD, "kind": KIND_CARD, "order": 210,
	},

	# ── The stops between fights ───────────────────────────────────────
	# The Recruit camp, NOT the post-fight spoils screen: the spoils screen hands
	# out relics and gold and says so on its own headers, while this is the only
	# place a card enters the deck — which is the mechanic a deckbuilder lives on
	# and the one nothing in the game had ever stated out loud.
	"recruit_card": {
		"title": "TAKE A CARD",
		"body": "The card you choose joins your deck for the rest of the run. Taking none is allowed, and keeps the deck sharp.",
		"group": GROUP_STOP, "kind": KIND_CARD, "order": 300,
	},
	"shop_trade": {
		"title": "BUY AND SELL",
		"body": "Gold buys cards, relics and potions. The trader also buys one card back per visit — that is how you thin the deck.",
		"group": GROUP_STOP, "kind": KIND_CARD, "order": 310,
	},
	# THREE FORKS, NOT TWO. Rest.gd builds RAISE THE DEAD beside REST and FORGE
	# (_add_choice_wake_if_available) whenever the roll of the fallen has names —
	# which, at row 16 after six fights, is nearly always. A closed list of two
	# taught the player to stop reading at the second banner.
	"camp_choice": {
		"title": "REST OR FORGE",
		"body": "One action per camp: heal, Forge a card into its permanent + version, or raise a fallen soldier for the next fight. Camp sits just before the keep.",
		"group": GROUP_STOP, "kind": KIND_CARD, "order": 320,
	},
	# "The choice is taken at once" is false on every gamble event: ten minigames
	# are live in Event.gd's MODAL_EFFECTS, and each opens a table the player then
	# has to play. What IS universal — and is the fact a player needs before
	# clicking — is that there is no way back.
	"event_choice": {
		"title": "ONE DECISION",
		"body": "Read the page, then choose. A choice cannot be taken back, and some open a game of chance or skill before the road moves on.",
		"group": GROUP_STOP, "kind": KIND_CARD, "order": 330,
	},
}


## Every lesson id, in reading order. The Field Manual's list and the probe's
## universe both come from here, so neither can drift from the other.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id in LESSONS:
		out.append(String(id))
	out.sort_custom(func(a: String, b: String) -> bool:
		return int(LESSONS[a].get("order", 0)) < int(LESSONS[b].get("order", 0)))
	return out


static func ids_in_group(group: String) -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		if String(LESSONS[id].get("group", "")) == group:
			out.append(id)
	return out


static func has(id: String) -> bool:
	return LESSONS.has(id)


static func title(id: String) -> String:
	return String(LESSONS.get(id, {}).get("title", ""))


## The body with its tokens filled. `args` keys are matched as `{key}`.
static func body(id: String, args: Dictionary = {}) -> String:
	var text := String(LESSONS.get(id, {}).get("body", ""))
	for k in args:
		text = text.replace("{%s}" % k, str(args[k]))
	return text


## The pre-registry UserSettings property backing this lesson, or "".
static func legacy_flag(id: String) -> String:
	return String(LESSONS.get(id, {}).get("legacy", ""))


static func kind(id: String) -> String:
	return String(LESSONS.get(id, {}).get("kind", KIND_TIP))


## The one-line form a combat tip is posted as: "TITLE — body". The em dash and
## the caps head are the house tip shape, kept identical to the six hand-written
## lines this replaced so the channel reads the same as it always has.
static func tip_line(id: String, args: Dictionary = {}) -> String:
	return "%s — %s" % [title(id), body(id, args)]
