extends SceneTree
## _probe_perf_pass.gd — headless verification for the 2026-07-06 lag pass.
## Run: Godot --headless --path . --script res://tools/_probe_perf_pass.gd
## Checks:
##  1. AudioBank async music: play_music resolves via the threaded loader,
##     caches the stream, and a stop_music cancels an in-flight play.
##  2. ScenePreload: every listed path ends up pinned + resource-cached.
##  3. Card/icon caches: live stat changes share card bakes, while painted
##     icons import at their bounded runtime size.

var _fails: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio: Node = root.get_node_or_null("AudioBank")
	var pre: Node = root.get_node_or_null("ScenePreload")
	var overlay: Node = root.get_node_or_null("PerformanceOverlay")
	var supersample: Node = root.get_node_or_null("Supersample")
	_check(audio != null, "AudioBank autoload present")
	_check(pre != null, "ScenePreload autoload present")
	_check(overlay != null, "F3 performance overlay autoload present")
	_check(supersample != null, "adaptive supersample autoload present")
	if audio == null or pre == null:
		quit(1)
		return
	if overlay != null:
		overlay._refresh_text()
		_check(overlay._label != null and "PERFORMANCE" in overlay._label.text,
			"F3 overlay builds its live diagnostics text")
	if supersample != null:
		_check(supersample.has_method("begin_adaptive_scope") \
				and supersample.has_method("get_effective_scale"),
			"adaptive render-scale API is available")

	# --- 1. async music ------------------------------------------------------
	audio.play_music("main_menu", 0.05)
	_check(audio._pending_music_track == "main_menu",
		"play_music marks the pending track immediately")
	var settled := false
	for _i in 600:  # up to ~10s of frames for the threaded load
		await process_frame
		if audio._current_music_track == "main_menu":
			settled = true
			break
	_check(settled, "threaded load lands and the track starts")
	_check(audio._music_streams.has("main_menu"), "stream cached for the session")
	_check(audio._music_inflight.is_empty(), "no in-flight requests left behind")

	# Cache-hit path: switching to a second track then back must be instant.
	audio.play_music("map", 0.05)
	for _i in 600:
		await process_frame
		if audio._current_music_track == "map":
			break
	audio.play_music("main_menu", 0.05)
	_check(audio._current_music_track == "main_menu",
		"cached track starts synchronously (no reload)")

	# stop_music cancels an in-flight play: request an uncached track, stop
	# immediately — when the load lands it must NOT start playing.
	audio.play_music("victory", 0.05)
	audio.stop_music(0.05)
	for _i in 600:
		await process_frame
		if audio._music_streams.has("victory"):
			break
	await process_frame
	_check(audio._music_streams.has("victory"), "cancelled load still caches")
	_check(audio._current_music_track == "", "stop_music wins over in-flight load")

	# --- 2. scene preload ----------------------------------------------------
	pre.start_for_probe()
	var done := false
	for _i in 1800:  # up to ~30s of frames; disk-bound, usually far quicker
		await process_frame
		if pre.is_warmup_complete() and not pre._keep.is_empty():
			done = true
			break
	_check(done, "preload queue drains")
	var missing: Array[String] = []
	for path in pre.PRELOAD_PATHS:
		if ResourceLoader.exists(path) and not pre._keep.has(path):
			missing.append(path)
	_check(missing.is_empty(), "every existing path is pinned (missing: %s)" % [missing])
	_check(ResourceLoader.has_cached("res://scenes/shop.tscn"),
		"shop.tscn is resource-cached after preload")
	_check(ResourceLoader.has_cached("res://scenes/combat.tscn"),
		"combat.tscn is resource-cached after preload")

	# --- 3. cache identity + bounded icon imports -----------------------------
	var card_cache: Node = root.get_node_or_null("CardTextureCache")
	var card_db: Node = root.get_node_or_null("CardDB")
	_check(card_cache != null, "CardTextureCache autoload present")
	_check(card_db != null, "CardDB autoload present")
	if card_cache != null and card_db != null:
		var base: Dictionary = card_db.get_card_data("pikeman")
		var stats := base.duplicate(true)
		stats["cost"] = int(stats.get("cost", 0)) + 2
		stats["atk"] = int(stats.get("atk", 0)) + 7
		stats["hp"] = int(stats.get("hp", 0)) + 9
		_check(card_cache.cache_key(base) == card_cache.cache_key(stats),
			"live cost/ATK/HP changes reuse the static card bake")
		var keyword_variant := base.duplicate(true)
		var kws: Array = keyword_variant.get("keywords", []).duplicate()
		kws.append("probe_only_keyword")
		keyword_variant["keywords"] = kws
		_check(card_cache.cache_key(base) != card_cache.cache_key(keyword_variant),
			"painted keyword changes receive a distinct card bake")
		var forged := base.duplicate(true)
		forged["is_upgraded"] = true
		_check(card_cache.cache_key(base) != card_cache.cache_key(forged),
			"forged finials receive a distinct card bake")
		var veteran := base.duplicate(true)
		veteran["veteran_kills"] = 4
		_check(card_cache.cache_key(base) != card_cache.cache_key(veteran),
			"campaign tally scratches receive a distinct card bake")
		var art_variant := base.duplicate(true)
		art_variant["id"] = "probe_other_art"
		_check(card_cache.cache_key(base) != card_cache.cache_key(art_variant),
			"different card art identities receive distinct card bakes")
		_check(card_cache.gallery_cache_key(base) != card_cache.cache_key(base),
			"gallery and gameplay snapshots cannot satisfy each other")
		_check(card_cache.battlefield_cache_key(base) \
				== card_cache.battlefield_cache_key(stats),
			"battlefield backgrounds ignore live cost/ATK/HP state")
		_check(card_cache.battlefield_cache_key(base) \
				== card_cache.battlefield_cache_key(keyword_variant),
			"battlefield backgrounds leave keyword/status devices live")
		_check(card_cache.battlefield_cache_key(base) \
				!= card_cache.battlefield_cache_key(art_variant),
			"battlefield backgrounds distinguish card art identities")
		var enemy_a := {"id": "enc_goblin_1", "name": "Goblin",
			"type": "creature", "atk": 1, "hp": 2}
		var enemy_b := {"id": "enc_goblin_999", "name": "Goblin",
			"type": "creature", "atk": 9, "hp": 9}
		_check(card_cache.battlefield_cache_key(enemy_a) \
				== card_cache.battlefield_cache_key(enemy_b),
			"volatile encounter ids reuse one resolved-art background")
		_check(card_cache.MAX_BATTLEFIELD_ENTRIES <= 64,
			"battlefield background cache has a bounded LRU")

	var painted_count := 0
	var bad_icons: Array[String] = []
	for folder in ["relics", "potions"]:
		var dir := DirAccess.open("res://assets/icons/%s" % folder)
		if dir == null:
			bad_icons.append("missing-dir:%s" % folder)
			continue
		for filename in dir.get_files():
			if not filename.ends_with(".png"):
				continue
			painted_count += 1
			var path := "res://assets/icons/%s/%s" % [folder, filename]
			var tex := load(path) as Texture2D
			if tex == null or tex.get_width() > 256 or tex.get_height() > 256:
				bad_icons.append("%s:%sx%s" % [path,
					0 if tex == null else tex.get_width(),
					0 if tex == null else tex.get_height()])
	_check(painted_count >= 100, "painted relic/potion import set is populated")
	_check(bad_icons.is_empty(),
		"painted relic/potion textures are capped at 256px (bad: %s)" % [bad_icons])

	print("RESULT: %s (%d fails)" % ["ALL PASS" if _fails == 0 else "FAILURES", _fails])
	quit(0 if _fails == 0 else 1)
