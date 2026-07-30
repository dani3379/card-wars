extends Node
## _probe_retinue_hooks.gd — the retinue's PASSIVES, RELICS and auras (2026-07-28).
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_retinue_hooks.tscn
##
## Sibling of _probe_retinue_spells.gd. That file covers the eight starter spells;
## this one covers everything that hangs off a hook rather than a cast:
##   4 creature passives  — debt_guard / lens_apprentice / mirror_guard / glass_savant
##   4 doctrine relics    — funeral_lantern / ledger_seal / mirror_primer / cinder_crown
##   2 reshapes           — war_bellows (timer clause dropped) / reserve_standard
##   2 dead mechanics     — Burial Goods' column bequest, Standard Page's HP aura
##   1 adjacency fix      — Fuse Tender now reaches its column-mate
##
## The assertions are arithmetic on named fields, not "it didn't crash", because
## every failure mode here is SILENT:
##
##   1. THE WRONG ATK FIELD. "+1 ATK this round" is temp_atk_buff. The nearest
##      template in the same match (coven_spell) writes persistent_atk_buff with
##      _rounds = 99, i.e. the rest of the FIGHT. Copying it makes the buff
##      permanent and nothing errors, so both passives assert temp == N AND
##      persistent == 0.
##   2. THE SHARED LATCH. _starter_second_distinct_seen_this_round feeds BOTH
##      Glass Savant and the Mirror Primer relic. If either re-tests the flag
##      instead of reading the computed local, whichever ran second finds it
##      already true and never fires — for the lifetime of the build. The test
##      demands both land on the SAME call.
##   3. THE ORDERING. Soul Lantern raises a Shade into the seat the corpse just
##      left; Ledger Seal buffs "a surviving friendly in its column". Sampled in
##      the wrong order the Seal feeds a 1/1 token that arrived a microsecond
##      ago. The test holds BOTH relics and checks the Shade stayed 1/1.
##   4. THE MAX-HP HALF. A grant that writes current_hp without card_data.hp is
##      erased by the next heal (every heal caps at card_data.hp), and an aura
##      that writes them without a ledger can never be taken back off.

const COMBAT_SCENE := "res://scenes/combat.tscn"

var _fails := 0
var combat


func _ready() -> void:
	RunState.start_new_run("acolyte", 0, 9191)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = _find_act1_combat()
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	await get_tree().process_frame

	combat = load(COMBAT_SCENE).instantiate()
	add_child(combat)
	# Poll on round + hand, NOT on phase: Phase.PLAYER_TURN is enum 0, which is
	# also the uninitialised default (documented trap).
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	_check(combat.round_number >= 1, "combat reached round 1")
	combat.enemy_hp = 400

	await _t_debt_guard()
	await _t_lens_apprentice()
	await _t_mirror_guard()
	await _t_glass_savant_and_primer()
	await _t_funeral_lantern()
	await _t_ledger_seal()
	await _t_column_bequest()
	await _t_cinder_crown()
	await _t_war_bellows()
	await _t_reserve_standard()
	await _t_standard_page()
	await _t_fuse_tender()

	print("[retinue-hooks] %d failures" % _fails)
	print("[retinue-hooks] " + ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(1 if _fails > 0 else 0)


# ── 1. DEBT GUARD (passive, ally-death) ──────────────────────────────────────
func _t_debt_guard() -> void:
	print("[retinue-hooks] --- starter_debt_guard ---")
	await _settle()
	_only_relics([])
	combat._debt_guard_used_this_round.clear()
	var guard = _put(false, combat.ROW_FRONT, 0, 2, 3)
	var guard2 = _put(false, combat.ROW_FRONT, 1, 2, 3)
	if not _check(guard != null and guard2 != null, "fixture placed"): return
	guard.card_data["passive"] = "starter_debt_guard"
	guard2.card_data["passive"] = "starter_debt_guard"

	# summon_token bodies ARE tokens, which is exactly the R4 case: the card text
	# says "another friendly" with no token clause, unlike Gravepact's reap.
	var victim = _put(false, combat.ROW_BACK, 3, 1, 1)
	_check(bool(victim.is_token), "the casualty used here is a TOKEN")
	combat._apply_ally_death_passives(false, victim)
	_check(int(guard.temp_atk_buff) == 1,
		"a dying token arms it (temp_atk_buff=%d)" % guard.temp_atk_buff)
	_check(int(guard.persistent_atk_buff) == 0,
		"...on the THIS-ROUND field, not the fight-long one (persistent=%d)"
			% guard.persistent_atk_buff)
	_check(int(guard2.temp_atk_buff) == 1,
		"each Guard owes its own first death (per-BODY latch)")

	var victim2 = _put(false, combat.ROW_BACK, 2, 1, 1)
	combat._apply_ally_death_passives(false, victim2)
	_check(int(guard.temp_atk_buff) == 1,
		"the round's second death pays nothing (temp=%d)" % guard.temp_atk_buff)

	combat._debt_guard_used_this_round.clear()   # what _start_round does
	combat._apply_ally_death_passives(false, victim2)
	_check(int(guard.temp_atk_buff) == 2,
		"the latch is per-ROUND, not per-fight (temp=%d)" % guard.temp_atk_buff)

	# "another friendly": the fallen never profits from its own fall.
	combat._debt_guard_used_this_round.clear()
	var lone = _put(false, combat.ROW_BACK, 0, 2, 3)
	lone.card_data["passive"] = "starter_debt_guard"
	combat._apply_ally_death_passives(false, lone)
	_check(int(lone.temp_atk_buff) == 0, "a Guard does not collect on its own death")


# ── 2. LENS APPRENTICE (passive, first spell each round) ─────────────────────
func _t_lens_apprentice() -> void:
	print("[retinue-hooks] --- starter_lens_apprentice ---")
	await _settle()
	_only_relics([])
	var lens = _put(false, combat.ROW_FRONT, 0, 1, 3)
	if not _check(lens != null, "fixture placed"): return
	lens.card_data["passive"] = "starter_lens_apprentice"

	_open_round()
	combat._record_spell_cast_board_payoffs(_dmg("probe_alpha"))
	_check(int(lens.temp_atk_buff) == 1,
		"the round's first working focuses (temp_atk_buff=%d)" % lens.temp_atk_buff)
	_check(int(lens.persistent_atk_buff) == 0,
		"...this ROUND, not this fight (persistent=%d)" % lens.persistent_atk_buff)

	combat._record_spell_cast_board_payoffs(_dmg("probe_beta"))
	_check(int(lens.temp_atk_buff) == 1,
		"the round's second working pays nothing (temp=%d)" % lens.temp_atk_buff)

	_open_round()
	combat._record_spell_cast_board_payoffs(_dmg("probe_alpha"))
	_check(int(lens.temp_atk_buff) == 2, "it re-arms next round (temp=%d)" % lens.temp_atk_buff)


# ── 3. MIRROR GUARD (passive, first NON-DAMAGE spell each round) ─────────────
func _t_mirror_guard() -> void:
	print("[retinue-hooks] --- starter_mirror_guard ---")
	await _settle()
	_only_relics([])
	var mg = _put(false, combat.ROW_FRONT, 0, 2, 3)
	if not _check(mg != null, "fixture placed"): return
	mg.card_data["passive"] = "starter_mirror_guard"

	_open_round()
	combat._record_spell_cast_board_payoffs(_dmg("probe_bolt"))
	_check(not bool(mg.state.has_shield), "a DAMAGE spell does not glaze her")

	combat._record_spell_cast_board_payoffs(_nodmg("probe_ward"))
	_check(bool(mg.state.has_shield), "the first non-damage spell does")

	mg.state.has_shield = false
	combat._record_spell_cast_board_payoffs(_nodmg("probe_ward2"))
	_check(not bool(mg.state.has_shield),
		"latched: a second non-damage spell the same round pays nothing")

	_open_round()
	combat._record_spell_cast_board_payoffs(_nodmg("probe_ward3"))
	_check(bool(mg.state.has_shield), "the latch is per-round")


# ── 4. GLASS SAVANT + MIRROR PRIMER (the SHARED distinct-name latch) ─────────
func _t_glass_savant_and_primer() -> void:
	print("[retinue-hooks] --- starter_glass_savant + mirror_primer ---")
	await _settle()
	_only_relics(["mirror_primer"])
	var savant = _put(false, combat.ROW_FRONT, 1, 2, 3)
	var foe = _put(true, combat.ROW_FRONT, 1, 1, 60)
	if not _check(savant != null and foe != null, "fixture placed"): return
	savant.card_data["passive"] = "starter_glass_savant"

	_open_round()
	if not _check(combat._hand.size() < combat.MAX_HAND_SIZE,
			"hand has room for the Primer's draw (%d)" % combat._hand.size()): return
	var hp0: int = int(foe.current_hp)
	var hand0: int = combat._hand.size()
	combat._record_spell_cast_board_payoffs(_dmg("probe_alpha"))
	_check(int(foe.current_hp) == hp0 and combat._hand.size() == hand0,
		"one working is not two — neither fires")

	combat._record_spell_cast_board_payoffs(_dmg("probe_beta"))
	_check(hp0 - int(foe.current_hp) == 1,
		"the lens throws on the second DISTINCT name (dealt %d)" % [hp0 - int(foe.current_hp)])
	_check(combat._hand.size() == hand0 + 1,
		"...and the Primer draws on the SAME cast — one latch, two consumers (hand %d -> %d)"
			% [hand0, combat._hand.size()])

	var hp1: int = int(foe.current_hp)
	var hand1: int = combat._hand.size()
	combat._record_spell_cast_board_payoffs(_dmg("probe_alpha"))
	combat._record_spell_cast_board_payoffs(_dmg("probe_gamma"))
	_check(int(foe.current_hp) == hp1 and combat._hand.size() == hand1,
		"a THIRD distinct name in the same round pays neither of them again")

	# The forge's scalar is spell_ping_bonus, not a bare is_upgraded ternary.
	_open_round()
	savant.card_data["spell_ping_bonus"] = 1
	var hp2: int = int(foe.current_hp)
	combat._record_spell_cast_board_payoffs(_dmg("probe_delta"))
	combat._record_spell_cast_board_payoffs(_dmg("probe_epsilon"))
	_check(hp2 - int(foe.current_hp) == 2,
		"the forge reads spell_ping_bonus (dealt %d)" % [hp2 - int(foe.current_hp)])

	# Positional, exactly like Cinder Acolyte: an empty opposing column throws nothing.
	_open_round()
	combat._enemy_field[1] = null
	foe.queue_free()
	var hand2: int = combat._hand.size()
	combat._record_spell_cast_board_payoffs(_dmg("probe_zeta"))
	combat._record_spell_cast_board_payoffs(_dmg("probe_eta"))
	_check(combat._hand.size() == hand2 + 1,
		"an empty opposing column silences the lens but NOT the Primer")


# ── 5. FUNERAL LANTERN (relic, first friendly death each round) ──────────────
func _t_funeral_lantern() -> void:
	print("[retinue-hooks] --- funeral_lantern ---")
	await _settle()
	_only_relics(["funeral_lantern"])
	combat._funeral_lantern_used_this_round = false

	var body = _kill_ready(combat.ROW_FRONT, 0)
	body.card_data["on_death"] = {"type": "bonus_mana_next_turn", "value": 1}
	var before: int = int(combat._bonus_mana_next_turn)
	combat._on_friendly_death(body, 0)
	_check(int(combat._bonus_mana_next_turn) == before + 1,
		"the fallen's bequest is read a SECOND time (%d -> %d)"
			% [before, combat._bonus_mana_next_turn])

	var body2 = _kill_ready(combat.ROW_FRONT, 1)
	body2.card_data["on_death"] = {"type": "bonus_mana_next_turn", "value": 1}
	var before2: int = int(combat._bonus_mana_next_turn)
	combat._on_friendly_death(body2, 1)
	_check(int(combat._bonus_mana_next_turn) == before2,
		"the round's second death is not doubled (latched)")

	# undying_grow writes a PERMANENT run-wide +1/+1 through RunState. Read the
	# Will refuses it; so must this, or the Acolyte farms it one death per round.
	combat._funeral_lantern_used_this_round = false
	var body3 = _kill_ready(combat.ROW_FRONT, 2)
	body3.card_data["on_death"] = {"type": "undying_grow"}
	combat._on_friendly_death(body3, 2)
	_check(not combat._funeral_lantern_used_this_round,
		"a DENIED will (undying_grow) is refused and does not even spend the latch")

	combat._funeral_lantern_used_this_round = false
	var body4 = _kill_ready(combat.ROW_FRONT, 3)
	body4.card_data["on_death"] = {"type": "return_to_hand_once"}
	combat._on_friendly_death(body4, 3)
	_check(not combat._funeral_lantern_used_this_round,
		"...and so is return_to_hand_once")

	# A bequest-less corpse must not burn the round's reading either.
	combat._funeral_lantern_used_this_round = false
	var plain = _kill_ready(combat.ROW_BACK, 0)
	plain.card_data.erase("on_death")
	combat._on_friendly_death(plain, 0)
	_check(not combat._funeral_lantern_used_this_round,
		"a corpse with no will does not spend the reading")


# ── 6. LEDGER SEAL (relic) + the ordering trap ───────────────────────────────
func _t_ledger_seal() -> void:
	print("[retinue-hooks] --- ledger_seal ---")
	await _settle()
	# BOTH lanterns held on purpose: Soul Lantern raises a 1/1 Shade into the seat
	# the corpse just left, and the Seal must NOT hand the inheritance to it.
	_only_relics(["ledger_seal", "soul_lantern"])
	combat._ledger_seal_used_this_round = false
	combat._soul_lantern_used_this_round = false

	var heir = _put(false, combat.ROW_BACK, 0, 2, 4)
	var dying = _kill_ready(combat.ROW_FRONT, 0)
	if not _check(heir != null and dying != null, "fixture placed"): return
	combat._on_friendly_death(dying, 0)
	_check(int(heir.current_atk) == 3,
		"the column's survivor inherits +1 ATK for the fight (atk=%d)" % heir.current_atk)
	_check(int(heir.card_data.hp) == 5 and int(heir.current_hp) == 5,
		"...and +1 HP on BOTH current and max (%d/%d)" % [heir.current_hp, heir.card_data.hp])

	var shade = combat._player_field[0]
	_check(shade != null and is_instance_valid(shade),
		"Soul Lantern's Shade did land in the vacated seat")
	if shade != null and is_instance_valid(shade):
		_check(int(shade.current_atk) == 1,
			"...and did NOT take the inheritance — the column was sampled first (shade atk=%d)"
				% shade.current_atk)

	_check(combat._ledger_seal_used_this_round, "the payout spent the round's use")
	var heir2 = _put(false, combat.ROW_BACK, 3, 2, 4)
	var dying2 = _kill_ready(combat.ROW_FRONT, 3)
	combat._on_friendly_death(dying2, 3)
	_check(int(heir2.current_atk) == 2, "the round's second death pays nothing (latched)")

	# An emptied column must not burn the round's use ("no dead rewards").
	await _settle()
	_only_relics(["ledger_seal"])
	combat._ledger_seal_used_this_round = false
	var lone = _kill_ready(combat.ROW_FRONT, 2)
	combat._on_friendly_death(lone, 2)
	_check(not combat._ledger_seal_used_this_round,
		"a death in an emptied column does not spend the round's use")


# ── 7. BURIAL GOODS' column bequest (on_death, shares the Seal's helper) ─────
func _t_column_bequest() -> void:
	print("[retinue-hooks] --- starter_buff_column_ally ---")
	await _settle()
	_only_relics([])
	var survivor = _put(false, combat.ROW_FRONT, 2, 2, 3)
	if not _check(survivor != null, "fixture placed"): return
	KeywordEffects._run_on_death({"type": "starter_buff_column_ally", "atk": 1, "hp": 1},
		2, false, combat, combat.ROW_BACK)
	_check(int(survivor.current_atk) == 3,
		"the column-mate inherits +1 ATK (atk=%d)" % survivor.current_atk)
	_check(int(survivor.card_data.hp) == 4 and int(survivor.current_hp) == 4,
		"...and +1 HP, current AND max (%d/%d)" % [survivor.current_hp, survivor.card_data.hp])

	# Reads from EITHER row (the levy is a 0/2 that can be posted anywhere).
	var back_only = _put(false, combat.ROW_BACK, 3, 1, 2)
	KeywordEffects._run_on_death({"type": "starter_buff_column_ally", "atk": 1, "hp": 1},
		3, false, combat, combat.ROW_FRONT)
	_check(int(back_only.current_atk) == 2, "a back-row survivor also inherits")

	KeywordEffects._run_on_death({"type": "starter_buff_column_ally", "atk": 1, "hp": 1},
		1, false, combat, combat.ROW_BACK)
	_check(true, "an empty column does not crash")

	# The card the arm exists for is still shaped the way the arm reads it.
	var bg: Dictionary = CardDB.CARD_POOL["grave_goods_levy"]
	_check(String(bg.get("on_death", {}).get("type", "")) == "starter_buff_column_ally",
		"Burial Goods still carries the bequest this arm resolves")


# ── 8. CINDER CROWN (relic, first spell each round deals +1) ─────────────────
func _t_cinder_crown() -> void:
	print("[retinue-hooks] --- cinder_crown ---")
	await _settle()
	_only_relics(["cinder_crown"])
	combat._cinder_crown_used_this_round = false
	var foe = _put(true, combat.ROW_FRONT, 0, 1, 90)
	if not _check(foe != null, "fixture placed"): return

	# A non-damage opener must not silently burn it ("no dead rewards").
	await combat._resolve_spell(_nodmg("probe_scry"), null, -1)
	_check(not combat._cinder_crown_used_this_round,
		"a non-damage spell does not spend the crown")

	var before: int = int(foe.current_hp)
	await combat._resolve_spell(_card("strike"), foe, 0)
	_check(before - int(foe.current_hp) == 4,
		"the round's first damage spell deals 3+1 (dealt %d)" % [before - int(foe.current_hp)])
	_check(combat._cinder_crown_used_this_round, "...and spent the crown")

	var before2: int = int(foe.current_hp)
	await combat._resolve_spell(_card("strike"), foe, 0)
	_check(before2 - int(foe.current_hp) == 3,
		"the round's second damage spell is plain (dealt %d)" % [before2 - int(foe.current_hp)])

	combat._cinder_crown_used_this_round = false   # what _start_round does
	var before3: int = int(foe.current_hp)
	await combat._resolve_spell(_card("strike"), foe, 0)
	_check(before3 - int(foe.current_hp) == 4, "it re-arms next round")

	# The reshape must be readable on the relic, not just in the code.
	var cc: Dictionary = RelicDB.get_relic("cinder_crown")
	_check(not String(cc.get("desc", "")).to_lower().contains("costs 0"),
		"the desc no longer promises a free cast")
	_check(cc.get("hooks", []).has("spell_played"), "hooks name the spell beat")


# ── 9. WAR BELLOWS (relic reshape: +2/+2, no timer clause) ───────────────────
func _t_war_bellows() -> void:
	print("[retinue-hooks] --- war_bellows ---")
	await _settle()
	_only_relics(["war_bellows"])
	combat._war_bellows_used_this_round = false
	var doomed = _put(false, combat.ROW_FRONT, 0, 1, 3, ["doom"])
	if not _check(doomed != null, "fixture placed"): return
	doomed.card_data["doom"] = 4
	doomed.doom_counter = 4
	combat._apply_starter_creature_play_relics(doomed, combat.ROW_FRONT, 0)
	_check(int(doomed.current_atk) == 3 and int(doomed.current_hp) == 5,
		"+2/+2, not +1/+1 (%d/%d)" % [doomed.current_atk, doomed.current_hp])
	_check(int(doomed.card_data.get("atk", 0)) == 3 and int(doomed.card_data.get("hp", 0)) == 5,
		"...written to card_data too, so heals cap at the new max")
	_check(int(doomed.doom_counter) == 4,
		"the fuse is NOT pushed out any more (doom=%d)" % doomed.doom_counter)

	var doomed2 = _put(false, combat.ROW_FRONT, 1, 1, 3, ["doom"])
	doomed2.card_data["doom"] = 4
	doomed2.doom_counter = 4
	combat._apply_starter_creature_play_relics(doomed2, combat.ROW_FRONT, 1)
	_check(int(doomed2.current_atk) == 1, "the round's second Doom body pays nothing (latched)")

	var plain = _put(false, combat.ROW_FRONT, 2, 1, 3)
	combat._war_bellows_used_this_round = false
	combat._apply_starter_creature_play_relics(plain, combat.ROW_FRONT, 2)
	_check(int(plain.current_atk) == 1 and not combat._war_bellows_used_this_round,
		"a fuseless body neither gains nor spends the latch")

	var wb: Dictionary = RelicDB.get_relic("war_bellows")
	_check(not String(wb.get("desc", "")).to_lower().contains("timer"),
		"the desc no longer promises a timer push")


# ── 10. RESERVE STANDARD (normalised onto _grant_combat_shield) ──────────────
func _t_reserve_standard() -> void:
	print("[retinue-hooks] --- reserve_standard ---")
	await _settle()
	_only_relics(["reserve_standard"])
	combat._reserve_standard_used_this_round = false
	var front = _put(false, combat.ROW_FRONT, 1, 1, 3)
	var back = _put(false, combat.ROW_BACK, 1, 1, 3)
	if not _check(front != null and back != null, "fixture placed"): return
	combat._apply_starter_creature_play_relics(back, combat.ROW_BACK, 1)
	_check(bool(back.state.has_shield), "a body posted behind a friendly is shielded")

	# The normalisation: _grant_combat_shield refuses a dead body, where the raw
	# state write did not. (Its already-shielded guard is the other half, but a
	# no-op is not observable from outside — this arm is.)
	combat._reserve_standard_used_this_round = false
	var corpse = _put(false, combat.ROW_BACK, 2, 1, 3)
	var front2 = _put(false, combat.ROW_FRONT, 2, 1, 3)
	corpse.current_hp = 0
	combat._apply_starter_creature_play_relics(corpse, combat.ROW_BACK, 2)
	_check(not bool(corpse.state.has_shield),
		"a body already at 0 HP is not shielded (the guard the raw write skipped)")
	_check(front2 != null, "fixture held")


# ── 11. STANDARD PAGE's adj_buff.hp (a REMOVABLE max-HP aura) ────────────────
func _t_standard_page() -> void:
	print("[retinue-hooks] --- standard_page adj_buff.hp ---")
	await _settle()
	_only_relics([])
	_check(int(CardDB.CARD_POOL["standard_page"].get("adj_buff", {}).get("hp", 0)) == 1,
		"the card still prints the aura this wiring serves")

	var page = _put(false, combat.ROW_FRONT, 2, 0, 3)
	var row_mate = _put(false, combat.ROW_FRONT, 1, 2, 3)
	var col_mate = _put(false, combat.ROW_BACK, 2, 2, 3)
	var far = _put(false, combat.ROW_FRONT, 0, 2, 3)
	if not _check(page != null and row_mate != null and col_mate != null and far != null,
			"fixture placed"): return
	page.card_data["adj_buff"] = {"atk": 0, "hp": 1}

	combat._refresh_adjacency_buffs()
	_check(int(row_mate.card_data.hp) == 4 and int(row_mate.current_hp) == 4,
		"the row neighbour gains +1 HP, current AND max (%d/%d)"
			% [row_mate.current_hp, row_mate.card_data.hp])
	_check(int(col_mate.card_data.hp) == 4,
		"the COLUMN-MATE gains it too — canonical adjacency (%d)" % col_mate.card_data.hp)
	_check(int(far.card_data.hp) == 3,
		"a non-neighbour is untouched (%d)" % far.card_data.hp)

	combat._refresh_adjacency_buffs()
	combat._refresh_adjacency_buffs()
	_check(int(row_mate.card_data.hp) == 4,
		"repeated sweeps do not stack (%d) — this is a ledger, not an increment"
			% row_mate.card_data.hp)

	# Wound it, then drop the banner: the aura comes back OFF, floored at 1.
	row_mate.current_hp = 2
	combat._player_field[2] = null
	page.queue_free()
	combat._refresh_adjacency_buffs()
	_check(int(row_mate.card_data.hp) == 3,
		"max HP returns when the banner falls (%d)" % row_mate.card_data.hp)
	_check(int(row_mate.current_hp) == 1,
		"...and so does current HP (%d)" % row_mate.current_hp)

	# The floor: losing the aura must never kill (this runs inside _cleanup_dead).
	await _settle()
	var page2 = _put(false, combat.ROW_FRONT, 2, 0, 3)
	var frail = _put(false, combat.ROW_FRONT, 1, 1, 1)
	page2.card_data["adj_buff"] = {"atk": 0, "hp": 1}
	combat._refresh_adjacency_buffs()
	frail.current_hp = 1
	combat._player_field[2] = null
	page2.queue_free()
	combat._refresh_adjacency_buffs()
	_check(is_instance_valid(frail) and int(frail.current_hp) == 1,
		"a body on 1 HP survives the banner falling (hp=%d)" % frail.current_hp)


# ── 12. FUSE TENDER's adjacency (now canonical) ──────────────────────────────
func _t_fuse_tender() -> void:
	print("[retinue-hooks] --- starter_fuse_tender adjacency ---")
	await _settle()
	_only_relics([])
	var tender = _put(false, combat.ROW_FRONT, 1, 1, 3)
	var row_mate = _put(false, combat.ROW_FRONT, 2, 1, 3, ["doom"])
	var col_mate = _put(false, combat.ROW_BACK, 1, 1, 3, ["doom"])
	var far = _put(false, combat.ROW_FRONT, 3, 1, 3, ["doom"])
	if not _check(tender != null and row_mate != null and col_mate != null, "fixture placed"):
		return
	for d in [row_mate, col_mate, far]:
		d.card_data["doom"] = 4
		d.doom_counter = 4
	tender.card_data["on_play"] = {"type": "starter_fuse_tender", "value": 1}
	combat._resolve_on_play_ability(tender, 1, false)
	_check(int(row_mate.current_atk) == 2, "the row neighbour is reached (atk=%d)" % row_mate.current_atk)
	_check(int(col_mate.current_atk) == 2,
		"the COLUMN-MATE is reached — 'adjacent' means the same thing on every card (atk=%d)"
			% col_mate.current_atk)
	_check(int(col_mate.doom_counter) == 5, "...and its fuse gained a round (doom=%d)" % col_mate.doom_counter)
	_check(int(far.current_atk) == 1, "a non-neighbour is untouched")


# ── helpers ──────────────────────────────────────────────────────────────────
func _card(id: String) -> Dictionary:
	return CardDB.CARD_POOL[id].duplicate(true)


## A synthetic DAMAGE spell with a chosen id, so "differently named" is exact.
func _dmg(id: String) -> Dictionary:
	return {"id": id, "name": id, "type": "spell", "cost": 1,
		"spell": {"type": "damage", "value": 1}, "targeting": "any_creature"}


## A synthetic NON-damage spell (the same classifier Worn Spellbook uses).
func _nodmg(id: String) -> Dictionary:
	return {"id": id, "name": id, "type": "spell", "cost": 1,
		"spell": {"type": "draw", "value": 1}, "targeting": "none"}


## Open a fresh round for the spell-payoff family, exactly as _start_round does.
func _open_round() -> void:
	combat._spells_cast_this_turn = 0
	combat._starter_spell_ids_this_round.clear()
	combat._starter_non_damage_spell_seen_this_round = false
	combat._starter_second_distinct_seen_this_round = false


## Take exact control of the relic cache. _has_relic rebuilds from RunState when
## the cache is EMPTY, so a sentinel keeps the cleared set from refilling itself.
func _only_relics(ids: Array) -> void:
	combat._relic_set.clear()
	combat._relic_set["__probe_sentinel__"] = true
	for id in ids:
		combat._relic_set[String(id)] = true


## Drop a synthetic body with exact stats, via the engine's own token primitive
## (the _probe_overkill / _probe_retinue_spells convention).
func _put(is_enemy: bool, row: int, lane: int, atk: int, hp: int, kw: Array = []):
	combat.summon_token(atk, hp, lane, is_enemy, row, {}, "Probe Body", kw)
	var card = combat._row_array(is_enemy, row)[lane]
	if card == null:
		return null
	card.state.ready_to_swing = true
	card.has_attacked_this_turn = false
	return card


## A player body posted and then UNSEATED, which is the state _on_friendly_death
## is always called in: _on_card_destroyed nulls the slot arrays before dispatch
## so on_death effects (and Soul Lantern) see the vacated seat.
func _kill_ready(row: int, lane: int):
	var card = _put(false, row, lane, 1, 1)
	if card == null:
		return null
	combat._row_array(false, row)[lane] = null
	return card


## Clear the board BETWEEN sections, but let the previous section's decorative FX
## tweens expire first — a bare queue_free() strands live tween lambdas holding
## the node and the engine prints "Lambda capture at index N was freed", harness
## noise that reads exactly like a real defect.
func _settle() -> void:
	await get_tree().create_timer(0.9).timeout
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(combat.LANES_PER_ROW):
				if arr[i] != null and is_instance_valid(arr[i]):
					arr[i].queue_free()
				arr[i] = null
	await get_tree().create_timer(0.2).timeout


func _find_act1_combat() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat":
			return String(id)
	return "goblin_scouts"


func _check(ok: bool, label: String) -> bool:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		printerr("  FAIL  " + label)
	return ok
