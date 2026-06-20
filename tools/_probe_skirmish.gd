extends SceneTree
## Logic probe — Online Skirmish (docs/MULTIPLAYER_SKIRMISH_PLAN.md). No rendering,
## no sockets: it verifies the pure net logic that a live 2-machine test can't
## cheaply re-check, and the Combat methods that touch only SkirmishState/NetMatch
## (not scene nodes) on a bare instance.
##
## Covers: the skirmish-legal draft pool (size / determinism / denylist / curses /
## type filter), denylist + supported-spell lists are real CardDB ids (catch
## typos), the deterministic uid scheme (slots don't collide), the mode flags
## (_is_net/_is_host/_is_client), the owner→side perspective map (the bug-prone
## bit), the _ctx_* deck/HP/mana routing, and _net_spell_supported gating.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_skirmish.gd
## (No save state is touched — this is read-only against the data layer + autoloads.)

var _fails: int = 0
var CDB: Node
var SS: Node
var NM: Node


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	print("[skirmish-probe] start")
	CDB = root.get_node_or_null("CardDB")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	if CDB == null or SS == null or NM == null:
		print("[skirmish-probe] FATAL: autoloads not found (CardDB/SkirmishState/NetMatch)")
		quit(1)
		return true

	_test_legal_pool()
	_test_denylist_real()
	_test_uid_scheme()
	_test_supported_spells_real()
	_test_mode_flags_and_perspective()
	_test_ctx_routing()
	_test_series_format()

	if _fails == 0:
		print("[skirmish-probe] ALL PASS")
	else:
		print("[skirmish-probe] %d FAILURES" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _test_legal_pool() -> void:
	print("— skirmish-legal draft pool")
	var pool: Array = SS.skirmish_legal_pool()
	_check(pool.size() >= 60, "pool is large enough for 1-of-3 x20 x2 (got %d, need >=60)" % pool.size())
	# Determinism: two calls return the SAME ordered list (host & client must agree).
	var pool2: Array = SS.skirmish_legal_pool()
	_check(pool == pool2, "pool is deterministic (identical order across calls)")
	# No denylisted card leaks in.
	var leaked: Array = []
	for id in SS.SKIRMISH_DENYLIST:
		if pool.has(id):
			leaked.append(id)
	_check(leaked.is_empty(), "no denylisted card in the pool (leaked: %s)" % str(leaked))
	# Every entry is a real, draftable creature/spell (no curses/enemy/tokens).
	var bad: Array = []
	for id in pool:
		var d: Dictionary = CDB.get_card_data(id)
		if d.is_empty() or not (String(d.get("type", "")) in ["creature", "spell"]):
			bad.append(id)
		elif CDB.is_curse(id):
			bad.append(id)
	_check(bad.is_empty(), "every pool entry is a real creature/spell, no curses (bad: %s)" % str(bad))


func _test_denylist_real() -> void:
	print("— denylist ids are real cards (catch typos)")
	var ghosts: Array = []
	for id in SS.SKIRMISH_DENYLIST:
		if CDB.get_card_data(id).is_empty():
			ghosts.append(id)
	_check(ghosts.is_empty(), "every denylist id resolves in CardDB (ghosts: %s)" % str(ghosts))
	_check(SS.SKIRMISH_DENYLIST.size() > 0, "denylist is non-empty (curation applied)")


func _test_uid_scheme() -> void:
	print("— deterministic uid scheme (slots never collide)")
	SS.reset()
	# Draft a few cards into each slot; uids must be unique across both slots and
	# reproducible (slot_index * STRIDE + position).
	var u00: int = SS.add_card_to(0, "goblin")
	var u01: int = SS.add_card_to(0, "goblin")
	var u10: int = SS.add_card_to(1, "goblin")
	var u11: int = SS.add_card_to(1, "goblin")
	_check(u00 == 0 and u01 == 1, "slot-0 uids count from 0 (got %d, %d)" % [u00, u01])
	_check(u10 == SS.UID_SLOT_STRIDE and u11 == SS.UID_SLOT_STRIDE + 1,
		"slot-1 uids offset by STRIDE (got %d, %d)" % [u10, u11])
	var all := {u00: 1, u01: 1, u10: 1, u11: 1}
	_check(all.size() == 4, "all four uids are distinct (no cross-slot collision)")
	# A full 20-card slot 0 never reaches slot 1's id space.
	SS.reset()
	for i in 20:
		SS.add_card_to(0, "goblin")
	var max0: int = SS.get_slot(0).deck_uids.back()
	_check(max0 < SS.UID_SLOT_STRIDE, "20 slot-0 uids stay below STRIDE (max %d)" % max0)
	SS.reset()


func _test_supported_spells_real() -> void:
	print("— net-supported spell lists reference real spells (catch typos)")
	var combat = load("res://scripts/scenes/Combat.gd").new()
	# Build a quick map of every draftable spell's id -> its spell sub-dict.
	var draftable_spell_ids := {}      # card id -> spell.type
	var custom_spell_ids := {}         # spell.id -> true  (custom resolver keys)
	for id in SS.skirmish_legal_pool():
		var d: Dictionary = CDB.get_card_data(id)
		if String(d.get("type", "")) != "spell":
			continue
		var sp: Dictionary = d.get("spell", {})
		draftable_spell_ids[id] = String(sp.get("type", ""))
		if String(sp.get("type", "")) == "custom":
			custom_spell_ids[String(sp.get("id", ""))] = true
	# Every NET_SPELL_TYPES value is a type some real draftable spell actually uses
	# (so the gate isn't advertising support for a type no card has).
	var live_types := {}
	for t in draftable_spell_ids.values():
		live_types[t] = true
	var unused_types: Array = []
	for t in SS.NET_SPELL_TYPES:
		if not live_types.has(t):
			unused_types.append(t)
	# Informational rather than fatal — a type with no current card is harmless.
	if not unused_types.is_empty():
		print("    note: NET_SPELL_TYPES with no draftable card yet: ", unused_types)
	# Every NET_SPELL_CUSTOMS id MUST be a real custom spell in the legal pool, or
	# clicking that card would advertise support and then no-op.
	var ghost_customs: Array = []
	for cid in SS.NET_SPELL_CUSTOMS:
		if not custom_spell_ids.has(cid):
			ghost_customs.append(cid)
	_check(ghost_customs.is_empty(),
		"every NET_SPELL_CUSTOMS id is a real custom spell (ghosts: %s)" % str(ghost_customs))
	# At least one supported spell of each major shape exists in the pool, so the
	# feature is actually reachable in a draft.
	var has_targeted := false
	var has_face := false
	for id in draftable_spell_ids:
		var t: String = draftable_spell_ids[id]
		if t == "damage":
			has_targeted = true
		elif t == "damage_face":
			has_face = true
	_check(has_targeted, "a 'damage' (targeted) spell is draftable")
	_check(has_face, "a 'damage_face' spell is draftable")
	combat.free()


func _test_mode_flags_and_perspective() -> void:
	print("— mode flags + owner→side perspective map")
	var combat = load("res://scripts/scenes/Combat.gd").new()
	# SOLO
	combat.combat_mode = combat.CombatMode.SOLO
	_check(not combat._is_net(), "SOLO: _is_net() false")
	# HOST (local index 0)
	combat.combat_mode = combat.CombatMode.NET_HOST
	NM.local_player_index = 0
	_check(combat._is_net() and combat._is_host() and not combat._is_client(),
		"NET_HOST: is_net & is_host, not client")
	# Host renders itself (owner 0) on the player side (is_enemy=false) and the
	# client (owner 1) on the enemy side (is_enemy=true).
	_check(combat._side_for_owner(0) == false, "host: own creatures (owner 0) -> player side")
	_check(combat._side_for_owner(1) == true, "host: client creatures (owner 1) -> enemy side")
	# CLIENT (local index 1) — the mirror.
	combat.combat_mode = combat.CombatMode.NET_CLIENT
	NM.local_player_index = 1
	_check(combat._is_net() and combat._is_client() and not combat._is_host(),
		"NET_CLIENT: is_net & is_client, not host")
	_check(combat._side_for_owner(1) == false, "client: own creatures (owner 1) -> player side")
	_check(combat._side_for_owner(0) == true, "client: host creatures (owner 0) -> enemy side")
	combat.free()


func _test_ctx_routing() -> void:
	print("— _ctx_* deck/HP/mana routing through SkirmishState")
	var combat = load("res://scripts/scenes/Combat.gd").new()
	SS.reset()
	SS.add_card_to(0, "goblin")
	SS.add_card_to(0, "strike")
	SS.add_card_to(1, "brute")
	SS.local_index = 0
	NM.local_player_index = 0
	combat.combat_mode = combat.CombatMode.NET_HOST
	var deck: Array = combat._ctx_deck()
	_check(deck.size() == 2 and String(deck[0]) == "goblin", "host _ctx_deck() = slot-0 deck")
	_check(combat._ctx_deck_uids().size() == 2, "host _ctx_deck_uids() parallels the deck")
	_check(combat._ctx_hero_hp() == SS.START_HP, "host _ctx_hero_hp() = START_HP (%d)" % SS.START_HP)
	_check(combat._ctx_max_mana() == SS.BASE_MAX_MANA, "host _ctx_max_mana() = BASE_MAX_MANA")
	# Switch the local view to the client slot: ctx must follow local_index.
	SS.local_index = 1
	NM.local_player_index = 1
	combat.combat_mode = combat.CombatMode.NET_CLIENT
	var cdeck: Array = combat._ctx_deck()
	_check(cdeck.size() == 1 and String(cdeck[0]) == "brute", "client _ctx_deck() = slot-1 deck")
	# Supported-spell gate: a damage spell is supported, an exotic type is not.
	var strike: Dictionary = CDB.get_card_data("strike")
	if not strike.is_empty() and String(strike.get("type", "")) == "spell":
		_check(combat._net_spell_supported(strike), "'strike' (a damage spell) is net-supported")
	var fake_unsupported := {"type": "spell", "spell": {"type": "shuffle_into_draw"}}
	_check(not combat._net_spell_supported(fake_unsupported),
		"an unsupported spell type is refused by the gate")
	combat.free()
	SS.reset()


## Best-of-N series math (SkirmishState) — the spine of the Best-of-3 mode. Pure
## state, no scene nodes, so we exercise it directly.
func _test_series_format() -> void:
	print("— best-of-N series format")
	SS.best_of = 3
	SS.reset_series()
	_check(SS.games_to_win() == 2, "Bo3 needs 2 game wins (got %d)" % SS.games_to_win())
	_check(SS.series_leader() == -1, "fresh series has no leader")
	SS.record_game_winner(0)
	_check(SS.series_wins[0] == 1 and SS.series_game == 2,
		"game 1 to slot 0 -> 1-0, game counter at 2")
	_check(SS.series_leader() == -1, "1-0 is not yet a clinch")
	SS.record_game_winner(-1)   # a draw credits neither side but advances the game
	_check(SS.series_wins == [1, 0] and SS.series_game == 3, "a draw advances the counter only")
	SS.record_game_winner(0)
	_check(SS.series_leader() == 0, "slot 0 clinches the series at 2 wins")
	# Bo1 degenerates to first-to-1.
	SS.best_of = 1
	SS.reset_series()
	_check(SS.games_to_win() == 1, "Bo1 needs 1 game win")
	SS.record_game_winner(1)
	_check(SS.series_leader() == 1, "Bo1 clinches on the first win")
	SS.best_of = 1
	SS.reset_series()
