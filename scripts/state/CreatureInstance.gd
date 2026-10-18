extends RefCounted
class_name CreatureInstance
## Authoritative gameplay state for one creature instance.
##
## This object deliberately contains no Node, Control, RID, Resource, Callable,
## or scene reference. It can therefore be copied into saves/network snapshots,
## tested headlessly, and owned by Card2D without creating a reference cycle.
## Card2D remains the view/input adapter and exposes compatibility properties
## while combat call sites migrate to `card.state`.

const SNAPSHOT_VERSION: int = 1

# Identity and board position.
var current_hp: int = 0
var current_atk: int = 0
var lane: int = -1
var row: int = 0
var is_opponent: bool = false
var is_on_battlefield: bool = false
var is_token: bool = false

# Turn/combat lifecycle.
## The muster delay: a body that entered play this round has not formed up yet
## and does not swing in the clash that ends the round it arrived in. Defaults
## FALSE so every arrival path gets the delay for free — there is no single
## "creature enters the board" funnel (seven placement sites plus six move
## sites), and stamping arrivals by hand would silently miss one and re-stamp
## the moves. Combat._start_round() sweeps every body on the board to true, and
## CombatNet routes through that same _start_round, so solo and skirmish share
## one rule. Swift is the exception (see Card2D.can_attack).
var ready_to_swing: bool = false
var has_attacked_this_turn: bool = false
var will_floop: bool = false
var has_flooped_this_turn: bool = false
var last_stand_used: bool = false
var temp_atk_buff: int = 0
var persistent_atk_buff: int = 0
var persistent_atk_buff_rounds: int = 0
var adjacency_atk_buff: int = 0
## Relic ATK bonus, state-DERIVED like adjacency_atk_buff: Combat rewrites it in
## _refresh_adjacency_buffs at every board mutation and nothing else may write it.
## It exists because the six ATK relics (swift_boots / glass_cannon /
## linked_banner / champions_belt / phalanx_stone, and steady_banner's round-1
## −1) used to be added inside Combat._effective_attack, OUTSIDE the card — so
## the wax seal printed a number the creature did not swing for. May be NEGATIVE;
## Card2D.effective_atk() floors the total, not the component.
var relic_atk_buff: int = 0
var doom_counter: int = -999

# Per-round flags.
var stunned: bool = false
var is_frozen: bool = false
var temp_armored: bool = false
var temp_thorns: bool = false
var temp_poison: bool = false
# THE VOLLEY (Soldier signature, 2026-07-30) grants Piercing for one clash. It
# needs its own erase order for the same reason temp_poison does: a Soldier that
# PRINTS Piercing must not have the printed keyword stripped at round end because
# a round-scoped grant happened to land on it.
var temp_piercing: bool = false
var bonus_thorns: int = 0
var redirecting: bool = false
var challenge_any_lane: bool = false
var charges_this_turn: bool = false
var battle_order_second_strike: bool = false
var enrage_vulnerable: bool = false
var marked: bool = false
var will_retreat: bool = false
# Roving Sellsword may take one free reposition per owning turn.
var free_move_used: bool = false
var war_cry_swift: bool = false
var drummer_swift: bool = false
var shield_wall_thorns: bool = false
# Pike Square (square_thorns passive): Thorns only while a friendly stands
# beside it. State-DERIVED like drummer_swift / hp_floor — cleared and
# recomputed in Combat._refresh_adjacency_buffs at every board mutation, so the
# pikes drop the moment the square opens. Never set it outside that sweep.
var square_thorns: bool = false
# The Old King's Body: only a creature's strike touches it — no spells, no
# abilities, no keywords, no potions, no relics. Set from the encounter passive
# at placement; read through Combat._is_effect_immune.
var effect_immune: bool = false
var inspire_piercing: bool = false
var counter_spent_this_clash: bool = false
var mummified_zero: bool = false
var pact_of_embers_zero: bool = false
var sealed_pending: bool = false

# Persistent/fight flags.
var has_shield: bool = false
var hp_floor: bool = false
var reborn_used: bool = false
var body_snatcher_used: bool = false
var linked_banner_buffed: bool = false
var steady_banner_locked: bool = false
var ready_to_ignite: bool = false
var martyr_chosen: bool = false
var familiar_pick_uid: int = -1
var wormwood_stacks: int = 0
var gravepact_round: int = -1
var offering_extra_on_death: int = 0
var pay_wagon_gold: int = 0
var credit_due_round: int = 999999

# Enemy intent state.
var current_intent: String = "ATK"
var last_intent: String = "ATK"
var intent_consecutive: int = 0
var intent_cycle_pos: int = 0


func tick_end_of_round() -> void:
	stunned = false
	is_frozen = false
	temp_armored = false
	temp_thorns = false
	temp_poison = false
	temp_piercing = false
	bonus_thorns = 0
	redirecting = false
	challenge_any_lane = false
	charges_this_turn = false
	battle_order_second_strike = false
	enrage_vulnerable = false
	marked = false
	will_retreat = false
	war_cry_swift = false
	shield_wall_thorns = false
	square_thorns = false
	inspire_piercing = false
	counter_spent_this_clash = false


func reset_temp_state() -> void:
	has_shield = false
	tick_end_of_round()


func to_snapshot() -> Dictionary:
	return {
		"v": SNAPSHOT_VERSION,
		"hp": current_hp, "atk": current_atk,
		"lane": lane, "row": row,
		"opp": is_opponent, "field": is_on_battlefield, "token": is_token,
		"ready": ready_to_swing,
		"attacked": has_attacked_this_turn,
		"will_floop": will_floop, "flooped": has_flooped_this_turn,
		"last_stand": last_stand_used,
		"temp_atk": temp_atk_buff,
		"persistent_atk": persistent_atk_buff,
		"persistent_rounds": persistent_atk_buff_rounds,
		"adj_atk": adjacency_atk_buff, "relic_atk": relic_atk_buff,
		"doom": doom_counter,
		"stunned": stunned, "frozen": is_frozen, "shield": has_shield,
		"temp_armored": temp_armored, "temp_thorns": temp_thorns,
		"temp_poison": temp_poison, "temp_piercing": temp_piercing,
		"bonus_thorns": bonus_thorns,
		"redirecting": redirecting, "challenge": challenge_any_lane,
		"charges": charges_this_turn, "second_strike": battle_order_second_strike,
		"vulnerable": enrage_vulnerable, "marked": marked,
		"retreat": will_retreat, "free_move_used": free_move_used,
		"war_cry_swift": war_cry_swift,
		"drummer_swift": drummer_swift,
		"wall_thorns": shield_wall_thorns, "square_thorns": square_thorns,
		"inspire_piercing": inspire_piercing,
		"counter_spent": counter_spent_this_clash, "hp_floor": hp_floor,
		# effect_immune rides beside hp_floor: both are "this body ignores a
		# class of harm" flags, and both must survive a board reconcile. It was
		# the ONE declared field missing from this dict (audited against all 60),
		# so a snapshot silently cleared it and The Old King's Body would take
		# spell/keyword/potion damage on the receiving peer.
		"effect_immune": effect_immune,
		"mummified_zero": mummified_zero,
		"pact_zero": pact_of_embers_zero, "sealed_pending": sealed_pending,
		"reborn_used": reborn_used, "snatcher_used": body_snatcher_used,
		"banner_buffed": linked_banner_buffed,
		"banner_locked": steady_banner_locked,
		"ready_to_ignite": ready_to_ignite, "martyr": martyr_chosen,
		"familiar_uid": familiar_pick_uid, "wormwood": wormwood_stacks,
		"gravepact_round": gravepact_round,
		"extra_on_death": offering_extra_on_death,
		"pay_wagon_gold": pay_wagon_gold, "credit_due": credit_due_round,
		"intent": current_intent, "last_intent": last_intent,
		"intent_n": intent_consecutive, "intent_pos": intent_cycle_pos,
	}


## Runtime fields safe to replicate on top of an existing local card instance.
## Position, ownership and attack components are excluded: board sync already
## sends those in viewer-relative form and sends effective ATK as a folded value.
func to_replication_snapshot() -> Dictionary:
	var data := to_snapshot()
	for key in [
		"hp", "atk", "lane", "row", "opp", "field", "token",
		"temp_atk", "persistent_atk", "persistent_rounds", "adj_atk",
		# relic_atk is an ATK COMPONENT like the four above: board sync sends the
		# folded effective ATK, so replicating the component too would add the
		# relic bonus a second time on the receiving peer.
		"relic_atk",
	]:
		data.erase(key)
	return data


func apply_snapshot(data: Dictionary) -> void:
	# Safe defaults keep older snapshots readable.
	current_hp = int(data.get("hp", current_hp))
	current_atk = int(data.get("atk", current_atk))
	lane = int(data.get("lane", lane))
	row = clampi(int(data.get("row", row)), 0, 1)
	is_opponent = bool(data.get("opp", is_opponent))
	is_on_battlefield = bool(data.get("field", is_on_battlefield))
	is_token = bool(data.get("token", is_token))
	# Legacy snapshots (pre-muster-delay) carry no "ready" key. Default TRUE on
	# read so a restored save or an older peer's board doesn't freeze every body
	# for a round — absent information must not become a phantom penalty.
	ready_to_swing = bool(data.get("ready", true))
	has_attacked_this_turn = bool(data.get("attacked", false))
	will_floop = bool(data.get("will_floop", false))
	has_flooped_this_turn = bool(data.get("flooped", false))
	last_stand_used = bool(data.get("last_stand", false))
	temp_atk_buff = int(data.get("temp_atk", 0))
	persistent_atk_buff = int(data.get("persistent_atk", 0))
	persistent_atk_buff_rounds = maxi(0, int(data.get("persistent_rounds", 0)))
	adjacency_atk_buff = int(data.get("adj_atk", 0))
	# Legacy snapshots (pre-2026-07-28) carry no "relic_atk". Default 0, not the
	# current value: it is re-derived by the next _refresh_adjacency_buffs sweep,
	# and a stale bonus surviving a restore would be the same false seal this
	# field was added to kill.
	relic_atk_buff = int(data.get("relic_atk", 0))
	doom_counter = int(data.get("doom", -999))
	stunned = bool(data.get("stunned", false))
	is_frozen = bool(data.get("frozen", false))
	has_shield = bool(data.get("shield", false))
	temp_armored = bool(data.get("temp_armored", false))
	temp_thorns = bool(data.get("temp_thorns", false))
	temp_poison = bool(data.get("temp_poison", false))
	temp_piercing = bool(data.get("temp_piercing", false))
	bonus_thorns = int(data.get("bonus_thorns", 0))
	redirecting = bool(data.get("redirecting", false))
	challenge_any_lane = bool(data.get("challenge", false))
	charges_this_turn = bool(data.get("charges", false))
	battle_order_second_strike = bool(data.get("second_strike", false))
	enrage_vulnerable = bool(data.get("vulnerable", false))
	marked = bool(data.get("marked", false))
	will_retreat = bool(data.get("retreat", false))
	free_move_used = bool(data.get("free_move_used", false))
	war_cry_swift = bool(data.get("war_cry_swift", false))
	drummer_swift = bool(data.get("drummer_swift", false))
	shield_wall_thorns = bool(data.get("wall_thorns", false))
	square_thorns = bool(data.get("square_thorns", false))
	inspire_piercing = bool(data.get("inspire_piercing", false))
	counter_spent_this_clash = bool(data.get("counter_spent", false))
	mummified_zero = bool(data.get("mummified_zero", false))
	pact_of_embers_zero = bool(data.get("pact_zero", false))
	sealed_pending = bool(data.get("sealed_pending", false))
	hp_floor = bool(data.get("hp_floor", false))
	# Defaults false, so an older snapshot that predates the key still applies.
	effect_immune = bool(data.get("effect_immune", false))
	reborn_used = bool(data.get("reborn_used", false))
	body_snatcher_used = bool(data.get("snatcher_used", false))
	linked_banner_buffed = bool(data.get("banner_buffed", false))
	steady_banner_locked = bool(data.get("banner_locked", false))
	ready_to_ignite = bool(data.get("ready_to_ignite", false))
	martyr_chosen = bool(data.get("martyr", false))
	familiar_pick_uid = int(data.get("familiar_uid", -1))
	wormwood_stacks = maxi(0, int(data.get("wormwood", 0)))
	gravepact_round = int(data.get("gravepact_round", -1))
	offering_extra_on_death = maxi(0, int(data.get("extra_on_death", 0)))
	pay_wagon_gold = maxi(0, int(data.get("pay_wagon_gold", 0)))
	credit_due_round = int(data.get("credit_due", 999999))
	current_intent = String(data.get("intent", "ATK"))
	last_intent = String(data.get("last_intent", "ATK"))
	intent_consecutive = maxi(0, int(data.get("intent_n", 0)))
	intent_cycle_pos = maxi(0, int(data.get("intent_pos", 0)))
