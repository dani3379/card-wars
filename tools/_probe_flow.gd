extends SceneTree
## Auto-exercise the NON-COMBAT scene flow — stability hardening (2026-06-18).
##
## The event EFFECT layer is already verified clean (tools/_probe_events.gd:
## 338 non-modal _apply_effect calls, 0 crashes). THE GAP this probe fills is
## everything that probe SKIPPED because it needs a live scene tree + button
## handlers:
##   • Event MODAL pickers (MODAL_EFFECTS): copy/remove(+variants)/butcher/
##     mirror_twin/upgrade(+multi)/stranger_hand/relic_sacrifice/sacrifice/
##     transform/dice_run/risk_loop/pawn_appraisal — each builds a picker and
##     resolves on click. We invoke the _start_* entry and drive the _on_*
##     pick/confirm/again handlers to resolution.
##   • Wayside verbs: drill_yard / muster_scale / standard_bearer / supply_cache.
##   • Recruit (Muster draft), Reward rolls, Shop/Rest/Treasure logic.
##
## Strategy (mirrors _probe_events): the scene is instantiated AND added to the
## tree (pickers build real Card2D children, so they need a parent in the tree),
## but we never let _ready auto-route — for Event we set _event_id/_current_node
## by hand; for the others _ready is harmless (it builds the first screen).
## Fixtures vary hp/gold/deck/potions/curses/relics so floor/cap/empty branches
## all run, and edge fixtures (1-card deck, 0 gold, full potions, no creatures,
## no non-starting relics) hit the "graceful empty" paths.
##
## Detection: a marker prints before each picker/scene. Capture stdout+stderr
## and scan for SCRIPT ERROR / "Invalid" between markers. We also assert RunState
## invariants after each driver (hp in [0,max], gold >= 0, deck not empty, deck
## and deck_uids in sync) and print an [INVARIANT] line on any violation.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_flow.gd

const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]

var RS: Node
var CDB: Node
var RDB: Node

var _drivers := 0
var _invariant_fails := 0
var _seq := 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	print("[flow] start")
	RS  = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	RDB = root.get_node_or_null("RelicDB")
	if RS == null or CDB == null or RDB == null:
		print("[flow] FATAL: autoloads missing")
		quit(1)
		return

	_run_event_modals()
	_run_wayside()
	_run_recruit()
	_run_reward()
	_run_treasure()
	_run_shop()
	_run_rest()

	print("[flow] ============ SUMMARY ============")
	print("[flow] drivers run     : %d" % _drivers)
	print("[flow] invariant fails : %d" % _invariant_fails)
	print("[flow] (scan the log for SCRIPT ERROR / Invalid / [INVARIANT] to find a bug)")
	print("[flow] DONE")
	quit(0)


# ── Fixtures ──────────────────────────────────────────────────────────────

func _new_run(kind: String) -> void:
	_seq += 1
	var hero: String = HEROES[_seq % HEROES.size()]
	RS.start_new_run(hero, 0, 4242 + _seq)
	match kind:
		"rich":
			RS.gold = 800
			RS.hero_hp = RS.hero_max_hp
			RS.add_potion("healing")
			RS.add_potion("healing")
			RS.add_card(CDB.random_curse_id())
			# A non-starting relic so relic_sacrifice has something to chew.
			var combat: Array = RDB.roll_relic_reward("combat", RS.relics, RS.current_hero_id)
			if combat.size() > 0:
				RS.add_relic(combat[0])
		"poor":
			RS.gold = 0
			RS.hero_hp = 1
		"full_potions":
			RS.gold = 200
			RS.hero_hp = RS.hero_max_hp
			while RS.can_add_potion():
				RS.add_potion("healing")
		"one_card":
			# Strip the deck down to a single card — every remove/sacrifice/
			# transform picker has a "deck.size() > 1" guard somewhere.
			RS.gold = 50
			RS.hero_hp = 5
			while RS.deck.size() > 1:
				RS.remove_card_at(RS.deck.size() - 1)
		"all_curse":
			# A deck that is ALL curses — sacrifice/transform/appraisal must not
			# crash when nothing qualifies.
			RS.gold = 100
			RS.hero_hp = 10
			while RS.deck.size() > 0:
				RS.remove_card_at(0)
			for _i in range(4):
				RS.add_card(CDB.random_curse_id())
		_:
			RS.gold = 150
			RS.hero_hp = maxi(1, int(RS.hero_max_hp * 0.5))


func _check_invariants(where: String) -> void:
	var bad: Array = []
	if RS.hero_hp < 0:
		bad.append("hp<0 (%d)" % RS.hero_hp)
	if RS.hero_hp > RS.hero_max_hp:
		bad.append("hp>max (%d/%d)" % [RS.hero_hp, RS.hero_max_hp])
	if RS.hero_max_hp < 1:
		bad.append("max_hp<1 (%d)" % RS.hero_max_hp)
	if RS.gold < 0:
		bad.append("gold<0 (%d)" % RS.gold)
	if RS.deck.size() < 1:
		bad.append("deck empty")
	if RS.deck.size() != RS.deck_uids.size():
		bad.append("deck/uids desync (%d/%d)" % [RS.deck.size(), RS.deck_uids.size()])
	if RS.potions.size() > RS.MAX_POTIONS:
		bad.append("potions>max (%d)" % RS.potions.size())
	if not bad.is_empty():
		_invariant_fails += 1
		print("[flow] [INVARIANT] %s -> %s" % [where, ", ".join(bad)])


## Make a fresh non-tree-routed scene instance, add it to the tree, and (for
## Event) plant a chosen event so _ready's _pick_event doesn't randomize. We
## stop the scene's _ready from running by adding AFTER manually wiring state:
## actually _ready DOES run on add_child, so we route it harmlessly — for Event
## we override _event_id right after.
func _make_scene(path: String) -> Node:
	var node = load(path).instantiate()
	root.add_child(node)
	return node


func _free_scene(node: Node) -> void:
	if is_instance_valid(node):
		node.free()


# ── Event modal pickers ─────────────────────────────────────────────────────

func _run_event_modals() -> void:
	print("[flow] === EVENT MODAL PICKERS ===")
	# copy_card (single + multi via re-entry), remove family, butcher,
	# mirror_twin, upgrade (single+multi), stranger_hand, relic_sacrifice,
	# sacrifice (gold/max_hp/relic), transform (1+2), dice_run (add+double),
	# risk_loop (bust+jackpot), pawn_appraisal.
	for fixture in ["rich", "poor", "one_card", "all_curse", "full_potions"]:
		_drive_remove_pickers(fixture)
		_drive_copy_picker(fixture)
		_drive_butcher_mirror(fixture)
		_drive_upgrade_pickers(fixture)
		_drive_stranger_hand(fixture)
		_drive_relic_sacrifice(fixture)
		_drive_sacrifice(fixture)
		_drive_transform(fixture)
		_drive_dice_run(fixture)
		_drive_risk_loop(fixture)
		_drive_appraisal(fixture)


## Event needs a parked event id so _show_result (which reads _event_data.name
## via _build_risk_screen etc.) has something. We hand-set it after _ready.
func _event_scene(event_id: String = "butcher") -> Node:
	var ev = _make_scene("res://scenes/event.tscn")
	var EvScript = load("res://scripts/scenes/Event.gd")
	ev._event_id = event_id
	ev._event_data = EvScript.EVENTS[event_id]
	ev._current_node = ev._event_data
	return ev


func _drive_remove_pickers(fixture: String) -> void:
	# remove_choice
	_new_run(fixture)
	print("[flow] remove_choice [%s] deck=%d" % [fixture, RS.deck.size()])
	var ev = _event_scene("woodcutter")
	ev._start_remove_mode()
	if RS.deck.size() > 0:
		ev._on_remove_pick(0)
	_check_invariants("remove_choice/%s" % fixture)
	_free_scene(ev); _drivers += 1

	# remove_choice_multi (value 2 and 3)
	_new_run(fixture)
	print("[flow] remove_choice_multi [%s] deck=%d" % [fixture, RS.deck.size()])
	ev = _event_scene("hermit")
	ev._start_multi_remove_mode(3)
	# Drive picks until the loop ends or deck would hit floor.
	var guard := 0
	while ev._multi_remove_remaining > 0 and RS.deck.size() > 1 and guard < 10:
		ev._on_multi_remove_pick(0, 3)
		guard += 1
	_check_invariants("remove_choice_multi/%s" % fixture)
	_free_scene(ev); _drivers += 1

	# remove_choice_filtered (curse + starter)
	for filt in ["curse", "starter"]:
		_new_run(fixture)
		print("[flow] remove_filtered(%s) [%s] deck=%d" % [filt, fixture, RS.deck.size()])
		ev = _event_scene("sin_eater")
		ev._start_remove_filtered_mode(filt)
		# If matches existed the picker built; resolve a pick on a matching index.
		var idx := _first_match_index(filt)
		if idx >= 0:
			ev._on_remove_filtered_pick(idx, filt)
		_check_invariants("remove_filtered_%s/%s" % [filt, fixture])
		_free_scene(ev); _drivers += 1

	# remove_choice_all_copies
	_new_run(fixture)
	print("[flow] remove_all_copies [%s] deck=%d" % [fixture, RS.deck.size()])
	ev = _event_scene("hermit")
	ev._start_remove_all_copies_mode("starter")
	var cid := _first_starter_id()
	if cid != "":
		ev._on_remove_all_copies_pick(cid)
	_check_invariants("remove_all_copies/%s" % fixture)
	_free_scene(ev); _drivers += 1


func _drive_copy_picker(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] copy_card x2 [%s] deck=%d" % [fixture, RS.deck.size()])
	var ev = _event_scene("glass_familiar")
	ev._start_copy_mode(2, "pre")
	var guard := 0
	while ev._copy_remaining > 0 and RS.deck.size() > 0 and guard < 6:
		ev._on_copy_pick(0)
		guard += 1
	_check_invariants("copy_card/%s" % fixture)
	_free_scene(ev); _drivers += 1


func _drive_butcher_mirror(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] butcher_buff [%s] deck=%d" % [fixture, RS.deck.size()])
	var ev = _event_scene("butcher")
	ev._start_butcher_mode()
	var ci := _first_creature_index()
	if ci >= 0:
		ev._on_butcher_pick(ci)
	_check_invariants("butcher/%s" % fixture)
	_free_scene(ev); _drivers += 1

	_new_run(fixture)
	print("[flow] mirror_twin_buff [%s] deck=%d" % [fixture, RS.deck.size()])
	ev = _event_scene("mirror_twin")
	ev._start_mirror_twin_mode()
	ci = _first_creature_index()
	if ci >= 0:
		ev._on_mirror_twin_pick(ci)
	_check_invariants("mirror_twin/%s" % fixture)
	_free_scene(ev); _drivers += 1


func _drive_upgrade_pickers(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] upgrade_choice [%s] deck=%d" % [fixture, RS.deck.size()])
	var ev = _event_scene("beekeeper")
	ev._start_upgrade_mode(1)
	var ui := _first_upgradeable_index()
	if ui >= 0:
		ev._on_upgrade_choice_pick(ui)
	_check_invariants("upgrade_choice/%s" % fixture)
	_free_scene(ev); _drivers += 1

	_new_run(fixture)
	print("[flow] upgrade_choice_multi(2) [%s] deck=%d" % [fixture, RS.deck.size()])
	ev = _event_scene("beekeeper_again")
	ev._start_upgrade_mode(2)
	var guard := 0
	while ev._upgrade_choice_remaining > 0 and guard < 12:
		var i := _first_upgradeable_index()
		if i < 0:
			break
		ev._on_upgrade_choice_pick(i)
		guard += 1
	_check_invariants("upgrade_choice_multi/%s" % fixture)
	_free_scene(ev); _drivers += 1


func _drive_stranger_hand(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] stranger_hand_pick [%s] deck=%d" % [fixture, RS.deck.size()])
	var ev = _event_scene("strangers_hand")
	ev._start_stranger_hand_mode()
	# Resolve a pick on each cost kind to hit all three branches over fixtures.
	var rares: Array = CDB.cards_of_rarity("rare")
	if rares.size() > 0:
		var costs := [
			{"kind": "hp", "value": 8, "label": "x"},
			{"kind": "gold", "value": 80, "label": "x"},
			{"kind": "curse", "value": 0, "label": "x"},
		]
		ev._on_stranger_hand_pick(rares[0], costs[_seq % 3])
	_check_invariants("stranger_hand/%s" % fixture)
	_free_scene(ev); _drivers += 1


func _drive_relic_sacrifice(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] relic_sacrifice_pick [%s] relics=%d" % [fixture, RS.relics.size()])
	var ev = _event_scene("old_forge")
	ev._start_relic_sacrifice_mode()
	# Pick the first non-starting relic if any.
	var rid := _first_nonstarting_relic()
	if rid != "":
		ev._on_relic_sacrifice_pick(rid)
	_check_invariants("relic_sacrifice/%s" % fixture)
	_free_scene(ev); _drivers += 1


func _drive_sacrifice(fixture: String) -> void:
	for reward in ["gold", "max_hp", "relic"]:
		_new_run(fixture)
		print("[flow] sacrifice(%s) [%s] deck=%d" % [reward, fixture, RS.deck.size()])
		var ev = _event_scene("dark_altar")
		var effect := {"reward": reward, "base": 3, "per_atk": 6, "prompt": "x"}
		ev._start_sacrifice_mode(effect)
		var ci := _first_creature_index()
		if ci >= 0:
			ev._on_sacrifice_pick(ci)
		_check_invariants("sacrifice_%s/%s" % [reward, fixture])
		_free_scene(ev); _drivers += 1


func _drive_transform(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] transform_choice(2) [%s] deck=%d" % [fixture, RS.deck.size()])
	var ev = _event_scene("the_chrysalis")
	ev._start_transform_mode(2)
	var guard := 0
	while ev._transform_remaining > 0 and guard < 12:
		var i := _first_noncurse_index()
		if i < 0:
			break
		ev._on_transform_pick(i)
		guard += 1
	_check_invariants("transform/%s" % fixture)
	_free_scene(ev); _drivers += 1


func _drive_dice_run(fixture: String) -> void:
	# add mode (Bone Pit) and double mode (coin) with a stake.
	_new_run(fixture)
	print("[flow] dice_run(add) [%s] gold=%d" % [fixture, RS.gold])
	var ev = _event_scene("the_bone_pit")
	ev._start_dice_run({"start": 25, "bank_relic": "warm_knucklebone", "bank_relic_at": 75})
	# Roll several times then bank.
	for _i in range(6):
		ev._on_dice_roll()
	ev._on_dice_bank()
	_check_invariants("dice_run_add/%s" % fixture)
	_free_scene(ev); _drivers += 1

	_new_run(fixture)
	print("[flow] dice_run(double,stake) [%s] gold=%d" % [fixture, RS.gold])
	ev = _event_scene("coin_on_edge")
	ev._start_dice_run({"stake": 25, "start": 40, "mode": "double", "bust_pct": 0.5,
		"bank_relic": "coin_landed", "bank_relic_at": 160})
	for _i in range(8):
		ev._on_dice_roll()
	ev._on_dice_bank()
	_check_invariants("dice_run_double/%s" % fixture)
	_free_scene(ev); _drivers += 1


func _drive_risk_loop(fixture: String) -> void:
	# bust mode (spring) — drive action until it resolves to a result.
	_new_run(fixture)
	print("[flow] risk_loop(bust) [%s] hp=%d" % [fixture, RS.hero_hp])
	var EvScript = load("res://scripts/scenes/Event.gd")
	var spring: Dictionary = EvScript.EVENTS["thrice_blessed_spring"]
	var bust_cfg: Dictionary = spring.choices[0].effects[0]
	var ev = _event_scene("thrice_blessed_spring")
	ev._start_risk_loop(bust_cfg)
	for _i in range(8):
		ev._on_risk_action()
	_check_invariants("risk_loop_bust/%s" % fixture)
	_free_scene(ev); _drivers += 1

	# jackpot mode (woodcutter) — has a modal upgrade jackpot.
	_new_run(fixture)
	print("[flow] risk_loop(jackpot) [%s] hp=%d" % [fixture, RS.hero_hp])
	var wc: Dictionary = EvScript.EVENTS["woodcutter"]
	var jp_cfg: Dictionary = wc.choices[0].effects[0]
	ev = _event_scene("woodcutter")
	ev._start_risk_loop(jp_cfg)
	for _i in range(8):
		ev._on_risk_action()
		# jackpot may launch upgrade_choice modal; resolve a pick if it did.
		if ev._upgrade_choice_remaining > 0:
			var i := _first_upgradeable_index()
			if i >= 0:
				ev._on_upgrade_choice_pick(i)
			break
	_check_invariants("risk_loop_jackpot/%s" % fixture)
	_free_scene(ev); _drivers += 1


func _drive_appraisal(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] pawn_appraisal [%s] deck=%d" % [fixture, RS.deck.size()])
	var ev = _event_scene("pawnbrokers_window")
	ev._start_appraisal_mode()
	# "Show another" up to the cap, then sell.
	if ev._appr_index >= 0:
		ev._on_appraisal_another()
		if ev._appr_index >= 0:
			ev._on_appraisal_sell()
	_check_invariants("pawn_appraisal/%s" % fixture)
	_free_scene(ev); _drivers += 1


# ── Wayside verbs ────────────────────────────────────────────────────────────

func _run_wayside() -> void:
	print("[flow] === WAYSIDE VERBS ===")
	for fixture in ["rich", "poor", "one_card", "all_curse", "full_potions"]:
		_drive_drill(fixture)
		_drive_scales(fixture)
		_drive_banner(fixture)
		_drive_cache(fixture)


func _wayside_scene(verb: String) -> Node:
	RS.current_wayside_id = verb
	return _make_scene("res://scenes/wayside.tscn")


func _drive_drill(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] drill_yard [%s] deck=%d" % [fixture, RS.deck.size()])
	var w = _wayside_scene("drill_yard")  # _ready builds intro
	var elig: Array = w._drill_eligible()
	if not elig.is_empty():
		w._on_drill_pick(elig[0])
		# Push the luck a few times.
		var guard := 0
		while w._drill_stacks < w.DRILL_MAX_STACKS and guard < 8:
			w._on_drill_again()
			guard += 1
	_check_invariants("drill_yard/%s" % fixture)
	_free_scene(w); _drivers += 1


func _drive_scales(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] muster_scale [%s] gold=%d deck=%d" % [fixture, RS.gold, RS.deck.size()])
	var w = _wayside_scene("muster_scale")
	w._build_scales_sell()
	if RS.deck.size() > 0:
		w._on_scales_sell_pick(0)
	_check_invariants("scales_sell/%s" % fixture)
	_free_scene(w); _drivers += 1

	# Potion + meal services (only valid when affordable / needed; call anyway
	# to confirm they don't go negative when conditions aren't met — they are
	# gated by tile.enabled in the UI, but the handlers themselves should be
	# safe to call).
	_new_run("rich")
	var w2 = _wayside_scene("muster_scale")
	if RS.gold >= w2.SCALE_POTION_COST and RS.can_add_potion():
		w2._on_scales_potion()
	_check_invariants("scales_potion/%s" % fixture)
	if RS.gold >= w2.SCALE_MEAL_COST and RS.hero_hp < RS.hero_max_hp:
		w2._on_scales_meal()
	_check_invariants("scales_meal/%s" % fixture)
	_free_scene(w2); _drivers += 1


func _drive_banner(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] standard_bearer [%s] deck=%d" % [fixture, RS.deck.size()])
	var w = _wayside_scene("standard_bearer")  # _ready built donor screen
	var donors: Array = w._banner_donors()
	# Find a valid donor with a receiver and drive the full trade.
	for di in donors:
		var data = RS.get_upgraded_card_data(di)
		var kws: Array = w._transferable_of(data)
		for kw in kws:
			var recv: Array = w._banner_receivers(di, kw)
			if not recv.is_empty():
				w._on_banner_donor_pick(di)
				w._on_banner_kw_pick(kw)
				w._on_banner_receiver_pick(recv[0])
				break
		break
	_check_invariants("standard_bearer/%s" % fixture)
	_free_scene(w); _drivers += 1


func _drive_cache(fixture: String) -> void:
	_new_run(fixture)
	print("[flow] supply_cache [%s]" % fixture)
	var w = _wayside_scene("supply_cache")  # _ready built cache
	# Take each spoil type across fixtures.
	for id in ["purse", "draught", "rations", "levy", "dispatches", "banner_case"]:
		_new_run(fixture)
		var ww = _wayside_scene("supply_cache")
		ww._on_cache_take(id)
		_check_invariants("supply_cache_%s/%s" % [id, fixture])
		_free_scene(ww)
	_free_scene(w); _drivers += 1


# ── Recruit / Reward / Treasure / Shop / Rest ────────────────────────────────

func _run_recruit() -> void:
	print("[flow] === RECRUIT (MUSTER) ===")
	for fixture in ["rich", "poor", "one_card"]:
		_new_run(fixture)
		print("[flow] recruit [%s] faction=%s" % [fixture, RS.get_act_faction()])
		var r = _make_scene("res://scenes/recruit.tscn")  # _ready rolls + builds
		var offer: Array = r._roll_offer()
		if offer.size() > 0:
			r._enlist(offer[0])
		_check_invariants("recruit/%s" % fixture)
		_free_scene(r); _drivers += 1
	# Collector's Tome path (double enlist).
	_new_run("rich")
	RS.add_relic("collectors_tome")
	var r2 = _make_scene("res://scenes/recruit.tscn")
	if r2._choices.size() > 1:
		r2._enlist(r2._choices[0])
		if r2._choices.size() > 0:
			r2._enlist(r2._choices[0])
	_check_invariants("recruit/collectors_tome")
	_free_scene(r2); _drivers += 1


func _run_reward() -> void:
	print("[flow] === REWARD ===")
	for nt in ["normal", "elite", "boss"]:
		_new_run("rich")
		RS.current_node_type = nt
		RS.current_floor = 3
		print("[flow] reward node_type=%s" % nt)
		var rw = _make_scene("res://scenes/reward.tscn")  # _ready rolls relics
		if rw._relic_choices.size() > 0:
			rw._pick_relic(rw._relic_choices[0])
		else:
			rw._skip()
		_check_invariants("reward/%s" % nt)
		_free_scene(rw); _drivers += 1
	# Olympian's Mark auto-upgrade on elite.
	_new_run("rich")
	RS.current_node_type = "elite"
	RS.add_relic("olympians_mark")
	var rw2 = _make_scene("res://scenes/reward.tscn")
	_check_invariants("reward/olympians_mark")
	_free_scene(rw2); _drivers += 1


func _run_treasure() -> void:
	print("[flow] === TREASURE ===")
	for fixture in ["rich", "poor"]:
		_new_run(fixture)
		print("[flow] treasure [%s] act=%d" % [fixture, RS.get_act()])
		var t = _make_scene("res://scenes/treasure.tscn")  # _ready builds
		# Re-roll a relic the same way _build_ui does, then pick.
		var relics: Array = RDB.roll_relic_reward("combat", RS.relics, RS.current_hero_id)
		if relics.size() > 0:
			t._pick_relic(relics[0])
		else:
			t._leave()
		_check_invariants("treasure/%s" % fixture)
		_free_scene(t); _drivers += 1


func _run_shop() -> void:
	print("[flow] === SHOP ===")
	for fixture in ["rich", "poor"]:
		_new_run(fixture)
		print("[flow] shop [%s] gold=%d" % [fixture, RS.gold])
		var s = _make_scene("res://scenes/shop.tscn")  # _ready rolls + builds
		# Buy a card if affordable.
		if s._card_stock.size() > 0:
			var cid: String = s._card_stock[0]
			var price: int = s._price(s.BASE_PRICES.get(CDB.get_card_data(cid).rarity, 50))
			s._buy_card(cid, price)
		# Buy relic if affordable.
		if s._relic_stock.size() > 0:
			s._buy_relic(s._relic_stock[0], s._price(s.RELIC_COST))
		# Buy potion.
		s._buy_potion(s._price(s.POTION_COST))
		# Removal flow.
		s._start_remove_mode(s._price(s.REMOVE_COST))
		if RS.deck.size() > 1:
			s._confirm_remove(0, s._price(s.REMOVE_COST))
		_check_invariants("shop/%s" % fixture)
		_free_scene(s); _drivers += 1


func _run_rest() -> void:
	print("[flow] === REST (MAKE CAMP) ===")
	# heal path
	_new_run("default")
	RS.hero_hp = 5
	print("[flow] rest/heal")
	var r = _make_scene("res://scenes/rest.tscn")  # _ready builds choice UI
	r._do_heal()
	_check_invariants("rest/heal")
	_free_scene(r); _drivers += 1

	# upgrade path (pick + confirm)
	_new_run("default")
	print("[flow] rest/upgrade")
	r = _make_scene("res://scenes/rest.tscn")
	r._start_upgrade_mode()
	var ui := _first_upgradeable_index()
	if ui >= 0:
		r._select_card_for_upgrade(ui)
		r._do_upgrade("plus", "")
	_check_invariants("rest/upgrade")
	_free_scene(r); _drivers += 1

	# reforge path (Whetstone, two picks)
	_new_run("default")
	RS.add_relic("whetstone")
	print("[flow] rest/reforge")
	r = _make_scene("res://scenes/rest.tscn")
	r._start_reforge_mode()
	var guard := 0
	while r._reforge_remaining > 0 and guard < 6:
		var i := _first_upgradeable_index()
		if i < 0:
			break
		r._select_card_for_upgrade(i)
		r._do_upgrade("plus", "")
		guard += 1
	_check_invariants("rest/reforge")
	_free_scene(r); _drivers += 1


# ── Deck-scan helpers ────────────────────────────────────────────────────────

func _first_match_index(filter: String) -> int:
	for i in range(RS.deck.size()):
		if filter == "curse" and CDB.is_curse(RS.deck[i]):
			return i
		if filter == "starter" and not CDB.is_curse(RS.deck[i]) \
				and CDB.get_card_data(RS.deck[i]).get("rarity", "") == "starter":
			return i
	return -1


func _first_starter_id() -> String:
	for cid in RS.deck:
		if not CDB.is_curse(cid) and CDB.get_card_data(cid).get("rarity", "") == "starter":
			return cid
	return ""


func _first_creature_index() -> int:
	for i in range(RS.deck.size()):
		if CDB.get_card_data(RS.deck[i]).get("type", "") == "creature":
			return i
	return -1


func _first_upgradeable_index() -> int:
	for i in range(RS.deck.size()):
		if RS.has_upgrade_path(i, "plus"):
			continue
		if not CDB.is_upgradeable(RS.deck[i]):
			continue
		return i
	return -1


func _first_noncurse_index() -> int:
	for i in range(RS.deck.size()):
		if not CDB.is_curse(RS.deck[i]):
			return i
	return -1


func _first_nonstarting_relic() -> String:
	for rid in RS.relics:
		var r = RDB.get_relic(rid)
		if r.get("tier", "starting") != "starting":
			return rid
	return ""
