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
##   5. The NetDraft scene runs the shared ARSENAL stage (3 relic slates + 2
##      potion slates by default, pass allowed per slate —
##      NetDeckBuilder._begin_arsenal, 2026-07-16) → card triplets; picks land in
##      the local slot, and the finished handoff ships the whole arsenal.
##   6. ARSENAL SIZE IS THE HOST'S (2026-09-14): the stage deals exactly the
##      configured number of rounds, a zero/zero setting raises no stage at all,
##      the host's loadout authority caps at the SAME number the stage dealt, and
##      NetMatch's mirrored defaults still equal SkirmishState's constants (they
##      cannot be read from NetMatch's field initializers — autoload order).
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_draft_relic.gd

var _fails: int = 0
var _started: bool = false
var _done: bool = false
## Wall-clock ceiling on the whole run. Generous — the widest-arsenal section
## alone drives 14 dealt tables — but BOUNDED. See _process.
const WATCHDOG_MS: int = 900000
var _start_ms: int = 0

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


## Wait until the stage has actually DEALT its table. `_on_ars_pick` refuses a
## slate that is still assembling (NetDeckBuilder guards on `_ars_slate_ready`,
## because the tiles arrive one per rendered frame), so a probe that fires picks
## back to back SILENTLY no-ops every one after the first — the stage stays put
## and every later assertion reads the wrong round. Poll the public accessor.
func _await_slate(screen: Node) -> void:
	for _tick in 60:
		if not is_instance_valid(screen) or not screen.arsenal_active():
			return
		if screen.arsenal_slate_ready():
			return
		await create_timer(0.05).timeout


## A structurally legal deck of the exact target size, for the loadout-authority
## checks. validate_loadout_event tests the DECK before the arsenal, so a probe
## that passes an empty card list is answered "loadout_deck_size" and proves
## nothing about the arsenal cap it meant to exercise.
func _legal_deck() -> Array:
	var pool: Array = SS.skirmish_legal_pool()
	var out: Array = []
	for id in pool:
		if out.size() >= SS.DECK_TARGET:
			break
		out.append(String(id))
	return out


func _unique_count(items: Array) -> int:
	var seen := {}
	for item in items:
		seen[String(item)] = true
	return seen.size()


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_start_ms = Time.get_ticks_msec()
		_run_test()
	# THE WATCHDOG, and it is not paranoia — it is the documented GDScript trap
	# turned on the harness itself. A RUNTIME error (an out-of-range index, a
	# write to a freed node) aborts _run_test WHERE IT STANDS: it does not raise,
	# does not stop the process, and never reaches _finish(). `_done` then stays
	# false forever and this SceneTree spins with nothing left to do. Measured
	# once, for real: `NET_RELIC_POOL[14]` on a 14-entry pool left a headless
	# Godot running 43 minutes, holding 377MB, until it was killed by hand — and
	# the harness reported the run as merely "timed out", which reads like a slow
	# probe rather than a dead one. Fail LOUDLY and with a nonzero code instead.
	if not _done and Time.get_ticks_msec() - _start_ms > WATCHDOG_MS:
		printerr("[draft-relic] WATCHDOG at %ds — _run_test never reached _finish. "
			% (WATCHDOG_MS / 1000)
			+ "Look for a SCRIPT ERROR above: it aborted the coroutine silently.")
		_finish(1)
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
	# THE THIRD TERM (2026-08-05). `is_connected_to_peer()` is
	# `vs_bot or (_connected and remote_present and _compatibility_confirmed)`,
	# and this probe set only the first two — so Combat booted SOLO, `_has_relic`
	# never consulted the drafted skirmish slot, and both assertions failed
	# while appearing to test the net path. This is the documented skirmish-probe
	# trap: miss a term and the harness silently measures the campaign instead.
	NM._compatibility_confirmed = true
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

	# ── 4. The draft opens on the shared ARSENAL stage (3 relics + 2 potions,
	#       NetDeckBuilder._begin_arsenal — 2026-07-16) ────────────────────────
	NM.start_vs_bot(SS.MatchMode.DRAFT, 1)
	var draft = load("res://scenes/net_draft.tscn").instantiate()
	root.add_child(draft)
	await create_timer(0.4).timeout
	if not is_instance_valid(draft):
		_check(false, "draft scene survived boot")
		_finish(1)
		return
	_check(draft.arsenal_active(), "draft opens on the arsenal stage")
	# 2026-07-19 restage: the slate row holds the 3 offering tiles; PASS moved to
	# its own quiet button below the row (_ars_pass_btn).
	var slots: int = draft._ars_row.get_child_count()
	_check(slots == 3, "relic slate shows 3 relic tiles (got %d)" % slots)
	_check(draft._ars_pass_btn != null and is_instance_valid(draft._ars_pass_btn)
		and draft._ars_pass_btn.visible, "the pass action exists below the slate")
	_check(String(draft._ars_header.text).begins_with("Choose a battle relic — 1 of 3"),
		"header prompts for relic 1 of 3")
	draft._on_ars_pick("deep_satchel", true)
	_check(SS.local_slot().relics.has("deep_satchel"), "relic pick 1 landed in the local slot")
	_check(String(draft._ars_header.text).begins_with("Choose a battle relic — 2 of 3"),
		"a second relic slate follows")
	await _await_slate(draft)
	draft._on_ars_pick("lantern", true)
	await _await_slate(draft)
	draft._on_ars_pick("", true)   # round 3: pass — fighting lighter is legal
	await create_timer(0.15).timeout
	_check(SS.local_slot().relics.size() == 2, "two picks + one pass = 2 relics held")
	_check(String(draft._ars_header.text).begins_with("Choose a battle potion — 1 of 2"),
		"potion slates follow the relic rounds")
	var pslots: int = draft._ars_row.get_child_count()
	_check(pslots == 3, "potion slate shows 3 potion tiles (got %d)" % pslots)
	await _await_slate(draft)
	draft._on_ars_pick("healing", false)
	_check(String(draft._ars_header.text).begins_with("Choose a battle potion — 2 of 2"),
		"a second potion slate follows")
	await _await_slate(draft)
	draft._on_ars_pick("insight_tonic", false)
	await create_timer(0.15).timeout
	_check(SS.local_slot().potions.size() == 2, "both potion picks landed in the local slot")
	_check(not draft.arsenal_active(), "the arsenal closes after the 3+2 rounds")
	_check(String(draft._header.text).begins_with("Pick a card"), "card picks follow the arsenal")

	# One card pick still works after the two opening stages. The triplet builds
	# progressively (one card per rendered frame) and `_on_pick` refuses until it
	# is dealt — the same shape as the arsenal slate above, so wait, don't sleep.
	for _tick in 60:
		if not is_instance_valid(draft) or draft._triplet_ready:
			break
		await create_timer(0.05).timeout
	_check(draft._triplet_ready, "the card triplet finished dealing")
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

	# ── 5. THE ARSENAL SIZE IS THE HOST'S PICK (2026-09-14) ──────────────────
	# NetMatch cannot read SkirmishState's constants from a field initializer
	# (it is registered FIRST in the autoload order), so its defaults are hand
	# mirrored. That mirror is the one thing here a future edit can silently
	# break — a drifted default would open a stage of one length and validate
	# the peer against another.
	NM.leave()
	_check(NM.arsenal_relics == SS.ARSENAL_RELIC_ROUNDS
		and NM.arsenal_potions == SS.ARSENAL_POTION_ROUNDS,
		"NetMatch's mirrored arsenal defaults match SkirmishState's constants (%d/%d vs %d/%d)"
			% [NM.arsenal_relics, NM.arsenal_potions,
				SS.ARSENAL_RELIC_ROUNDS, SS.ARSENAL_POTION_ROUNDS])
	# Every offered round must deal a FULL table. A slate is ARSENAL_SLATE_SIZE ids
	# never re-dealt, so the ceiling is pool/3 — a hardcoded one was wrong the day
	# it was typed (NET_RELIC_POOL holds 14, so five rounds would deal a short
	# fifth table). Both defaults must also sit under their own ceiling.
	var rmax: int = SS.arsenal_relic_max()
	var pmax: int = SS.arsenal_potion_max()
	# A relic is held or not held, so a round past the pool's last distinct id
	# cannot add anything — that, not pool/3, is the relic ceiling now that the
	# lap rule keeps every table full past the first pass through the pool.
	_check(rmax >= 1 and rmax <= SS.NET_RELIC_POOL.size(),
		"the relic ceiling (%d rounds) is the pool's distinct count (%d ids)"
			% [rmax, SS.NET_RELIC_POOL.size()])
	# Potions are capped by the COMBAT BELT, not the pool: the shelf is
	# 16 + n*52 + (n-1)*6 wide against the board's left edge at x272.
	_check(pmax >= 1 and pmax <= SS.NET_POTION_POOL.size()
			and 16 + pmax * 52 + (pmax - 1) * 6 <= 272,
		"the potion ceiling (%d rounds) fits both the pool (%d) and the belt (%dpx)"
			% [pmax, SS.NET_POTION_POOL.size(), 16 + pmax * 52 + (pmax - 1) * 6])
	_check(16 + (pmax + 1) * 52 + pmax * 6 > 272,
		"one more potion than the ceiling would put the belt through the board")
	_check(SS.ARSENAL_RELIC_ROUNDS <= rmax and SS.ARSENAL_POTION_ROUNDS <= pmax,
		"the shipped defaults (%d/%d) sit inside the ceilings (%d/%d)"
			% [SS.ARSENAL_RELIC_ROUNDS, SS.ARSENAL_POTION_ROUNDS, rmax, pmax])

	# An out-of-range config is REFUSED rather than clamped on the wire — the two
	# peers must agree on the number, and a silently narrowed one would not.
	NM.is_host = false
	var before_relics: int = NM.arsenal_relics
	NM._apply_match_config(SS.MatchMode.DRAFT, 1, NM.STYLE_ALTERNATING, 99, 1)
	_check(NM.arsenal_relics == before_relics,
		"an over-ceiling arsenal count is rejected, not clamped")
	NM._apply_match_config(SS.MatchMode.DRAFT, 1, NM.STYLE_ALTERNATING, rmax, 1)
	_check(NM.arsenal_relics == rmax and NM.arsenal_potions == 1,
		"a legal arsenal count crosses the wire (got %d/%d)"
			% [NM.arsenal_relics, NM.arsenal_potions])
	# A peer that predates the setting sends NEITHER key. That must leave the
	# stage at its default, never at zero — a bare int() on a missing key is 0.
	NM._apply_match_config(SS.MatchMode.DRAFT, 1, NM.STYLE_ALTERNATING)
	_check(NM.arsenal_relics == rmax and NM.arsenal_potions == 1,
		"a payload with no arsenal keys leaves the count alone (got %d/%d)"
			% [NM.arsenal_relics, NM.arsenal_potions])

	# A configured stage deals exactly that many rounds, on both categories.
	NM.start_vs_bot(SS.MatchMode.DRAFT, 1, rmax, 1)
	var big = load("res://scenes/net_draft.tscn").instantiate()
	root.add_child(big)
	await create_timer(0.4).timeout
	if not is_instance_valid(big):
		_check(false, "the wide-arsenal draft scene survived boot")
		_finish(1)
		return
	_check(SS.arsenal_relics == rmax and SS.arsenal_potions == 1,
		"begin_session adopted the host's arsenal size (got %d/%d)"
			% [SS.arsenal_relics, SS.arsenal_potions])
	_check(big._ars_pips.size() == rmax + 1,
		"the progress rail is one pip per pick (got %d, want %d)"
			% [big._ars_pips.size(), rmax + 1])
	_check(String(big._ars_header.text).begins_with(
			"Choose a battle relic — 1 of %d" % rmax),
		"the header counts against the configured size, got: %s" % big._ars_header.text)
	var dealt_relics := 0
	var short_table := ""
	for _i in rmax:
		await _await_slate(big)
		if not big.arsenal_active():
			break
		if String(big._ars_header.text).begins_with("Choose a battle relic"):
			dealt_relics += 1
			# Every offered round must lay a FULL table — the reason the ceiling
			# is derived from the pool rather than written down.
			if big._ars_row.get_child_count() != SS.ARSENAL_SLATE_SIZE:
				short_table = "round %d dealt %d tiles" % [
					dealt_relics, big._ars_row.get_child_count()]
		big._on_ars_pick("", true)
	_check(dealt_relics == rmax,
		"the widest legal stage dealt %d relic slates (got %d)" % [rmax, dealt_relics])
	_check(short_table == "",
		"every relic round at the ceiling dealt a full table%s"
			% ("" if short_table == "" else " — " + short_table))
	_check(String(big._ars_header.text).begins_with("Choose a battle potion — 1 of 1"),
		"the single potion round follows, got: %s" % big._ars_header.text)
	await _await_slate(big)
	big._on_ars_pick("", false)
	await create_timer(0.2).timeout
	_check(not big.arsenal_active(), "the stage closes after %d + 1 rounds" % rmax)
	# The host's own authority must cap where the stage did. The DECK is filled
	# first: validate_loadout_event tests deck size before the arsenal, so an
	# empty card list answers "loadout_deck_size" and proves nothing here.
	var deck: Array = _legal_deck()
	var held: Array = []
	for rid in SS.NET_RELIC_POOL:
		if held.size() < rmax:
			held.append(String(rid))
	_check(SS.validate_loadout_event({"cards": deck, "relics": held, "potions": []},
			SS.MatchMode.DRAFT) == "",
		"a full-arsenal loadout passes when the host set %d rounds" % rmax)
	# One MORE than the stage offered. At the ceiling the pool has no unused id
	# left to add, so this repeats one — and the size check runs BEFORE the
	# distinctness loop, so "loadout_arsenal_size" is still the exact verdict
	# under test (the bare-steel case below covers the same cap from zero).
	held.append(String(SS.NET_RELIC_POOL[0]))
	_check(SS.validate_loadout_event({"cards": deck, "relics": held, "potions": []},
			SS.MatchMode.DRAFT) == "loadout_arsenal_size",
		"one relic past the configured stage is refused")
	# THE LAP RULE. Below pool/3 rounds nothing changes (no lap ever turns over),
	# which is what makes the shipped 3+2 stage byte-identical to before it
	# existed; past that, tables stay FULL instead of being dealt short or empty.
	var lap_rng := RandomNumberGenerator.new()
	lap_rng.seed = 1234
	var lap_seen: Array = []
	var lap_rounds: Array = []
	for _i in rmax:
		lap_rounds.append(SS.deal_arsenal_slate(SS.NET_RELIC_POOL, lap_rng, lap_seen))
	var all_full := true
	var first_lap_unique := {}
	var laps_turned := 0
	for i in lap_rounds.size():
		var table: Array = lap_rounds[i]
		if table.size() != SS.ARSENAL_SLATE_SIZE:
			all_full = false
		if i < SS.NET_RELIC_POOL.size() / SS.ARSENAL_SLATE_SIZE:
			for id in table:
				if first_lap_unique.has(String(id)):
					laps_turned += 1
				first_lap_unique[String(id)] = true
	_check(all_full, "every table is full at the ceiling, all %d of them" % rmax)
	_check(laps_turned == 0,
		"no id repeats inside the first lap (got %d repeats)" % laps_turned)
	_check(_unique_count(lap_rounds[0]) == SS.ARSENAL_SLATE_SIZE,
		"a table never offers the same id twice")

	var offers: Dictionary = SS.arsenal_source_offers(NM.match_seed, 0)
	_check(offers.get("relics", []).size() == rmax
			and offers.get("potions", []).size() == 1,
		"the host rebuilds the SAME number of slates it dealt (got %d/%d)"
			% [offers.get("relics", []).size(), offers.get("potions", []).size()])
	big.queue_free()
	await create_timer(0.2).timeout

	# Zero and zero: a bare-steel duel raises no stage at all, and the card draft
	# still opens — the finish callback has to fire for a stage that never built.
	NM.start_vs_bot(SS.MatchMode.DRAFT, 1, 0, 0)
	var bare = load("res://scenes/net_draft.tscn").instantiate()
	root.add_child(bare)
	await create_timer(0.5).timeout
	if not is_instance_valid(bare):
		_check(false, "the bare-steel draft scene survived boot")
		_finish(1)
		return
	_check(not bare.arsenal_active(), "a 0+0 arsenal never raises the stage")
	_check(String(bare._header.text).begins_with("Pick a card"),
		"the card draft still opens with no arsenal, got: %s" % bare._header.text)
	_check(SS.validate_loadout_event({"cards": _legal_deck(),
			"relics": [String(SS.NET_RELIC_POOL[0])], "potions": []},
			SS.MatchMode.DRAFT) == "loadout_arsenal_size",
		"with no arsenal dealt, ANY submitted relic is refused")

	# THE BOT FIGHTS UNDER THE SAME TERMS, and it has to for a mechanical reason
	# as well as a fair one: its emulated handoff goes through the very same
	# loadout authority a human peer's does (only PROVENANCE is skipped for a
	# drill). A bot that drafts a fixed 3 relics into a bare-steel match is
	# refused "loadout_arsenal_size" — and a refused handoff never finishes, so
	# the drill waits forever on an opponent that already answered.
	var rejected := ""
	var on_reject := func(reason: String) -> void: rejected = reason
	NM.protocol_rejected.connect(on_reject)
	NM.send_draft_event({"t": "finished", "cards": _legal_deck(),
		"relics": [], "potions": []})
	await create_timer(0.3).timeout
	NM.protocol_rejected.disconnect(on_reject)
	var bot_slot = SS.get_slot(SS.opponent_index())
	_check(rejected == "",
		"the bot's handoff is accepted at a 0-relic arsenal (rejected: '%s')" % rejected)
	_check(bot_slot != null and bot_slot.relics.is_empty(),
		"the bot drafts no relics when the host set none (got %s)"
			% str(bot_slot.relics if bot_slot != null else []))
	_check(bot_slot != null and bot_slot.deck.size() == SS.DECK_TARGET,
		"the bot's deck still landed, so the drill can actually start (got %d)"
			% (bot_slot.deck.size() if bot_slot != null else -1))
	bare.queue_free()
	await create_timer(0.2).timeout

	_finish(_fails)


func _finish(code: int) -> void:
	if code == 0:
		print("[draft-relic] ALL PASS")
	else:
		print("[draft-relic] FAILED: %d checks" % code)
	_done = true
	quit(code)
