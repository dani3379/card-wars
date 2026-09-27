extends SceneTree
## Throwaway probe for the 2026-07-02 shell restructure: drives every screen
## the sweep touched (sutler shop + sell grid, supply cache, boss-reward lord
## tiles, game over with MARCH AGAIN, the map relic viewer, the writ-resolution
## pickers, and the rematch path) far enough to catch runtime nulls
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


## The writ pickers name nothing, so find them structurally: each one clears the
## menu root down to Background/Atmosphere/Menu and mounts a container of tiles.
## Two shapes exist — the deck pickers (forge/remove/remount) scroll a
## GridContainer, the offer pickers (enlist/arsenal) centre a short HBoxContainer
## — so accept either and require it to hold at least one tile.
func _picker_tiles_of(mm: Node) -> Node:
	for child in mm.get_children():
		if child is ScrollContainer:
			for gc in child.get_children():
				if (gc is GridContainer or gc is FlowContainer) \
						and gc.get_child_count() > 0:
					return gc
		elif child is HBoxContainer and child.get_child_count() > 0:
			return child
	return null


func _run() -> void:
	_snapshot_saves()
	var RS: Node = root.get_node_or_null("RunState")

	# ── Fixture: a live run ──
	RS.start_new_run("raider", 0, 777)
	print("[shell] run started: deck=%d relics=%d faction=%s rival=%s" % [
		RS.deck.size(), RS.relics.size(), RS.get_act_faction(), RS.get_act_rival()])
	_check(RS.get_act_faction() != "", "conquest deal live (war-event gates can fire)")

	# ── Sutler shop: build, removal grid, one strike ──
	print("[shell] shop (sutler) ...")
	var shop = load("res://scenes/shop.tscn").instantiate()
	root.add_child(shop)
	await _settle()
	_check(true, "sutler shop built")
	var deck_before: int = RS.deck.size()
	# The removal is a PURCHASE now, so the purse has to be able to afford it —
	# a run opening on less than the fee would otherwise read as a broken grid.
	RS.gold = maxi(RS.gold, shop.REMOVE_FEE * 2)
	var gold_before: int = RS.gold
	var fee: int = int(shop._removal_fee())
	shop._start_removal_mode()
	await _settle()
	_check(true, "removal grid built")
	shop._confirm_removal(1)
	await _settle()
	_check(RS.deck.size() == deck_before - 1, "removal took exactly one card")
	_check(RS.gold == gold_before - fee, "removal charged the fee (%d)" % fee)
	_check(shop._struck_this_visit, "removal latched (one per visit)")
	shop._confirm_removal(0)
	await _settle()
	_check(RS.deck.size() == deck_before - 1, "second removal rejected")
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
	# 2026-08-01: this passed `RS.current_act_idx + 1`. _show_march_choice has
	# taken the candidate LORDS (Array[String]) since the player-chosen rival
	# order landed, so the int raised "Cannot convert argument 1 from int to
	# Array" and aborted _run() — which is why this probe hung instead of
	# reaching everything below it. Feed it the real candidate list.
	var march_candidates: Array[String] = RS.get_next_march_candidates()
	_check(march_candidates.size() >= 2,
		"boss victory offers a choice of next kingdom (%d)" % march_candidates.size())
	rw._show_march_choice(march_candidates)
	await _settle()
	_check(rw.get_child_count() > 0, "lord tiles built")
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

	# ── Main menu: every picker-routed WRIT + rematch path ──
	#
	# 2026-08-01: this used to open `_show_blessing_select` (THE WAR CHEST) and
	# then hand `_pick_blessing` entries shaped {"id": ..., "risky": ...}. Both
	# are gone: the screen was deleted with the rest of the legacy run opening,
	# and `_pick_blessing` has read WritDB's {effect, value, is_pact} shape since
	# the writ model landed — so every one of those entries fell straight through
	# the `match` to `fade_out_then_change_scene`, which is why the picker checks
	# below it were all bare `_check(true, ...)`. They now drive the real writ
	# effects and assert the picker grid actually appeared.
	print("[shell] main menu writ pickers ...")
	var mm = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(mm)
	await _settle()
	RS.start_new_run("raider", 0, 779)
	for spec in [
			{"entry": {"effect": "forge", "value": 1}, "label": "forge picker"},
			{"entry": {"effect": "remove", "value": 1}, "label": "remove picker"},
			{"entry": {"effect": "remount", "value": 2}, "label": "remount picker"},
			{"entry": {"effect": "enlist", "value": 3}, "label": "enlist offer picker"},
			{"entry": {"effect": "arsenal", "value": 3}, "label": "arsenal relic picker"}]:
		mm._pick_blessing((spec["entry"] as Dictionary).duplicate())
		await _settle()
		_check(_picker_tiles_of(mm) != null, "%s built its tiles" % spec["label"])
	var remount_deck_n: int = RS.deck.size()
	mm._blessing_transform_at(0)
	_check(RS.deck.size() == remount_deck_n, "remount trade keeps deck size")
	# THE PACT bills its 6 max HP BEFORE the goods are handed over.
	var pact_max_hp: int = RS.hero_max_hp
	mm._pick_blessing({"effect": "forge", "value": 1, "is_pact": true})
	await _settle()
	_check(RS.hero_max_hp == pact_max_hp - WritDB.PACT_COST_MAX_HP,
		"pact bills %d max HP up front (%d -> %d)" \
			% [WritDB.PACT_COST_MAX_HP, pact_max_hp, RS.hero_max_hp])
	_check(RS.hero_hp <= RS.hero_max_hp, "pact clamps current HP to the new cap")
	mm.queue_free()
	await _settle()

	# ── MARCH AGAIN ──
	# 2026-08-01: these two used to assert that the rematch had already CALLED
	# start_new_run ("same hero") and landed on THE WAR CHEST. Both describe the
	# bug that was fixed — committing straight out of _start_rematch is exactly
	# what ran every rematch on seed 1 with no dealt terms. The live contract is
	# that MARCH AGAIN enters RUN SETUP with the picks restored and NOTHING
	# committed until the bonus tile, so that is what is asserted now.
	print("[shell] rematch path ...")
	RS.start_new_run("raider", 0, 780)   # a different lord to detect a false pass
	RS.rematch_request = {"hero": "stalwart", "ascension": 0}
	var mm2 = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(mm2)
	await _settle(10)
	_check(RS.rematch_request.is_empty(), "rematch request consumed")
	_check(mm2._muster_step == 3, "rematch lands on RUN SETUP")
	_check(mm2._selected_hero == "stalwart", "rematch restores the ended run's lord")
	_check(RS.current_hero_id == "raider",
		"rematch has NOT started a run yet (nothing commits before the bonus)")
	# The two things _start_rematch used to skip, and the reason it had to stop
	# calling _begin_run_with directly.
	_check(mm2._pending_run_seed() != 1, "rematch rolled a fresh seed, not the default 1")
	_check(not mm2._muster_writ_slate.is_empty(), "rematch dealt a slate of terms")
	_check(mm2._selected_writ_id != "", "rematch has a term selected to commit")
	mm2.queue_free()
	await _settle()

	_restore_saves()
	print("[shell] saves restored")
	if _fails == 0:
		print("[shell-probe] ALL PASS")
	else:
		print("[shell-probe] FAILS: %d" % _fails)
	quit(_fails)
