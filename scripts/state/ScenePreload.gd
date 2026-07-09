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

var _keep: Dictionary = {}          # path -> Resource; the pin IS the feature
var _pending: Array[String] = []
var _prewarmed := false


func _ready() -> void:
	set_process(false)
	# Deferred so the boot frame (menu build, autoload chain) isn't competing
	# with a burst of worker-thread requests for disk bandwidth.
	_start.call_deferred()


func _start() -> void:
	for path in PRELOAD_PATHS:
		if not ResourceLoader.exists(path):
			continue
		if ResourceLoader.has_cached(path):
			_keep[path] = load(path)  # cache hit — just pin it
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending.append(path)
	set_process(not _pending.is_empty())


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
	if _pending.is_empty():
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
	await CardTextureCache.bake_many(datas)
	_deck_warm_busy = false


## Same idle-time bake for an explicit card-id list — the net deck-builders
## call this the moment the local warband is sealed, so the "waiting for your
## opponent" screen (pure idle) absorbs the bake instead of the fight's first
## second. Net combat resolves cards straight from CardDB, so base data gives
## the exact cache keys _prebake_hand_textures will ask for; if combat starts
## while this is still in flight, CardTextureCache._bake_busy serializes the
## two queues per key. Lives here so the scene change can't kill the coroutine.
func warm_card_ids(ids: Array) -> void:
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
	await CardTextureCache.bake_many(datas)


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
		await CardTextureCache.bake(creature)
	if not spell.is_empty():
		await CardTextureCache.bake(spell)
