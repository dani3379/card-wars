extends Node
## WritDB.gd — autoload. THE WAR CHEST's four commissions.
##
## Replaces the old 11-entry blessing pool, which dealt 3 random "honest" tiles
## plus 1 "RISKY" tile. That set was audited (docs/RUN_OPENING_REDESIGN_20260728.md)
## and found to be four different CURRENCIES with no shared axis — a real dealt
## slate was "2 random potions / a Boss relic + 2 Curses / +7 max HP / 75 gold",
## and not one of them changed how the player plays. Worse, the labels lied:
## `black_ledger` was flagged RISKY and was the always-take, because 15 of the 21
## boss relics are retired and the 6 survivors are all strictly positive.
##
## THE FIX IS STRUCTURAL, and it is the Slay the Spire 1 answer rather than a
## rebalance: the chest deals ONE tile from each of four fixed ROLE slots. The
## player is never asked "which currency is worth most?" — a question about
## internal exchange rates. They are asked "which axis of my run do I want
## moved?", and take whatever that slot rolled.
##
##   I  · THE ROLL    — the deck. Surgery on the ten cards you already own.
##   II · THE ARSENAL — the gear. Choose 1 of 3 Foundation relics.
##   III· THE PURSE   — the road. Economy as a standing RULE, never a lump sum.
##   IV · THE PACT    — the price. Always the same currency, always the twin of
##                      the ROLL or PURSE tile standing beside it on screen.
##
## Two bans are permanent, both audited:
##  * NO CURSES. A drawn curse is unplayable AND exempt from discard-marking, so
##    under HAND_REFILL_TARGET = 5 with a persistent hand it occupies a hand slot
##    for the REST OF THE FIGHT — about -20% throughput each, compounding, for
##    every fight of the run. That is not a price a player can read at minute one.
##  * NO BOSS RELICS. A 6-entry all-positive pool is a handout wearing a warning
##    label, and it carries the widest hero-dependent variance in the game
##    (Conjurer's Coffer: 9 rare bodies for Raider, 1 for the Kindler).
##
## There is also NO SKIP. It was audited as never correct, so it taxed only the
## players who did not know that.
##
## Every player-facing string lives in this dictionary rather than inline in
## MainMenu, because tools/_probe_copy_lint.tscn only reads DB dictionaries —
## copy authored in a scene script is size-gated but NOT wording-gated.

# effect ids resolved by MainMenu._apply_writ / _resolve_writ_picker:
#   forge      value = how many cards to forge (opens the card grid, value times)
#   remove     value = how many cards to remove
#   enlist     value = how many uncommons to offer, pick 1
#   remount    value = how many cards to re-roll one rarity higher
#   arsenal    value = how many Foundation relics to offer, pick 1
#   purse      relic = the id of the standing-rule relic granted
const WRITS: Dictionary = {
	# ── I · THE ROLL — the deck ───────────────────────────────────────────
	"whetstone_cart": {
		"id": "whetstone_cart", "slot": "roll",
		"name": "The Whetstone Cart",
		"desc": "Forge 1 card of your choice.",
		"effect": "forge", "value": 1,
	},
	"provosts_broom": {
		"id": "provosts_broom", "slot": "roll",
		"name": "The Discharge Papers",
		"desc": "Strike 1 card of your choice off your deck.",
		"effect": "remove", "value": 1,
	},
	"muster_tent": {
		"id": "muster_tent", "slot": "roll",
		"name": "The Recruiting Tent",
		"desc": "Enlist 1 of 5 uncommon cards.",
		"effect": "enlist", "value": 5,
	},
	"remount_line": {
		"id": "remount_line", "slot": "roll",
		"name": "The Horse Fair",
		"desc": "Choose 1 card. It becomes a random card one rarity higher.",
		"effect": "remount", "value": 1,
	},

	# ── II · THE ARSENAL — the gear ───────────────────────────────────────
	# One entry only: the slot IS "choose your relic". Offering a CHOICE is also
	# what retires the dead-roll problem the old blind grant had — the Burnt
	# Dispatches needs an exhausted spell and is inert for 4 of the 5 lords, but
	# nobody is forced to take it when two alternatives sit beside it.
	"the_arsenal": {
		"id": "the_arsenal", "slot": "arsenal",
		"name": "The Quartermaster's Arsenal",
		"desc": "Choose 1 of 3 relics.",
		"effect": "arsenal", "value": 3,
	},

	# ── III · THE PURSE — the road ────────────────────────────────────────
	# Every entry is a STANDING RULE carried on the relic rail all run, never a
	# lump sum. The old 75-gold tile was the purest form of the "doesn't change
	# how you play" failure: it could not be spent until map row 4, and a route
	# only reaches about 1 to 1.5 shops an act.
	"sutlers_bond": {
		"id": "sutlers_bond", "slot": "purse",
		"name": "The Trader's Bond",
		"desc": "Shop goods cost a quarter less, all run.",
		"effect": "purse", "relic": "merchants_license",
	},
	"paymasters_ledger": {
		"id": "paymasters_ledger", "slot": "purse",
		"name": "The Paymaster's Ledger",
		"desc": "The shop pays double for every card you sell.",
		"effect": "purse", "relic": "scavengers_pouch",
	},
	"recruiting_warrant": {
		"id": "recruiting_warrant", "slot": "purse",
		"name": "The Second Look",
		"desc": "Take 2 cards at every Recruit Camp instead of 1.",
		"effect": "purse", "relic": "collectors_tome",
	},
	"armourers_writ": {
		"id": "armourers_writ", "slot": "purse",
		"name": "The Armourer's Order",
		"desc": "Once an act, forge 2 cards at camp instead of 1.",
		"effect": "purse", "relic": "whetstone",
	},
}

## THE PACT. Dealt last, and always the escalated twin of whichever ROLL or
## PURSE writ is already standing on screen — joined to it so the price reads as
## an exchange rate rather than a mystery. This is Slay the Spire 2's mirrored
## pair, inverted: instead of stripping the collision out of the offer, we
## REQUIRE it, because the whole legibility win is the loud option sitting
## beside its quiet twin on the same axis.
##
## EVERY pact costs the same thing: 6 max HP. One currency, one number, forever.
## The player never has to price a curse against gold against a relic again.
const PACT_COST_MAX_HP: int = 6

## twin id -> {name, desc, effect, value/relic}. Keyed by the free writ it
## escalates; MainMenu only ever offers a pact whose twin is on the screen.
const PACTS: Dictionary = {
	"whetstone_cart": {
		"name": "Pact of the Whetstone",
		"desc": "Forge 2 cards of your choice. Lose 6 max HP.",
		"effect": "forge", "value": 2,
	},
	"provosts_broom": {
		"name": "Pact of the Papers",
		"desc": "Strike 2 cards off your deck. Lose 6 max HP.",
		"effect": "remove", "value": 2,
	},
	"muster_tent": {
		"name": "Pact of the Tent",
		"desc": "Enlist 2 of 5 uncommon cards. Lose 6 max HP.",
		"effect": "enlist2", "value": 5,
	},
	"remount_line": {
		"name": "Pact of the Fair",
		"desc": "Choose 2 cards. Each becomes a random card one rarity higher. Lose 6 max HP.",
		"effect": "remount", "value": 2,
	},
	"sutlers_bond": {
		"name": "Pact of the Bond",
		"desc": "Shop goods cost a quarter less, and the shop pays double for cards you sell. Lose 6 max HP.",
		"effect": "purse2", "relic": "merchants_license", "relic2": "scavengers_pouch",
	},
	"paymasters_ledger": {
		"name": "Pact of the Ledger",
		"desc": "The shop pays double for cards you sell, and every Recruit Camp offers 2 cards. Lose 6 max HP.",
		"effect": "purse2", "relic": "scavengers_pouch", "relic2": "collectors_tome",
	},
	"recruiting_warrant": {
		"name": "Pact of the Second Look",
		"desc": "Every Recruit Camp offers 2 cards, and camps forge 2. Lose 6 max HP.",
		"effect": "purse2", "relic": "collectors_tome", "relic2": "whetstone",
	},
	"armourers_writ": {
		"name": "Pact of the Armourer",
		"desc": "Camps forge 2 cards, and shop goods cost a quarter less. Lose 6 max HP.",
		"effect": "purse2", "relic": "whetstone", "relic2": "merchants_license",
	},
}


static func ids_in_slot(slot: String) -> Array[String]:
	var out: Array[String] = []
	for id in WRITS:
		if String(WRITS[id].get("slot", "")) == slot:
			out.append(String(id))
	out.sort()   # stable input order — the caller's seeded rng does the shuffling
	return out


static func get_writ(id: String) -> Dictionary:
	return WRITS.get(id, {})


static func get_pact_for(twin_id: String) -> Dictionary:
	return PACTS.get(twin_id, {})


## Deal the slate: one writ from each of ROLL / ARSENAL / PURSE, then the PACT
## as the twin of the ROLL or PURSE tile already dealt. Fully seeded — the old
## roll used global shuffle()/randi(), which meant two players on the same Daily
## March seed got the same map and DIFFERENT opening gifts.
##
## Returns an ordered Array of entry dicts, each carrying at least
## {id, slot, name, desc, effect} plus "is_pact" and "twin" on the pact.
static func roll_slate(rng: RandomNumberGenerator) -> Array:
	var slate: Array = []
	for slot in ["roll", "arsenal", "purse"]:
		var pool := ids_in_slot(slot)
		if pool.is_empty():
			continue
		var pick: String = pool[rng.randi() % pool.size()]
		var entry: Dictionary = WRITS[pick].duplicate(true)
		entry["is_pact"] = false
		slate.append(entry)

	# The pact escalates a tile the player can SEE — never an absent one.
	var twins: Array = []
	for e in slate:
		if PACTS.has(String(e.get("id", ""))):
			twins.append(String(e.get("id", "")))
	if not twins.is_empty():
		var twin: String = twins[rng.randi() % twins.size()]
		var pact: Dictionary = PACTS[twin].duplicate(true)
		pact["id"] = "pact_" + twin
		pact["slot"] = "pact"
		pact["is_pact"] = true
		pact["twin"] = twin
		slate.append(pact)
	return slate


## Player-facing slot furniture. The roman numeral and the role word are what
## make the four tiles comparable AS AXES — without them the screen is four
## unrelated nouns again.
const SLOT_LABELS: Dictionary = {
	"roll": "I · THE ROLL",
	"arsenal": "II · THE ARSENAL",
	"purse": "III · THE PURSE",
	"pact": "IV · THE PACT",
}

const SLOT_HINTS: Dictionary = {
	"roll": "your deck",
	"arsenal": "your gear",
	"purse": "the road",
	"pact": "the price",
}

## The opening screen's own chrome. It lives HERE, not inline in MainMenu, for
## the reason the doc's trap list gives: _probe_copy_lint reads DB dictionaries
## only, so copy authored in a scene script is size-gated but escapes the WORDING
## rules — which is exactly how the first draft of this screen shipped saying
## "sign one Writ" over a lint that bans the word.
##
## Two collisions were fixed when it moved: the screen and the band both wore
## words the lint bans, and the CENTRE band was called "THE ROLL" while slot I is
## also "THE ROLL" — one screen, one name, two meanings. The centre is the
## marching column; the band over the four tiles is the terms you march under.
## Every key is either in the lint's COPY_KEYS or ends in `_text`, which is how
## _is_copy_key decides what to read. A key it does not recognise is silently
## skipped — an unscanned string here looks exactly like a scanned one.
const MUSTER_COPY: Dictionary = {
	"title": "ORDER OF MARCH",
	"subtitle": "Choose the host, declare a banner, accept one term."
		+ " Nothing is final until you take the field.",
	"host_head_text": "THE HOST",
	"column_head_text": "THE COLUMN",
	"banner_head_text": "THE BANNER",
	"terms_head_text": "THE TERMS",
	"terms_rule_text": "I changes your deck  ·  II your gear  ·  III the road"
		+ "  ·  IV doubles a shown offer for 6 max HP.",
	"seed_tooltip_text": "Same seed, same opening and same road.",
	"banner_card_fallback_text": "a banner card",
}


static func muster_copy(key: String) -> String:
	return String(MUSTER_COPY.get(key, ""))
