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
## ── THE THREE AXES MUST ACTUALLY BE THREE (2026-08-01 audit) ───────────────
## The four-slot model is only legible while the three FREE tiles stand on three
## different axes, because the pact doubles one of them by construction. That
## invariant was being broken from inside THE PURSE, which had quietly become a
## second ROLL: `recruiting_warrant` granted collectors_tome ("Take 2 cards at
## each Recruit Camp") and `armourers_writ` granted whetstone ("Reforge ... to
## upgrade 2 cards"). Both are deck power wearing a slot label that says "the
## road", and on seed 1 the dealt row read Forge 1 card / Forge 2 cards / Choose
## 1 of 3 relics / forge 2 cards at camp — THREE of four tiles saying forge. On
## that slate the free PURSE tile also strictly DOMINATED the pact beside it:
## every route passes REST_ROW (CampaignMapGenerator forces every row-16 node to
## `rest` and connects all of them to the boss), so whetstone is +1 forge an act
## × 3 acts, free, against the pact's +1 forge for a fifth of the run's max HP.
##
## THE PURSE is now four road verbs and no deck verb: BUY · SELL · EARN · MEND.
## The two deck-power relics went back to the Reliquary's campaign pool, which
## is where Treasure.gd already says they belong ("the run-shaping relics — forge
## strength, recruit slate, veterancy speed"), and which the war chest was
## spending four of nine entries out of.
##
## Gate: tools/_probe_terms.tscn. It reads the four dealt descs the way a player
## does and fails if any house verb lands on more than two tiles, and it audits
## every granted relic against RELICDB'S OWN desc rather than a list authored
## here — so the slot label cannot be made true again by rewording a tile.
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
#
# `verb` is the AXIS the term moves, and it is data rather than a comment because
# the pact contract is stated in it: a pact may only escalate its twin's own
# verb, never bolt a second, unrelated permanent on beside it for the same price.
# Not a copy field — _probe_copy_lint reads COPY_KEYS and `*text*` segments only,
# so it is skipped by the wording scan the way `effect` and `value` are.
const WRITS: Dictionary = {
	# ── I · THE ROLL — the deck ───────────────────────────────────────────
	"whetstone_cart": {
		"id": "whetstone_cart", "slot": "roll", "verb": "forge",
		"name": "The Whetstone Cart",
		"desc": "Forge 1 card of your choice.",
		"effect": "forge", "value": 1,
	},
	"provosts_broom": {
		"id": "provosts_broom", "slot": "roll", "verb": "strike",
		"name": "The Discharge Papers",
		"desc": "Remove 1 card from your deck.",
		"effect": "remove", "value": 1,
	},
	"muster_tent": {
		"id": "muster_tent", "slot": "roll", "verb": "enlist",
		"name": "The Recruiting Tent",
		"desc": "Add 1 of 5 uncommon cards to your deck.",
		"effect": "enlist", "value": 5,
	},
	"remount_line": {
		"id": "remount_line", "slot": "roll", "verb": "raise",
		"name": "The Horse Fair",
		"desc": "1 card becomes a random card one rarity higher.",
		"effect": "remount", "value": 1,
	},

	# ── II · THE ARSENAL — the gear ───────────────────────────────────────
	# One entry only: the slot IS "choose your relic". Offering a CHOICE is also
	# what retires the dead-roll problem the old blind grant had — the Burnt
	# Dispatches needs an exhausted spell and is inert for 4 of the 5 lords, but
	# nobody is forced to take it when two alternatives sit beside it.
	"the_arsenal": {
		"id": "the_arsenal", "slot": "arsenal", "verb": "arm",
		"name": "The Quartermaster's Arsenal",
		"desc": "Choose 1 of 3 relics.",
		"effect": "arsenal", "value": 3,
	},

	# ── III · THE PURSE — the road ────────────────────────────────────────
	# Every entry is a STANDING RULE carried on the relic rail all run, never a
	# lump sum. The old 75-gold tile was the purest form of the "doesn't change
	# how you play" failure: it could not be spent until map row 4, and a route
	# only reaches about 1 to 1.5 shops an act.
	#
	# And every entry is about MONEY OR THE BODY — never about cards. Four road
	# verbs, deliberately one each, so the slot cannot repeat itself and cannot
	# repeat THE ROLL: BUY · SELL · EARN · MEND. Two of the four used to grant
	# deck-power relics; see the audit block at the top of this file.
	#
	# On tiers: the test a purse relic has to pass is WHEN ITS RULE FIRES (on the
	# road, between fights, at a stop), not which bucket RelicDB files it under.
	# coin_purse is tier "starting" — a legacy skirmish opener, hero-restricted to
	# nobody and in no campaign roll pool, so granting it by id is safe and takes
	# nothing off a later shelf. vultures_feast is tier "combat" but settles in
	# the victory block after the fight, which is the road.
	"sutlers_bond": {
		"id": "sutlers_bond", "slot": "purse", "verb": "coin",
		"name": "The Trader's Bond",
		"desc": "Shop goods cost a quarter less, all run.",
		"effect": "purse", "relic": "merchants_license",
	},
	"paymasters_ledger": {
		"id": "paymasters_ledger", "slot": "purse", "verb": "coin",
		"name": "The Paymaster's Ledger",
		"desc": "The shop pays double for cards you sell.",
		"effect": "purse", "relic": "scavengers_pouch",
	},
	# Replaces `recruiting_warrant` (The Second Look → collectors_tome). Ids are
	# not persisted anywhere — nothing outside this file names one — so the id
	# moved with the meaning rather than being left to lie.
	"campaign_chest": {
		"id": "campaign_chest", "slot": "purse", "verb": "coin",
		"name": "The Campaign Chest",
		"desc": "Each win pays 10 more gold.",
		"effect": "purse", "relic": "coin_purse",
	},
	# Replaces `armourers_writ` (The Armourer's Order → whetstone). The one road
	# rule that is not money: HP is the road's other currency, and it is the one
	# the PACT bills in, so a term that pays it back belongs on the same screen.
	"field_surgery": {
		"id": "field_surgery", "slot": "purse", "verb": "mend",
		"name": "The Camp Surgeon",
		"desc": "After each win, heal 1 HP per friendly that fell. Up to 5.",
		"effect": "purse", "relic": "vultures_feast",
	},
}

## THE PACT. Always the escalated twin of whichever ROLL or PURSE writ is already
## standing on screen, and dealt INTO THE SLOT BESIDE IT — not appended — so the
## price reads as an exchange rate rather than a mystery. This is Slay the Spire 2's mirrored
## pair, inverted: instead of stripping the collision out of the offer, we
## REQUIRE it, because the whole legibility win is the loud option sitting
## beside its quiet twin on the same axis.
##
## EVERY pact costs the same thing: 6 max HP. One currency, one number, forever.
## The player never has to price a curse against gold against a relic again.
const PACT_COST_MAX_HP: int = 6

## ── WHAT ONE PRICE HAS TO BUY (2026-08-01) ────────────────────────────────
## One price with one number is only honest while it buys ONE AMOUNT. It did
## not: the deck half of this table bought one extra one-shot action, and the
## road half bought a whole second permanent relic. Pact of the Ledger added
## collectors_tome — worth several free cards a run — for the same 6 max HP that
## Pact of the Whetstone charged for a single extra forge. So the pact was a
## dominated option on about half the deals and a near-auto-take on the other
## half, which is exactly the "a RISKY tile that was the always-take" failure the
## four-slot model was built to retire.
##
## THE UNIT IS ONE FORGE, and it is the GAME's unit, not one invented here. The
## Supply Cache (Treasure.gd `_run_arsenal`) offers one forge OR two potions OR
## 70/90/110 gold as three ways of spending the same find; the Shop posts a
## common relic at 90 gold and a potion at 40. So the road itself already says
##
##     one forge  =  two potions  =  ~90 gold  =  one common relic
##
## and that is the exchange rate the band below is measured in. Its consequence
## is the useful one: "one more forge" and "one more relic" are the SAME
## purchase, so the two halves of this table were never structurally mismatched
## — only their contents were.
##
## THE BAND: every pact must buy between 1.00 and 2.00 forges over its own free
## twin. The floor is one whole unit, because a pact that buys less than the
## smallest thing the road sells cannot be worth a fifth of the run's max HP.
## The ceiling is twice that, because at 2× the cheapest pact the loud tile
## becomes the always-take again — and 2× is also the widest ratio the four
## slots can carry while a player is still choosing an axis rather than a
## number. Both halves are ALSO required to agree on their mean (±20%), because
## a band alone would let every deck pact sit at 1.0 and every road pact at 2.0.
##
## The worth of each unit is derived in `unit_worth` / `road_rule_worth` below;
## the arithmetic is asserted by tools/_probe_terms.tscn, which prints every
## pact's delta so the table can be read at a glance.
const PACT_WORTH_MIN: float = 1.00
const PACT_WORTH_MAX: float = 2.00

## twin id -> {name, desc, verb, effect, value/relic}. Keyed by the free writ it
## escalates; MainMenu only ever offers a pact whose twin is on the screen.
##
## A pact carries its twin's `verb` and may never introduce another. The old road
## pacts each named TWO unrelated rules ("Camps forge 2 cards, and shop goods
## cost a quarter less") — two axes bought with one price, which is unreadable
## whichever way you price it. Each road pact now deepens one axis: the coin
## pacts each add a second money rule, and the surgeon's pact moves the same
## healing to both sides of the fight.
const PACTS: Dictionary = {
	"whetstone_cart": {
		"name": "Pact of the Whetstone", "verb": "forge",
		"desc": "Forge 2 cards of your choice. Lose 6 max HP.",
		"effect": "forge", "value": 2,
	},
	"provosts_broom": {
		"name": "Pact of the Papers", "verb": "strike",
		"desc": "Remove 2 cards from your deck. Lose 6 max HP.",
		"effect": "remove", "value": 2,
	},
	"muster_tent": {
		"name": "Pact of the Tent", "verb": "enlist",
		"desc": "Add 2 of 5 uncommon cards to your deck. Lose 6 max HP.",
		"effect": "enlist2", "value": 5,
	},
	# THREE, not two. A transform is a forge you do not get to aim, so one extra
	# roll priced below every other pact in the table (0.75 forges against a 1.00
	# floor). Buying two more instead of one puts the Horse Fair back inside the
	# band AS the table's variance option, which is the honest shape for it:
	# a third of an eleven-card opener re-rolled upward, sight unseen.
	"remount_line": {
		"name": "Pact of the Fair", "verb": "raise",
		"desc": "3 cards each become a random card one rarity higher. Lose 6 max HP.",
		"effect": "remount", "value": 3,
	},
	"sutlers_bond": {
		"name": "Pact of the Bond", "verb": "coin",
		"desc": "Shop goods cost a quarter less; sales pay double. Lose 6 max HP.",
		"effect": "purse2", "relic": "merchants_license", "relic2": "scavengers_pouch",
	},
	"paymasters_ledger": {
		"name": "Pact of the Ledger", "verb": "coin",
		"desc": "Sales pay double; each win pays 10 more gold. Lose 6 max HP.",
		"effect": "purse2", "relic": "scavengers_pouch", "relic2": "coin_purse",
	},
	"campaign_chest": {
		"name": "Pact of the Chest", "verb": "coin",
		"desc": "Each win pays 10 more gold; shop goods cost a quarter less. Lose 6 max HP.",
		"effect": "purse2", "relic": "coin_purse", "relic2": "merchants_license",
	},
	"field_surgery": {
		"name": "Pact of the Surgeon", "verb": "mend",
		"desc": "Each death heals 1 HP: enemies now, friendlies after. Up to 5 each. Lose 6 max HP.",
		"effect": "purse2", "relic": "vultures_feast", "relic2": "stygian_soul",
	},
}


## How many times a term performs its verb. NOT the same as `value` — the enlist
## resolvers read `value` as the WIDTH of the slate offered (MainMenu calls
## `_writ_enlist_step(picks, width)`), so the pick count lives in the effect id.
## Getting this wrong is how a "1 of 5" tile would price as five enlistments.
static func action_count(entry: Dictionary) -> int:
	match String(entry.get("effect", "")):
		"forge", "remove", "remount":
			return int(entry.get("value", 1))
		"enlist":
			return 1
		"enlist2":
			return 2
		"arsenal":
			return 1
		"purse":
			return 1
		"purse2":
			return 2
	return 0


## Worth of one performance of a verb, in forges. See the PACT_WORTH block above
## for where the unit comes from; each number below is an argument, not a taste.
static func unit_worth(verb: String) -> float:
	match verb:
		# Definitional: the Supply Cache prices one forge at 70/90/110 gold.
		"forge":
			return 1.00
		# Above a forge. The road SELLS a forge; it will not sell you a second
		# removal at any price — the sutler's buy-back is capped at one card a
		# visit — and thinning an eleven-card opener is the strongest single
		# lever in the genre. Priced at one and a half forges, not two, because
		# the buy-back does eventually reach most cards a run wants gone.
		"strike":
			return 1.50
		# A pool uncommon posts at 75 gold against the forge's 90; choosing 1 of
		# 5 is worth at least the 15-gold gap, so it lands level with a forge.
		"enlist":
			return 1.00
		# A forge you do not get to aim. The roll can hand back a card the deck
		# did not want, and it consumes a card that was already doing a job.
		"raise":
			return 0.75
		# The Shop posts a common relic at 90 gold — the forge price exactly.
		"arm":
			return 1.00
	return 0.0


## Worth of one standing road rule, in forges. A relic's sticker is one forge
## (90 gold at the shop); an ECONOMY relic is bought to return more than its
## sticker, so each estimate below is the run return, discounted for the fact
## that gold is only worth what the road has left to sell.
static func road_rule_worth(relic_id: String) -> float:
	match relic_id:
		# A quarter off a run's shop spend. A route reaches roughly 1 to 1.5
		# shops an act and a full basket runs about 200 gold, so ~100-150 gold
		# back: one forge.
		"merchants_license":
			return 1.00
		# The buy-back is one card a visit at 10 + 8 per Command; doubling it
		# adds roughly 25 gold a visit across about four visits. One forge.
		"scavengers_pouch":
			return 1.00
		# 10 gold a won fight across 21 fights on a full route is 210 gold —
		# 2.3 forges at sticker. Discounted to 1.5 because late gold outruns the
		# shelf: a shop stocks 3 cards, 2 relics and a potion, and a route only
		# reaches a handful of them.
		"coin_purse":
			return 1.50
		# Up to 5 HP after every won fight, against a 30 HP march. Realistically
		# 2 to 3 a fight, which over a run is more HP than the camps pay — but it
		# arrives as attrition relief rather than as a resource, so 1.5.
		"vultures_feast":
			return 1.50
		# Same cap, landing DURING the fight where it can decide one, which is
		# worth more per point; but it needs kills, so a losing board pays
		# nothing. The two effects settle at the same 1.5.
		"stygian_soul":
			return 1.50
	return 0.0


## What a term is worth in forges, whichever slot it came from.
static func entry_worth(entry: Dictionary) -> float:
	var effect := String(entry.get("effect", ""))
	if effect.begins_with("purse"):
		var total := 0.0
		for key in ["relic", "relic2"]:
			var rid := String(entry.get(key, ""))
			if rid != "":
				total += road_rule_worth(rid)
		return total
	return float(action_count(entry)) * unit_worth(String(entry.get("verb", "")))


## What the 6 max HP actually buys: the pact's worth over its own free twin.
## This — not the pact's absolute worth — is the number the band gates, because
## the free tile is standing on the screen beside it and is what the player is
## pricing against.
static func pact_delta_worth(twin_id: String) -> float:
	if not PACTS.has(twin_id) or not WRITS.has(twin_id):
		return 0.0
	return entry_worth(PACTS[twin_id]) - entry_worth(WRITS[twin_id])


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
		# INSERTED BESIDE ITS TWIN, not appended. This docstring has always said
		# the pact is "joined to it so the price reads as an exchange rate", and
		# appending never joined anything: the twin is drawn from the ROLL tile
		# or the PURSE tile, so roughly half of all deals put the pair at slot 0
		# and slot 3 — opposite ends of the row with two unrelated terms between
		# them. The player was asked to notice that two of four tiles share a
		# verb, across a gap, with nothing pointing it out (the legend that used
		# to explain the relationship was retired when the row got its own step).
		# Side by side, the escalation reads without a word of explanation.
		var at: int = slate.size()
		for i in slate.size():
			if String(slate[i].get("id", "")) == twin:
				at = i + 1
				break
		slate.insert(at, pact)
	return slate


## Player-facing slot furniture. The roman numeral and the role word are what
## make the three AXES comparable — without them the screen is a row of
## unrelated nouns again.
## The pact carries NO NUMERAL, and that is the point. I/II/III each name a part
## of the run — your deck, your gear, the road — so they are three comparable
## AXES and the numerals are what make them read as a series. The pact is not a
## fourth axis; it is a PRICE on one of the three, and numbering it "IV" asserted
## a parallel that does not exist. That false parallel is why the row needed a
## legend above it explaining how to read itself.
##
## It also has to be unnumbered now that roll_slate INSERTS the pact beside its
## twin rather than appending it — a fixed "IV" in the second column would read
## I, IV, II, III.
const SLOT_LABELS: Dictionary = {
	"roll": "I · YOUR DECK",
	"arsenal": "II · YOUR GEAR",
	"purse": "III · RUN RULES",
	"pact": "THE TRADE",
}

const SLOT_HINTS: Dictionary = {
	"roll": "one card",
	"arsenal": "one relic",
	"purse": "whole run",
	"pact": "at a cost",
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
## Split into three steps 2026-07-31. The one-screen version asked six questions
## at once — an identity, a build modifier, an economy pick and three session
## settings, all drawn as equals — and the owner's verdict on the rendered frame
## was that it reads as overwhelming. The steps are ordered by DEPENDENCY, which
## is why they are steps and not just three tabs: the banner's card joins the
## host's opener, and the terms are weighed against the column both of them
## build. Each step's heading is signage, so a run of capped words is intended.
##
## `subtitle` is now the standing promise printed under the rail on every step
## rather than a one-line summary of the whole screen — it is the sentence that
## makes BACK legible, so it belongs everywhere BACK does.
const MUSTER_COPY: Dictionary = {
	"title": "RUN SETUP",
	"subtitle": "Nothing is final until you press Start Run.",
	"host_head_text": "THE HEROES",
	# Named for what the pane LEADS with, not for its tail. It said "YOUR STARTING
	# DECK" while holding a 216x287 portrait, the lord's name at 30px, his record,
	# his pitch and his signature relic above the cards — the heading named the
	# bottom third of its own pane. The roll line under the name already labels
	# the deck inline ("11 cards · The Colours adds Line Marker").
	"column_head_text": "YOUR HERO",
	"banner_head_text": "THE BANNERS",
	"terms_head_text": "STARTING BONUS",
	"step_host_text": "I · THE HERO",
	"step_banner_text": "II · THE BANNER",
	"step_terms_text": "III · THE BONUS",
	# STEPS I AND II NO LONGER CARRY A DESC LINE, and the two that lived here are
	# retired rather than left unread (2026-08-01). Step I's ("Who leads the march,
	# and the company that marches with them") glossed the two panel headings
	# printed directly beneath it; step II's ("Declare your colours. One of them
	# falls in with you now, and more of them will find you on the road") said what
	# banner_rule_text says forty words lower on the same screen. Four stacked
	# centred lines opened every step — and since _make_display_label floors at
	# GameTheme.MIN_LABEL_SIZE, the two written small rendered as loud as the two
	# written large. See MainMenu._show_muster_step.
	# Printed ONCE under the six chips. Every banner does exactly this, so saying
	# it on each chip would be six copies of a sentence that cannot vary — and it
	# would crowd out the one line where the six actually differ. Same
	# screen-scoped rule the terms glossary follows.
	"banner_rule_text": "Whichever banner you choose: one of its cards joins"
		+ " your starting deck now, and its kind is offered more often at every"
		+ " Recruit Camp.",
	# The one desc line the split kept: "accept ONE" is the rule of the row and no
	# tile states it. Second sentence cut 2026-08-01 — "each names the part of the
	# run it moves" taught the reader to read a suffix the four tiles print for
	# themselves ("— your deck", "— your gear", "— the road", "— the price").
	# A CAPTION NOW, NOT A SENTENCE. This was a centred line of prose under three
	# left-aligned small-caps captions, so the fourth decision on the screen wore
	# a different uniform from the other three and read as an aside. Same shape as
	# THE HEROES / YOUR HERO / THE BANNERS, with the pick-ONE rule carried inside
	# it — no tile states that rule, so it cannot simply be dropped.
	"terms_step_desc_text": "STARTING BONUS — CHOOSE ONE",
	"next_banner_text": "NEXT: BANNER",
	"next_terms_text": "NEXT: BONUS",
	"seed_tooltip_text": "Same seed, same map and same offers.",
	"banner_card_fallback_text": "a banner card",
}


static func muster_copy(key: String) -> String:
	return String(MUSTER_COPY.get(key, ""))


## House vocabulary the opening prices its decisions in, defined where the
## decision is made. "Forge" appears in six of the seventeen terms — including
## one that charges 6 max HP for two of them — and is defined nowhere in the
## game; asking a first-time player to price a currency they have not been told
## the value of is the sharpest legibility hole on the first screen of the run.
##
## Keys carry the `_text` suffix because _probe_copy_lint reads COPY_KEYS and
## `*_text` only and silently skips anything else — but note that the suffix
## alone is NOT enough, and assuming it was is how the first version of this
## block shipped unscanned: the lint walks an explicit list of named constants,
## so a new dictionary is invisible until `_scan_writs` is told it exists. The
## suffix decides which keys inside a scanned dict get read; `_scan_writs`
## decides whether the dict is read at all. Both are required.
const GLOSSARY: Dictionary = {
	"forge_text": "Forge — permanently upgrade a card. Every card has one"
		+ " stronger version; forging is how you get it.",
	"enlist_text": "Enlist — the card joins your deck for the rest of the run.",
	"strike_text": "Strike — the card leaves your deck for good.",
}
## Most specific first: "Strike 2 cards off your deck" must not answer to a
## glossary walk that happens to check `enlist` earlier.
const GLOSSARY_ORDER: Array = ["forge", "enlist", "strike"]


## The one house word worth defining for a WHOLE dealt slate, or "" when every
## term on screen already stands on its own.
##
## Screen-scoped, not tile-scoped, and both halves of that are load-bearing. The
## Pact is by construction the escalated twin of a term already on screen, so a
## per-tile gloss printed the same definition twice on most deals — and three
## lines of it overflowed the tile's bottom border. Scoped to the screen it
## cannot repeat and cannot overflow anything.
##
## One line, not a legend: the terms row lost its old four-part legend for
## exactly the reason a four-part glossary would fail here too.
static func gloss_for_slate(entries: Array) -> String:
	var joined := ""
	for entry in entries:
		joined += String((entry as Dictionary).get("desc", "")).to_lower() + " "
	for key in GLOSSARY_ORDER:
		if joined.contains(String(key)):
			return String(GLOSSARY.get("%s_text" % key, ""))
	return ""
