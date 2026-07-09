extends SceneTree
## Throwaway probe for the 2026-07-02 shell restructure: drives every screen
## the sweep touched (sutler shop + sell grid, supply cache, boss-reward lord
## tiles, game over with MARCH AGAIN, the map relic viewer, the war-chest
## blessing pickers, and the rematch path) far enough to catch runtime nulls
## the parse-check can't see. Snapshots run_*.save first and restores them
## before quit — several driven paths (rematch, map checkpoint) write saves.
##   Godot.exe --headless --path . --script res://tools/_probe_shellpass.gd

var _fails := 0
var _started := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _snapshot_saves() -> void:
	for i in range(3):
		var p := "user://run_%d.save" % i
		if FileAccess.file_exists(p):
			DirAccess.copy_absolute(p, p + ".shellbak")


func _restore_saves() -> void:
	for i in range(3):
		var b := "user://run_%d.save.shellbak" % i
		if FileAccess.file_exists(b):
			DirAccess.copy_absolute(b, "user://run_%d.save" % i)
			DirAccess.remove_absolute(b)


func _settle(frames: int = 3) -> void:
	for _i in range(frames):
		await process_frame


func _run() -> void:
	_snapshot_saves()
	var RS: Node = root.get_node_or_null("RunState")

	# ── Fixture: a live run ──
	RS.start_new_run("raider", 0, 777)
	print("[shell] run started: deck=%d relics=%d faction=%s rival=%s" % [
		RS.deck.size(), RS.relics.size(), RS.get_act_faction(), RS.get_act_rival()])
	_check(RS.get_act_faction() != "", "conquest deal live (war-event gates can fire)")

	# ── Sutler shop: build, sell grid, one sale ──
	print("[shell] shop (sutler) ...")
	var shop = load("res://scenes/shop.tscn").instantiate()
	root.add_child(shop)
	await _settle()
	_check(true, "sutler shop built")
	var deck_before: int = RS.deck.size()
	var gold_before: int = RS.gold
	shop._start_sell_mode()
	await _settle()
	_check(true, "sell grid built")
	shop._confirm_sell(1)
	await _settle()
	_check(RS.deck.size() == deck_before - 1, "sell removed exactly one card")
	_check(RS.gold > gold_before, "sell paid gold")
	_check(shop._sold_this_visit, "sell latched (one per visit)")
	shop._confirm_sell(0)
	await _settle()
	_check(RS.deck.size() == deck_before - 1, "second sell rejected")
	shop.queue_free()
	await _settle()

	# ── Supply cache: build + take each new spoil ──
	print("[shell] wayside supply cache ...")
	RS.current_wayside_id = "supply_cache"
	var ws = load("res://scenes/wayside.tscn").instantiate()
	root.add_child(ws)
	await _settle()
	_check(true, "supply cache built")
	ws._on_cache_take("free_lance")
	await _settle()
	_check(String(RS.next_combat_gift_creature.get("name", "")) == "Free Lance",
		"free_lance queues a gift creature")
	var deck_n: int = RS.deck.size()
	ws._on_cache_take("commission")
	await _settle()
	_check(RS.deck.size() == deck_n + 1, "commission adds an uncommon")
	ws.queue_free()
	await _settle()

	# ── Boss reward: lord tiles ──
	print("[shell] boss reward march choice ...")
	RS.current_node_type = "boss"
	var rw = load("res://scenes/reward.tscn").instantiate()
	root.add_child(rw)
	await _settle()
	_check(true, "boss reward built")
	rw._show_march_choice(RS.current_act_idx + 1)
	await _settle()
	_check(true, "lord tiles built")
	rw.queue_free()
	RS.current_node_type = ""
	await _settle()

	# ── Game over: defeat with MARCH AGAIN ──
	print("[shell] game over ...")
	RS.hero_hp = 0
	RS.cause_of_death = "the probe"
	var go = load("res://scenes/game_over.tscn").instantiate()
	root.add_child(go)
	await _settle(6)
	# The exit actions live inside the chronicle page now (2026-07-07), so
	# find them by name anywhere under the scene rather than as direct kids.
	_check(go.find_child("RematchBtn", true, false) != null, "MARCH AGAIN present")
	_check(go.find_child("BackBtn", true, false) != null, "BACK TO MENU present")
	go.queue_free()
	await _settle()

	# ── Map relic viewer ──
	print("[shell] map + relic viewer (plate bake — slow) ...")
	RS.start_new_run("raider", 0, 778)
	var mv = load("res://scenes/map.tscn").instantiate()
	root.add_child(mv)
	await _settle(12)
	mv._show_relic_viewer()
	await _settle()
	_check(mv.get_node_or_null("RelicOverlay") != null, "relic viewer opened")
	mv.queue_free()
	await _settle()

	# ── Main menu: war chest + every picker-routed blessing + rematch path ──
	print("[shell] main menu blessing pickers ...")
	var mm = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(mm)
	await _settle()
	RS.start_new_run("raider", 0, 779)
	mm._show_blessing_select()
	await _settle()
	_check(mm.get_node_or_null("BlessingTitle") != null, "war chest built")
	mm._pick_blessing({"id": "upgrade", "risky": false})
	await _settle()
	_check(true, "whetstone picker built")
	mm._pick_blessing({"id": "butchers_kindness", "risky": true})
	await _settle()
	_check(true, "butcher's kindness picker built")
	mm._pick_blessing({"id": "transform2", "risky": false})
	await _settle()
	_check(true, "remount line picker built")
	var remount_deck_n: int = RS.deck.size()
	mm._blessing_transform_at(0)
	_check(RS.deck.size() == remount_deck_n, "remount trade keeps deck size")
	mm._pick_blessing({"id": "recruit", "risky": false})
	await _settle()
	_check(true, "muster tent offer picker built")
	var levy_deck_n: int = RS.deck.size()
	mm._pick_blessing({"id": "hollow_levy", "risky": true})
	await _settle()
	_check(RS.deck.size() == levy_deck_n + 1, "hollow levy signs its Curse up front")
	mm.queue_free()
	await _settle()

	print("[shell] rematch path ...")
	RS.rematch_request = {"hero": "stalwart", "ascension": 0}
	var mm2 = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(mm2)
	await _settle(6)
	_check(RS.rematch_request.is_empty(), "rematch request consumed")
	_check(RS.current_hero_id == "stalwart", "rematch started as same hero")
	_check(mm2.get_node_or_null("BlessingTitle") != null,
		"rematch lands on the war chest")
	mm2.queue_free()
	await _settle()

	_restore_saves()
	print("[shell] saves restored")
	if _fails == 0:
		print("[shell-probe] ALL PASS")
	else:
		print("[shell-probe] FAILS: %d" % _fails)
	quit(_fails)
