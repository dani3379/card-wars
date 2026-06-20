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


static func dispatch_reactive(ctx, trigger: String, source_card, _lane_idx: int) -> void:
	## Reactive passive: fires on a player action (spell, sacrifice, floop,
	## summon, draw, or creature death).
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
					break
		"double_on_death":
			# Necromancer Tower: re-fire the dying card's on_death once more.
			# Run the effect directly (not via dispatch_on_death) to avoid the
			# reactive loop calling itself.
			if source_card != null and is_instance_valid(source_card):
				var data: Dictionary = source_card.card_data
				if not data.is_empty() and data.has("on_death"):
					KeywordEffects._run_on_death(data.on_death, _lane_idx, true, ctx)
		"face_damage":
			ctx.damage_player_hero(ctx._reactive_passive.get("value", 2))
		"damage_flooper":
			var value = ctx._reactive_passive.get("value", 1)
			if source_card != null and is_instance_valid(source_card):
				source_card.take_damage(value)
		"summon_puppet":
			ctx._summon_enemy_token(ctx._reactive_passive.get("atk", 2), ctx._reactive_passive.get("hp", 2))
		"heal_all_enemies":
			var value = ctx._reactive_passive.get("value", 1)
			for c in ctx._all_enemy_creatures():
				c.current_hp = mini(c.current_hp + value, c.card_data.hp)
				c.update_stat_display()
		"face_damage_per_draw":
			ctx.damage_player_hero(1)
		"summon_shard":
			var atk = ctx._reactive_passive.get("atk", 1)
			var hp = ctx._reactive_passive.get("hp", 1)
			ctx._summon_enemy_token(atk, hp)
		"exile_card":
			if not ctx._player_draw_pile.is_empty():
				ctx._player_draw_pile.pop_front()


static func dispatch_passive_start_of_round(ctx) -> void:
	match ctx._encounter_passive:
		"orc_random_buff":
			ctx._buff_random_enemy_atk(1)
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
				ctx._summon_enemy_token_with_keyword(2, 2, "swift")
		"pyre_ritual":
			# Climax beat: check each Pyre and ignite if it crossed the
			# threshold last round. Telegraphed at end of last round when
			# `ready_to_ignite` was set; the player sees the build-up then,
			# and the bang lands here at the top of the next round.
			for s in ctx._all_structures():
				if String(s.card_data.get("name", "")) == "Pyre" and s.get_meta("ready_to_ignite", false):
					ctx._fire_pyre_ignition(s)
		"crypt_rite":
			# Mausoleum climax: when at threshold, the Mausoleum collapses
			# into the Lich — a 6/6 piercing creature that takes its place.
			for s in ctx._all_structures():
				if String(s.card_data.get("name", "")) == "Mausoleum" and s.get_meta("ready_to_ignite", false):
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
				if String(s.card_data.get("name", "")) == "Trebuchet" and s.get_meta("ready_to_ignite", false):
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
		"forge_burn_all":
			for c in ctx._all_creatures_both_sides():
				c.take_damage(1)
		"hollow_king_snipe":
			var highest = ctx._highest_atk_player_creature()
			if highest != null:
				highest.take_damage(3)
		"void_exile":
			if not ctx._player_draw_pile.is_empty():
				ctx._player_draw_pile.pop_front()
		"nexus_rotation":
			var cycle = (ctx.round_number - 1) % ctx.PASSIVE_HEAL_INTERVAL
			match cycle:
				0:
					for c in ctx._all_enemy_creatures():
						c.current_atk += 1
						c.update_stat_display()
				1:
					for c in ctx._all_enemy_creatures():
						c.current_hp = mini(c.current_hp + 2, c.card_data.hp)
						c.update_stat_display()
				2:
					pass  # Thorns handled in combat resolution
		"dragon_lair_periodic":
			if ctx.round_number > 1 and (ctx.round_number - 1) % ctx.PASSIVE_HEAL_INTERVAL == 0:
				for c in ctx._all_player_creatures():
					c.take_damage(3)
		"devil_cycle":
			var cycle = (ctx.round_number - 1) % ctx.PASSIVE_HEAL_INTERVAL
			match cycle:
				0:
					ctx.damage_player_hero(2)
				1:
					ctx.enemy_hp = mini(ctx.enemy_hp + ctx._all_enemy_creatures().size(), ctx.enemy_max_hp)
				2:
					var highest = ctx._highest_atk_player_creature()
					if highest != null:
						highest.take_damage(3)
		"puppet_keyword_copy":
			var source = ctx._highest_atk_player_creature()
			var target = ctx._random_enemy_creature()
			if source != null and target != null:
				for kw in source.card_data.get("keywords", []):
					if not target.card_data.keywords.has(kw):
						target.card_data.keywords.append(kw)
				target.update_stat_display()
		# Phase 2 passives
		"hollow_king_phase2":
			# Two highest-ATK player creatures take 3 damage (any row).
			var sorted_creatures: Array = ctx._all_player_creatures()
			sorted_creatures.sort_custom(func(a, b): return a.current_atk > b.current_atk)
			for i in range(mini(2, sorted_creatures.size())):
				sorted_creatures[i].take_damage(3)
			ctx._player_discard_pile.append(CardDB.random_curse_id())
		"dragon_lord_phase2":
			for c in ctx._all_enemy_creatures():
				c.current_atk += 1
				c.update_stat_display()
		"collector_phase2":
			pass  # Handled in creature play hook
		"devil_phase2":
			var cycle = (ctx.round_number - 1) % ctx.PASSIVE_HEAL_INTERVAL
			match cycle:
				0: ctx.damage_player_hero(4)
				1:
					ctx.enemy_hp = mini(ctx.enemy_hp + ctx._all_enemy_creatures().size() * 2, ctx.enemy_max_hp)
				2:
					var highest = ctx._highest_atk_player_creature()
					if highest != null:
						highest.take_damage(6)
		"devil_phase3":
			ctx.damage_player_hero(3)
			ctx._summon_enemy_token(3, 3)
			for c in ctx._all_enemy_creatures():
				c.current_atk += 1
				c.update_stat_display()


static func dispatch_passive_end_of_round(ctx) -> void:
	match ctx._encounter_passive:
		"iron_warden_burn":
			ctx.damage_player_hero(2)
		"iron_warden_siege":
			ctx.damage_player_hero(3)
			for c in ctx._all_enemy_creatures():
				if "armored" not in c.card_data.keywords:
					c.card_data.keywords.append("armored")
		"mushroom_heal":
			for c in ctx._all_enemy_creatures():
				c.current_hp = mini(c.current_hp + 1, c.card_data.hp)
				c.update_stat_display()
		"executioner_face":
			var highest = ctx._highest_atk_enemy_creature()
			if highest != null:
				ctx.damage_player_hero(highest.effective_atk())
		"crone_drip":
			ctx._player_discard_pile.append(CardDB.random_curse_id())
		"crone_lash":
			ctx._player_discard_pile.append(CardDB.random_curse_id())
			ctx.damage_player_hero(curses_in_deck(ctx))
		"crone_doom":
			ctx._player_discard_pile.append(CardDB.random_curse_id())
			ctx._player_discard_pile.append(CardDB.random_curse_id())
			ctx.damage_player_hero(curses_in_deck(ctx))
			ctx._summon_enemy_token_with_keyword(2, 3, "swift")
		"tide_swell":
			if ctx._all_enemy_creatures().size() < 4:
				ctx._summon_enemy_token(2, 3)
		"tide_surge":
			if ctx._all_enemy_creatures().size() < 4:
				ctx._summon_enemy_token(2, 3)
			for c in ctx._all_enemy_creatures():
				c.current_atk += 1
				c.update_stat_display()
		"tide_drown":
			if ctx._all_enemy_creatures().size() < 4:
				ctx._summon_enemy_token(2, 3)
			for c in ctx._all_enemy_creatures():
				c.current_atk += 1
				c.update_stat_display()
			var weakest = lowest_hp_player_creature(ctx)
			if weakest != null:
				weakest.take_damage(3)


static func dispatch_encounter_on_enemy_death(ctx, lane_idx: int, dead_card = null) -> void:
	# 4x4: lane_idx is the column. Wolf-pack revenge buffs same-row neighbors
	# in the front row, since that's where most fights take place; if you want
	# back-row revenge too, also buff back-row adjacents.
	match ctx._encounter_passive:
		"wolf_pack_revenge":
			for row in [ctx.ROW_FRONT, ctx.ROW_BACK]:
				for adj_card in ctx._adjacent_in_row(true, row, lane_idx):
					adj_card.temp_atk_buff += 1
					adj_card.update_stat_display()
		"necro_death_summon":
			if dead_card == null or dead_card.card_data.get("name", "") != "Skeleton":
				ctx._summon_enemy_token(1, 1)
		"crypt_ghost":
			ctx._summon_enemy_token_with_keyword(1, 1, "swift")
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


static func has_encounter_passive_keyword(ctx, card, keyword: String) -> bool:
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
## the keywords array so the armor shows on the card chips.
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
	if lockstep:
		for c in ctx._row_array(true, ctx.ROW_FRONT):
			if c != null and "armored" not in c.card_data.keywords:
				c.card_data.keywords.append("armored")
				c.update_stat_display()
	if grew:
		ctx._show_info("The wall holds — its line grows +1/+1.")


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
