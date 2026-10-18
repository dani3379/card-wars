extends RefCounted
class_name EventDB
## Static event definitions. Event.gd owns presentation and effect execution;
## this file owns content only so data audits do not need to load a scene script.
##
## Prose register (2026-07-18 readability pass, Failbetter budgets): root desc
## ≤ ~40 words, choice flavor ≤ ~20, results ≤ ~60. Name things plainly before
## coloring them; short active sentences; direct speech over reported speech;
## period vocabulary is seasoning, not an ingredient. Shared-world canon: the
## Old King (dead, unpaying — the Successor Wars' corpse), the Fourth Legion
## he never paid, the spinner, the road. See COPY_STYLE.md §10.
const EVENTS: Dictionary = {

	# ══════════════════ KEPT — distinct mechanic + distinct fiction ══════════════════

	"pawnbrokers_window": {
		"presentation": {"layout": "bargain", "focal_uv": Vector2(0.30, 0.48), "zoom": 1.070},
		"name": "The Pawnbroker's Window",
		"desc": "A pawnbroker buys cards through a slot in smoked glass. She has an eye, and asks for your best. Each refusal cools her next offer.",
		"mood": "gilt",
		"choices": [
			{
				"label": "Let her name a card",
				"desc": "She asks for your best card first. Each refusal shows a lesser one, for less.",
				"effects": [
					{"type": "pawn_appraisal"},
				],
			},
			{
				# Campaign memory: the shelf kept what you sold her (recorded by
				# the appraisal counter). Act 2+, and only when the fee is there —
				# a blue option that can't pay would be a lie.
				#
				# 60 -> 90 on 2026-09-16, when the counter started asking for the
				# player's BEST card instead of a card at random. A flat 60 was
				# priced against an average pull (~35-45 gold); against a rare or
				# a forged card it made the round trip strictly profitable — sell
				# high, redeem cheap, and pocket the difference AND a free forge.
				# 90 is the road's own unit (one forge = two potions = ~90 gold),
				# so redeeming now buys the forge at about sticker and the whole
				# trade is a real loan against your deck rather than a money pump.
				"blue": {"type": "all", "gates": [
					{"type": "pawned_at_least", "value": 1},
					{"type": "act_at_least", "value": 2},
					{"type": "gold_at_least", "value": 90},
				]},
				"label": "Buy back {pawned}",
				"desc": "Pay 90 gold. Forge {pawned} and return it to your deck.",
				"effects": [
					{"type": "pawn_buyback", "price": 90},
				],
			},
			{
				"blue": {"type": "potions_full"},
				"label": "Sell a potion",
				"desc": "Lose one potion. Gain 65 gold.",
				"effects": [
					{"type": "sell_potion", "value": 65},
				],
			},
			{
				"label": "Buy an unclaimed relic",
				"desc": "Pay 75 gold. Gain a random relic.",
				"effects": [
					{"type": "gold", "value": -75},
					{"type": "random_relic"},
				],
			},
		],
	},

	"the_crossing": {
		"presentation": {"layout": "location", "focal_uv": Vector2(0.52, 0.45), "zoom": 1.025},
		# Phase 2.5 — fires at bridge-flagged nodes (the plate painted the
		# bridge on the road in; this room honors it). First bridge of the
		# run always rolls it (_pick_event override); later bridges compete
		# normally via the at_bridge gate.
		"name": "The Crossing",
		"desc": "Three toll collectors block a bridge over a fast river. You can pay, find another crossing, or force your way through.",
		"gate": {"type": "at_bridge"},
		"art": "tollkeeper_bridge",
		"mood": "bone",
		"ambience": "river",
		"choices": [
			{
				"label": "Pay 45 gold",
				"desc": "Lose 45 gold.",
				"effects": [
					{"type": "gold", "value": -45},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "stalwart"},
				"label": "Cross at the ford",
				"desc": "Cross for free. Gain either 20 gold or 4 HP.",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "You find a shallow ford and cross safely. A dropped purse on the far bank contains 20 gold.",
							"effects": [{"type": "gold", "value": 20}]},
						{"weight": 1,
							"text": "A cattle path leads through shallow water. The cold crossing restores 4 HP.",
							"effects": [{"type": "heal", "value": 4}]},
					]},
				],
			},
			{
				"label": "Fight across the bridge",
				"desc": "Take damage and gain gold. The amounts are random.",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "You win quickly and take the toll box. Lose 4 HP and gain 60 gold.",
							"effects": [{"type": "damage", "value": 4}, {"type": "gold", "value": 60}]},
						{"weight": 1,
							"text": "The collectors put up a hard fight, and the toll box is nearly empty. Lose 9 HP and gain 15 gold.",
							"effects": [{"type": "damage", "value": 9}, {"type": "gold", "value": 15}]},
					]},
				],
			},
			{
				# The Tollkeeper's trophy shelf, folded in when her own event was
				# retired — the chain post carries what the crossing has cost others.
				"label": "Add a Curse and remove a card",
				"desc": "Add a Curse. Remove one random card.",
				"effects": [
					{"type": "add_curse"},
					{"type": "remove_cards", "value": 1},
				],
			},
		],
	},

	"gravesong_choir": {
		"presentation": {"layout": "ritual", "focal_uv": Vector2(0.50, 0.38), "zoom": 1.035},
		"name": "The Gravesong Choir",
		"desc": "Four singers stand around an open grave. Their song carries the name {fallen}, and they leave one place open for you.",
		"mood": "bone",
		"ambience": "choir",
		"choices": [
			{
				"label": "Sing for growing rewards",
				"desc": "Risk a Curse to earn 25 gold, 35 more gold, then a relic. You can stop after any verse.",
				"effects": [
					{"type": "risk_loop", "mode": "bust",
						"open_text": "You step into the open place. Complete each verse to gain its reward, or stop and keep what you have earned.",
						"action": "Sing the next verse",
						"action_body": "Continue for the next reward.",
						"leave": "Stop singing",
						"leave_sub": "Keep your current rewards.",
						"leave_text": "You step out of the circle and keep your rewards.",
						"leave_text_early": "The circle closes without you, and the road goes on.",
						"steps": [
							{"chance": 1.0, "sub": "Gain 25 gold. This step cannot fail.",
								"effects": [{"type": "gold", "value": 25}],
								"text": "A coin purse rises from the soil. Gain 25 gold."},
							{"chance": 0.7, "sub": "Gain 35 gold. 70% chance to succeed.",
								"effects": [{"type": "gold", "value": 35}],
								"text": "More valuables rise from the grave. Gain 35 gold."},
							{"chance": 0.5, "sub": "Gain A Verse of You. 50% chance to succeed.",
								"effects": [{"type": "specific_relic", "id": "verse_of_you"}],
								"text": "A written verse rises from the grave. Gain A Verse of You."},
						],
						"bust": {"effects": [{"type": "add_curse"}],
							"text": "You miss the verse, and the song leaves a mark on you. Add a Curse."},
						"done_text": "The final verse ends. You leave with everything the grave returned."},
				],
			},
			{
				"label": "Remove two cards for a rare card",
				"desc": "Lose 6 HP. Remove two chosen cards. Gain a rare card.",
				"effects": [
					{"type": "damage", "value": 6},
					{"type": "remove_choice_multi", "value": 2},
					{"type": "add_rare"},
				],
			},
			{
				"label": "Forge one card",
				"desc": "Forge a chosen card.",
				"effects": [
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	# ── Recurring NPC: the Sin-Eater pair ──

	"sin_eater": {
		"presentation": {"layout": "ritual", "focal_uv": Vector2(0.50, 0.52), "zoom": 1.030},
		"name": "The Sin-Eater",
		"desc": "A hooded man eats funeral bread beside a body in a crypt. He offers to remove one of your cards, but his price depends on what you give him.",
		"gate": {"type": "has_curse"},
		"mood": "verdigris",
		"choices": [
			{
				"label": "Remove a Curse for 3 HP",
				"desc": "Lose 3 HP. Remove a chosen Curse.",
				"effects": [
					{"type": "damage", "value": 3},
					{"type": "remove_choice_filtered", "filter": "curse"},
				],
			},
			{
				"label": "Sell a starting card",
				"desc": "Remove a chosen starting card. Gain 50 gold.",
				"effects": [
					{"type": "gold", "value": 50},
					{"type": "remove_choice_filtered", "filter": "starter"},
				],
			},
			{
				"label": "Take 1 gold and leave",
				"desc": "Gain 1 gold.",
				"effects": [
					{"type": "gold", "value": 1},
				],
			},
		],
	},

	"fattened_sin_eater": {
		"presentation": {"layout": "ritual", "focal_uv": Vector2(0.50, 0.48), "zoom": 1.035},
		"name": "The Fattened Sin-Eater",
		"desc": "You meet the Sin-Eater again. He has prepared a feast and saved you a seat.",
		"mood": "verdigris",
		"gate": {"type": "all", "gates": [
			{"type": "act_at_least", "value": 3},
			{"type": "seen_all", "events": ["sin_eater"]},
		]},
		"choices": [
			{
				"label": "Eat, heal, and remove a card",
				"desc": "Heal to full. Gain 2 max HP. Pay 30 gold. Remove a chosen card.",
				"effects": [
					{"type": "heal_full"},
					{"type": "gain_max_hp", "value": 2},
					{"type": "gold", "value": -30},
					{"type": "remove_choice"},
				],
			},
			{
				"label": "Remove a Curse for a relic",
				"desc": "Remove a chosen Curse. Gain the Sin-Eater's Crust relic.",
				"effects": [
					{"type": "specific_relic", "id": "sin_eaters_crust"},
					{"type": "remove_choice_filtered", "filter": "curse"},
				],
			},
			{
				"label": "Take 60 gold and leave",
				"desc": "Gain 60 gold.",
				"effects": [
					{"type": "gold", "value": 60},
				],
			},
		],
	},

	# ── Hidden-info: the tells are the game ──

	"rotting_carnival": {
		"name": "The Rotting Carnival",
		"desc": "Three abandoned carnival tents stand beside the road. You may listen at each entrance before choosing one.",
		"mood": "verdigris",
		"ambience": "carnival",
		"choices": [
			{
				"hidden": true,
				"tell": "The red tent: blades strike wood in a steady rhythm. Faint applause follows each hit.",
				"desc": "Hidden",
				"effects": [
					{"type": "upgrade_random"},
					{"type": "damage", "value": 4},
				],
			},
			{
				"hidden": true,
				"tell": "The yellow tent: you smell incense and hear cards shuffling and coins being counted.",
				"desc": "Hidden",
				"effects": [
					{"type": "gold", "value": 80},
					{"type": "add_curse"},
				],
			},
			{
				"hidden": true,
				"tell": "The black tent: there is no sound or smell. Its entrance stands open.",
				"desc": "Hidden",
				"effects": [
					{"type": "random_relic"},
					{"type": "remove_cards", "value": 1},
				],
			},
		],
	},

	# ── Choose-from-curated-pool (fixed slot costs: HP / gold / Curse) ──

	"strangers_hand": {
		"name": "The Wet Cards",
		"desc": "A stranger deals wet cards on a crypt floor. Each card has a visible cost. Pay it to add that card to your deck.",
		"mood": "verdigris",
		"auto_effect": {"type": "stranger_hand_pick"},
		"choices": [],
	},

	# ── Pure gamble (absurd register) ──

	"coin_on_edge": {
		"name": "The Coin That Won't Land",
		"desc": "A silver coin spins on its edge in the road. You can stake gold, call the result, or leave it alone.",
		"mood": "gilt",
		"choices": [
			{
				"label": "Play the coin game",
				"desc": "Each call has even odds. Double the pot or lose it.",
				"effects": [
					{"type": "dice_run", "stake": 25, "start": 40,
						"mode": "double", "bust_pct": 0.5, "prop": "coin",
						"bank_relic": "coin_landed", "bank_relic_at": 160,
						"bank_relic_text": "You stop with a pot of at least 160 gold. Gain The Coin, Landed relic.",
						"broke_text": "You need 25 gold to start this game.",
						"open_text": "The pot contains {pot} gold. Call the coin again to double it, or stop and take the pot.",
						"roll_label": "Call it again",
						"roll_sub": "Even odds. Win to double the pot; lose to forfeit it.",
						"roll_body": "A wrong call loses the entire pot.",
						"bank_label": "Take the pot",
						"bank_sub": "Take {pot} gold and walk.",
						"bank_body": "End the game and keep the current pot.",
						"grow_text": "You call it correctly. The pot is now {pot} gold.",
						"bust_text": "You call it incorrectly and lose the entire pot.",
						"bank_text": "You stop and take {pot} gold.",
						# The Old Debt thread: the coin knows the Bone Pit's
						# table (seen_texts wake when the other half of the
						# story is in events_seen — see Event._dice_text).
						"seen_texts": {"the_bone_pit": {
							"open_text": "The pot contains {pot} gold. Call the coin again to double it, or stop and take the pot.",
							"bust_text": "You call the coin incorrectly and lose the entire pot."}}},
				],
			},
			{
				"blue": {"type": "has_nonstarting_relic"},
				"label": "Call the coin for 90 gold",
				"desc": "Even odds. Gain 90 gold or nothing.",
				"effects": [
					{"type": "wager_gold", "stake": 0, "payout": 90},
				],
			},
			{
				"label": "Draw a relic or two Curses",
				"desc": "Gain a relic or add two Curses.",
				"effects": [
					{"type": "wager_relic_or_curse", "curses": 2},
				],
			},
			{
				"label": "Take 10 gold and leave",
				"desc": "Gain 10 gold.",
				"effects": [
					{"type": "gold", "value": 10},
				],
			},
		],
	},

	# ── Push-your-luck pot game ──

	"the_bone_pit": {
		"name": "The Bone Pit",
		"desc": "Four dead soldiers play knucklebones for wages they never received. They invite you to join their push-your-luck game.",
		"mood": "bone",
		"choices": [
			{
				"label": "Play with a 25-gold pot",
				"desc": "Start with a 25-gold pot. Stop at any time and take it. Rolling skulls loses the pot.",
				"effects": [
					{"type": "dice_run", "start": 25,
						"bank_relic": "warm_knucklebone", "bank_relic_at": 75,
						"bank_relic_text": "You stop with a pot of at least 75 gold. Gain the Warm Knucklebone relic.",
						# The Old Debt thread: the pit knows the spinner, and
						# it knows its own creditor's clerk.
						"seen_texts": {"coin_on_edge": {
							"open_text": "The pot contains {pot} gold. Roll again to increase it, or stop and take the pot.",
							"bust_text": "You roll skulls and lose the entire pot."},
						"old_army_game": {
							"open_text": "The pot contains {pot} gold. Roll again to increase it, or stop and take the pot."}}},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["coin_on_edge"]},
				"label": "Play with a 50-gold pot",
				"desc": "Start with a 50-gold pot. Stop at any time and take it. Rolling skulls loses the pot.",
				"effects": [
					# This seat only exists when the spinner has been met
					# (blue gate) — its table-talk bakes the link in directly.
					{"type": "dice_run", "start": 50,
						"bank_relic": "warm_knucklebone", "bank_relic_at": 75,
						"bank_relic_text": "You stop with a pot of at least 75 gold. Gain the Warm Knucklebone relic.",
						"open_text": "The free starting pot contains {pot} gold. Roll again to increase it, or stop and take the pot.",
						"bust_text": "You roll skulls and lose the entire pot."},
				],
			},
			{
				"label": "Take 35 gold and a Curse",
				"desc": "Gain 35 gold. Add a Curse.",
				"effects": [
					{"type": "gold", "value": 35},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Take 5 gold and leave",
				"desc": "Gain 5 gold.",
				"effects": [
					{"type": "gold", "value": 5},
				],
			},
		],
	},

	# ── The shell game (the old debt, personified) ──

	"old_army_game": {
		"name": "The Old Army Game",
		"desc": "A dead paymaster hides a coin beneath one of three helmets. Follow the coin through the shuffle to win his shell game.",
		"mood": "verdigris",
		"art": "the_bone_pit",
		"choices": [
			{
				"label": "Play for 30 gold",
				"desc": "Stake 30 gold. Follow the coin through the shuffle and find it to win the Scavenger card.",
				"effects": [
					# The clerk pays in kind, not in coin: the card he deals out
					# is the game itself, still turning a profit off the dead.
					{"type": "shell_game", "stake": 30, "payout": 80, "swaps": 7,
						"win_effects": [{"type": "add_card_id", "id": "scavenger"}],
						"lose_effects": [{"type": "gold", "value": 10}],
						"open_text": "Your coin starts under the middle helmet. Watch the shuffle, then choose the helmet containing the coin.",
						"win_text": "You find the coin. The clerk pays you in kind.",
						"lose_text": "Wrong helmet. The clerk keeps the stake and returns 10 gold.",
						"broke_text": "You need {stake} gold to play.",
						# The Old Debt thread: the clerk knows the spinner's
						# work when he smells it on you — and he knows who
						# keeps the book of charges.
						"seen_texts": {"coin_on_edge": {
							"open_text": "Your coin starts under the middle helmet. Watch the shuffle, then choose the helmet containing the coin."},
						"the_provost_marshal": {
							"open_text": "Your coin starts under the middle helmet. Watch the slower shuffle, then choose the helmet containing the coin."}}},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["the_bone_pit"]},
				"label": "Play for free",
				"desc": "Play for free. Follow the coin through the shuffle and find it to gain 60 gold.",
				"effects": [
					# The free seat stays a coin game — the card is what the
					# staked seat buys, and a free prize would price it at zero.
					{"type": "shell_game", "stake": 0, "payout": 60, "swaps": 6,
						"open_text": "This round is free. Watch the slower shuffle, then choose the helmet containing the coin.",
						"win_text": "You find the coin. Gain {payout} gold.",
						"lose_text": "Wrong helmet. This round was free, so you lose nothing."},
				],
			},
			{
				"label": "Take 5 gold and leave",
				"desc": "Gain 5 gold.",
				"effects": [
					{"type": "gold", "value": 5},
				],
			},
		],
	},

	# ── The straw drawing (a game of pure arithmetic vs the dead) ──

	"the_short_straw": {
		"name": "The Short Straw",
		"desc": "Three dead sentries play a drawing game with bone straws. Draw safely to win, but whoever takes the last straw must stand watch.",
		"mood": "ember",
		# Was "the_last_garrison" — an EVENT id, not a file. The resolver does not
		# follow that chain, so this was the one event in the pool that resolved
		# to nothing and shipped on the generic forest plate. The intent is clear
		# and correct (the Last Garrison is the dead still at their post, which is
		# this event's fiction exactly), so point at the file that event resolves
		# to. ART DEBT: still a two-event borrow until bespoke art lands.
		"art": "plague_bell",
		"choices": [
			{
				"label": "Play Short Straw",
				"desc": "Win to gain the Lookout card. Draw the last straw and lose 6 HP.",
				"effects": [
					# The loser stands the watch. Win and the sentry stands it —
					# and walks with your column after, which is the whole prize.
					{"type": "straw_game", "counts": [12, 14, 15, 16],
						"win_effects": [{"type": "add_card_id", "id": "lookout"}],
						"lose_effects": [{"type": "damage", "value": 6},
							{"type": "gold", "value": 20}],
						"open_text": "There are {count} straws. Take 1, 2, or 3. Whoever takes the last straw loses the round.",
						"win_text": "The corporal takes the last straw, and takes the watch with it.",
						"lose_text": "You take the last straw. Lose 6 HP. The sentries pay 20 gold for the watch you stood.",
						# The Old Debt thread: the watch knows the Fourth's table.
						"seen_texts": {"the_bone_pit": {
							"open_text": "There are {count} straws. Take 1, 2, or 3. Whoever takes the last straw loses the round."}}},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["the_bone_pit"]},
				"label": "Play for free",
				"desc": "Play for free. Win to gain 40 gold and 5 HP. Lose with no penalty.",
				"effects": [
					# The free seat keeps the coin payout: no stake, no card.
					{"type": "straw_game", "counts": [12, 14, 15, 16],
						"win_effects": [{"type": "gold", "value": 40},
							{"type": "heal", "value": 5}],
						"lose_effects": [],
						"open_text": "This round is free. There are {count} straws. Take 1, 2, or 3. Whoever takes the last straw loses.",
						"lose_text": "You take the last straw. This round is free, so you lose nothing."},
				],
			},
			{
				"label": "Trade 3 HP for 30 gold",
				"desc": "Lose 3 HP. Gain 30 gold.",
				"effects": [
					{"type": "damage", "value": 3},
					{"type": "gold", "value": 30},
				],
			},
			{
				"label": "Take 5 gold and leave",
				"desc": "Gain 5 gold.",
				"effects": [
					{"type": "gold", "value": 5},
				],
			},
		],
	},

	# ── The Widow's Cut (high-card duel vs the dead, best of three) ──
	# NOTE: event KEY retained (`widows_tray`) so the shared-world threads and
	# map assignments keep resolving; regenerated 2026-07-21 from the old
	# Kim's-game "Widow's Tray" to a readable high-card duel over her dead
	# soldier's paybook. Shares the `pawnbrokers_window` stand-in for now.

	"widows_tray": {
		"name": "The Widow's Keeping",
		"desc": "A widow has kept her husband's kit oiled since the King's war. She has no son to give it to, and yours is the first column past her door in a year.",
		"mood": "verdigris",
		"art": "pawnbrokers_window",
		"choices": [
			{
				"label": "Take his mail",
				"desc": "One of your creatures wears it from here on. Teach it Armored.",
				"effects": [
					{"type": "grant_keyword_pick", "keyword": "armored"},
				],
			},
			{
				"label": "Take his boots",
				"desc": "One of your creatures wears them from here on. Teach it Swift.",
				"effects": [
					{"type": "grant_keyword_pick", "keyword": "swift"},
				],
			},
			{
				"blue": {"type": "fallen_at_least", "value": 1},
				"label": "Recruit a Standard Bearer",
				"desc": "She keeps the roll of every column that passed. Gain a Standard Bearer.",
				"effects": [
					{"type": "add_card_id", "id": "standard_bearer"},
				],
			},
		],
	},

	# ── The counting game (informed push-your-luck at the ford) ──

	"the_couriers_satchel": {
		"name": "The Courier's Satchel",
		"desc": "A drowned courier searches the ford for lost pay tokens. Draw tokens, then stop when you are happy with the reward.",
		"mood": "bone",
		"art": "the_crossing",
		"choices": [
			{
				"label": "Play for 20 gold",
				"desc": "Stake 20 gold. Stop at 8 or more to win 20 gold, at 11 for 40, or at 12 or 13 for the Mule card.",
				"effects": [
					# The satchel's terminal prize: hold your nerve to 12 and the
					# drowned man's pack animal walks out of the ford with you.
					# Under the floor the tiers pay in coin exactly as before.
					{"type": "sack_game", "stake": 20, "target": 13,
						"pay": [[13, 80], [12, 55], [11, 40], [8, 20]],
						"win_effects_at": 55,
						"win_effects": [{"type": "add_card_id", "id": "mule"}],
						"lose_effects": [{"type": "gold", "value": 6}],
						"win_text": "Stopped at {sum}. The courier settles up.",
						"perfect_text": "Exact total: {sum}. The courier settles up.",
						"flat_text": "Stopped at {sum}, below the lowest reward. The courier keeps the stake and hands back 6 gold.",
						"bust_text": "Your total is {sum}, above the target. The courier keeps the stake and hands back 6 gold.",
						# The Old Debt thread: the courier knows the clerk's
						# arithmetic, and doesn't rate it.
						"seen_texts": {"old_army_game": {
							"open_text": "Draw pay tokens toward {target}. Stop after any draw to take the reward for your total."}}},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["the_bone_pit"]},
				"label": "Take 60 gold",
				"desc": "Gain 60 gold.",
				"effects": [
					{"type": "gold", "value": 60},
				],
			},
			{
				"label": "Take 8 gold and leave",
				"desc": "Gain 8 gold.",
				"effects": [
					{"type": "gold", "value": 8},
				],
			},
		],
	},

	# ── The Wheel of the Fourth (roulette; back a colour, spin the wheel) ──
	# NOTE: event KEY retained (`the_beetle_derby`) so shared-world threads and
	# map assignments keep resolving; regenerated 2026-07-21 from the old
	# invisible-beetle "Sappers' Derby" to a readable painted fortune-wheel.
	# The runner configs carry over unchanged (name/mult/weight/tint) — the
	# wheel gives each colour a share of slices equal to its weight. Shares the
	# `coin_on_edge` stand-in for now.

	"the_beetle_derby": {
		"name": "The Wheel of the Fourth",
		"desc": "Three sappers run a betting wheel with three sections. Smaller sections are less likely to win but pay more.",
		"mood": "gilt",
		"art": "coin_on_edge",
		"choices": [
			{
				"label": "Bet on a color",
				"desc": "Stake 20 gold. Old Crown pays 40, Widow's Mite pays 60, and Little Fourth pays 100.",
				"effects": [
					{"type": "wheel_game", "stake": 20,
						"runners": [
							{"name": "Old Crown", "mult": 2, "weight": 3,
								"tint": Color(0.85, 0.68, 0.25),
								"blurb": "The favourite. Half the wheel is the Old King's gold, and, like the Old King, it mostly comes up."},
							{"name": "Widow's Mite", "mult": 3, "weight": 2,
								"tint": Color(0.58, 0.52, 0.66),
								"blurb": "Two quiet slices. The widows back it, patiently."},
							{"name": "Little Fourth", "mult": 5, "weight": 1,
								"tint": Color(0.80, 0.32, 0.20),
								"blurb": "One red slice, alone. Nobody backs the Fourth. You know why."},
						],
						"open_text": "Choose a color, then spin. The number of slices in that color shows its chance to win. Smaller sections pay more.",
						# The Old Debt thread: the pit's creditor is known here.
						"seen_texts": {"the_bone_pit": {
							"open_text": "Choose a color, then spin. Little Fourth has one slice in six and pays the largest reward."}}},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["the_bone_pit"]},
				"label": "Play with better odds",
				"desc": "Stake 20 gold. Little Fourth covers two sections and still pays 100.",
				"effects": [
					{"type": "wheel_game", "stake": 20,
						"runners": [
							{"name": "Old Crown", "mult": 2, "weight": 3,
								"tint": Color(0.85, 0.68, 0.25),
								"blurb": "The favourite. Still the Old King's gold, still mostly up."},
							{"name": "Widow's Mite", "mult": 3, "weight": 2,
								"tint": Color(0.58, 0.52, 0.66),
								"blurb": "Two quiet slices. The widows back it, patiently."},
							{"name": "Little Fourth", "mult": 5, "weight": 2,
								"tint": Color(0.80, 0.32, 0.20),
								"blurb": "Two red slices now. It runs for the ledger."},
						],
						"open_text": "Little Fourth now has two slices in six and still pays the largest reward. Choose a color, then spin."},
				],
			},
			{
				"label": "Take 10 gold",
				"desc": "Gain 10 gold.",
				"effects": [
					{"type": "gold", "value": 10},
				],
			},
		],
	},

	# ── The liars' game (bids and calls against a man who can't lie) ──

	"the_provost_marshal": {
		"name": "The Dead Marshal",
		"desc": "A dead marshal still holds the roll-call he did not live to finish. He wants your names read out to him. The ones he does not care for, he strikes off.",
		"mood": "bone",
		"art": "gravesong_choir",
		"choices": [
			{
				"label": "Remove all copies of one card",
				"desc": "Choose one card. Every copy of it is struck from your deck.",
				"effects": [
					{"type": "remove_choice_all_copies", "filter": ""},
				],
			},
			{
				"blue": {"type": "has_curse"},
				"label": "Remove a Curse",
				"desc": "He strikes a mark from the record instead. Remove a curse.",
				"effects": [
					{"type": "remove_choice_filtered", "filter": "curse"},
				],
			},
			{
				"label": "Recruit a Pikeman",
				"desc": "He presses the next body down the road. Gain a Pikeman.",
				"effects": [
					{"type": "add_card_id", "id": "pikeman"},
				],
			},
		],
	},

	# ── The flash of fingers (morra — reading a dead man's drill) ──

	"the_old_game": {
		"name": "The Old Game",
		"desc": "Dead pikemen run the drill they ran every dawn of the King's war. They have not stopped for it ending. They will make room for anyone who keeps the step.",
		"mood": "ember",
		"art": "strangers_hand",
		"choices": [
			{
				"label": "Teach a creature Thorns",
				"desc": "Teach one of your creatures Thorns.",
				"effects": [
					{"type": "grant_keyword_pick", "keyword": "thorns"},
				],
			},
			{
				"blue": {"type": "starters_at_least", "value": 2},
				"label": "Trade starters for better cards",
				"desc": "Choose a starting card. Its copies march off and come back as something better.",
				"effects": [
					{"type": "veteran_swap"},
				],
			},
			{
				"label": "Forge one card",
				"desc": "Forge one card in your deck.",
				"effects": [
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	# ── The Venus throw (keep-and-recast tali against the burial fund) ──

	"the_burial_fund": {
		"presentation": {"layout": "bargain", "focal_uv": Vector2(0.50, 0.55), "zoom": 1.060},
		"name": "The Burial Fund",
		"desc": "The Fourth Legion's standard-bearer guards an unfinished burial fund. Beat his knucklebone throw to win from the box.",
		"mood": "gilt",
		"art": "dark_altar",
		"choices": [
			{
				"label": "Play for 25 gold",
				"desc": "Stake 25 gold. Beat his throw to gain 75 gold. Win with Venus to gain 150 gold.",
				"effects": [
					{"type": "tali_game", "stake": 25, "payout": 75,
						"venus_pay": 150,
						"open_text": "The standard-bearer rolls openly. You each receive one reroll. Select the bones you want to keep, then reroll the rest.",
						# The Old Debt thread: the fund knows its debtors and
						# its lost remittances.
						"seen_texts": {"the_bone_pit": {
							"open_text": "The standard-bearer rolls openly. You each receive one reroll. Select the bones you want to keep, then reroll the rest."},
						"the_couriers_satchel": {
							"open_text": "The standard-bearer rolls openly. You each receive one reroll. Select the bones you want to keep, then reroll the rest."}}},
				],
			},
			{
				"blue": {"type": "fallen_at_least", "value": 1},
				"label": "Buy 4 max HP for 20 gold",
				"desc": "Pay 20 gold. Gain 4 max HP.",
				"effects": [
					{"type": "gold", "value": -20},
					{"type": "gain_max_hp", "value": 4},
				],
			},
			{
				"label": "Buy 6 HP for 10 gold",
				"desc": "Pay 10 gold. Heal 6 HP.",
				"effects": [
					{"type": "gold", "value": -10},
					{"type": "heal", "value": 6},
				],
			},
		],
	},

	# ── The sand-table exam (minesweeper crossing at the sapper school) ──

	"the_proving_ground": {
		"name": "The Proving Ground",
		"desc": "A sapper has hidden three powder charges across five paths on a sand table. Cross as many paths as you can without hitting one.",
		"mood": "verdigris",
		"art": "rotting_carnival",
		"choices": [
			{
				"label": "Play the minefield",
				"desc": "Stake 20 gold. Safe paths pay 10, 25, 45, then 65 gold. Cross all five to win the Slow Match card. Each charge deals 3 damage.",
				"effects": [
					# The school pays a graduate in his own trade: cross the whole
					# table and the master hands over a fuse. Stop short and the
					# tiers pay in coin, as they always did.
					{"type": "field_game", "stake": 20, "charges": 3, "singe": 3,
						"pay": [0, 10, 25, 45, 65, 90],
						"win_effects_at": 90,
						"win_effects": [{"type": "add_card_id", "id": "slow_match"}],
						"lose_effects": [{"type": "gold", "value": 8}],
						"win_text": "You crossed all five paths. The sapper hands you a fuse of his own making.",
						"bank_text": "You lifted your marker after crossing {files} of the five paths.",
						"bust_text": "You stepped on a charge. The sapper keeps the fee and leaves you 8 gold.",
						"open_text": "Five paths hide three charges, with no more than one charge per path. A safe step shows how many charges touch it. A 0 means every neighboring path is safe. Stop after any safe step to keep the current reward.",
						# The Old Debt thread: the derby runs behind the same
						# spoil-heap, and the pit lost a sapper once.
						"seen_texts": {"the_beetle_derby": {
							"open_text": "Five paths hide three charges. A safe step shows how many charges touch it. Stop after any safe step to keep the current reward."},
						"the_bone_pit": {
							"open_text": "Five paths hide three charges. A safe step shows how many charges touch it. Stop after any safe step to keep the current reward."}}},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["the_beetle_derby"]},
				"label": "Play with one charge revealed",
				"desc": "Stake 20 gold. One charge is revealed before you begin.",
				"effects": [
					{"type": "field_game", "stake": 20, "charges": 3, "singe": 3,
						"scout": true,
						"pay": [0, 10, 25, 45, 65, 90],
						"win_effects_at": 90,
						"win_effects": [{"type": "add_card_id", "id": "slow_match"}],
						"lose_effects": [{"type": "gold", "value": 8}],
						"win_text": "You crossed all five paths. The sapper hands you a fuse of his own making.",
						"bank_text": "You lifted your marker after crossing {files} of the five paths.",
						"bust_text": "You stepped on a charge. The sapper keeps the fee and leaves you 8 gold.",
						"open_text": "Five paths hide three charges, but one charge is already marked. A safe step shows how many charges touch it. Stop after any safe step to keep the current reward."},
				],
			},
			{
				"label": "Take 12 gold",
				"desc": "Gain 12 gold.",
				"effects": [
					{"type": "gold", "value": 12},
				],
			},
		],
	},

	# ── Gallows Green (quoits, where the wind is the house) ──

	"the_gibbet_green": {
		"name": "Gallows Green",
		"desc": "Crows have held the gibbet since spring and are not frightened of a column. They watch the packs go by. They are known to trade, and they choose what they take.",
		"mood": "bone",
		"art": "sin_eater",
		"ambience": "wind",
		"choices": [
			{
				"label": "Transform one card",
				"desc": "Choose a card. It goes with the crows, and something of its worth takes the slot.",
				"effects": [
					{"type": "transform_choice", "value": 1},
				],
			},
			{
				"blue": {"type": "act_at_least", "value": 2},
				"label": "Transform two cards",
				"desc": "They know the column by now. Transform two cards.",
				"effects": [
					{"type": "transform_choice", "value": 2},
				],
			},
			{
				"label": "Cut the hanged man down",
				"desc": "The Hanged Man (0/7, Thorns) joins your next fight.",
				"effects": [
					{"type": "gift_creature", "name": "The Hanged Man", "atk": 0, "hp": 7,
						"kw": ["thorns"],
						"text": "The Hanged Man (0/7, Thorns) joins your front row in the next fight."},
				],
			},
		],
	},

	# ── Crown & Pike (Crown-and-Anchor; back a mark, cast three dice) ──
	# NOTE: event KEY retained (`the_drummers_tattoo`) so shared-world threads
	# and map assignments keep resolving; regenerated 2026-07-21 from the old
	# Simon "Drummer's Tattoo" to a readable six-mark dice game. Shares the
	# `three_doors` stand-in for now.

	"the_drummers_tattoo": {
		"name": "Crown & Pike",
		"desc": "Dead sappers play a dice game with six symbols. Choose one symbol, roll three dice, and win more for each match.",
		"mood": "gilt",
		"art": "three_doors",
		"ambience": "wind",
		"choices": [
			{
				"label": "Play Crown & Pike for 15 gold",
				"desc": "Stake 15 gold. One matching die pays x2, two pay x3, and three pay x4. Stop holding 60 or more to win the Battle Drummer card instead.",
				"effects": [
					# Ride the pot to 60 and the sappers pay in their drummer
					# rather than their coin. Under that the pot pays in gold.
					{"type": "crown_game", "stake": 15,
						"win_effects_at": 60,
						"win_effects": [{"type": "add_card_id", "id": "battle_drummer"}],
						"lose_effects": [{"type": "gold", "value": 8}],
						"win_text": "You lift the pot off the drumhead.",
						"bust_text": "No die matched. The sappers keep the pot and stand you 8 gold.",
						"open_text": "Choose one of six symbols, then roll three dice. One matching die doubles the pot, two triple it, and three quadruple it. After a win, take the pot or risk it on another roll.",
						# The Old Debt thread: the board's players know the pit,
						# the watch, the fund, the sentry.
						"seen_texts": {"the_bone_pit": {
							"open_text": "Choose one of six symbols, then roll three dice. Each matching die increases the pot. After a win, take the pot or roll again."},
						"the_short_straw": {
							"open_text": "Choose one of six symbols, then roll three dice. Each matching die increases the pot. After a win, take the pot or roll again."},
						"the_burial_fund": {
							"open_text": "Choose one of six symbols, then roll three dice. Each matching die increases the pot. After a win, take the pot or roll again."},
						"the_sentrys_board": {
							"open_text": "Choose one of six symbols, then roll three dice. Each matching die increases the pot. After a win, take the pot or roll again."}}},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["widows_tray"]},
				"label": "Gain 2 max HP",
				"desc": "Gain 2 max HP.",
				"effects": [
					{"type": "gain_max_hp", "value": 2},
				],
			},
			{
				"label": "Take 8 gold",
				"desc": "Gain 8 gold.",
				"effects": [
					{"type": "gold", "value": 8},
				],
			},
		],
	},

	# ── The Quartermaster's Scale (balance-weighing; find the false coin) ──

	"the_quartermasters_scale": {
		"name": "The Quartermaster's Scale",
		"desc": "The Fourth Legion's quartermaster asks you to find one underweight coin. Use the balance, then name the false coin.",
		"mood": "gilt",
		"art": "the_chrysalis",
		"choices": [
			{
				"label": "Find the light coin",
				"desc": "Stake 18 gold. Find the false coin and the quartermaster issues proper kit to a soldier of your choosing.",
				"effects": [
					# He does not pay in the coin he has just been shown is bad.
					# He pays out of stores: Armored, taught to a chosen soldier.
					{"type": "scale_game", "stake": 18, "coins": 9, "weighings": 3,
						"base": 30, "per_saved": 12,
						"win_effects": [{"type": "grant_keyword_pick",
							"keyword": "armored"}],
						"lose_effects": [{"type": "gold", "value": 8}],
						"win_text": "Correct. The quartermaster will not pay in coin he now knows is light. He opens the stores instead.",
						"poor_text": "Wrong coin. He keeps the stake and returns 8 gold for your trouble.",
						"open_text": "Nine coins are shown; one is lighter. Place coins on the left and right pans, then weigh them. The lighter pan rises. Name the false coin when you are ready. Unused weighings increase the reward.",
						# The Old Debt thread: everyone who handles the Fourth's
						# money knows the coin was bad.
						"seen_texts": {"the_burial_fund": {
							"open_text": "Nine coins are shown; one is lighter. Use the balance, then name the false coin. Unused weighings increase the reward."},
						"the_couriers_satchel": {
							"open_text": "Nine coins are shown; one is lighter. Use the balance, then name the false coin. Unused weighings increase the reward."},
						"old_army_game": {
							"open_text": "Nine coins are shown; one is lighter. Use the balance, then name the false coin. Unused weighings increase the reward."}}},
				],
			},
			{
				"blue": {"type": "pawned_at_least", "value": 1},
				"label": "Play the six-coin version",
				"desc": "Stake 18 gold. Search only six coins for the same reward.",
				"effects": [
					{"type": "scale_game", "stake": 18, "coins": 6, "weighings": 3,
						"base": 30, "per_saved": 12,
						"win_effects": [{"type": "grant_keyword_pick",
							"keyword": "armored"}],
						"lose_effects": [{"type": "gold", "value": 8}],
						"win_text": "Correct. The quartermaster will not pay in coin he now knows is light. He opens the stores instead.",
						"poor_text": "Wrong coin. He keeps the stake and returns 8 gold for your trouble.",
						"open_text": "Six coins are shown; one is lighter. Use the balance, then name the false coin. Unused weighings increase the reward."},
				],
			},
			{
				"label": "Take 10 gold",
				"desc": "Gain 10 gold.",
				"effects": [
					{"type": "gold", "value": 10},
				],
			},
		],
	},

	# ── The Fourth's Strongbox (Mastermind; crack the lost combination) ──

	"the_fourths_strongbox": {
		"name": "The Fourth's Strongbox",
		"desc": "A moneylender is trying to open the Fourth Legion's locked pay chest. Solve the four-number combination to claim a share.",
		"mood": "bone",
		"art": "fattened_sin_eater",
		"choices": [
			{
				"label": "Solve the strongbox",
				"desc": "Stake 20 gold. Open the chest and pay one of your own cards the back-wages the King never paid: forge it.",
				"effects": [
					# The Old Debt, settled. The chest holds the Fourth's unpaid
					# wages; what it buys is a soldier of YOURS, made whole.
					{"type": "box_game", "stake": 20, "marks": 6, "tries": 7,
						"base": 40, "per_saved": 14,
						"win_effects": [{"type": "upgrade_choice"}],
						"lose_effects": [{"type": "gold", "value": 10}],
						"win_text": "The wards fall. A century of back-wages sits in the chest, and one of your soldiers is owed it.",
						"poor_text": "No attempts remain. The code was {code}. The moneylender keeps the stake and returns 10 gold.",
						"open_text": "Set each of four dials to a number from 1 to 6. After each attempt, \"Exact\" means right number and right position; \"Misplaced\" means right number but wrong position. Open the chest in as few attempts as possible.",
						# The Old Debt thread: everyone connected to the Fourth's
						# money has a piece of this box's story.
						"seen_texts": {"the_burial_fund": {
							"open_text": "Set each of four dials to a number from 1 to 6. \"Exact\" means right number and position; \"Misplaced\" means right number but wrong position."},
						"the_couriers_satchel": {
							"open_text": "Set each of four dials to a number from 1 to 6. \"Exact\" means right number and position; \"Misplaced\" means right number but wrong position."},
						"the_bone_pit": {
							"open_text": "Set each of four dials to a number from 1 to 6. \"Exact\" means right number and position; \"Misplaced\" means right number but wrong position."}}},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["old_army_game"]},
				"label": "Solve the easier strongbox",
				"desc": "Stake 20 gold. Each dial uses only numbers 1–5. The reward is unchanged.",
				"effects": [
					{"type": "box_game", "stake": 20, "marks": 5, "tries": 7,
						"base": 40, "per_saved": 14,
						"win_effects": [{"type": "upgrade_choice"}],
						"lose_effects": [{"type": "gold", "value": 10}],
						"win_text": "The wards fall. A century of back-wages sits in the chest, and one of your soldiers is owed it.",
						"poor_text": "No attempts remain. The code was {code}. The moneylender keeps the stake and returns 10 gold.",
						"open_text": "Set each of four dials to a number from 1 to 5. \"Exact\" means right number and position; \"Misplaced\" means right number but wrong position."},
				],
			},
			{
				"label": "Heal 5 HP",
				"desc": "Heal 5 HP.",
				"effects": [
					{"type": "heal", "value": 5},
				],
			},
		],
	},

	# ── The Old Forge (the anvil trade) ──
	# WIRING A FEATURE THAT WAS ALREADY FINISHED (2026-08-29). Everything this
	# event needs shipped long ago and none of it could be reached: the
	# `relic_sacrifice_pick` effect, its picker UI with a "Keep them all" decline
	# path, its no-target reason ("No non-starting relic to trade."), the
	# `has_nonstarting_relic` gate, and `assets/events/old_forge.png` — which two
	# OTHER events had been borrowing as a stand-in for art whose owner did not
	# exist. `tools/_probe_reachability.gd` found it: dispatched, listed in
	# MODAL_EFFECTS, emitted by nothing, exactly the shape of the six dead
	# minigames deleted 2026-08-07 — but with no live replacement, so the fix is
	# to wire it rather than delete it.
	#
	# The key is `old_forge` so the painting resolves by event id and the file is
	# finally OWNED rather than borrowed twice over.
	#
	# Design note carried over from the picker's own comment: the player CHOOSES
	# which relic goes on the anvil. The random-destruction version of this was
	# "the worst feel-bad in the event pool".
	"old_forge": {
		"name": "The Old Forge",
		"desc": "A smith works a roadside forge, and the fire is far hotter than horseshoes need. He will take one thing you carry and hand back something better. He will not say what.",
		"gate": {"type": "has_nonstarting_relic"},
		"mood": "ember",
		"choices": [
			{
				"label": "Lay a relic on the anvil",
				"desc": "Choose one relic to give up. Gain a stronger one in its place.",
				"effects": [
					{"type": "relic_sacrifice_pick"},
				],
			},
			{
				"label": "Keep the road",
				"desc": "Trade nothing and move on.",
				"effects": [],
			},
		],
	},

	# ── The Dead Man's Deal (high-low card climb vs a dead card-sharp) ──
	# NOTE: event KEY retained (`the_powder_move`) so the shared-world threads
	# and map assignments keep resolving; regenerated 2026-07-21 from the old
	# Tower-of-Hanoi "Powder Move" to the readable high-low climb.
	# ART RE-POINTED 2026-08-29: it had been borrowing `old_forge`, which now has
	# a real owner (the Old Forge event above, finally wired). The art ledger in
	# tools/_probe_event_art.gd had already named this event as holding the WEAKER
	# claim on that plate — "it is now 'The Dead Man's Deal', a card game" — so it
	# is the one that moves. `three_doors` reads as a choice among unknowns and
	# already carries Crown & Pike, so the pairing is two roadside games of chance
	# rather than a forge cart standing in for a card table.

	"the_powder_move": {
		"name": "The Dead Man's Deal",
		"desc": "A dead card player offers a game of higher or lower. The remaining numbers are always visible, and each correct call raises the reward.",
		"mood": "gilt",
		"art": "three_doors",
		"choices": [
			{
				"label": "Play Higher or Lower",
				"desc": "Stake 16 gold. Each correct call raises the reward. Call the whole bag correctly to win the Gambit card. One wrong call loses the stake.",
				"effects": [
					# Only emptying the bag takes the sharp's own trick off him.
					# Any earlier stop banks its ladder tier in coin, as before.
					{"type": "deal_game", "stake": 16, "ranks": 9,
						"pay": [0, 7, 16, 28, 44, 66, 96, 140, 200],
						"win_effects_at": 200,
						"win_effects": [{"type": "add_card_id", "id": "gambit"}],
						"lose_effects": [{"type": "gold", "value": 8}],
						"win_text": "You called every remaining number. The sharp deals you his own trick and folds his hands.",
						"bank_text": "You stopped and collected.",
						"poor_text": "Wrong call. The sharp keeps the stake and slides back 8 gold.",
						"open_text": "Call whether the next number will be higher or lower. The remaining numbers are shown, so you can judge the odds. Each correct call raises the reward. Stop at any time or risk it on another call.",
						# The Old Debt thread: the sapper's board and the pit.
						"seen_texts": {"the_proving_ground": {
							"open_text": "Call higher or lower. The remaining numbers are shown. Each correct call raises the reward; one wrong call loses the stake."},
						"the_bone_pit": {
							"open_text": "Call higher or lower. The remaining numbers are shown. Each correct call raises the reward; one wrong call loses the stake."}}},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["the_bone_pit"]},
				"label": "Play the 13-card version",
				"desc": "Stake 16 gold. Play with 13 numbers for a longer game and larger rewards.",
				"effects": [
					{"type": "deal_game", "stake": 16, "ranks": 13,
						"pay": [0, 6, 14, 26, 42, 64, 92, 130, 180, 246, 332, 446, 600],
						"win_effects_at": 600,
						"win_effects": [{"type": "add_card_id", "id": "gambit"}],
						"lose_effects": [{"type": "gold", "value": 8}],
						"win_text": "You called every remaining number. The sharp deals you his own trick and folds his hands.",
						"bank_text": "You stopped and collected.",
						"poor_text": "Wrong call. The sharp keeps the stake and slides back 8 gold.",
						"open_text": "This version uses 13 numbers. Call higher or lower. Each correct call raises the reward; one wrong call loses the stake."},
				],
			},
			{
				"label": "Take 12 gold",
				"desc": "Gain 12 gold.",
				"effects": [
					{"type": "gold", "value": 12},
				],
			},
		],
	},

	# ── The Signal Line (1-D Lights Out; light the beacon-chain) ──
	# NOTE: shares the `hollow_lantern` stand-in (a light in the dark) until
	# bespoke art lands at assets/events/the_signal_line.png.

	"the_signal_line": {
		"name": "The Signal Line",
		"desc": "The beacon chain along the ridge has stood unlit since the King died. The watchman lights it for your column. Somewhere off east, after a long moment, something answers.",
		"mood": "ember",
		"art": "hollow_lantern",
		"ambience": "wind",
		"choices": [
			{
				"label": "Recruit a Lookout",
				"desc": "A watchman comes down off the ridge to march with you. Gain a Lookout.",
				"effects": [
					{"type": "add_card_id", "id": "lookout"},
				],
			},
			{
				"label": "Copy a card in your deck",
				"desc": "Choose a card in your deck. A second copy of it joins the march.",
				"effects": [
					{"type": "copy_card"},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["the_short_straw"]},
				"label": "Answer in the watch's own code",
				"desc": "The Beacon Watch (1/4, Swift) joins your next fight.",
				"effects": [
					{"type": "gift_creature", "name": "The Beacon Watch", "atk": 1, "hp": 4,
						"kw": ["swift"],
						"text": "The Beacon Watch (1/4, Swift) joins your front row in the next fight."},
				],
			},
		],
	},

	"the_sentrys_board": {
		"name": "The Sentry's Post",
		"desc": "A sentry of the Fourth holds a post nobody ever relieved him from. He cannot leave it. He will pay out of its stores for anyone who will stand it in his place.",
		"mood": "bone",
		# Stand-in (shared with the toll-keeper — a lone keeper at his post;
		# bespoke art auto-wins at assets/events/the_sentrys_board.png).
		"art": "tollkeeper_bridge",
		"choices": [
			{
				"label": "Trade a creature for a relic",
				"desc": "Choose a creature. It stays behind, and the post's stores are yours.",
				"effects": [
					{"type": "sacrifice_pick", "reward": "relic",
						"prompt": "Choose a creature to stand the post."},
				],
			},
			{
				"blue": {"type": "fallen_at_least", "value": 1},
				"label": "Recruit a Revenant",
				"desc": "He takes a name where a body will not do. Gain a Revenant.",
				"effects": [
					{"type": "add_card_id", "id": "revenant"},
				],
			},
			{
				"label": "Remove a starting card",
				"desc": "You leave a raw recruit at the post. Remove a starting card.",
				"effects": [
					{"type": "remove_choice_filtered", "filter": "starter"},
				],
			},
		],
	},

	# ── War events (gate: at_war; speak through {kingdom}/{lord}) ──

	"the_siege_kitchen": {
		"presentation": {"layout": "character", "focal_uv": Vector2(0.34, 0.48), "zoom": 1.020, "speaker": "HEAD COOK  //  THE ABANDONED FIELD KITCHEN"},
		"name": "The Siege Kitchen",
		"desc": "{lord}'s army abandoned a field kitchen, but the cooks stayed. They offer food, supplies, and a place in the serving line.",
		"gate": {"type": "at_war"},
		"art": "the_siege_kitchen-character-stage-v2",
		"mood": "ember",
		"ambience": "fire_crackle",
		"choices": [
			{
				"label": "Heal 9 HP",
				"desc": "Heal 9 HP.",
				"effects": [
					{"type": "heal", "value": 9},
				],
			},
			{
				"label": "Recruit the Camp Cook",
				"desc": "The Camp Cook (1/5) joins your next fight.",
				"effects": [
					{"type": "gift_creature", "name": "Camp Cook", "atk": 1, "hp": 5, "kw": [],
						"text": "The Camp Cook (1/5) joins your front row in the next fight."},
				],
			},
			{
				"label": "Gain 55 gold and a Curse",
				"desc": "Gain 55 gold. Add a Curse.",
				"effects": [
					{"type": "gold", "value": 55},
					{"type": "add_curse"},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "kindler"},
				"label": "Forge one card",
				"desc": "Forge a chosen card for free.",
				"effects": [
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	# ══════════════════ NEW — 2026-07-03 pool remake ══════════════════
	# Design bar: one concept per event, and the payoff should touch the BUILD
	# or the FIGHTING (keywords, whole-deck swaps, specific cards, max-HP
	# stakes, next-fight boons) — not just re-price gold/HP/Curse.

	# ── The keyword teacher (pick a school, pick a soldier) ──

	"the_lame_master": {
		"presentation": {"layout": "confrontation", "focal_uv": Vector2(0.52, 0.48), "zoom": 1.055},
		"name": "The Old Drill Master",
		"desc": "A retired drill master offers to teach one creature a permanent keyword. Her paid lessons cost HP.",
		"art": "beekeeper_returns",
		"mood": "ember",
		"choices": [
			{
				"label": "Teach Armored for 4 HP",
				"desc": "Lose 4 HP. A chosen creature permanently gains Armored.",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "grant_keyword_pick", "keyword": "armored",
						"prompt": "Choose a creature to teach Armored"},
				],
			},
			{
				"label": "Teach Swift for 4 HP",
				"desc": "Lose 4 HP. A chosen creature permanently gains Swift.",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "grant_keyword_pick", "keyword": "swift",
						"prompt": "Choose a creature to teach Swift"},
				],
			},
			{
				"label": "Teach Thorns for 4 HP",
				"desc": "Lose 4 HP. A chosen creature permanently gains Thorns.",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "grant_keyword_pick", "keyword": "thorns",
						"prompt": "Choose a creature to teach Thorns"},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "stalwart"},
				"label": "Teach Armored for free",
				"desc": "A chosen creature permanently gains Armored for free.",
				"effects": [
					{"type": "grant_keyword_pick", "keyword": "armored",
						"prompt": "Choose a creature to teach Armored"},
				],
			},
		],
	},

	# ── The whole-deck swap (levies out, veterans in) ──

	"the_free_company": {
		"presentation": {"layout": "location", "focal_uv": Vector2(0.50, 0.58), "zoom": 1.025},
		"name": "The Free Company",
		"desc": "A mercenary company is packing up beside the road. Its recruiter offers to buy starters, trade cards, or sell an uncommon card.",
		"gate": {"type": "starters_at_least", "value": 2},
		"art": "fork_in_the_long_road",
		"mood": "gilt",
		"choices": [
			{
				# Campaign memory: word of a 6-kill veteran travels between camps.
				"blue": {"type": "veteran_kills_at_least", "value": 6},
				"label": "Take 35 gold",
				"desc": "Gain 35 gold.",
				"effects": [
					{"type": "gold", "value": 35},
				],
			},
			{
				"label": "Trade starters for uncommons",
				"desc": "Remove up to 2 copies of one chosen starter. Gain that many random uncommon cards.",
				"effects": [
					{"type": "veteran_swap"},
				],
			},
			{
				"label": "Buy an uncommon card",
				"desc": "Pay 65 gold. Gain a random uncommon card.",
				"effects": [
					{"type": "gold", "value": -65},
					{"type": "add_card", "rarity": "uncommon"},
				],
			},
			{
				"label": "Gain 45 gold and a Curse",
				"desc": "Gain 45 gold. Add a Curse.",
				"effects": [
					{"type": "gold", "value": 45},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── The Curse outlet with scale (mass purge, priced in flesh) ──

	"the_scapegoat": {
		"presentation": {"layout": "ritual", "focal_uv": Vector2(0.50, 0.50), "zoom": 1.035},
		"name": "The Scapegoat",
		"desc": "A village has tied its written sins to a goat. You may use the ritual to remove Curses from your deck.",
		"gate": {"type": "has_curse"},
		"art": "two_headed_calf",
		"mood": "verdigris",
		"choices": [
			{
				"label": "Remove all Curses",
				"desc": "Remove every Curse from your deck. Lose 2 max HP for each Curse removed.",
				"effects": [
					{"type": "purge_curses", "max_hp_per": 2},
				],
			},
			{
				"label": "Remove one Curse for 25 gold",
				"desc": "Pay 25 gold. Remove a chosen Curse.",
				"effects": [
					{"type": "gold", "value": -25},
					{"type": "remove_choice_filtered", "filter": "curse"},
				],
			},
			{
				"label": "Recruit the Scapegoat and add a Curse",
				"desc": "The Scapegoat (1/4) joins your next fight. Add a Curse.",
				"effects": [
					{"type": "gift_creature", "name": "The Scapegoat", "atk": 1, "hp": 4, "kw": [],
						"text": "The Scapegoat (1/4) joins your front row in the next fight. Add a Curse."},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── The all-in gamble (poverty for power) ──

	"the_reliquary_cart": {
		"presentation": {"layout": "bargain", "focal_uv": Vector2(0.52, 0.50), "zoom": 1.060},
		"name": "The Rolling Chapel",
		"desc": "A traveling priest sells blessings and relics from a chapel on wheels. Better rewards cost more.",
		"art": "the_answering_well",
		"mood": "gilt",
		"choices": [
			{
				"blue": {"type": "hero_is", "value": "pyromancer"},
				"label": "Gain 1 max Command next fight",
				"desc": "Gain 1 max Command in the next fight for free.",
				"effects": [
					{"type": "combat_mana", "value": 1,
						"text": "Gain 1 max Command in the next fight."},
				],
			},
			{
				"blue": {"type": "gold_at_least", "value": 120},
				"label": "Trade all gold for a boss relic",
				"desc": "Lose all your gold. Gain a boss-tier relic.",
				"effects": [
					{"type": "lose_gold_partial", "value": 99999},
					{"type": "add_boss_relic"},
				],
			},
			{
				"label": "Pay 25 gold",
				"desc": "Pay 25 gold. Gain 1 max Command in the next fight.",
				"effects": [
					{"type": "gold", "value": -25},
					{"type": "combat_mana", "value": 1,
						"text": "Gain 1 max Command in the next fight."},
				],
			},
			{
				"label": "Risk the chapel's poor-box",
				"desc": "Either gain 85 gold and add a Curse, or lose 7 HP and gain 35 gold.",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "You break the chain and escape. Gain 85 gold and add a Curse.",
							"effects": [{"type": "gold", "value": 85}, {"type": "add_curse"}]},
						{"weight": 1,
							"text": "The priest stops you. Lose 7 HP and gain 35 gold.",
							"effects": [{"type": "damage", "value": 7}, {"type": "gold", "value": 35}]},
					]},
				],
			},
		],
	},

	# ── The fallen paid forward (campaign-memory payoff) ──

	"the_bell_of_names": {
		"presentation": {"layout": "ritual", "focal_uv": Vector2(0.35, 0.52), "zoom": 1.060},
		"name": "The Bell of Names",
		"desc": "A bell-maker offers rewards based on the number of names in your Roll of the Fallen.",
		"gate": {"type": "fallen_at_least", "value": 2},
		"art": "drowned_bell",
		"mood": "ember",
		"choices": [
			{
				"label": "Gain max HP for the fallen",
				"desc": "Gain 1 max HP for each name on your Roll of the Fallen, up to 6.",
				"effects": [
					{"type": "scaled", "count": "fallen", "per": 1, "cap": 6, "outcome": "max_hp"},
				],
			},
			{
				"label": "Take 40 gold",
				"desc": "Gain 40 gold.",
				"effects": [
					{"type": "gold", "value": 40},
				],
			},
			{
				"label": "Gain 1 max Command next fight",
				"desc": "Gain 1 max Command in the next fight.",
				"effects": [
					{"type": "combat_mana", "value": 1,
						"text": "Gain 1 max Command in the next fight."},
				],
			},
		],
	},

	# ── The hp-gated heal, with teeth (enemy mercy) ──

	"the_chirurgeon": {
		"presentation": {"layout": "confrontation", "focal_uv": Vector2(0.52, 0.50), "zoom": 1.050},
		"name": "The Enemy Surgeon",
		"desc": "An enemy surgeon offers treatment and supplies in an abandoned field hospital.",
		"gate": {"type": "hp_below_pct", "value": 0.5},
		"art": "tooth_witch",
		"mood": "verdigris",
		"choices": [
			{
				"label": "Heal to full and add a Wound",
				"desc": "Heal to full. Add a Wound.",
				"effects": [
					{"type": "heal_full"},
					{"type": "add_curse_id", "id": "wound"},
				],
			},
			{
				"label": "Buy two potions",
				"desc": "Pay 35 gold. Gain two random potions.",
				"effects": [
					{"type": "gold", "value": -35},
					{"type": "gain_potion_random"},
					{"type": "gain_potion_random"},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "acolyte"},
				"label": "Heal 9 HP",
				"desc": "Heal 9 HP for free.",
				"effects": [
					{"type": "heal", "value": 9},
				],
			},
			{
				"label": "Leave",
				"desc": "No effect.",
				"effects": [],
			},
		],
	},

	# ── The clean exhale (life insists, mid-war) ──

	"the_wedding_at_the_ford": {
		"presentation": {"layout": "location", "focal_uv": Vector2(0.55, 0.55), "zoom": 1.030},
		"name": "The Wedding at the Ford",
		"desc": "Two damaged villages are holding a wedding at the river. As the only armed guest, you are invited to take part.",
		"art": "thrice_blessed_spring",
		"mood": "ember",
		"choices": [
			{
				"label": "Heal 8 HP and gain 15 gold",
				"desc": "Heal 8 HP. Gain 15 gold.",
				"effects": [
					{"type": "heal", "value": 8},
					{"type": "gold", "value": 15},
				],
			},
			{
				"label": "Risk the sword-dance",
				"desc": "Either gain 35 gold, or lose 2 HP and gain a potion.",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "You complete the dance. Gain 35 gold.",
							"effects": [{"type": "gold", "value": 35}]},
						{"weight": 1,
							"text": "You fall into the river. Lose 2 HP and gain a potion.",
							"effects": [{"type": "damage", "value": 2}, {"type": "gain_potion"}]},
					]},
				],
			},
			{
				"label": "Buy 4 max HP for 30 gold",
				"desc": "Pay 30 gold. Gain 4 max HP.",
				"effects": [
					{"type": "gold", "value": -30},
					{"type": "gain_max_hp", "value": 4},
				],
			},
		],
	},

	# ── War comedy: the arms dealer (gate: at_war) ──

	"the_ladder_merchant": {
		"presentation": {"layout": "bargain", "focal_uv": Vector2(0.35, 0.50), "zoom": 1.070},
		"name": "The Ladder-Merchant",
		"desc": "A merchant sells siege equipment between the two armies. He claims {lord} bought the inferior stock.",
		"gate": {"type": "at_war"},
		# Stand-in: the forge cart — the closest fit for an arms dealer's rig.
		"art": "old_forge",
		"mood": "gilt",
		"choices": [
			{
				"label": "Recruit the Patent Ladder",
				"desc": "Pay 30 gold. The Patent Ladder (0/7, Armored) joins your next fight.",
				"effects": [
					{"type": "gold", "value": -30},
					{"type": "gift_creature", "name": "Patent Ladder", "atk": 0, "hp": 7,
						"kw": ["armored"],
						"text": "The Patent Ladder (0/7, Armored) joins your front row in the next fight."},
				],
			},
			{
				"label": "Buy a random relic",
				"desc": "Pay 70 gold. Gain a random relic.",
				"effects": [
					{"type": "gold", "value": -70},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Gain 50 gold and a Curse",
				"desc": "Gain 50 gold. Add a Curse.",
				"effects": [
					{"type": "gold", "value": 50},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── The named-card payoff (grim; pays Old Bones by name) ──

	"the_last_garrison": {
		"presentation": {"layout": "location", "focal_uv": Vector2(0.52, 0.55), "zoom": 1.030},
		"name": "The Last Garrison",
		"desc": "Five dead soldiers still guard an abandoned fort. They will accept new orders if you claim to speak for the Old King.",
		"gate": {"type": "act_at_least", "value": 2},
		"art": "plague_bell",
		"mood": "bone",
		"choices": [
			{
				"label": "Gain Old Bones and a Grave-Debt",
				"desc": "Gain Old Bones, a rare card. Add a Grave-Debt.",
				"effects": [
					{"type": "add_card_id", "id": "old_bones"},
					{"type": "add_curse_id", "id": "grave_debt"},
				],
			},
			{
				"label": "Trade 5 HP for 55 gold",
				"desc": "Gain 55 gold. Lose 5 HP.",
				"effects": [
					{"type": "gold", "value": 55},
					{"type": "damage", "value": 5},
				],
			},
			{
				"label": "Recruit a Garrison Shade",
				"desc": "A Garrison Shade (2/5, Last Stand) joins your next fight.",
				"effects": [
					{"type": "gift_creature", "name": "Garrison Shade", "atk": 2, "hp": 5,
						"kw": ["last_stand"],
						"text": "A Garrison Shade (2/5, Last Stand) joins your front row in the next fight."},
				],
			},
		],
	},

	# ── The transform verb's home (funny livestock register) ──

	"the_remount_fair": {
		"presentation": {"layout": "bargain", "focal_uv": Vector2(0.62, 0.50), "zoom": 1.050},
		"name": "The War-Horse Fair",
		"desc": "Horse traders offer card purchases and transformations behind the lines. Their deals are final.",
		"art": "hermit",
		"mood": "ember",
		"choices": [
			{
				"blue": {"type": "hero_is", "value": "raider"},
				"label": "Buy an uncommon card",
				"desc": "Pay 20 gold. Gain a random uncommon card.",
				"effects": [
					{"type": "gold", "value": -20},
					{"type": "add_card", "rarity": "uncommon"},
				],
			},
			{
				"label": "Transform one card",
				"desc": "Transform a chosen card into a random card of the same rarity.",
				"effects": [
					{"type": "transform_choice", "value": 1},
				],
			},
			{
				"label": "Transform two cards for 4 HP",
				"desc": "Lose 4 HP. Transform two chosen cards.",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "transform_choice", "value": 2},
				],
			},
			{
				"label": "Buy an uncommon card",
				"desc": "Pay 45 gold. Gain a random uncommon card.",
				"effects": [
					{"type": "gold", "value": -45},
					{"type": "add_card", "rarity": "uncommon"},
				],
			},
		],
	},

	# ── The eerie max-HP wager ──

	"the_kings_measure": {
		"name": "The King's Measure",
		"desc": "A royal surveyor measures the road, then asks to measure you. His record can permanently raise or lower your max HP.",
		"art": "marked_one",
		"mood": "bone",
		"choices": [
			{
				"label": "Risk your max HP",
				"desc": "Either gain 4 max HP or lose 2 max HP.",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 3,
							"text": "The surveyor increases your recorded size. Gain 4 max HP.",
							"effects": [{"type": "gain_max_hp", "value": 4}]},
						{"weight": 2,
							"text": "The surveyor reduces your recorded size. Lose 2 max HP.",
							"effects": [{"type": "lose_max_hp", "value": 2}]},
					]},
				],
			},
			{
				"label": "Trade 3 HP for 45 gold",
				"desc": "Lose 3 HP. Gain 45 gold.",
				"effects": [
					{"type": "damage", "value": 3},
					{"type": "gold", "value": 45},
				],
			},
			{
				"label": "Add a Curse and forge a card",
				"desc": "Add a Curse. Forge a chosen card.",
				"effects": [
					{"type": "add_curse"},
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	# ══════════════════ NEW — 2026-07-04 additions ══════════════════
	# One build-reader (the scaled engine pays spells, gated so a deck
	# without the material never rolls it), two act-3 heavyweights (the
	# road before the last keep), and a second hidden+tell room so
	# tell-reading stays a skill past act 1.

	# ── The build-reader: he pays for what your magic did (scaled: spells) ──

	"the_war_poet": {
		"presentation": {"layout": "location", "focal_uv": Vector2(0.50, 0.48), "zoom": 1.030},
		"name": "The War-Poet",
		"desc": "A poet wants stories about your spells. He pays according to how many spells are in your deck.",
		"gate": {"type": "deck_count_at_least", "kind": "spells", "value": 2},
		"art": "woodcutter",
		"mood": "gilt",
		"choices": [
			{
				"label": "Gain gold for each spell",
				"desc": "Gain 6 gold for each spell in your deck, up to 60.",
				"effects": [
					{"type": "scaled", "count": "spells", "per": 6, "cap": 60,
						"outcome": "gold"},
				],
			},
			{
				"label": "Risk 70 gold or Craven",
				"desc": "Either gain 70 gold or add Craven.",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "The poet believes your story. Gain 70 gold.",
							"effects": [{"type": "gold", "value": 70}]},
						{"weight": 1,
							"text": "The poet mocks your story. Add Craven.",
							"effects": [{"type": "add_curse_id", "id": "craven"}]},
					]},
				],
			},
			{
				"blue": {"type": "fallen_at_least", "value": 1},
				"label": "Honor {fallen}",
				"desc": "Gain 25 gold. Heal 6 HP.",
				"effects": [
					{"type": "gold", "value": 25},
					{"type": "heal", "value": 6},
				],
			},
		],
	},

	# ── Act 3: the army lightens for the last climb ──

	"the_ninth_milestone": {
		"presentation": {"layout": "location", "focal_uv": Vector2(0.52, 0.50), "zoom": 1.030},
		"name": "The Ninth Milestone",
		"desc": "Armies discard supplies beside the ninth milestone before the final climb. You can leave cards behind or search what others abandoned.",
		"gate": {"type": "act_at_least", "value": 3},
		"art": "the_weeping_orchard",
		"mood": "bone",
		"choices": [
			{
				"label": "Remove two cards",
				"desc": "Remove two chosen cards.",
				"effects": [
					{"type": "remove_choice_multi", "value": 2},
				],
			},
			{
				"label": "Take a relic and a Grave-Debt",
				"desc": "Gain a random relic. Add a Grave-Debt.",
				"effects": [
					{"type": "random_relic"},
					{"type": "add_curse_id", "id": "grave_debt"},
				],
			},
			{
				"label": "Gain 1 max Command next fight",
				"desc": "Gain 1 max Command in the next fight.",
				"effects": [
					{"type": "combat_mana", "value": 1,
						"text": "Gain 1 max Command in the next fight."},
				],
			},
		],
	},

	# ── Act 3, at war: one of the five sees the ending coming ──

	"the_turncoat_general": {
		"presentation": {"layout": "confrontation", "focal_uv": Vector2(0.65, 0.52), "zoom": 1.050},
		"name": "The Turncoat General",
		"desc": "One of {lord}'s officers offers to defect from {kingdom}. He wants protection before your victory.",
		"gate": {"type": "all", "gates": [
			{"type": "at_war"},
			{"type": "act_at_least", "value": 3},
		]},
		"art": "mirror_twin",
		"mood": "ember",
		"choices": [
			{
				"label": "Recruit the Turncoat General",
				"desc": "The Turncoat General (3/6) joins your next fight. Add a War-Debt.",
				"effects": [
					{"type": "gift_creature", "name": "Turncoat General", "atk": 3, "hp": 6,
						"kw": [],
						"text": "The Turncoat General (3/6) joins your front row in the next fight. Add a War-Debt."},
					{"type": "add_curse_id", "id": "war_debt"},
				],
			},
			{
				"label": "Buy 1 max Command next fight",
				"desc": "Pay 45 gold. Gain 1 max Command in the next fight.",
				"effects": [
					{"type": "gold", "value": -45},
					{"type": "combat_mana", "value": 1,
						"text": "Gain 1 max Command in the next fight."},
				],
			},
			{
				"label": "Gain 50 gold and a Deserter's Mark",
				"desc": "Gain 50 gold. Add a Deserter's Mark.",
				"effects": [
					{"type": "gold", "value": 50},
					{"type": "add_curse_id", "id": "deserters_mark"},
				],
			},
		],
	},

	# ── Hidden-info #2 (act 2+): the tells stay a skill past the carnival ──

	"the_drowned_ferry": {
		"presentation": {"layout": "location", "focal_uv": Vector2(0.50, 0.48), "zoom": 1.030},
		"name": "The Drowned Ferry",
		"desc": "Three ferrymen offer to cross a lake that is not marked on your map. Each landing hides a different outcome.",
		"gate": {"type": "act_at_least", "value": 2},
		"art": "hollow_lantern",
		"mood": "verdigris",
		"choices": [
			{
				"hidden": true,
				"tell": "First boat: it sits low in the water and is patched with coffin wood. The ferryman keeps bailing.",
				"desc": "Hidden",
				"effects": [
					{"type": "add_rare"},
					{"type": "add_curse_id", "id": "grave_debt"},
				],
			},
			{
				"hidden": true,
				"tell": "Second boat: it is dry and filled with open birdcages. The ferryman looks well fed.",
				"desc": "Hidden",
				"effects": [
					{"type": "lose_gold_partial", "value": 25},
					{"type": "transform_choice", "value": 1},
				],
			},
			{
				"hidden": true,
				"tell": "Third boat: it floats slightly above the water. The ferryman's pole comes up dry.",
				"desc": "Hidden",
				"effects": [
					{"type": "random_relic"},
					{"type": "damage", "value": 5},
				],
			},
		],
	},

	# ══════════════════ NEW — 2026-07-07 visual-diversity pass ══════════════════
	# These five are designed AROUND the strongest unused paintings (the art is
	# the brief, per the art-sourcing standard): the pool's only golden-daylight
	# canvas, the burning apiary, the blood basin, the cocoon barn, and the
	# glass cat. One concept per event, payoffs touch the build or the fighting.

	# ── The bee-wife (part 1 of 2): the road's one warm afternoon ──

	"the_bee_wife": {
		"presentation": {"layout": "confrontation", "focal_uv": Vector2(0.52, 0.50), "zoom": 1.055},
		"name": "The Bee-Wife",
		"desc": "A beekeeper moving her hives away from the war stops beside your army. She offers honey, supplies, and a place for one hive.",
		"art": "beekeeper_again",
		"mood": "gilt",
		"ambience": "bees",
		"choices": [
			{
				"label": "Recruit a Straw Hive",
				"desc": "Pay 25 gold. The Straw Hive (0/5, Thorns) joins your next fight.",
				"effects": [
					{"type": "gold", "value": -25},
					{"type": "gift_creature", "name": "Straw Hive", "atk": 0, "hp": 5,
						"kw": ["thorns"],
						"text": "The Straw Hive (0/5, Thorns) joins your front row in the next fight."},
				],
			},
			{
				# Campaign memory: the old custom — deaths must be told to the bees.
				"blue": {"type": "fallen_at_least", "value": 1},
				"label": "Heal 8 HP and gain a Healing Potion",
				"desc": "Heal 8 HP. Gain a Healing Potion.",
				"effects": [
					{"type": "heal", "value": 8},
					{"type": "gain_potion"},
				],
			},
			{
				"label": "Heal 7 HP",
				"desc": "Heal 7 HP.",
				"effects": [
					{"type": "heal", "value": 7},
				],
			},
			{
				"label": "Gain 40 gold and a Curse",
				"desc": "Gain 40 gold. Add a Curse.",
				"effects": [
					{"type": "gold", "value": 40},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── The bee-wife (part 2 of 2): the war reached her anyway ──

	"the_burned_apiary": {
		"presentation": {"layout": "location", "focal_uv": Vector2(0.70, 0.52), "zoom": 1.035},
		"name": "The Burned Bee-Yard",
		"desc": "You find the beekeeper's yard burned down. Her surviving swarm can join your next fight, and she needs help searching the ashes.",
		"gate": {"type": "all", "gates": [
			{"type": "act_at_least", "value": 2},
			{"type": "seen_all", "events": ["the_bee_wife"]},
		]},
		"art": "beekeeper",
		"mood": "ember",
		"ambience": "fire_crackle",
		"choices": [
			{
				"label": "Recruit the Swarm",
				"desc": "The Swarm (3/1, Swift) joins your next fight.",
				"effects": [
					{"type": "gift_creature", "name": "The Swarm", "atk": 3, "hp": 1,
						"kw": ["swift"],
						"text": "The Swarm (3/1, Swift) joins your front row in the next fight."},
				],
			},
			{
				"label": "Search the ashes",
				"desc": "Either heal 8 HP and gain a potion, or gain 25 gold.",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "You find the queen alive. Heal 8 HP and gain a potion.",
							"effects": [{"type": "heal", "value": 8}, {"type": "gain_potion"}]},
						{"weight": 1,
							"text": "You do not find the queen. Gain 25 gold for helping.",
							"effects": [{"type": "gold", "value": 25}]},
					]},
				],
			},
			{
				"label": "Buy 3 max HP for 30 gold",
				"desc": "Pay 30 gold. Gain 3 max HP.",
				"effects": [
					{"type": "gold", "value": -30},
					{"type": "gain_max_hp", "value": 3},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "kindler"},
				"label": "Gain 1 max Command next fight",
				"desc": "Gain 1 max Command in the next fight.",
				"effects": [
					{"type": "combat_mana", "value": 1,
						"text": "You identify the army that burned the yard. Gain 1 max Command in the next fight."},
				],
			},
		],
	},

	# ── The flesh-priced forge (the well converts between flesh and steel) ──

	"the_red_tithe": {
		"presentation": {"layout": "bargain", "focal_uv": Vector2(0.50, 0.52), "zoom": 1.060},
		"name": "The Blood Tax",
		"desc": "A red well trades health for forges and cards for max HP. It can also fill a potion flask.",
		"art": "blood_fountain",
		"mood": "ember",
		"choices": [
			{
				"label": "Lose 3 max HP and forge two cards",
				"desc": "Lose 3 max HP. Forge two chosen cards.",
				"effects": [
					{"type": "lose_max_hp", "value": 3},
					{"type": "upgrade_choice_multi", "value": 2},
				],
			},
			{
				"label": "Remove a card and gain 3 max HP",
				"desc": "Remove a chosen card. Gain 3 max HP.",
				"effects": [
					{"type": "gain_max_hp", "value": 3},
					{"type": "remove_choice"},
				],
			},
			{
				"label": "Trade 4 HP for a potion",
				"desc": "Lose 4 HP. Gain a random potion.",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "gain_potion_random"},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "acolyte"},
				"label": "Forge one card",
				"desc": "Forge a chosen card for free.",
				"effects": [
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	# ── The cocoon barn (act 2+; the gamble is what hatches, never whether) ──

	"the_chrysalis": {
		"presentation": {"layout": "ritual", "focal_uv": Vector2(0.55, 0.52), "zoom": 1.035},
		"name": "The Cocoon Barn",
		"desc": "Large cocoons fill an abandoned barn. You can take one into the next fight, or strip the silk for gold.",
		"gate": {"type": "act_at_least", "value": 2},
		"mood": "verdigris",
		"choices": [
			{
				"label": "Recruit one cocoon creature",
				"desc": "Your next fight begins with either The Hatched (4/2, Swift) or The Half-Made (1/4).",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 3,
							"text": "The cocoon hatches during the next fight. The Hatched (4/2, Swift) joins your front row.",
							"effects": [{"type": "gift_creature", "name": "The Hatched",
								"atk": 4, "hp": 2, "kw": ["swift"],
								"text": "The Hatched (4/2, Swift) joins your front row in the next fight."}]},
						{"weight": 2,
							"text": "The cocoon hatches early. The Half-Made (1/4) joins your front row in the next fight.",
							"effects": [{"type": "gift_creature", "name": "The Half-Made",
								"atk": 1, "hp": 4, "kw": [],
								"text": "The Half-Made (1/4) joins your front row in the next fight."}]},
					]},
				],
			},
			{
				# Campaign memory, at its least comfortable.
				"blue": {"type": "fallen_at_least", "value": 1},
				"label": "Recruit The Almost and add a Curse",
				"desc": "The Almost (2/4) joins your next fight. Add a Curse.",
				"effects": [
					{"type": "gift_creature", "name": "The Almost", "atk": 2, "hp": 4,
						"kw": [],
						"text": "The Almost (2/4) joins your front row in the next fight. Add a Curse."},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Take 40 gold",
				"desc": "Gain 40 gold.",
				"effects": [
					{"type": "gold", "value": 40},
				],
			},
		],
	},

	# ── The glass cat (perfect memory sold by the copy) ──

	"the_glass_familiar": {
		"presentation": {"layout": "ritual", "focal_uv": Vector2(0.72, 0.62), "zoom": 1.060},
		"name": "The Glass Cat",
		"desc": "A glass cat can copy one card in your deck. It may also join your next fight if you take a risk.",
		"art": "glass_familiar",
		"mood": "verdigris",
		"choices": [
			{
				"label": "Pay 45 gold to copy a card",
				"desc": "Pay 45 gold. Add a copy of a chosen card to your deck.",
				"effects": [
					{"type": "gold", "value": -45},
					{"type": "copy_card"},
				],
			},
			{
				# Campaign memory: it has been watching the column, the way cats do.
				"blue": {"type": "veteran_kills_at_least", "value": 6},
				"label": "Copy {veteran} for free",
				"desc": "Add a copy of a chosen card for free.",
				"effects": [
					{"type": "copy_card"},
				],
			},
			{
				"label": "Risk the Glass Cat or a Curse",
				"desc": "Either the Glass Cat (1/1, Thorns) joins your next fight or you add a Curse.",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "The Glass Cat (1/1, Thorns) joins your front row in the next fight.",
							"effects": [{"type": "gift_creature", "name": "Glass Cat",
								"atk": 1, "hp": 1, "kw": ["thorns"],
								"text": "The Glass Cat (1/1, Thorns) joins your front row in the next fight."}]},
						{"weight": 1,
							"text": "The glass cracks. Add a Curse.",
							"effects": [{"type": "add_curse"}]},
					]},
				],
			},
			{
				"label": "Take 15 gold",
				"desc": "Gain 15 gold.",
				"effects": [
					{"type": "gold", "value": 15},
				],
			},
		],
	},
}
