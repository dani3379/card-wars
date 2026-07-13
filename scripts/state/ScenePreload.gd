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
var _prewarmed := false
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
	# with a burst of worker-thread requests for disk bandwidth.
	_start.call_deferred()


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


## Bake the campaign deck's card textures during idle screen time — MapView
## calls this on every open (fire-and-forget). Every fight used to open with
## ~1s at ~23 FPS while _prebake_hand_textures rasterized the deck's writ
## frames; the deck is fully known on the map, so the bake happens behind the
## war chart instead and the fight's prebake is cache hits end to end. Cards
## already baked return instantly, so re-opens only pay for new drafts/forges.
## Lives on this autoload so leaving the map mid-queue can't kill the coroutine
## (the bake simply finishes behind whatever screen comes next).
var _deck_warm_busy := false

func warm_run_deck() -> void:
	if _deck_warm_busy or DisplayServer.get_name() == "headless":
		return
	_deck_warm_busy = true
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
	for cd in datas:
		await CardArtAliases.prewarm_card_art(cd)
	await CardTextureCache.bake_many(datas)
	await CardTextureCache.bake_battlefield_many(datas)
	_deck_warm_busy = false


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
	# reuses them.
	if _prewarmed or DisplayServer.get_name() == "headless":
		return
	_prewarmed = true
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
