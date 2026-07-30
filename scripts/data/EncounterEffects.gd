extends Node
## EncounterEffects.gd — encounter passive + reactive dispatchers.
##
## All effect logic lives here as static functions taking ctx (the Combat
## instance). Mirrors the KeywordEffects.gd pattern. Combat.gd holds thin
## wrapper functions named `_dispatch_*` that forward here, so existing call
## sites scattered through the combat loop don't have to change.
##
## State accessed via ctx — _reactive_passive, _encounter_passive,
## _player_draw_pile/discard, _hand, enemy_hp/max, round_number,
## _boss_phases/_boss_current_phase, _bonus_mana_next_turn, etc.


## ── Retargeting clock damage onto the BOARD ──────────────────────────────────
## 2026-07-28. A pile of encounter passives read "end of round: take N" — damage
## on a pure clock, with no input the player could offer. Counted across a bad
## Act 1 route that came to ~40 unavoidable face damage against 30 max HP, which
## is not difficulty, it is a toll. These helpers move that damage onto the
## board, where it becomes something the player can answer with positioning,
## healing, walls, and trades.
##
## `strike_the_champion` is the preferred shape: it lands on the biggest thing
## you have. That reads as the enemy behaving intelligently, AND it is standing
## pressure against piling every buff onto one creature — the exact loop that
## made fights feel like "one giant stat stick plus chaff".
##
## An empty board still pays, or clearing your own line would be a free dodge.
static func strike_the_champion(ctx, amount: int, msg: String = "") -> void:
	var target = ctx._highest_atk_player_creature()
	if target != null and is_instance_valid(target) and target.current_hp > 0:
		target.take_damage(amount)
		if msg != "":
			ctx._show_info(msg)
		return
	# Nothing standing — the blow lands on you. from_effect=false so the game's
	# own anti-face-damage answers (Shieldmaiden's interpose, Portcullis, wall
	# passives) are actually allowed to fire; every call site here used to
	# default it true, which switched those cards off against exactly this
	# damage.
	#
	# The caller's line named a champion that isn't there, so it would now be a
	# lie — but staying silent is the OTHER failure (a face hit with no cause).
	# Say what actually happened instead, and only when the caller meant to speak.
	if msg != "":
		ctx._show_info("Nothing stands to take it — the blow lands on you.")
	ctx.damage_player_hero(amount, false)


## Chip the front rank — the line standing on the ground that is shaking/burning.
static func strike_the_line(ctx, amount: int, msg: String = "") -> void:
	var struck := 0
	for c in ctx._row_array(false, ctx.ROW_FRONT):
		if c != null and is_instance_valid(c) and c.current_hp > 0:
			c.take_damage(amount)
			struck += 1
	if struck > 0:
		if msg != "":
			ctx._show_info(msg)
		return
	if msg != "":
		ctx._show_info("Nothing stands to take it — the blow lands on you.")
	ctx.damage_player_hero(amount, false)


## ── Naming the enemy's hand ──────────────────────────────────────────────────
## 2026-07-29, from COMBAT_LEGIBILITY_20260728.md §4 items 5 and 6. The audit's
## verdict on this file: stats moved across the enemy line, bodies appeared, and
## cards left the player's deck with no cause ever named — and an unexplained
## state change does not read as a clever opponent, it reads as the game
## cheating. Combat._dispatch_reactive does punch the standing-rule plaque, but
## that is one 10% scale pop on a corner panel AND it rides Motion.punch, which
## returns early under Reduce Motion — so it cannot carry this on its own.
##
## Two rules keep the fix from becoming its own noise problem (the callout layer
## is a QUANTITY problem — every new chip competes with every other one):
##
##   1. If the change already floats its own number, add the CAUSE ONCE and no
##      second number. A moving ATK/HP seal is floated and punched by
##      Card2D.update_stat_display; damage floats from take_damage; a face hit
##      already shakes, floats, flashes AND logs inside damage_player_hero.
##   2. If the change floats NOTHING — a body arriving, a card exiled, a Curse
##      posted into the discard — it gets its own line, because otherwise there
##      is nothing on screen at all.
##
## And nothing here announces a beat that did not happen: every announce is
## guarded on the effect actually landing, the same rule the wall and spore lines
## already follow, and the same reason Combat skips the lane dwell on a column
## where nothing swings.
##
## Deliberately still silent: `face_damage` / `face_damage_per_draw`. Face damage
## is the loudest beat in the game (shake + vignette + big number + a log row)
## and the fight's rule is printed on the plaque that just pulsed. A sentence on
## top of that is noise, not honesty.


## A body joined the enemy line. Summons are the one board change with no float
## of their own — a creature simply exists that did not before — so they get a
## beat of their own.
##
## 2026-07-29: that beat is now ON THE ARRIVING BODY. This used to take a `before`
## count sampled ahead of the summon and compare enemy-board sizes afterwards,
## because _summon_enemy_token returned void — arithmetic that could only ever
## produce a caption in the middle of the screen, detached from the thing it was
## describing, and that competed for the info queue with everything else the round
## had to say (necro_death_summon fires once per corpse: three deaths in one clash
## spent the whole flush on it). The helpers return the placed Card2D now, so the
## SUMMONED chip lands on the creature itself and the flavour goes where a record
## belongs — the chronicle, with the new body's own thumbnail beside it.
##
## `card` is null when the board had no seat for the arrival (full, closed or
## salted ground) or when the body died on landing. Naming an arrival that never
## arrived is the same lie pointed the other way, so that case stays silent.
static func announce_arrival(ctx, card, msg: String) -> void:
	if card == null or not is_instance_valid(card) or card.current_hp <= 0:
		return
	ctx.spawn_keyword_callout_kw(card, "summoned")
	ctx._log_event(msg, ctx._log_data(card), ctx._log_side(card))


## A card leaving the draw pile forever. The audit rated this the worst silence
## in the file: it happens face-down, off screen, and the only trace is a pile
## counter reading one lower — so "where did my Bulwark go" had no answer
## anywhere in the game. Name the card out loud AND write it into the chronicle
## with its own thumbnail, so the record survives the two seconds on screen.
static func exile_top_draw(ctx) -> void:
	if ctx._player_draw_pile.is_empty():
		return
	var entry = ctx._player_draw_pile.pop_front()
	var data: Dictionary = ctx._resolve_card_data(
		ctx._entry_id(entry), ctx._entry_uid(entry))
	var lost := String(data.get("name", "a card"))
	ctx._show_info("The foe reads your draw pile — %s is exiled." % lost)
	ctx._log_event("The foe exiles %s from your draw pile — gone from this fight."
		% lost, data, 0)


## Curses posted straight into the discard pile are the mirror image of an exile:
## the player's deck changes without the player, off screen, with nothing to see.
## Same treatment — say it once, and put it in the record.
static func post_curses(ctx, count: int, msg: String) -> void:
	if count <= 0:
		return
	for _i in count:
		ctx._player_discard_pile.append(CardDB.random_curse_id())
	ctx._show_info(msg)
	ctx._log_event(msg)


static func dispatch_reactive(ctx, trigger: String, source_card, _lane_idx: int) -> void:
	## Reactive passive: fires on a player action (spell, sacrifice, floop,
	## summon, draw, or creature death).
	##
	## Every arm below used to change the board and say nothing (§4 #5). See the
	## "Naming the enemy's hand" block above for the rules the signals follow.
	if ctx._reactive_passive.is_empty():
		return
	if ctx._reactive_passive.get("trigger", "") != trigger:
		return
	var effect = ctx._reactive_passive.get("effect", "")
	match effect:
		"buff_chieftain_atk":
			for c in ctx._all_enemy_creatures():
				if c.card_data.get("name", "") == "Chieftain":
					c.current_atk += 1
					c.update_stat_display()
					# The +1 already floats off his seal; WHO grew, and why, was
					# the missing half. Name it, don't re-print the number.
					ctx._show_info("The Chieftain takes heart — +1 ATK.")
					ctx._log_event("%s takes heart: [color=#f2e6c8]+1 ATK[/color]."
						% ctx._log_card_ref(c), ctx._log_data(c), ctx._log_side(c))
					break
		"double_on_death":
			# Necromancer Tower: re-fire the dying card's on_death once more.
			# Run the effect directly (not via dispatch_on_death) to avoid the
			# reactive loop calling itself.
			if source_card != null and is_instance_valid(source_card):
				var data: Dictionary = source_card.card_data
				if not data.is_empty() and data.has("on_death"):
					# Spoken BEFORE the re-run, so the sentence arrives ahead of
					# the effect it explains. The second firing is pixel-identical
					# to the first, so unannounced it reads as a double-resolve bug
					# rather than the fight's own rule.
					ctx._show_info("The death echoes — %s fires On-Death again."
						% String(data.get("name", "it")))
					ctx._log_event("%s dies twice over — its On-Death fires again."
						% ctx._log_card_ref(source_card),
						ctx._log_data(source_card), ctx._log_side(source_card))
					KeywordEffects._run_on_death(data.on_death, _lane_idx, true, ctx)
		"face_damage":
			# Left unannounced on purpose — see the block above.
			ctx.damage_player_hero(ctx._reactive_passive.get("value", 2))
		"damage_flooper":
			var value = ctx._reactive_passive.get("value", 1)
			if source_card != null and is_instance_valid(source_card):
				# take_damage floats the number; this names the hand behind it.
				ctx._show_info("%s pays for the ability — %d damage."
					% [String(source_card.card_data.get("name", "Your creature")), value])
				source_card.take_damage(value)
		"summon_puppet":
			announce_arrival(ctx, ctx._summon_enemy_token(
					ctx._reactive_passive.get("atk", 2),
					ctx._reactive_passive.get("hp", 2)),
				"Strings go taut — a Puppet is cut free.")
		"heal_all_enemies":
			var value = ctx._reactive_passive.get("value", 1)
			var mended := 0
			for c in ctx._all_enemy_creatures():
				var was: int = c.current_hp
				c.current_hp = mini(c.current_hp + value, c.card_data.hp)
				c.update_stat_display()
				if c.current_hp > was:
					mended += 1
			# Each mend floats its own "+N HP" off the seal — only the cause was
			# missing. Silent on an already-whole line: nothing happened there.
			if mended > 0:
				ctx._show_info("The enemy line closes its wounds.")
		"face_damage_per_draw":
			# Left unannounced on purpose — this fires on EVERY draw, and the face
			# plaque already shakes, floats and logs each one.
			ctx.damage_player_hero(1)
		"summon_shard":
			var atk = ctx._reactive_passive.get("atk", 1)
			var hp = ctx._reactive_passive.get("hp", 1)
			announce_arrival(ctx, ctx._summon_enemy_token(atk, hp),
				"A shard splits off and stands up.")
		"exile_card":
			exile_top_draw(ctx)


static func dispatch_passive_start_of_round(ctx) -> void:
	match ctx._encounter_passive:
		"orc_random_buff":
			# Inlined from ctx._buff_random_enemy_atk(1) so the body that grew can
			# be NAMED. The +1 already floats off its seal, but a number rising
			# somewhere in the enemy line with nothing to attribute it to is
			# exactly the §4 #6 silence. Same single _random_enemy_creature() draw
			# as the wrapper, so the seeded RNG stream is untouched.
			var orc_target = ctx._random_enemy_creature()
			if orc_target != null:
				orc_target.current_atk += 1
				orc_target.update_stat_display()
				ctx._show_info("One of them works itself up — +1 ATK.")
				ctx._log_event("%s works itself up: [color=#f2e6c8]+1 ATK[/color]."
					% ctx._log_card_ref(orc_target), ctx._log_data(orc_target),
					ctx._log_side(orc_target))
		"sentinel_stone":
			# The Tooth-Stones (A1 combat): they mean to HOLD. Every enemy enters
			# Armored (granted in _place_enemy_card), and from round 2 the front
			# rank digs in — +1 ATK PERMANENTLY each round it stands. Armored blunts
			# your blows going in; the longer the wall holds, the harder it hits
			# back. You have to break the line, not out-last it.
			#
			# From round 3 the ground itself turns against you: the ancient stones
			# grind and the tremor deals 2 face damage a round. A defensive wall
			# with no clock lets you race its face; the tremor makes STALLING lethal,
			# so you must break the Armored line, not out-wait it.
			#
			# The two beats used to be crushed into ONE sentence (2026-07-27),
			# because this is not a coroutine and _show_info wrote a single label —
			# so from round 3 the tremor line provably destroyed the dig-in line on
			# the same frame. _show_info is a real QUEUE since 2026-07-28
			# (COMBAT_LEGIBILITY §10), so that workaround is retired: two distinct
			# things happen, and each now gets its own line and its own 2s hold.
			var sentinel_dug_in := false
			if ctx.round_number >= 2:
				for c in ctx._row_array(true, ctx.ROW_FRONT):
					if c != null and is_instance_valid(c) and c.current_hp > 0:
						c.current_atk += 1
						c.update_stat_display()
						sentinel_dug_in = true
			if sentinel_dug_in:
				ctx._show_info("The Tooth-Stones dig in — enemy front rank gains +1 ATK.")
			if ctx.round_number >= 3:
				# Was 2 face on a pure clock, and the Tooth-Stones were the single
				# worst offender in Act 1 — a five-hero simulation died here on 4
				# of 5 seeds. Deliberately strike_the_champion, NOT strike_the_line:
				# the line version multiplies 2 damage across up to four bodies,
				# which is a far bigger blow than the 2 it replaced and punishes
				# exactly the wide boards this fight already pressures. One target
				# preserves the original magnitude while making it answerable.
				strike_the_champion(ctx, 2,
					"The ground gives under your heaviest — 2 damage.")
		"bandit_reinforce":
			# The Toll-Takers (A1 combat): the camp never runs out of men. A fresh
			# 2/2 Swift raider joins from round 2, and from round 4 the camp empties
			# out — TWO a round. A weak deck that can't close gets buried under the
			# flood; a fast one ends the fight before it matters.
			if ctx.round_number >= 2:
				var reinforce_n: int = 2 if ctx.round_number >= 4 else 1
				# Report what ARRIVED, not what was ordered — a full or closed board
				# eats the summon silently. announce_arrival now takes the placed
				# body itself, so the count-the-line-before-and-after arithmetic that
				# used to answer that question is gone; a summon that fizzled hands
				# back null and says nothing.
				for _i in reinforce_n:
					announce_arrival(ctx, ctx._summon_enemy_token_with_keyword(2, 2, "swift"),
						"A raider joins the road.")
		"chieftain_rally":
			if ctx.round_number >= 2:
				var chieftain_alive := false
				for c in ctx._all_enemy_creatures():
					if c.card_data.get("name", "") == "Chieftain":
						chieftain_alive = true
						break
				if chieftain_alive:
					var rallied := false
					for c in ctx._row_array(true, ctx.ROW_FRONT):
						if c != null and is_instance_valid(c) and c.current_hp > 0:
							c.temp_atk_buff += 1
							c.update_stat_display()
							rallied = true
					if rallied:
						ctx._show_info("The Chieftain rallies the front rank.")
						ctx._log_event("The Chieftain rallies the front rank: enemy front row gains [color=#f2e6c8]+1 ATK[/color] this round.")
		"stampede_charge":
			if ctx.round_number <= 2:
				var charged := false
				for c in ctx._all_enemy_creatures():
					c.temp_atk_buff += 1
					c.update_stat_display()
					charged = true
				if charged:
					# The Piercing half of this sentence used to be the only trace the
					# grant existed. It now flashes and stands on every body in the
					# herd, so the caption keeps the cause and the +1 ATK (whose
					# floats need attributing) and stops repeating the keyword. The
					# chronicle row below is a record, not a competing signal, so it
					# still says the whole rule.
					ctx._show_info("The herd stampedes — enemies gain +1 ATK this round.")
					ctx._log_event("The herd stampedes: enemy creatures gain [color=#f2e6c8]+1 ATK[/color] and Piercing this round.")
			elif ctx.round_number == 3 and not ctx._stampede_broken_logged:
				ctx._stampede_broken_logged = true
				ctx._show_info("The stampede breaks.")
				ctx._log_event("The stampede breaks.")
		"formation_drill":
			# THE STALWART phase 1 — the Last Wall's Formation engine.
			# (Also the amalgam finale's wall phase.)
			formation_drill_tick(ctx, false)
		"formation_lockstep":
			# THE STALWART phase 2 — the drill continues, the front armors up.
			formation_drill_tick(ctx, true)
		"formation_muster":
			# THE STALWART (act 1 gate) — a gentler muster: front rank only, from
			# round 3. Same growing-wall identity at act-1 intensity (see front_only).
			formation_drill_tick(ctx, false, true)
		"throne_husks":
			# Amalgam finale phase 1 — the burned kingdoms' dead trickle back
			# as Swift chaff. Skips the setup round like every engine.
			if ctx.round_number >= 2:
				announce_arrival(ctx,
					ctx._summon_enemy_token_with_keyword(2, 2, "swift"),
					"The burned kingdoms send up another husk.")
		"pyre_ritual":
			# Climax beat: check each Pyre and ignite if it crossed the
			# threshold last round. Telegraphed at end of last round when
			# `ready_to_ignite` was set; the player sees the build-up then,
			# and the bang lands here at the top of the next round.
			for s in ctx._all_structures():
				if String(s.card_data.get("name", "")) == "Pyre" and s.state.ready_to_ignite:
					ctx._fire_pyre_ignition(s)
		"crypt_rite":
			# Mausoleum climax: when at threshold, the Mausoleum collapses
			# into the Lich — a 6/6 piercing creature that takes its place.
			for s in ctx._all_structures():
				if String(s.card_data.get("name", "")) == "Mausoleum" and s.state.ready_to_ignite:
					ctx._rise_from_mausoleum(s)
		"altar_sacrifice":
			# Cultist Altar: every round, the lowest-HP cultist offers itself
			# to the Altar. The Altar climaxes at round 4 / charge 3 with a
			# 5/6 Champion summon and 3 face damage.
			ctx._cultist_altar_tick()
		"siege_ritual":
			# Iron Warden's Trebuchet: enemy deaths feed it (see on_enemy_death).
			# When at threshold, it FIRES at the start of next round — 3 damage
			# to every player creature + 4 face damage. Different from the Pyre
			# Ignition (which hits both sides and respects adjacency) — this is
			# a pure siege artillery strike, all on the player.
			for s in ctx._all_structures():
				if String(s.card_data.get("name", "")) == "Trebuchet" and s.state.ready_to_ignite:
					ctx._fire_trebuchet_strike(s)
		"cauldron_brew":
			# The Crone's Cauldron: ticks +1 charge every round (no death feed)
			# and ALSO drips one curse into your discard (same as crone_drip).
			# At Charge 5 it OVERFLOWS — summons a Wraith, adds 2 more curses,
			# deals 3 face damage. The ticking visual + drip combine into one
			# legible threat instead of two parallel ones.
			ctx._cauldron_brew_tick()
		"cultist_buff":
			var target = ctx._random_enemy_creature()
			if target != null:
				target.current_atk += 1
				target.current_hp = mini(target.current_hp + 1, target.card_data.hp + 1)
				target.card_data.hp += 1
				target.update_stat_display()
				# Both seals float their own +1; only the rite behind them was
				# missing. (court_wither replaced this arm in the live pools
				# precisely because it was invisible — the arm survives for old
				# encounters, so it gets the same honesty as the rest.)
				ctx._show_info("The rite feeds one of them — +1/+1.")
				ctx._log_event("The rite feeds %s: [color=#f2e6c8]+1/+1[/color]."
					% ctx._log_card_ref(target), ctx._log_data(target),
					ctx._log_side(target))
		"martyr_pact":
			ctx._mark_martyr_chosen()
		"forge_burn_all":
			var forge_all: Array = ctx._all_creatures_both_sides()
			for c in forge_all:
				c.take_damage(1)
			if not forge_all.is_empty():
				ctx._show_info("The forge flares — 1 damage to every creature.")
		"hollow_king_snipe":
			var highest = ctx._highest_atk_player_creature()
			if highest != null:
				# Damage on a body with no attacker across from it is the clearest
				# "the game is cheating" read there is; the eye has to be named.
				ctx._show_info("The great eye finds your strongest — 3 damage.")
				highest.take_damage(3)
		"void_exile":
			exile_top_draw(ctx)
		"nexus_rotation":
			var cycle = (ctx.round_number - 1) % ctx.PASSIVE_HEAL_INTERVAL
			var nexus_sprites: Array = ctx._all_enemy_creatures()
			match cycle:
				0:
					for c in nexus_sprites:
						c.current_atk += 1
						c.update_stat_display()
					if not nexus_sprites.is_empty():
						ctx._show_info("The storm gathers — all enemies gain +1 ATK.")
				1:
					var nexus_mended := 0
					for c in nexus_sprites:
						var was: int = c.current_hp
						c.current_hp = mini(c.current_hp + 2, c.card_data.hp)
						c.update_stat_display()
						if c.current_hp > was:
							nexus_mended += 1
					if nexus_mended > 0:
						ctx._show_info("The storm mends its own.")
				2:
					# This arm used to change the fight while doing literally nothing
					# on screen — Thorns was granted by lookup at strike time, so the
					# §4 #10 silence was total and this line was the ONLY signal the
					# bristle round was running. It is not any more: every enemy body
					# now flashes THORNS and keeps an ember orb on its status rail for
					# the round (Combat._refresh_encounter_keyword_grants).
					#
					# The line stays anyway, trimmed to what the rail cannot say. The
					# orbs report a state, one body at a time; they cannot name the
					# storm as the cause, and they cannot tell you this is one beat of
					# a rotation — which is the read the whole encounter is built on.
					# So: cause here, keyword on the bodies, and no repetition.
					if not nexus_sprites.is_empty():
						ctx._show_info("The storm bristles.")
		"dragon_lair_periodic":
			if ctx.round_number > 1 and (ctx.round_number - 1) % ctx.PASSIVE_HEAL_INTERVAL == 0:
				var lair_crs: Array = ctx._all_player_creatures()
				for c in lair_crs:
					c.take_damage(3)
				if not lair_crs.is_empty():
					ctx._show_info("The lair breathes — 3 damage to each of your creatures.")
		"drake_breath":
			# Where the Old Drake Sleeps (A3): the old dragon exhales from round 2 —
			# 1 damage to each of your creatures, +1 more for every creature beyond
			# the second. Going wide is punished; a tall board of 1-2 big bodies
			# shrugs it. Replaces the DEAD dragon_lair_periodic, which only fired on
			# round 4 — past the life of a real fight.
			if ctx.round_number >= 2:
				var drake_crs: Array = ctx._all_player_creatures()
				var drake_burn: int = 1 + maxi(0, drake_crs.size() - 2)
				for c in drake_crs:
					c.take_damage(drake_burn)
				if not drake_crs.is_empty():
					ctx._show_info("The drake breathes — %d damage to each of your creatures." % drake_burn)
		"forge_heat":
			# The Forge That Eats (A2): the forge cooks YOUR line, not its own forged
			# bodies. 1 from the start, 2 from round 3 — wide fragile boards melt and
			# the player is pushed onto tall bruisers + burst. Bypasses armor (ambient
			# heat, not an attack). Replaces a shared forge_burn_all.
			var forge_heat_amt: int = 2 if ctx.round_number >= 3 else 1
			var forge_heat_crs: Array = ctx._all_player_creatures()
			for c in forge_heat_crs:
				c.take_damage_bypass_armor(forge_heat_amt)
			# Ambient heat, not an attack — so nothing lunges and nothing is across
			# from the bodies losing HP. Without the cause it reads as your own line
			# bleeding for no reason, and the Armored bypass reads as a bug.
			if not forge_heat_crs.is_empty():
				ctx._show_info("The forge cooks your line — %d damage to each of your creatures."
					% forge_heat_amt)
		"court_wither":
			# The Withered Court (A3): from round 2 the court leaches your army —
			# every one of your creatures loses 1 ATK this round (temp, refreshed each
			# round, self-corrects when you break the court). Replaces the generic,
			# invisible cultist_buff with a legible "your army is dying, hurry" clock.
			if ctx.round_number >= 2:
				var court_any := false
				for c in ctx._all_player_creatures():
					c.temp_atk_buff -= 1
					c.update_stat_display()
					court_any = true
				if court_any:
					ctx._show_info("The court withers your army — your creatures lose 1 ATK this round.")
		"dirge_swell":
			# The Carrion Choir (A2): the hymn itself bleeds you. Each singing crow
			# — one that shrieks on death (an on_death face hit) — chips 1 face at
			# the top of the round, so walling the front and waiting loses: you must
			# push damage onto the back-row singers. Skips the setup round.
			if ctx.round_number >= 2:
				var dirge_singers := 0
				for c in ctx._all_enemy_creatures():
					if c.card_data.get("on_death", {}).get("type", "") == "damage_face":
						dirge_singers += 1
				if dirge_singers > 0:
					ctx.damage_player_hero(dirge_singers)
					ctx._show_info("The choir sings — %d damage." % dirge_singers)
		"glass_refract":
			# The Glass Menagerie (A3): the hall replaces a shattered pane — a 3/1
			# Swift shard each round from round 2. Spot-killing one-at-a-time never
			# gets ahead; you must sweep wide. Replaces a shared executioner_face so
			# the Menagerie reads as "endless fragile swarm," distinct from the
			# Executioner's Block ("one big telegraphed axe").
			if ctx.round_number >= 2:
				announce_arrival(ctx,
					ctx._summon_enemy_token_with_keyword(3, 1, "swift"),
					"The hall replaces a shattered pane — a Shard steps out.")
		"devil_cycle":
			var cycle = (ctx.round_number - 1) % ctx.PASSIVE_HEAL_INTERVAL
			match cycle:
				0:
					# Matches arm 2 below (which already strikes the champion), so
					# the whole three-beat cycle is answerable by board play.
					strike_the_champion(ctx, 2,
						"The pact collects — 2 damage to your champion.")
				1:
					# The foe's own bar moving is the quietest change on the screen
					# — it is not even on the board the player is watching.
					var devil_healed: int = mini(ctx.enemy_hp
						+ ctx._all_enemy_creatures().size(), ctx.enemy_max_hp) - ctx.enemy_hp
					ctx.enemy_hp += devil_healed
					if devil_healed > 0:
						ctx._show_info("The devil drinks from its own — the foe heals %d HP."
							% devil_healed)
				2:
					var highest = ctx._highest_atk_player_creature()
					if highest != null:
						ctx._show_info("The pact takes your strongest — 3 damage.")
						highest.take_damage(3)
		"puppet_keyword_copy":
			var source = ctx._highest_atk_player_creature()
			var target = ctx._random_enemy_creature()
			if source != null and target != null:
				# Name the keywords AND both ends of the theft. A marionette that
				# silently grows Armored is indistinguishable from a card that
				# always had it — and the grant never reaches card printing, so
				# the player's only clue was the rail orb they weren't watching.
				var stolen: Array[String] = []
				for kw in source.card_data.get("keywords", []):
					if not target.card_data.keywords.has(kw):
						target.card_data.keywords.append(kw)
						stolen.append(String(KeywordEffects.KEYWORDS.get(kw, {})
							.get("display", String(kw).capitalize())))
				target.update_stat_display()
				if not stolen.is_empty():
					ctx._show_info("The strings copy %s off %s."
						% [", ".join(stolen), String(source.card_data.get("name", "your champion"))])
					ctx._log_event("%s copies %s from %s."
						% [ctx._log_card_ref(target), ", ".join(stolen),
							ctx._log_card_ref(source)],
						ctx._log_data(target), ctx._log_side(target))
		# Phase 2 passives
		"hollow_king_phase2":
			# Two highest-ATK player creatures take 3 damage (any row).
			var sorted_creatures: Array = ctx._all_player_creatures()
			sorted_creatures.sort_custom(func(a, b): return a.current_atk > b.current_atk)
			var judged: int = mini(2, sorted_creatures.size())
			if judged > 0:
				ctx._show_info("The great eye judges your strongest — 3 damage each.")
			for i in range(judged):
				sorted_creatures[i].take_damage(3)
			post_curses(ctx, 1, "A Curse settles into your discard pile.")
		"dragon_lord_phase2":
			var drake_lord: Array = ctx._all_enemy_creatures()
			for c in drake_lord:
				c.current_atk += 1
				c.update_stat_display()
			if not drake_lord.is_empty():
				ctx._show_info("The Dragon Lord roars — all enemies gain +1 ATK.")
		"collector_phase2":
			pass  # Handled in creature play hook
		"devil_phase2":
			var cycle = (ctx.round_number - 1) % ctx.PASSIVE_HEAL_INTERVAL
			match cycle:
				# Arm 2 of this same cycle already strikes the champion; arm 0 now
				# matches it instead of taxing the face, so the whole cycle is
				# something you position against rather than a metronome.
				0:
					strike_the_champion(ctx, 4,
						"The pact collects — 4 damage to your champion.")
				1:
					var devil2_healed: int = mini(ctx.enemy_hp
						+ ctx._all_enemy_creatures().size() * 2, ctx.enemy_max_hp) - ctx.enemy_hp
					ctx.enemy_hp += devil2_healed
					if devil2_healed > 0:
						ctx._show_info("The devil drinks from its own — the foe heals %d HP."
							% devil2_healed)
				2:
					var highest = ctx._highest_atk_player_creature()
					if highest != null:
						ctx._show_info("The pact takes your strongest — 6 damage.")
						highest.take_damage(6)
		"devil_phase3":
			strike_the_champion(ctx, 3,
				"The pact collects — 3 damage to your champion.")
			announce_arrival(ctx, ctx._summon_enemy_token(3, 3),
				"The circle widens — another devil steps through.")
			var devil3_host: Array = ctx._all_enemy_creatures()
			for c in devil3_host:
				c.current_atk += 1
				c.update_stat_display()
			if not devil3_host.is_empty():
				ctx._show_info("The host sharpens — all enemies gain +1 ATK.")
	# Some of these grants are ROUND-SCOPED — the Nexus bristles on one beat of
	# three, the herd's charge lapses at round 3 — so the rail has to be re-derived
	# at the round boundary even when nothing on the board moved. Every other path
	# is covered by Combat._refresh_adjacency_buffs, which runs at every mutation.
	ctx._refresh_encounter_keyword_grants()


static func dispatch_passive_end_of_round(ctx) -> void:
	match ctx._encounter_passive:
		"spore_regrowth":
			# The Spore-Cathedral (A1 combat): a vice. Every round the grove knits
			# its wounded back up (+2 HP each) so chip damage is undone, AND while
			# the congregation still breathes it chokes you for 2 face damage. The
			# only way out is to BURST bodies down and END the fight fast — the heal
			# undoes chipping, and the choke grinds a slow deck to death. The choke
			# only fires while enemies live (a cleared board can't spore you).
			var spore_enemies: Array = ctx._all_enemy_creatures()
			if not spore_enemies.is_empty():
				for c in spore_enemies:
					var maxhp: int = int(c.card_data.get("hp", c.current_hp))
					if c.current_hp < maxhp:
						c.current_hp = mini(c.current_hp + 2, maxhp)
						c.update_stat_display()
				# The choke scales with the board you FAILED to clear — 1 face per
				# living enemy (cap 4). Clearing bodies eases your own suffocation,
				# so the burst-kill puzzle and your survival are the same problem.
				var choke: int = mini(spore_enemies.size(), 4)
				ctx.damage_player_hero(choke)
				ctx._show_info("The spores knit the wounded (+2 HP) and choke you for %d." % choke)
		"iron_warden_burn":
			strike_the_line(ctx, 2, "Burning pitch comes over the wall — 2 to your front rank.")
		"iron_warden_siege":
			# The Warden's artillery now ranges on the biggest thing on the field
			# instead of taxing the player directly (see the retarget note up top).
			# The Armored grant is the phase's identity and carries its difficulty.
			# It goes into card_data.keywords because that is the ONLY place the
			# rules read Armored (Card2D.has_keyword) — grant_field_keyword writes
			# it there AND files the receipt that stops the Captain looting it.
			strike_the_champion(ctx, 3,
				"The Warden's engine ranges on your champion — 3 damage.")
			for c in ctx._all_enemy_creatures():
				grant_field_keyword(c, "armored")
		"mushroom_heal":
			var shroom_mended := 0
			for c in ctx._all_enemy_creatures():
				var was: int = c.current_hp
				c.current_hp = mini(c.current_hp + 1, c.card_data.hp)
				c.update_stat_display()
				if c.current_hp > was:
					shroom_mended += 1
			# The +1 HP floats off each seal already; silent on a whole line.
			if shroom_mended > 0:
				ctx._show_info("The grove knits its wounded.")
		"executioner_face":
			var axe = ctx._passive_threat_marked
			if axe != null and is_instance_valid(axe) and axe.current_hp > 0 \
					and bool(axe.is_opponent):
				var axe_dmg: int = axe.effective_atk()
				ctx._log_event("%s drops the axe for [color=#e06a50]%d[/color]." \
					% [ctx._log_card_ref(axe), axe_dmg],
					ctx._log_data(axe), ctx._log_side(axe))
				ctx.damage_player_hero(axe_dmg)
				if axe.has_method("set_danger_marked"):
					axe.set_danger_marked(false)
			else:
				ctx._log_event("The raised axe finds no neck.")
			ctx._passive_threat_marked = null
			ctx._passive_threat_amount = 0
		"crone_drip":
			post_curses(ctx, 1, "The Crone spits — a Curse settles into your discard pile.")
		"crone_lash":
			# One line for one beat: the Curse arriving and the Curses biting are
			# the same act of hers, and the face hit is loud on its own.
			post_curses(ctx, 1,
				"The Crone lashes out — another Curse, and every Curse bites.")
			ctx.damage_player_hero(curses_in_deck(ctx))
		"crone_doom":
			post_curses(ctx, 2,
				"The Crone dooms you — 2 more Curses, and every Curse bites.")
			ctx.damage_player_hero(curses_in_deck(ctx))
			announce_arrival(ctx, ctx._summon_enemy_token_with_keyword(2, 3, "swift"),
				"A Wraith rises at her call.")
		"tide_swell":
			# The tide only wades ashore onto a line of three or fewer — the cap is
			# the rule, and it is read BEFORE the summon, exactly as before.
			if ctx._all_enemy_creatures().size() < 4:
				announce_arrival(ctx, ctx._summon_enemy_token(2, 3),
					"The tide rises — a Deepling wades ashore.")
		"tide_surge":
			if ctx._all_enemy_creatures().size() < 4:
				announce_arrival(ctx, ctx._summon_enemy_token(2, 3),
					"The tide rises — a Deepling wades ashore.")
			var surge_host: Array = ctx._all_enemy_creatures()
			for c in surge_host:
				c.current_atk += 1
				c.update_stat_display()
			if not surge_host.is_empty():
				ctx._show_info("The tide surges — all enemies gain +1 ATK.")
		"tide_drown":
			if ctx._all_enemy_creatures().size() < 4:
				announce_arrival(ctx, ctx._summon_enemy_token(2, 3),
					"The tide rises — a Deepling wades ashore.")
			var drown_host: Array = ctx._all_enemy_creatures()
			for c in drown_host:
				c.current_atk += 1
				c.update_stat_display()
			var weakest = lowest_hp_player_creature(ctx)
			if weakest != null:
				weakest.take_damage(3)
			# The surge and the undertow share a sentence deliberately. This arm
			# fires EVERY round of the boss's last phase, and three lines a round
			# is how a legibility fix turns into the noise it was meant to cure.
			if weakest != null and not drown_host.is_empty():
				ctx._show_info("The tide surges (+1 ATK) and the undertow deals 3 damage to your weakest.")
			elif not drown_host.is_empty():
				ctx._show_info("The tide surges — all enemies gain +1 ATK.")
			elif weakest != null:
				ctx._show_info("The undertow takes your weakest — 3 damage.")
	# Same reason as the start-of-round sweep: the boss phase that turns over here
	# can change which keywords the field lends its line.
	ctx._refresh_encounter_keyword_grants()


static func dispatch_encounter_on_enemy_death(ctx, lane_idx: int, dead_card = null,
		row: int = -1) -> void:
	# 4x4: lane_idx is the column; row is the dead creature's row when the
	# death path knows it (-1 legacy fallback sweeps both rows' adjacencies).
	match ctx._encounter_passive:
		"wolf_pack_revenge":
			# "Adjacent enemies gain +1 ATK" — canonical adjacency of the fallen
			# wolf (its row ±1 + its column-mate).
			var wp_rows: Array = [row] if row >= 0 else [ctx.ROW_FRONT, ctx.ROW_BACK]
			var wp_raged := false
			for r in wp_rows:
				for adj_card in ctx._adjacent_creatures(true, r, lane_idx):
					adj_card.temp_atk_buff += 1
					adj_card.update_stat_display()
					wp_raged = true
			# A CONSTANT sentence on purpose: this fires once per corpse, and a
			# clash that kills three wolves would otherwise spend the whole info
			# queue on one flush. _show_info collapses exact consecutive repeats,
			# so three deaths read as one statement of the rule. The chronicle
			# still gets a row per death — that is what a record is for.
			if wp_raged:
				ctx._show_info("The pack rages — enemies beside the fallen gain +1 ATK this round.")
				ctx._log_event("The pack rages: enemies beside the fallen gain [color=#f2e6c8]+1 ATK[/color] this round.")
		"flock_enrage":
			# The Shepherd Who Lost His Sheep (A3): a death feeds the survivors beside
			# it +1 ATK PERMANENTLY (current_atk, not temp), so kill order compounds.
			# "Beside" is the row-lateral word — the fallen sheep's own rank only,
			# matching the passive's printed text (canonical "adjacent" is _adjacent_creatures).
			var fe_rows: Array = [row] if row >= 0 else [ctx.ROW_FRONT, ctx.ROW_BACK]
			var fe_raged := false
			for r in fe_rows:
				for adj_card in ctx._adjacent_in_row(true, r, lane_idx):
					adj_card.current_atk += 1
					adj_card.update_stat_display()
					fe_raged = true
			# Guarded now: a sheep dying alone at the end of a rank sharpened
			# nobody, and the line claimed otherwise.
			if fe_raged:
				ctx._show_info("The flock rages — survivors beside the fallen gain +1 ATK.")
		"pyre_spread":
			# The Pyre Cult (A3): every cultist that dies bursts — 1 damage to the
			# opposing creature and 1 face. Killing the line all at once lights the
			# whole row, so HOW you kill matters. Replaces a shared forge_burn_all.
			# Structure deaths don't chain.
			if dead_card == null or not dead_card.has_keyword("structure"):
				var pyre_opp = ctx._player_field[lane_idx] if lane_idx >= 0 and lane_idx < ctx._player_field.size() else null
				if pyre_opp != null and is_instance_valid(pyre_opp):
					# Constant sentence, same reason as wolf_pack_revenge: this
					# fires once per cultist, and lighting the whole row at once is
					# the fight's own puzzle, not three separate announcements.
					ctx._show_info("The cultist bursts — 1 damage to the opposing creature.")
					pyre_opp.take_damage(1)
				# The extra 1 face per cultist death is gone (2026-07-28). The
				# "how you kill matters" puzzle lives entirely in the opposing-lane
				# hit above; the face chip added nothing but an unavoidable tax on
				# doing the thing the fight requires you to do.
		"necro_death_summon":
			# The risen do not raise more risen. Guard on is_token, NOT on the
			# name: _summon_enemy_token leaves summon_token's hardcoded "Token",
			# so the old `name != "Skeleton"` test never matched its own product
			# and every token's death raised another one, without bound.
			if dead_card == null or not bool(dead_card.card_data.get("is_token", false)):
				announce_arrival(ctx, ctx._summon_enemy_token(1, 1),
					"The tower fills the gap — a Skeleton stands up.")
		"chieftain_rally":
			if dead_card != null and dead_card.card_data.get("name", "") == "Chieftain":
				ctx._show_info("The war drum falls silent.")
				ctx._log_event("The war drum falls silent.")
		"martyr_pact":
			ctx._double_martyr_on_death(dead_card, lane_idx, row)
		"crypt_ghost":
			# A Ghost's death does NOT raise another Ghost. Without this guard the
			# passive fired on its own spawn, so killing a Ghost produced a Ghost
			# and the enemy board could never be reduced by killing at all. Same
			# rule as necro_death_summon above; the encounter's intended puzzle
			# ("leave certain creatures alive") only has an answer once the loop
			# is bounded.
			if dead_card == null or not bool(dead_card.card_data.get("is_token", false)):
				announce_arrival(ctx, ctx._summon_enemy_token_with_keyword(1, 1, "swift"),
					"The crypt gives up a Ghost.")
		"mirror_instant_place":
			pass  # handled in player death below
		"pyre_ritual":
			# Each cultist death feeds the nearest Pyre. The pyre with the
			# smallest column-distance wins; ties broken left-to-right by the
			# iteration order of _all_structures(). Structures themselves
			# dying (somehow) shouldn't feed each other — skip those.
			if dead_card != null and dead_card.has_keyword("structure"):
				return
			var nearest = null
			var best_dist: int = 999
			for s in ctx._all_structures():
				if String(s.card_data.get("name", "")) != "Pyre":
					continue
				var dist: int = abs(s.current_lane - lane_idx)
				if dist < best_dist:
					best_dist = dist
					nearest = s
			if nearest != null:
				ctx._add_structure_charge(nearest, 1)
		"crypt_rite":
			# Each enemy death feeds the Mausoleum. When it reaches threshold,
			# the round-start handler resurrects the Lich.
			if dead_card != null and dead_card.has_keyword("structure"):
				return
			for s in ctx._all_structures():
				if String(s.card_data.get("name", "")) == "Mausoleum":
					ctx._add_structure_charge(s, 1)
					break
		"siege_ritual":
			# Iron Warden trebuchet feeds on every enemy death (the engineers
			# fall and the trebuchet team scrambles to load). Structure deaths
			# themselves don't feed it.
			if dead_card != null and dead_card.has_keyword("structure"):
				return
			for s in ctx._all_structures():
				if String(s.card_data.get("name", "")) == "Trebuchet":
					ctx._add_structure_charge(s, 1)
					break


static func dispatch_encounter_on_player_death(ctx, _lane_idx: int) -> void:
	match ctx._encounter_passive:
		"mirror_instant_place":
			ctx._enemy_place_creatures()
		"pack_hunt":
			# The Cinder-Hounds (A2): your dead is their scent. Every friendly death
			# whets the Swift pack +1 ATK this round (temp, clears next round —
			# pressure, not permanent snowball). Replaces a shared forge_burn_all so
			# the rush deck and its passive finally pull the same direction.
			var pack_whetted := false
			for c in ctx._all_enemy_creatures():
				if c.has_keyword("swift"):
					c.temp_atk_buff += 1
					c.update_stat_display()
					pack_whetted = true
			# Guarded: with no Swift hound left standing, the line was naming a
			# beat that did not happen.
			if pack_whetted:
				ctx._show_info("Blood in the air — the pack quickens.")


static func dispatch_encounter_on_enter(ctx, _data: Dictionary, _lane_idx: int) -> void:
	# Bandit Camp's "mana steal" passive. Fires exactly once per round on the
	# first reinforcement (matches the passive description). Two prior bugs:
	#   1. The maxi(0, _bonus_mana_next_turn - 1) clamp meant the steal could
	#      never actually reduce mana below the base — it could only cancel
	#      a positive bonus the player didn't usually have. Now we decrement
	#      directly; Combat clamps player_mana to 0 at round start.
	#   2. It fired on EVERY enemy entry (3-4 times per round on a swarm
	#      placement), stacking the no-op. Now gated by a per-round flag that
	#      Combat resets at start_round.
	if ctx._encounter_passive == "bandit_mana_steal":
		if not ctx._bandit_steal_fired_this_round:
			ctx._bandit_steal_fired_this_round = true
			ctx._bonus_mana_next_turn -= 1
			# A resource the player will simply not have next turn, taken with
			# nothing on screen — §4 #8's sibling. Player-facing word is Command
			# (COPY_STYLE §6); the identifier stays _bonus_mana_next_turn.
			ctx._show_info("The camp lifts your purse — 1 less Command next turn.")


## ── THE FIELD LENDS A KEYWORD, AND THE LOAN IS RECORDED ──────────────────────
## 2026-07-29. `card_data.keywords` records THAT a body is Armored and never WHO
## made it so — and four separate readers reach into that array:
##
##   Combat._defection_steal_target  `DEFECTION_STEALABLE` lists "armored" FIRST,
##                                   so a field rule is the Free Company Captain's
##                                   highest-priority loot.
##   copy_last_dead (Doppelganger)   copies a corpse's list onto a player body.
##   copy_opposing_keywords (Mirror  same, off the living body opposite.
##     Knight)
##   Combat._desert_enemy_to_player  card_data.duplicate(true) walks the whole
##                                   dict across to your banner.
##
## Without provenance not one of them can tell a printed Armored from one this
## fight handed out.
##
## The six LOOKUP-based grants (dragon_lord_piercing, swamp_thorns, merc_piercing,
## nexus_rotation, stampede_charge, stone_armor) dodge the problem by never
## entering `keywords` at all: they are re-derived at strike time and mirrored to
## `encounter_grants` purely so the status rail can show them.
##
## THESE TWO CANNOT FOLLOW THEM, and that is why the write below stays. Armored's
## only reader anywhere is `Card2D.has_keyword` (Card2D.gd:3601 via :635), which
## reads `keywords` and nothing else — no strike path consults the lookup for it.
## Moving the write onto a mirror would not clean up a signal, it would SILENTLY
## DELETE Armored from three boss phases (and from the overkill arithmetic at
## Combat.gd:10844/:10855 and its CombatNet twin, and from the forecast).
##
## So the keyword still goes where the rules read it, and a RECEIPT goes beside
## it. `has_encounter_passive_keyword` answers from that receipt, which is what
## lets Combat._defection_steal_target's guard — it already asks this function —
## refuse to loot a rule that belongs to the fight rather than to the card.
##
## Deliberately NOT named `encounter_grants`: Combat._refresh_encounter_keyword_grants
## rebuilds that key from scratch on every board mutation and would erase this.
##
## Returns true only when the keyword was NEWLY lent. A body that already PRINTS
## the keyword is left entirely alone — no append, no receipt — so the Captain can
## still loot a Shieldbearer's own Armored, which is his card doing its job.
static func grant_field_keyword(card, keyword: String) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if not card.card_data.has("keywords"):
		card.card_data["keywords"] = []
	if card.card_data.keywords.has(keyword):
		return false
	card.card_data.keywords.append(keyword)
	var lent: Array = card.card_data.get("field_granted_keywords", [])
	if not lent.has(keyword):
		lent.append(keyword)
	card.card_data["field_granted_keywords"] = lent
	return true


static func has_encounter_passive_keyword(ctx, card, keyword: String) -> bool:
	# THE RECEIPT ANSWERS FIRST (2026-07-29). A keyword this fight lent the body
	# belongs to the fight however it was recorded — see grant_field_keyword above.
	# Checked ahead of the match because sentinel_stone / formation_lockstep /
	# iron_warden_siege grant STATEFULLY rather than by a standing rule: there is
	# no round number, ATK threshold or boss phase to re-derive the answer from,
	# so the receipt IS the answer. Null-safe, and never true for a body that
	# prints the keyword itself.
	if card != null and is_instance_valid(card):
		var lent: Array = card.card_data.get("field_granted_keywords", [])
		if lent.has(keyword):
			return true
	match ctx._encounter_passive:
		"dragon_lord_piercing":
			return keyword == "piercing"
		"dragon_lord_phase2":
			return keyword == "piercing"
		"swamp_thorns":
			return keyword == "thorns"
		"merc_piercing":
			if keyword == "piercing" and card != null:
				return card.effective_atk() >= 4
		"stone_armor":
			if keyword == "armored" and card != null:
				return card.card_data.get("keywords", []).has("armored")
		"harpy_swift_face":
			return false
		"nexus_rotation":
			if keyword == "thorns":
				return (ctx.round_number - 1) % 3 == 2
		"stampede_charge":
			if keyword == "piercing":
				return ctx.round_number <= 2
	return false


# ---------------------------------------------------------------------------
# Helpers used only by the dispatchers above
# ---------------------------------------------------------------------------

## THE STALWART's Formation engine: bodies holding a line grow together.
## "Beside" = same row, adjacent column, both alive. The buff is permanent
## (+1 ATK, +1 max HP) so breaking the line — kill the middle, isolate the
## ends — is the counterplay, not waiting it out. Skips the setup round so
## the player gets one clean read of the opening formation; ticks from
## round 2 (engines must fire by round 2 — CONQUEST_REDESIGN.md §15.2).
## Lockstep (phase 2) additionally hard-grants Armored to the front row via
## the keywords array so the armor shows on the card chips — through
## grant_field_keyword, which files the provenance receipt beside it (a body
## that already PRINTS Armored is left alone and keeps no receipt).
static func formation_drill_tick(ctx, lockstep: bool, front_only := false) -> void:
	# front_only = the gentler act-1 "muster" cadence: only the front rank drills
	# (the back row is queue space, not part of the growing wall) and it starts a
	# round later, so the act-1 gate isn't carrying the act-3 finale's full
	# compounding snowball. The act-3 amalgams/ascendants keep the both-row,
	# round-2 version below.
	if ctx.round_number < (3 if front_only else 2):
		return
	var grew := false
	var rows: Array = [ctx.ROW_FRONT] if front_only else [ctx.ROW_FRONT, ctx.ROW_BACK]
	for row in rows:
		var arr: Array = ctx._row_array(true, row)
		for i in arr.size():
			var c = arr[i]
			if c == null:
				continue
			var left = arr[i - 1] if i > 0 else null
			var right = arr[i + 1] if i < arr.size() - 1 else null
			if left == null and right == null:
				continue
			c.current_atk += 1
			c.card_data.hp += 1
			c.current_hp = mini(c.current_hp + 1, c.card_data.hp)
			c.update_stat_display()
			grew = true
	var closed_ranks := false
	if lockstep:
		for c in ctx._row_array(true, ctx.ROW_FRONT):
			if grant_field_keyword(c, "armored"):
				c.update_stat_display()
				closed_ranks = true
	# Lockstep's Armored grant used to ride under the growth line without ever
	# being named. It does reach card_data.keywords (so the device and rail orb
	# appear), but a keyword arriving on four bodies at once still needs the beat
	# said out loud — otherwise your blows just start doing 1 less for no reason.
	if grew and closed_ranks:
		ctx._show_info("The wall holds — its line grows +1/+1 and the front rank goes Armored.")
	elif grew:
		ctx._show_info("The wall holds — its line grows +1/+1.")
	elif closed_ranks:
		ctx._show_info("The wall closes ranks — its front rank goes Armored.")


static func curses_in_deck(ctx) -> int:
	var n := 0
	for entry in ctx._player_draw_pile:
		if CardDB.is_curse(ctx._entry_id(entry)):
			n += 1
	for entry in ctx._player_discard_pile:
		if CardDB.is_curse(ctx._entry_id(entry)):
			n += 1
	for c in ctx._hand:
		if CardDB.is_curse(c.card_id):
			n += 1
	return n


static func lowest_hp_player_creature(ctx):
	var creatures = ctx._all_player_creatures()
	if creatures.is_empty():
		return null
	var best = creatures[0]
	for c in creatures:
		if c.current_hp < best.current_hp:
			best = c
	return best
