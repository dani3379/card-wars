extends SceneTree
## Probe for the 2026-07-07 skirmish battle-relic draft + net discard flow.
##
## Covers, without sockets (same fake-peer trick as _probe_skirmish_combat):
##   1. SkirmishState.NET_RELIC_POOL / NET_POTION_POOL: every entry is a real
##      RelicDB relic / non-targeted PotionDB potion.
##   2. Net combat honors the drafted relic: a host with Deep Satchel refills
##      to 6 (5 base + 1), _has_relic answers from the slot (never RunState),
##      and the HUD relic rail shows the drafted chip.
##   3. The end-of-turn discard flush works in net (hand-local piles) and the
##      EV_DISCARD_FX intent routes into the foe-discard fx without crashing.
##   4. Net potions: the drafted potion shows in the belt, Rallying Horn adds
##      +2 Command caster-local, the heal routes through _net_heal_hero, and
##      EV_POTION_FX routes without crashing.
##   5. The NetDraft scene runs relic slate → potion slate → card triplets; each
##      pick lands in the local slot, and the finished handoff ships the potion.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_draft_relic.gd

var _fails: int = 0
var _started: bool = false
var _done: bool = false

var SS: Node
var NM: Node
var RDB: Node
var combat: Node


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _unique_count(items: Array) -> int:
	var seen := {}
	for item in items:
		seen[String(item)] = true
	return seen.size()


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_test()
	return _done


func _run_test() -> void:
	print("[draft-relic] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	RDB = root.get_node_or_null("RelicDB")
	if SS == null or NM == null or RDB == null:
		print("[draft-relic] FATAL: autoloads missing")
		_finish(1)
		return

	# ── 1. The net relic + potion pools are made of real entries ─────────────
	_check(SS.NET_RELIC_POOL.size() >= 12,
		"net battle relic pool has broad variety (got %d)" % SS.NET_RELIC_POOL.size())
	for rid in SS.NET_RELIC_POOL:
		_check(not RDB.get_relic(String(rid)).is_empty(), "pool relic exists: %s" % rid)
	var PDB = root.get_node_or_null("PotionDB")
	_check(SS.NET_POTION_POOL.size() >= 10,
		"net battle potion pool has broad variety (got %d)" % SS.NET_POTION_POOL.size())
	var supported_potion_effects := [
		"heal_hp", "gain_mana", "draw", "aoe_enemies", "chain_lightning",
		"shield_wall", "summon_recruits", "revive_last_dead", "column_strike",
		"grant_rampage", "grant_lifelink", "sacrifice_for_command",
		"detonate_doom_all",
	]
	for ppid in SS.NET_POTION_POOL:
		var pd: Dictionary = PDB.get_potion(String(ppid)) if PDB != null else {}
		_check(not pd.is_empty() and String(pd.get("effect", "")) in supported_potion_effects,
			"pool potion exists + has a net-supported effect: %s" % ppid)
	var relic_union := {}
	var relic_slates_unique := true
	for seed in range(24):
		var rrng := RandomNumberGenerator.new()
		rrng.seed = 7000 + seed
		var slate: Array = SS.deal_unique_cards(SS.NET_RELIC_POOL, 3, rrng)
		if _unique_count(slate) != slate.size():
			relic_slates_unique = false
		for slate_rid in slate:
			relic_union[String(slate_rid)] = true
	_check(relic_slates_unique, "sampled relic slates have no internal duplicates")
	_check(relic_union.size() >= 12,
		"sampled relic slates cover the expanded pool (got %d)" % relic_union.size())
	var potion_union := {}
	var potion_slates_unique := true
	for seed in range(18):
		var prng := RandomNumberGenerator.new()
		prng.seed = 9000 + seed
		var pslate: Array = SS.deal_unique_cards(SS.NET_POTION_POOL, 3, prng)
		if _unique_count(pslate) != pslate.size():
			potion_slates_unique = false
		for slate_pid in pslate:
			potion_union[String(slate_pid)] = true
	_check(potion_slates_unique, "sampled potion slates have no internal duplicates")
	_check(potion_union.size() >= 7,
		"sampled potion slates cover the expanded pool (got %d)" % potion_union.size())

	# ── 2 + 3. Net combat with a drafted Deep Satchel + Rallying Horn ────────
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "strike", "goblin",
			"strike", "brute", "goblin"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 4242
	SS.slots[0].relics = ["deep_satchel"]
	SS.slots[0].potions = ["mana_surge"]
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0
	NM.entities.clear()
	NM._next_entity_id = 1

	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()   # headless: skip the parked texture prebake
	# Draws deal in staggered (~80ms apart) — wait until the count is STABLE
	# across two ticks so we never sample mid-deal.
	var last_n := -1
	for _tick in 12:
		await create_timer(0.4).timeout
		if not is_instance_valid(combat):
			break
		var n: int = combat._hand.size()
		if n > 0 and n == last_n:
			break
		last_n = n
	if not is_instance_valid(combat):
		_check(false, "combat scene survived boot")
		_finish(1)
		return

	_check(combat._has_relic("deep_satchel"), "_has_relic reads the drafted slot relic in net")
	_check(not combat._has_relic("snecko_eye"), "unpicked relics stay absent in net")
	_check(combat._hand.size() == 6, "Deep Satchel refilled the net hand to 6 (got %d)" % combat._hand.size())
	var chips: int = combat._relic_panel.get_child_count() if combat._relic_panel != null else 0
	_check(chips == 1, "HUD relic rail shows exactly the drafted chip (got %d)" % chips)

	# Net discard flush: mark one card, flush hand-locally.
	var victim = combat._hand[0]
	combat._on_card_dismiss_requested(victim)
	_check(victim.marked_for_discard, "marking works during the host's net window")
	var d0: int = combat._player_discard_pile.size()
	var shed: int = combat._flush_marked_discards()
	_check(shed == 1 and combat._player_discard_pile.size() == d0 + 1,
		"net flush moved the marked card to the local discard pile")

	# Foe-discard fx event routes without error (intent + event switches).
	combat._on_net_intent(2, {"t": NM.EV_DISCARD_FX, "n": 2})
	await create_timer(0.2).timeout
	_check(true, "EV_DISCARD_FX intent routed (no crash)")

	# ── Net potions: the drafted potion shows in the belt and resolves ──────
	_check(combat._ctx_potions().has("mana_surge"), "drafted potion sits in the net belt")
	_check(combat._net_potion_slots == 1, "belt froze at the drafted count (got %d)" % combat._net_potion_slots)
	# Rallying Horn is caster-local (+2 Command): resolve + consume in-place.
	combat._net_active_index = 0
	var mana_before: int = combat.player_mana
	combat._net_use_potion("mana_surge", 0)
	await create_timer(0.1).timeout
	_check(combat.player_mana == mana_before + 2, "Rallying Horn gained +2 Command (%d→%d)" % [mana_before, combat.player_mana])
	_check(combat._ctx_potions().is_empty(), "the drafted potion was consumed from the slot")
	# Host heal potion routes through the authoritative _net_heal_hero.
	combat._net_my_slot().potions = ["healing"]
	combat._net_potion_slots = 1
	combat.player_hp = 10
	combat._net_use_potion("healing", 0)
	await create_timer(0.1).timeout
	_check(combat.player_hp == 18, "Healing potion healed the host hero 10→18 (got %d)" % combat.player_hp)
	combat._net_my_slot().potions = ["conscript_brew"]
	combat._net_potion_slots = 1
	var recruits_before: int = combat._all_player_creatures().size()
	combat._net_use_potion("conscript_brew", 0)
	await create_timer(0.15).timeout
	var recruits_after: int = combat._all_player_creatures().size()
	_check(recruits_after >= recruits_before + 2,
		"Conscription Brew summoned two host-side recruits (%d->%d)" % [recruits_before, recruits_after])
	_check(combat._ctx_potions().is_empty(), "host-authoritative board potion consumed from the slot")
	# Foe-potion fx routes from both directions without crashing.
	combat._on_net_intent(2, {"t": NM.EV_POTION_FX, "pid": "healing"})
	await create_timer(0.15).timeout
	_check(true, "EV_POTION_FX intent routed (no crash)")

	combat.queue_free()
	await create_timer(0.3).timeout

	# ── 4. The draft scene opens on the relic slate ──────────────────────────
	NM.start_vs_bot(SS.MatchMode.DRAFT, 1)
	var draft = load("res://scenes/net_draft.tscn").instantiate()
	root.add_child(draft)
	await create_timer(0.4).timeout
	if not is_instance_valid(draft):
		_check(false, "draft scene survived boot")
		_finish(1)
		return
	_check(draft._relic_stage, "draft opens on the battle-relic stage")
	var slots: int = draft._card_row.get_child_count()
	_check(slots == 4, "relic slate shows 3 relics + the decline column (got %d)" % slots)
	draft._on_relic_pick("deep_satchel")
	await create_timer(0.2).timeout
	_check(not draft._relic_stage, "picking a relic ends the relic stage")
	_check(SS.local_slot().relics.has("deep_satchel"), "the pick landed in the local slot's relics")

	# ── The POTION slate follows the relic (pick 1 of 3 or decline) ──────────
	_check(draft._potion_stage, "potion slate follows the relic stage")
	_check(String(draft._header.text).begins_with("Choose a battle potion"),
		"header prompts for a potion")
	var pslots: int = draft._card_row.get_child_count()
	_check(pslots == 4, "potion slate shows 3 potions + the decline column (got %d)" % pslots)
	draft._on_potion_pick("healing")
	await create_timer(0.2).timeout
	_check(not draft._potion_stage, "picking a potion ends the potion stage")
	_check(SS.local_slot().potions.has("healing"), "the pick landed in the local slot's potions")
	_check(String(draft._header.text).begins_with("Pick a card"), "card picks follow the potion stage")

	# One card pick still works after the two opening stages.
	var legal: Array = SS.skirmish_legal_pool()
	draft._on_pick(String(legal[0]))
	await create_timer(0.2).timeout
	_check(SS.local_slot().deck.size() == 1, "card picks still fill the deck after the opening stages")

	# The finished handoff ships the potion; the opponent stores it.
	var opp_before: Array = SS.get_slot(SS.opponent_index()).potions.duplicate()
	draft._on_draft_event({"t": "finished", "cards": ["brute"], "relics": ["lantern"],
		"potions": ["insight_tonic"]})
	await create_timer(0.1).timeout
	_check(SS.get_slot(SS.opponent_index()).potions.has("insight_tonic"),
		"opponent's drafted potion stored from the finished handoff")
	draft.queue_free()
	await create_timer(0.2).timeout

	_finish(_fails)


func _finish(code: int) -> void:
	if code == 0:
		print("[draft-relic] ALL PASS")
	else:
		print("[draft-relic] FAILED: %d checks" % code)
	_done = true
	quit(code)
