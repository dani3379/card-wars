extends Node
## SetPieceDB.gd — SET-PIECE HOLDS (2026-07-20).
##
## A set-piece is a NAMED ACTION of the war: an authored scenario fought on the
## normal combat engine with (a) an opening board someone placed on purpose,
## (b) ONE twisted rule, and (c) an objective that is not "kill the face,"
## carrying a deadline. Thronebreaker's puzzle battles are the model; the
## house translation is "your deck + one twisted rule + a clock" — a handed
## deck would bypass the build, which is the standard complaint about the form.
##
## WHY THIS SHAPE (docs/DESIGN_RESEARCH_20260718.md §4-C2, and the 2026-07-20
## positioning audit): normal holds are UNDER-CONSTRAINED — the player can
## usually afford to answer everything, so there is nothing to triage and
## placement collapses to "plug the hole." A set-piece is OVER-constrained by
## construction (authored board, closed ground, a clock), which is the only
## place the Into-the-Breach cold-reading pressure can be delivered without
## rebalancing the whole curve. It attacks "fights feel samey" through STAKES,
## which is the lever [[combat-feels-samey]] sanctions — not through new
## mechanics, which is the lever it forbids.
##
## A set-piece is NOT a new map node type. It is a `combat` node carrying a
## `setpiece_id` — the same precedent as `wayside_id` / `mutator_id`. Every
## existing routing, save, medallion, music and gold path therefore works
## unchanged, and in the fiction it is exactly right: a named action IS a hold,
## it just happens to be one people wrote down afterwards.
##
## ─────────────────────────────────────────────────────────────────────────
##  SCHEMA
## ─────────────────────────────────────────────────────────────────────────
##   name          player-facing title of the action
##   act           1-3 — which act's road it sits on
##   brief         the despatch. COPY_STYLE §10 road register, <= ~40 words.
##   ground        {name, text} — the ONE twisted rule, printed on the brief
##                 and on the standing-order plaque all fight.
##   objective     {kind, value, rounds, label, short} — see KINDS below
##   rules         mechanical switches the engine reads:
##                   closed_lanes      Array[int] — lanes no body may hold
##                   revive_while_mark bool — enemy deaths return while the
##                                     marked body stands
##                   no_reinforce      bool — neither side is reinforced
##   opening       {enemy: [placement], player: [placement]}
##                 placement = creature dict + {"row","lane"} (+ "mark"/"ward")
##   deck          ordered reinforcement creatures (EncounterDB creature dicts)
##   reinforcement the infinite backup body
##   hp            enemy face HP
##   trophy        {relic: id} — the named prize, granted on the field
##   gold          gold paid on top of the normal hold purse
##   toll          HP lost when the clock runs out and the army withdraws
##   won / lost    one line of prose for each verdict
##
## ─────────────────────────────────────────────────────────────────────────
##  OBJECTIVE KINDS (all five live in Combat._sp_evaluate_objective)
## ─────────────────────────────────────────────────────────────────────────
##   hold_rounds   survive to the end of round `rounds`
##   slay_marked   kill the body flagged "mark" before round `rounds` ends
##   protect       the body flagged "ward" is alive at the end of round `rounds`
##   break_face    deal `value` face damage by the end of round `rounds`
##   clear_board   no enemy creature on the field at any round's end
##
## FAILURE IS NOT DEATH. When the clock runs out the army WITHDRAWS: the toll
## is paid in HP, no trophy is granted, and the march continues. Dying the
## normal way (HP 0) still ends the run. This is deliberate — an authored
## puzzle that ends a 40-minute run on a whiff is a feel-bad, and the ItB
## lesson is that a good run is built from modest losses taken in the right
## place. The toll is stated on the map tooltip BEFORE the player commits.
##
## Verify: tools/_probe_setpiece.gd (headless).

const SET_PIECES: Dictionary = {

# ═══════════════════════════════════════════════════════════════════════════
#  ACT 1 — THE SUNKEN ROAD
#  Teaching set-piece. The ground itself is the twist: two lanes, not four.
#  Nothing exotic — it just takes the player's most reliable habit (spread out
#  and plug holes) and removes the room to do it.
# ═══════════════════════════════════════════════════════════════════════════
"the_sunken_road": {
	"name": "The Sunken Road",
	"act": 1,
	"brief": "Your baggage column is crossing a narrow sunken road. Hold the two open lanes until it clears.",
	"ground": {
		"name": "THE BANKS",
		"text": "Only the two center lanes can be used by either side.",
	},
	"objective": {
		"kind": "hold_rounds", "rounds": 5,
		"label": "Hold the cut for five rounds.",
		"short": "HOLD THE CUT",
	},
	"rules": {"closed_lanes": [0, 3]},
	"hp": 22,
	"opening": {
		"enemy": [
			{"row": 0, "lane": 1, "name": "Ditch Raider", "atk": 2, "hp": 3, "kw": ["swift"]},
			{"row": 0, "lane": 2, "name": "Bank Climber", "atk": 2, "hp": 4, "kw": []},
		],
		"player": [],
	},
	"deck": [
		{"name": "Ditch Raider", "atk": 2, "hp": 3, "kw": ["swift"]},
		{"name": "Road Breaker", "atk": 3, "hp": 3, "kw": []},
		{"name": "Bank Climber", "atk": 2, "hp": 4, "kw": []},
		{"name": "Long Knife", "atk": 3, "hp": 2, "kw": ["swift"]},
		{"name": "Ditch Raider", "atk": 2, "hp": 3, "kw": ["swift"]},
		{"name": "Road Breaker", "atk": 3, "hp": 3, "kw": ["armored"]},
	],
	"reinforcement": {"name": "Ditch Raider", "atk": 2, "hp": 3, "kw": ["swift"]},
	"trophy": {"relic": "sunken_road_stone"},
	"gold": 45,
	"toll": 6,
	"won": "The baggage column clears the road. Your army can move on.",
	"lost": "The line breaks and part of the baggage column is lost.",
},

# ═══════════════════════════════════════════════════════════════════════════
#  ACT 2 — THE PAY COLUMN
#  The protect objective. The cart cannot fight, so the player's whole board
#  becomes a screening problem: the enemy dealer already prefers occupied
#  player columns, which means it comes for the cart without any bespoke AI.
#  Canon anchor: the Fourth's back pay, the clerk's strongbox (see the event
#  pool's `box_game` — one shared world, one line, no lore dump).
# ═══════════════════════════════════════════════════════════════════════════
"the_pay_column": {
	"name": "The Pay Column",
	"act": 2,
	"brief": "The Fourth Legion's pay is ninety years late. Protect the cart until it reaches the ford.",
	"ground": {
		"name": "THE CART",
		"text": "The Paymaster's Cart cannot attack and cannot be healed. "
			+ "Everything out there wants it.",
	},
	"objective": {
		"kind": "protect", "rounds": 5,
		"label": "Keep the Paymaster's Cart standing for five rounds.",
		"short": "THE CART STANDS",
	},
	"rules": {},
	"hp": 26,
	"opening": {
		"enemy": [
			{"row": 0, "lane": 0, "name": "Road Agent", "atk": 3, "hp": 4, "kw": ["swift"]},
			{"row": 0, "lane": 2, "name": "Cart Breaker", "atk": 4, "hp": 4, "kw": []},
			{"row": 1, "lane": 3, "name": "Whistler", "atk": 2, "hp": 3, "kw": ["sniper"]},
		],
		"player": [
			{"row": 0, "lane": 1, "ward": true, "name": "Paymaster's Cart",
				"atk": 0, "hp": 9, "kw": ["armored"]},
		],
	},
	"deck": [
		{"name": "Road Agent", "atk": 3, "hp": 4, "kw": ["swift"]},
		{"name": "Cart Breaker", "atk": 4, "hp": 4, "kw": []},
		{"name": "Whistler", "atk": 2, "hp": 3, "kw": ["sniper"]},
		{"name": "Wheel Cutter", "atk": 3, "hp": 3, "kw": ["swift"]},
		{"name": "Road Agent", "atk": 3, "hp": 4, "kw": ["swift"]},
		{"name": "Cart Breaker", "atk": 4, "hp": 5, "kw": ["armored"]},
	],
	"reinforcement": {"name": "Road Agent", "atk": 3, "hp": 4, "kw": ["swift"]},
	"trophy": {"relic": "paymasters_tally"},
	"gold": 60,
	"toll": 8,
	"won": "The cart reaches the ford with most of its cargo intact.",
	"lost": "The cart overturns, and the pay is lost on the road.",
},

# ═══════════════════════════════════════════════════════════════════════════
#  ACT 3 — THE STANDARD OF THE FOURTH
#  The priority-target puzzle. The revive rule makes every kill that ISN'T the
#  Bearer a wasted swing, which is the whole lesson: read the board, spend on
#  the thing that matters. Bearer is FRONT row on purpose — a back-row Bearer
#  would be unkillable for a deck with no reach, and an authored scenario must
#  never be unwinnable on a draft the player couldn't have known to make.
# ═══════════════════════════════════════════════════════════════════════════
"the_standard_of_the_fourth": {
	"name": "The Standard of the Fourth",
	"act": 3,
	"brief": "The dead Fourth Legion still follows its standard. Destroy the Bearer to stop the others from returning.",
	"ground": {
		"name": "THE EAGLE STILL UP",
		"text": "While the Bearer is alive, every other enemy that dies returns "
			+ "at the end of the round.",
	},
	"objective": {
		"kind": "slay_marked", "rounds": 6,
		"label": "Break the Bearer before the sixth round ends.",
		"short": "BREAK THE BEARER",
	},
	"rules": {"revive_while_mark": true},
	"hp": 30,
	"opening": {
		"enemy": [
			{"row": 0, "lane": 1, "mark": true, "name": "The Bearer",
				"atk": 3, "hp": 14, "kw": ["armored", "last_stand"]},
			{"row": 0, "lane": 0, "name": "Fourth Legion Dead", "atk": 3, "hp": 3, "kw": []},
			{"row": 0, "lane": 2, "name": "Fourth Legion Dead", "atk": 3, "hp": 3, "kw": []},
			{"row": 1, "lane": 3, "name": "Legion Hornblower", "atk": 2, "hp": 4, "kw": ["sniper"]},
		],
		"player": [],
	},
	"deck": [
		{"name": "Fourth Legion Dead", "atk": 3, "hp": 3, "kw": []},
		{"name": "Fourth Legion Dead", "atk": 3, "hp": 4, "kw": ["armored"]},
		{"name": "Legion Hornblower", "atk": 2, "hp": 4, "kw": ["sniper"]},
		{"name": "Unpaid Officer", "atk": 4, "hp": 4, "kw": ["swift"]},
		{"name": "Fourth Legion Dead", "atk": 3, "hp": 3, "kw": []},
	],
	"reinforcement": {"name": "Fourth Legion Dead", "atk": 3, "hp": 3, "kw": []},
	"trophy": {"relic": "eagle_of_the_fourth"},
	"gold": 75,
	"toll": 10,
	"won": "The Bearer falls, and the rest of the dead stop returning.",
	"lost": "You withdraw while the Bearer still stands. The fallen enemies begin returning again.",
},

# -----------------------------------------------------------------------------
#  ACT 2 ALTERNATE - THE RELIEF FORT
#  The break-face objective. The closed reserve book leaves one finite board
#  and one honest question: how much of the player's force can go THROUGH the
#  defenders instead of spending the whole clock cleaning them up? One lane is
#  open from the first hand, and a plain 2-ATK body played there on round one
#  can meet the order by itself after paying muster delay.
#
#  This is an alternate Act 2 named action, so it carries the same act trophy
#  as The Pay Column. CampaignMapGenerator deals exactly one named action per
#  act; the duplicate ID can never be awarded twice on one march.
# -----------------------------------------------------------------------------
"the_relief_fort": {
	"name": "The Relief Fort",
	"act": 2,
	"brief": "The Fourth Legion's back pay is locked in a fort by the ford. Its relief column is six rounds away. Break the wall before they arrive.",
	"ground": {
		"name": "NO RESERVES",
		"text": "No enemy reinforcements enter before the relief column arrives.",
	},
	"objective": {
		"kind": "break_face", "value": 10, "rounds": 6,
		"label": "Deal 10 damage to the fort before the sixth round ends.",
		"short": "THE FORT IS BROKEN",
	},
	"rules": {"no_reinforce": true},
	"hp": 28,
	"opening": {
		"enemy": [
			{"row": 0, "lane": 0, "name": "Fort Warder", "atk": 3, "hp": 5,
				"kw": ["armored"]},
			{"row": 0, "lane": 2, "name": "Toll Spear", "atk": 3, "hp": 4, "kw": []},
			{"row": 1, "lane": 3, "name": "Relief Lookout", "atk": 2, "hp": 4,
				"kw": ["sniper"]},
		],
		"player": [],
	},
	# The no-reserve rule leaves this deck sealed. It is still authored so the
	# scenario remains a complete encounter payload if the rule is ever revised.
	"deck": [
		{"name": "Fort Warder", "atk": 3, "hp": 5, "kw": ["armored"]},
		{"name": "Toll Spear", "atk": 3, "hp": 4, "kw": []},
		{"name": "Relief Lookout", "atk": 2, "hp": 4, "kw": ["sniper"]},
	],
	"reinforcement": {"name": "Toll Spear", "atk": 3, "hp": 4, "kw": []},
	"trophy": {"relic": "paymasters_tally"},
	"gold": 60,
	"toll": 8,
	"won": "The fort breaks before the relief column reaches the ford.",
	"lost": "The relief column reaches the ford. You leave the wall standing.",
},

# -----------------------------------------------------------------------------
#  ACT 3 ALTERNATE - THE LAST MUSTER
#  The clear-board objective. Four known bodies, no reserve deck, six rounds:
#  the player may trade, control and build slowly, but cannot leave one durable
#  survivor behind and solve the fight by racing face. After the campaign's
#  ordinary Act 3 body thickening, the company has 18 HP in all - low enough
#  for a defensive deck to finish on the stated clock.
#
#  Like the Act 2 alternate above, this shares its act's event-tier trophy.
#  Only one Act 3 named action is ever dealt onto a campaign map.
# -----------------------------------------------------------------------------
"the_last_muster": {
	"name": "The Last Company",
	"act": 3,
	"brief": "A dead company of the Fourth Legion has formed around its old roll. No other soldiers are coming. Put every one down before the sixth round ends.",
	"ground": {
		"name": "THE WHOLE COMPANY",
		"text": "No enemy reinforcements enter. The four soldiers before you are all that remain.",
	},
	"objective": {
		"kind": "clear_board", "rounds": 6,
		"label": "Leave no enemy standing before the sixth round ends.",
		"short": "THE ROLL IS EMPTY",
	},
	"rules": {"no_reinforce": true},
	"hp": 30,
	"opening": {
		"enemy": [
			{"row": 0, "lane": 0, "name": "Fourth Legion Dead", "atk": 3, "hp": 3,
				"kw": ["armored"]},
			{"row": 0, "lane": 2, "name": "Fourth Legion Dead", "atk": 4, "hp": 3,
				"kw": []},
			{"row": 1, "lane": 1, "name": "Legion Bow", "atk": 3, "hp": 2,
				"kw": ["sniper"]},
			{"row": 1, "lane": 3, "name": "Standard Keeper", "atk": 2, "hp": 2,
				"kw": []},
		],
		"player": [],
	},
	# Sealed by THE WHOLE COMPANY; retained as a valid encounter fallback.
	"deck": [
		{"name": "Fourth Legion Dead", "atk": 3, "hp": 3, "kw": ["armored"]},
		{"name": "Fourth Legion Dead", "atk": 4, "hp": 3, "kw": []},
		{"name": "Legion Bow", "atk": 3, "hp": 2, "kw": ["sniper"]},
		{"name": "Standard Keeper", "atk": 2, "hp": 2, "kw": []},
	],
	"reinforcement": {"name": "Fourth Legion Dead", "atk": 3, "hp": 3, "kw": []},
	"trophy": {"relic": "eagle_of_the_fourth"},
	"gold": 75,
	"toll": 10,
	"won": "The last name is struck from the roll. Nothing else moves.",
	"lost": "The dead company closes ranks. You leave the roll behind.",
},

}


## ─────────────────────────────────────────────────────────────────────────
##  QUERIES
## ─────────────────────────────────────────────────────────────────────────

func exists(id: String) -> bool:
	return id != "" and SET_PIECES.has(id)


func get_set_piece(id: String) -> Dictionary:
	if SET_PIECES.has(id):
		return SET_PIECES[id]
	if id != "":
		push_warning("SetPieceDB: unknown set-piece '%s'" % id)
	return {}


## Every set-piece authored for an act, in declaration order. The map generator
## picks one per act; a thin act simply gets none (the road stays a plain road)
## rather than borrowing from another act — these are named ground, and named
## ground does not move.
func ids_for_act(act: int) -> Array:
	var out: Array = []
	for id in SET_PIECES:
		if int(SET_PIECES[id].get("act", 0)) == act:
			out.append(id)
	return out


## Deck / opening / reinforcement bodies as real card data, built through
## EncounterDB.make_card_data so set-pieces inherit the exact enemy card schema
## (and its authored-flag whitelist) rather than growing a parallel one.
func build_deck(id: String) -> Array[Dictionary]:
	var sp: Dictionary = get_set_piece(id)
	var out: Array[Dictionary] = []
	if sp.is_empty():
		return out
	for creature in sp.get("deck", []):
		out.append(EncounterDB.make_card_data(creature))
	return out


func get_reinforcement(id: String) -> Dictionary:
	var sp: Dictionary = get_set_piece(id)
	if sp.is_empty() or not sp.has("reinforcement"):
		return {}
	return EncounterDB.make_card_data(sp.reinforcement)


## Opening placements for one side, as [{row, lane, data}] with the mark/ward
## flags carried through on the card data (make_card_data is a strict
## whitelist, so the flags are re-stamped here rather than authored into it).
func build_opening(id: String, side: String) -> Array:
	var sp: Dictionary = get_set_piece(id)
	var out: Array = []
	if sp.is_empty():
		return out
	for entry in sp.get("opening", {}).get(side, []):
		var data: Dictionary = EncounterDB.make_card_data(entry)
		if bool(entry.get("mark", false)):
			data["sp_mark"] = true
		if bool(entry.get("ward", false)):
			data["sp_ward"] = true
		out.append({
			"row": int(entry.get("row", 0)),
			"lane": int(entry.get("lane", 0)),
			"data": data,
		})
	return out


## Lanes closed to BOTH sides for the whole fight. Empty for most set-pieces.
func closed_lanes(id: String) -> Array:
	var sp: Dictionary = get_set_piece(id)
	if sp.is_empty():
		return []
	return sp.get("rules", {}).get("closed_lanes", [])


## The objective's one-line order, as it prints on the brief and the plaque.
func objective_label(id: String) -> String:
	var sp: Dictionary = get_set_piece(id)
	if sp.is_empty():
		return ""
	return String(sp.get("objective", {}).get("label", ""))


## The deadline in rounds. 0 = no clock (only clear_board runs open-ended).
func deadline(id: String) -> int:
	var sp: Dictionary = get_set_piece(id)
	if sp.is_empty():
		return 0
	return int(sp.get("objective", {}).get("rounds", 0))
