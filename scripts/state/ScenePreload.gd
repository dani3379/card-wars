extends Node
## ScenePreload.gd — autoload. Warms and PINS every screen's PackedScene (plus
## the big script-loaded textures) so scene transitions stop paying disk I/O.
##
## Why: nothing held a reference to the .tscn resources, so Godot's resource
## cache dropped each screen the moment the player left it — every
## change_scene_to_file() re-parsed the scene file AND re-decoded its ~2 MB
## painted background on the main thread. Holding a permanent PackedScene
## reference keeps the scene and its ext_resources (backgrounds, fonts) alive
## in the resource cache for the whole session, so change_scene_to_file()'s
## internal load() is a cache hit: transitions cost instantiation only.
##
## The warm-up itself runs on ResourceLoader's worker threads, requested a few
## frames after boot — the menu appears first, the library fills in behind it.
## Everything here is an optimization only: a path that fails to load (or a
## probe context without rendering) just leaves the old lazy-load behavior for
## that screen in place.

const PRELOAD_PATHS: Array[String] = [
	# Screens, roughly in first-use order for a fresh run.
	"res://scenes/map.tscn",
	"res://scenes/combat.tscn",
	"res://assets/portraits/player_knight.png",
	"res://assets/portraits/enemy_commander.png",
	"res://assets/portraits/hero_portrait_raider.png",
	"res://assets/portraits/hero_portrait_stalwart.png",
	"res://assets/portraits/hero_portrait_acolyte.png",
	"res://assets/portraits/hero_portrait_pyromancer.png",
	"res://assets/portraits/hero_portrait_kindler.png",
	"res://scenes/reward.tscn",
	"res://scenes/event.tscn",
	"res://scenes/wayside.tscn",
	"res://scenes/shop.tscn",
	"res://scenes/rest.tscn",
	"res://scenes/recruit.tscn",
	"res://scenes/treasure.tscn",
	"res://scenes/game_over.tscn",
	"res://scenes/main_menu.tscn",
	"res://scenes/collection.tscn",
	"res://scenes/credits.tscn",
	"res://scenes/net_lobby.tscn",
	"res://scenes/net_quick.tscn",
	"res://scenes/net_draft.tscn",
	"res://scenes/net_sealed.tscn",
	"res://scenes/net_constructed.tscn",
	# Script-loaded big art that would otherwise decode on scene entry
	# (per-act arena/campfire swaps in Combat.gd / Rest.gd, map paper fiber).
	"res://assets/backgrounds/combat_arena_act2.png",
	"res://assets/backgrounds/combat_arena_act3.png",
	"res://assets/backgrounds/rest_campfire_act2.png",
	"res://assets/backgrounds/rest_campfire_act3.png",
	"res://assets/backgrounds/map_parchment.jpg",
]

const MAX_INFLIGHT := 1
var _keep: Dictionary = {}          # path -> Resource; the pin IS the feature
var _pending: Array[String] = []
var _queue: Array[String] = []
var _prewarm_started := false
var _prewarmed := false  # true only after textures and live overlay are warm
var _game_over_ui_warm_started := false
var _game_over_ui_warmed := false
var _loading_writ_warm_started := false
var _loading_writ_warmed := false
var _encounter_art_busy: Dictionary = {}
var _encounter_art_warmed: Dictionary = {}
var _encounter_art_active: String = ""
var _encounter_art_queued: String = ""


func _ready() -> void:
	set_process(false)
	# Headless gameplay probes compile/load their own scenes on demand. A parallel
	# threaded scene parse can race that compile and produce false dependency
	# errors; there is no renderer or player transition to warm in that mode.
	if DisplayServer.get_name() == "headless":
		return
	# Deferred so the boot frame (menu build, autoload chain) isn't competing
	# with a burst of worker-thread requests for disk bandwidth. The tiny loading
	# sleeve shader warm starts first; Compatibility can only compile a Canvas
	# shader after it is actually drawn in-frustum.
	_prewarm_loading_writ_shader.call_deferred()
	_start.call_deferred()


func _prewarm_loading_writ_shader() -> void:
	# Godot's Compatibility renderer cannot precompile Canvas pipelines from a
	# loaded resource alone. Draw the real material for one frame behind the main
	# menu so the first deck/recruit/shop opening never pays that compilation.
	if _loading_writ_warm_started or DisplayServer.get_name() == "headless":
		return
	_loading_writ_warm_started = true
	var texture := load("res://assets/ui/card_back.png") as Texture2D
	if texture == null:
		return
	var warm_layer := CanvasLayer.new()
	warm_layer.layer = -1000
	add_child(warm_layer)
	var sample := TextureRect.new()
	sample.texture = texture
	sample.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sample.stretch_mode = TextureRect.STRETCH_SCALE
	sample.position = Vector2.ZERO
	sample.size = Vector2(8, 12)
	sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sample.material = Motion.loading_writ_material()
	warm_layer.add_child(sample)
	await RenderingServer.frame_post_draw
	if is_instance_valid(warm_layer):
		warm_layer.queue_free()
	_loading_writ_warmed = true


func start_for_probe() -> void:
	# The dedicated preload probe opts in after its own scripts have settled.
	if is_warmup_complete() and _keep.is_empty():
		_start()


func _start() -> void:
	_queue.clear()
	for path in PRELOAD_PATHS:
		if not ResourceLoader.exists(path):
			continue
		if ResourceLoader.has_cached(path):
			_keep[path] = load(path)
			continue
		_queue.append(path)
	_pump_requests()
	set_process(not is_warmup_complete())
	if is_warmup_complete():
		_prewarm_card_pipeline()


func _pump_requests() -> void:
	# Limit concurrent parsing/decoding so the first visible menu frames keep
	# their CPU and disk bandwidth. PRELOAD_PATHS order is the priority order.
	while _pending.size() < MAX_INFLIGHT and not _queue.is_empty():
		var path: String = _queue.pop_front()
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending.append(path)


func is_warmup_complete() -> bool:
	return _pending.is_empty() and _queue.is_empty()


func _process(_dt: float) -> void:
	# Poll in-flight requests; collect finished ones. load_threaded_get on a
	# LOADED request returns immediately (no main-thread wait).
	for i in range(_pending.size() - 1, -1, -1):
		var path := _pending[i]
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				_keep[path] = ResourceLoader.load_threaded_get(path)
				_pending.remove_at(i)
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pass
			_:
				# Failed/invalid — drop it; that screen keeps lazy loading.
				_pending.remove_at(i)
	_pump_requests()
	if is_warmup_complete():
		set_process(false)
		_prewarm_card_pipeline()


## Prime the run chronicle's exact font faces and sizes during the held verdict.
## Pinning game_over.tscn removes I/O, but Godot still lazily shapes/rasterizes
## these sizes the first time the summary lays itself out. That work used to
## make the first Game Over frame take about 41 ms even with every deck card
## already baked. The warm is state-free and split across frames; Combat calls
## it only once a killing blow is known to lead to Game Over.
func warm_game_over_ui() -> void:
	if _game_over_ui_warm_started or DisplayServer.get_name() == "headless":
		return
	_game_over_ui_warm_started = true
	# Never lengthen the killing-blow frame itself.
	await get_tree().process_frame
	var specs: Array[Dictionary] = [
		# Scene title, verdict copy and seed footnote.
		{"font": GameTheme.font_display, "size": 64,
			"text": "VICTORY DEFEAT"},
		{"font": GameTheme.font_body, "size": 20,
			"text": "You claimed the throne. The run ends here. Felled by"},
		{"font": GameTheme.font_body, "size": 16,
			"text": "Seed 0123456789 click to copy"},
		# Chronicle headings, actions and closing seal.
		{"font": GameTheme.font_display, "size": 30,
			"text": "MDCLXVI"},
		{"font": GameTheme.font_display, "size": 21,
			"text": "RUN SUMMARY"},
		{"font": GameTheme.font_display, "size": 20,
			"text": "PLAY AGAIN"},
		{"font": GameTheme.font_display, "size": 19,
			"text": "SEALED CLOSED"},
		{"font": GameTheme.font_display, "size": 18,
			"text": "BACK TO MENU"},
		{"font": GameTheme.font_display, "size": 16,
			"text": "RELICS THE DECK BATTLE RULES SURVIVED SPECIAL BATTLES WON"},
		# Tally figures and handwritten page copy.
		{"font": GameTheme.font_title_black, "size": 40,
			"text": "0123456789"},
		{"font": GameTheme.font_card_body, "size": 14,
			"text": "PROVINCES FIGHTS WON GOLD KILLS VETERANS LOST"},
		{"font": GameTheme.font_card_body, "size": 14,
			"text": "The final deck and relics carried through the march."},
		{"font": GameTheme.font_card_body, "size": 13,
			"text": "Total runs 0123456789 Wins  \u00b7  \u00d7  \u2014"},
	]
	# TextServer is a thread-safe server API. Raster the requested glyphs there
	# rather than making Font.get_string_size pay a 30-70 ms first-size cache
	# allocation on the render thread. Only immutable RID/size/text values cross
	# the boundary; no Resource or scene-tree object is touched by the worker.
	var raster_jobs: Array[Dictionary] = []
	for spec in specs:
		var raster_font: Font = spec.font
		var rids: Array[RID] = []
		if raster_font != null:
			for rid_value in raster_font.get_rids():
				var rid: RID = rid_value
				if rid.is_valid():
					rids.append(rid)
		raster_jobs.append({"rids": rids, "size": int(spec.size),
			"text": String(spec.text)})
	var raster_task := WorkerThreadPool.add_task(func() -> void:
		var text_server = TextServerManager.get_primary_interface()
		for job in raster_jobs:
			var seen := {}
			var text_value := String(job.text)
			for i in text_value.length():
				var codepoint := text_value.unicode_at(i)
				if seen.has(codepoint):
					continue
				seen[codepoint] = true
				for rid_value in job.rids:
					var rid: RID = rid_value
					if text_server.font_has_char(rid, codepoint):
						text_server.font_render_range(rid,
							Vector2i(int(job.size), 0), codepoint, codepoint)
						break
	)
	while not WorkerThreadPool.is_task_completed(raster_task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(raster_task)
	# Shape the real strings after rasterization. These calls are now sub-ms;
	# keeping them on the main thread primes Font's own line-layout cache safely.
	for spec in specs:
		var font: Font = spec.font
		if font != null:
			font.get_string_size(String(spec.text), HORIZONTAL_ALIGNMENT_LEFT,
				-1, int(spec.size))
		await get_tree().process_frame
	# Let the final glyph uploads retire before the fade can swap scenes.
	for _i in 2:
		await RenderingServer.frame_post_draw
	_game_over_ui_warmed = true


## Bake the campaign deck's card textures during idle screen time — MapView
## calls this on every open (fire-and-forget). Every fight used to open with
## ~1s at ~23 FPS while _prebake_hand_textures rasterized the deck's writ
## frames; the deck is fully known on the map, so the bake happens behind the
## war chart instead and the fight's prebake is cache hits end to end. Cards
## already baked return instantly, so re-opens only pay for new drafts/forges.
## Lives on this autoload so leaving the map mid-queue can't kill the coroutine
## (the bake simply finishes behind whatever screen comes next).
var _deck_warm_busy := false
var _deck_warm_cancel := false


## Stand the idle deck warm down — a fight has begun and wants the bake
## viewport. MEASURED (2026-07-25): CardTextureCache serializes every baker
## through _bake_busy, so a player who commits to a node WHILE this warm is
## still baking made the fight's own art prewarm queue behind the remaining
## deck cards — board-visible went 0.49 s -> 1.61 s and time-to-playable
## 1.98 s -> 3.10 s. The warm is speculative; the fight is on screen, and its
## _prebake_hand_textures covers the SAME card list, so standing down costs
## nothing and the cards still get baked (behind the fight's intro instead).
func cancel_deck_warm() -> void:
	if _deck_warm_busy:
		_deck_warm_cancel = true


func warm_run_deck() -> void:
	if _deck_warm_busy or DisplayServer.get_name() == "headless":
		return
	_deck_warm_busy = true
	_deck_warm_cancel = false
	# Give the map's own open (plate bake, focus glide) the first frames.
	await get_tree().create_timer(1.0).timeout
	var datas: Array = []
	var seen := {}
	for i in range(RunState.deck.size()):
		var cd: Dictionary = RunState.get_upgraded_card_data(i)
		if cd.is_empty():
			continue
		var key: String = CardTextureCache.cache_key(cd)
		if seen.has(key):
			continue
		seen[key] = true
		datas.append(cd)
	# Paintings FIRST, for all of them: a card baked before its art decodes bakes
	# without one, and the batched bake below renders many cards in a single pass.
	for cd in datas:
		if _deck_warm_cancel:
			break
		await CardArtAliases.prewarm_card_art(cd)
	# bake_many / bake_battlefield_many poll this between render passes, so a
	# fight that commits mid-warm waits out at most ONE pass (a few frames)
	# instead of the rest of the deck.
	var still_wanted := func() -> bool: return not _deck_warm_cancel
	await CardTextureCache.bake_many(datas, still_wanted)
	await CardTextureCache.bake_battlefield_many(datas, still_wanted)
	_deck_warm_busy = false
	_deck_warm_cancel = false


## Same idle-time bake for an explicit card-id list — the net deck-builders
## call this the moment the local warband is sealed, so the "waiting for your
## opponent" screen (pure idle) absorbs the bake instead of the fight's first
## second. Net combat resolves cards straight from CardDB, so base data gives
## the exact cache keys _prebake_hand_textures will ask for; if combat starts
## while this is still in flight, CardTextureCache._bake_busy serializes the
## two queues per key. Lives here so the scene change can't kill the coroutine.
func warm_card_ids(ids: Array, include_battlefield: bool = false) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var datas: Array = []
	var seen := {}
	for cid in ids:
		var cd: Dictionary = CardDB.get_card_data(String(cid))
		if cd.is_empty():
			continue
		var key: String = CardTextureCache.cache_key(cd)
		if seen.has(key):
			continue
		seen[key] = true
		datas.append(cd)
	for cd in datas:
		await CardArtAliases.prewarm_card_art(cd)
	# A grid readback wins on large idle-time deck warms, but it is the wrong
	# trade for a three/four-card foreground offer. On Compatibility, the same
	# four identities measured 163 ms total / 107 ms worst-frame as one sheet,
	# versus 97 ms total / 23 ms worst-frame serialized. Keep Shop and Recruit
	# responsive; network decks still take the throughput-oriented batch path.
	if not include_battlefield and datas.size() <= 4:
		for cd in datas:
			await CardTextureCache.bake(cd)
	else:
		await CardTextureCache.bake_many(datas)
	if include_battlefield:
		await CardTextureCache.bake_battlefield_many(datas)


## Start loading every painting an encounter can reveal. MapView calls this on
## hover and commit, overlapping decode with route-reading and the march/fade.
func begin_warm_encounter_art(encounter_id: String) -> void:
	if encounter_id == "" or DisplayServer.get_name() == "headless":
		return
	if _encounter_art_warmed.has(encounter_id):
		_encounter_art_queued = ""
		return
	if _encounter_art_active == encounter_id:
		# The latest hover/commit points at the active job; discard an older
		# speculative hover waiting behind it.
		_encounter_art_queued = ""
		return
	if _encounter_art_queued == encounter_id:
		return
	# Only one encounter decode stream runs at once. Sweeping across map nodes
	# replaces the speculative queued job instead of launching a worker burst.
	_encounter_art_queued = encounter_id
	_start_next_encounter_art()


func _start_next_encounter_art() -> void:
	if _encounter_art_active != "" or _encounter_art_queued == "":
		return
	var encounter_id := _encounter_art_queued
	_encounter_art_queued = ""
	if _encounter_art_warmed.has(encounter_id):
		_start_next_encounter_art.call_deferred()
		return
	_encounter_art_active = encounter_id
	_encounter_art_busy[encounter_id] = true
	_warm_encounter_art(encounter_id)


func _finish_encounter_art(encounter_id: String, warmed: bool) -> void:
	_encounter_art_busy.erase(encounter_id)
	if warmed:
		_encounter_art_warmed[encounter_id] = true
	if _encounter_art_active == encounter_id:
		_encounter_art_active = ""
	_start_next_encounter_art.call_deferred()


func _warm_encounter_art(encounter_id: String) -> void:
	var enc: Dictionary = EncounterDB.get_encounter(encounter_id)
	if enc.is_empty():
		_finish_encounter_art(encounter_id, false)
		return
	var names := {}
	_collect_art_names(enc, names)
	_collect_art_names(EncounterDB.get_boss_phases(encounter_id), names)
	_collect_art_names(EncounterDB.get_reactive_passive(encounter_id), names)
	_collect_art_names(EncounterDB.get_encounter_script(encounter_id), names)
	for raw_name in names:
		var name_id := String(raw_name).to_lower() \
			.replace(" ", "_").replace("'", "")
		if name_id == "":
			continue
		var art: Texture2D = await CardArtAliases.prewarm_creature_art(name_id)
		if art == null and not name_id.begins_with("e_"):
			await CardArtAliases.prewarm_creature_art("e_" + name_id)
	var enc_type := String(enc.get("type", ""))
	if enc_type == "boss" or enc_type == "elite":
		await CardArtAliases.prewarm_texture_path(
			"res://assets/portraits/boss_%s.png" % encounter_id)
	if enc_type == "boss":
		await CardArtAliases.prewarm_texture_path(
			"res://assets/portraits/boss_act%d.png" % RunState.get_act())
	# Do not build or roll a roster here. Encounter composition/reinforcement
	# helpers consume RNG and allocate volatile entity ids; speculative hovering
	# must never mutate the fight the player eventually commits to. Combat bakes
	# the one actual rolled roster after _setup_fight_state instead.
	_finish_encounter_art(encounter_id, true)


func _collect_art_names(value, out: Dictionary) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for key in value:
				var nested = value[key]
				if (key == "name" or key == "id") and nested is String \
						and nested != "":
					out[nested] = true
				else:
					_collect_art_names(nested, out)
		TYPE_ARRAY:
			for nested in value:
				_collect_art_names(nested, out)


func wait_for_encounter_art(encounter_id: String, max_msec: int = 150) -> void:
	# A tiny grace period can catch an almost-finished hover warm, but never hold
	# the player on a dead map for seconds. Combat joins any remaining request.
	var deadline := Time.get_ticks_msec() + maxi(0, max_msec)
	while (_encounter_art_busy.has(encounter_id) \
			or _encounter_art_active == encounter_id \
			or _encounter_art_queued == encounter_id) \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func invalidate_encounter_art_warm_state() -> void:
	# CardArtAliases.clear_runtime_caches releases completed art pins. Mirror that
	# fact here so a continued run does not incorrectly skip a later warm.
	_encounter_art_warmed.clear()
	_encounter_art_queued = ""


func _prewarm_card_pipeline() -> void:
	# The session's first card bake pays a one-time bundle: card-font glyph
	# atlases (Cinzel/Alegreya at card sizes), the procedural writ painters,
	# and the bake viewport's first render. That used to land inside the first
	# fight's _ready. Baking one creature + one spell here — behind the main
	# menu, after the disk queue drains — moves it to idle time. The textures
	# stay in CardTextureCache keyed by stats, so a matching real card even
	# reuses them. `_prewarmed` is the completion flag read by probes;
	# `_prewarm_started` prevents re-entry while the awaited work is active.
	if _prewarm_started or DisplayServer.get_name() == "headless":
		return
	_prewarm_started = true
	var creature: Dictionary = {}
	var spell: Dictionary = {}
	for id in CardDB.CARD_POOL:
		var card: Dictionary = CardDB.CARD_POOL[id]
		if creature.is_empty() and card.get("type", "") == "creature":
			creature = CardDB.get_card_data(id)
		elif spell.is_empty() and card.get("type", "") == "spell":
			spell = CardDB.get_card_data(id)
		if not creature.is_empty() and not spell.is_empty():
			break
	if not creature.is_empty():
		await CardArtAliases.prewarm_card_art(creature)
		await CardTextureCache.bake(creature)
		await CardTextureCache.bake_battlefield(creature)
	if not spell.is_empty():
		await CardArtAliases.prewarm_card_art(spell)
		await CardTextureCache.bake(spell)
	if not creature.is_empty():
		await _prewarm_live_card_overlay(creature)
	await _prewarm_map_cartouche_fonts()
	await _prewarm_skirmish_ui_fonts()
	_prewarmed = true


## The network setup family shares one opening document: a headline, a five-step
## rail, and three rich relic/potion tiles. These exact faces and sizes otherwise
## allocate their glyph atlases on the first Skirmish frame. Raster them on the
## thread-safe TextServer during menu idle time, then touch Font's layout cache
## on the main thread in small frame-separated pieces.
func _prewarm_skirmish_ui_fonts() -> void:
	var names := ""
	var descriptions := ""
	for raw_id in SkirmishState.NET_RELIC_POOL:
		var relic: Dictionary = RelicDB.get_relic(String(raw_id))
		names += " " + String(relic.get("name", raw_id))
		descriptions += " " + String(relic.get("desc", ""))
	for raw_id in SkirmishState.NET_POTION_POOL:
		var potion: Dictionary = PotionDB.get_potion(String(raw_id))
		names += " " + String(potion.get("name", raw_id))
		descriptions += " " + String(potion.get("desc", ""))
	var specs: Array[Dictionary] = [
		{"font": GameTheme.font_display, "size": 34,
			"text": "RELICS & POTIONS QUICK BATTLE BUILD YOUR DECK DRAFT"},
		{"font": GameTheme.font_display, "size": 18,
			"text": "SKIP THESE OPTIONS CHOOSE READY RANDOM MIRRORED REROLL NEW POOL AUTO-FILL CLEAR FILL SAVE LOAD DELETE"},
		{"font": GameTheme.font_display, "size": 37,
			"text": "ABCDEFGHIJKLMNOPQRSTUVWXYZ"},
		{"font": GameTheme.font_body, "size": 20,
			"text": "Choose a battle relic potion 0123456789 of"},
		{"font": GameTheme.font_body, "size": 19, "text": names},
		{"font": GameTheme.font_body, "size": 18,
			"text": descriptions + " CHOOSE You Opponent building ready deck cards"},
	]
	var raster_jobs: Array[Dictionary] = []
	for spec in specs:
		var raster_font: Font = spec.font
		var rids: Array[RID] = []
		if raster_font != null:
			for rid_value in raster_font.get_rids():
				var rid: RID = rid_value
				if rid.is_valid():
					rids.append(rid)
		raster_jobs.append({"rids": rids, "size": int(spec.size),
			"text": String(spec.text)})
	var raster_task := WorkerThreadPool.add_task(func() -> void:
		var text_server = TextServerManager.get_primary_interface()
		for job in raster_jobs:
			var seen := {}
			var text_value := String(job.text)
			for i in text_value.length():
				var codepoint := text_value.unicode_at(i)
				if seen.has(codepoint):
					continue
				seen[codepoint] = true
				for rid_value in job.rids:
					var rid: RID = rid_value
					if text_server.font_has_char(rid, codepoint):
						text_server.font_render_range(rid,
							Vector2i(int(job.size), 0), codepoint, codepoint)
						break
	)
	while not WorkerThreadPool.is_task_completed(raster_task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(raster_task)
	for spec in specs:
		var font: Font = spec.font
		if font != null:
			font.get_string_size(String(spec.text), HORIZONTAL_ALIGNMENT_LEFT,
				-1, int(spec.size))
		await get_tree().process_frame


func _prewarm_map_cartouche_fonts() -> void:
	# MapTerrain sizes its title cartouche with Font.get_string_size(). The first
	# request for Kreon Bold at 15 px used to build every missing glyph in one
	# foreground frame (107 ms measured on the cold map). Prime the exact two
	# faces/sizes after the card warm, split into short alphabets so menu-time
	# work remains bounded instead of merely moving the hitch. Measuring is
	# sufficient: the later draw_string calls measured below 1 ms once these
	# glyph caches existed, so an extra hidden viewport would add no value.
	var specs: Array[Dictionary] = [
		{"font": GameTheme.font_title, "size": 22, "text": "ACT III \u00b7 THE"},
		{"font": GameTheme.font_title, "size": 22, "text": "BURNING ISLE"},
		{"font": GameTheme.font_display, "size": 15, "text": "ABCDEFGHIJKLM"},
		{"font": GameTheme.font_display, "size": 15, "text": "NOPQRSTUVWXYZ"},
		{"font": GameTheme.font_display, "size": 15, "text": "abcdef"},
		{"font": GameTheme.font_display, "size": 15, "text": "ghijkl"},
		{"font": GameTheme.font_display, "size": 15, "text": "mnopqr"},
		{"font": GameTheme.font_display, "size": 15, "text": "stuvwx"},
		{"font": GameTheme.font_display, "size": 15, "text": "yz"},
		{"font": GameTheme.font_display, "size": 15, "text": "0123"},
		{"font": GameTheme.font_display, "size": 15, "text": "4567"},
		{"font": GameTheme.font_display, "size": 15, "text": "89"},
		{"font": GameTheme.font_display, "size": 15,
			"text": " .,'-/\u00b7"},
	]
	for spec in specs:
		var font: Font = spec.font
		if font != null:
			font.get_string_size(String(spec.text), HORIZONTAL_ALIGNMENT_LEFT,
				-1, int(spec.size))
		# Keep each new-glyph raster batch on its own idle frame.
		await get_tree().process_frame


func _prewarm_live_card_overlay(base_data: Dictionary) -> void:
	# Bakes strip name/rules/stat text. The first foreground cached card used to
	# pay RichTextLabel's font, BBCode, hint and inline-device setup (140 ms for
	# a keyword-rich Shop card). Prime that exact path in an invisible viewport.
	# Short paragraphs bound the one-time work below 50 ms per frame rather than
	# merely moving one 150 ms stall behind the menu. No warm card is shown or retained.
	if base_data.is_empty() or not CardTextureCache.has(base_data):
		return
	var packed := load("res://scenes/card_2d.tscn") as PackedScene
	if packed == null:
		return
	var warm_viewport := SubViewport.new()
	warm_viewport.size = Vector2i(CardTextureCache.TEX_W,
		CardTextureCache.TEX_H)
	warm_viewport.transparent_bg = true
	warm_viewport.disable_3d = true
	warm_viewport.gui_disable_input = true
	warm_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(warm_viewport)
	var parts: Array[Dictionary] = [
		{"desc": "On-Death."},
		{"desc": "A friendly creature."},
		{"desc": "Gains +2/+2 this fight."},
		{"desc": "Exhaust. Curse. Guardian."},
		# Together these two short body lines cover the remaining glyph atlas.
		{"desc": "Sphinx of black quartz."},
		{"desc": "Judge my vow."},
		{"desc": "0123456789"},
		# Card names have three size bands; the tribe footer uses another font.
		{"name": "Hexwright"},
		{"name": "Black Quartz Vow"},
		{"name": "Sphinx of Black Quartz"},
		{"ctype": "warlock"},
	]
	for part in parts:
		if not is_instance_valid(warm_viewport):
			return
		var warm_data := base_data.duplicate(true)
		warm_data["name"] = String(part.get("name", ""))
		warm_data["ctype"] = String(part.get("ctype", ""))
		warm_data["desc"] = String(part.get("desc", ""))
		var card = packed.instantiate()
		card.card_data = warm_data
		card.card_id = String(warm_data.get("id", ""))
		card.is_on_battlefield = true
		card.static_display = true
		card.live_baked_mode = true
		card.position = Vector2(CardTextureCache.BAKE_PAD,
			CardTextureCache.BAKE_PAD)
		warm_viewport.add_child(card)
		# Two draws populate the dynamic font atlas; the third presents the stable
		# paragraph before this disposable card is released.
		for _i in 3:
			await RenderingServer.frame_post_draw
		if is_instance_valid(card):
			card.queue_free()
		for _i in 2:
			await get_tree().process_frame
	warm_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	warm_viewport.queue_free()
	await get_tree().process_frame
