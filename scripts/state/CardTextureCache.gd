extends Node
# Autoload. Bakes Card2D's heavy static-display visual into a single
# ImageTexture per card identity and keeps a quality-tiered LRU for the run.
# Combat / Reward / Shop share the gameplay cache. Collection uses the same
# lookup surface with native-size snapshots, then clears them when it exits.
#
# Why bake: Card2D v4's full layout creates ~20 Control nodes per card. At
# the 5-card hand size that's ~100 nodes drawing ~200 sub-draws / frame just
# for the player's hand; the Card Gallery (122 cards) was ~5000 sub-draws —
# enough that the GL Compatibility renderer choked on batching. Baking the
# static layers (frame, art, banner, well, orb spheres) into one quad and
# leaving the dynamic numerals + floop indicator as live Labels collapses
# that to ~5 nodes per card while keeping stat updates instant.
#
# Cache keys include only fields painted into the static texture. Cost/ATK/HP
# numerals are stripped during bake and drawn by live overlay Labels, so dynamic
# stat/cost changes deliberately reuse the same texture. Forge finials and
# campaign tally scratches are painted, so their state remains part of the key.

const BAKE_PAD := 12
const SLOT_W := 225
const SLOT_H := 300
const TEX_W := SLOT_W + BAKE_PAD * 2  # 249  (LOGICAL display size — overlay keys off this)
const TEX_H := SLOT_H + BAKE_PAD * 2  # 324
# Ultra's hand-card bake stays at the existing 3× quality. Low/Medium use 2×
# because a full 3× mipmapped snapshot is roughly twice the memory and bake work;
# High/Ultra retain the cleanest curved frame edges for lifted cards.
const SUPERSAMPLE := 3
const CARD_SCENE = preload("res://scenes/card_2d.tscn")
# Upper bound retained for compatibility/readability. The live limit is tiered.
const MAX_ENTRIES := 48
const GAMEPLAY_KEY_PREFIX := "gameplay|"
const GAMEPLAY_BAKE_SCALE_BY_TIER := {
	"low": 2,
	"medium": 2,
	"high": 3,
	"ultra": 3,
}
const GAMEPLAY_MAX_ENTRIES_BY_TIER := {
	"low": 24,
	"medium": 32,
	"high": 40,
	"ultra": 48,
}
const GALLERY_KEY_PREFIX := "gallery|"
const BATTLEFIELD_W := 200
const BATTLEFIELD_H := 150
const BATTLEFIELD_PAD := 8
const BATTLEFIELD_TEX_W := BATTLEFIELD_W + BATTLEFIELD_PAD * 2
const BATTLEFIELD_TEX_H := BATTLEFIELD_H + BATTLEFIELD_PAD * 2
const BATTLEFIELD_SUPERSAMPLE := 2
const MAX_BATTLEFIELD_ENTRIES := 48

# --- Batched bake (2026-07-26) ----------------------------------------------
# The dominant cost of a card bake is not the pixels. It is (a) the two
# `await RenderingServer.frame_post_draw` the glyph atlas needs — vsync-bound at
# ~33 ms per card on a 60 Hz screen no matter how cheap the card is — and (b)
# the synchronous GPU flush inside `get_image()` (godotengine#75877: the
# readback stalls the whole pipeline). BOTH are paid per PASS, not per card.
#
# A cold 30-card deck therefore dribbled out one card every other frame for
# about a second, flushing the pipeline each time. That window sits exactly
# under the fight's intro banner and opening muster, which is why a fight could
# open smooth-on-paper and still feel like it was chewing on something.
#
# Laying a pass out as a GRID and taking ONE readback collapses ~30 stalls into
# two. The slice afterwards is a pure CPU `Image.get_region`, so every card
# still becomes its own mipmapped ImageTexture and nothing downstream changes.
const BATCH_GUTTER := 16              # logical px between cells, so a card's
                                      # shadow can't bleed into its neighbour
const BATCH_MAX_DIM := 4096           # common GL max texture size
const BATCH_MAX_PIXELS := 8_400_000   # ~34 MB transient RGBA8 render target
# Cards per pass. The pixel budget alone allows ~21, but the render frame that
# draws them is ONE frame however big it is: at 21 cards that frame measured
# ~110-170 ms and it lands wherever it lands — under the intro banner, or worse,
# under the opening muster. Eight keeps each render frame small enough to read
# as a frame rather than a hitch, and the extra passes are free (they overlap
# animation the player is watching anyway).
const BATCH_MAX_CARDS := 8
# Full ornate Card2D construction is CPU-heavy even while the viewport sleeps.
# Four in one frame measured 110-161 ms on the target AMD iGPU; two cut that
# peak materially, for about 6% extra wall time on a synthetic 30-card warm.
const BATCH_BUILD_PER_FRAME := 2
const BATCH_SLICE_PER_FRAME := 2      # get_region + mipmaps + upload per frame

signal battlefield_texture_ready(key: String)

var _cache: Dictionary = {}  # String → ImageTexture
var _cache_order: Array[String] = []  # least-recently used -> newest
var _battlefield_cache: Dictionary = {}
var _battlefield_order: Array[String] = []
var _bake_viewport: SubViewport = null
var _active_gameplay_bake_scale := -1
var _active_cache_limit := -1
# Serializes concurrent bakers. Two bake() calls interleaving their awaits would
# both parent a card into the shared viewport and capture each other's overlap —
# possible since the idle deck warm (ScenePreload.warm_run_deck, running behind
# the map) can still be in flight when Combat's _prebake_hand_textures starts.
var _bake_busy := false
# Upper bound on the `while _bake_busy` queue wait, in frames. A legitimate queue
# is short: a batch pass is a handful of frames, and even a pathological serial
# run of a full LRU's worth of single bakes lands around 200. Anything past this
# is not a queue, it is a wedge — see _wait_for_bake_slot.
const BAKE_QUEUE_MAX_FRAMES := 600


func _ready() -> void:
	_sync_gameplay_quality()
	_bake_viewport = SubViewport.new()
	_bake_viewport.size = Vector2i(
		TEX_W * _active_gameplay_bake_scale,
		TEX_H * _active_gameplay_bake_scale)
	# transparent_bg lets the card's drop shadow alpha out into surrounding
	# UI when displayed. disable_3d kills the 3D camera the viewport would
	# otherwise spin up. gui_disable_input stops the off-screen card from
	# eating clicks. UPDATE_ALWAYS so render fires every frame — the cost
	# of rendering an empty viewport between bakes is one clear, negligible.
	_bake_viewport.transparent_bg = true
	_bake_viewport.disable_3d = true
	_bake_viewport.gui_disable_input = true
	# NOTE: 2D MSAA is a no-op in the gl_compatibility renderer (engine issue
	# #69462 — not implemented), so it is intentionally left DISABLED here. The
	# baked cards stay crisp purely from the tiered 2×/3× bake + mipmaps, which is
	# real supersampling and renderer-independent. Setting MSAA here did nothing
	# but emit a "2D MSAA not supported" warning per bake.
	_bake_viewport.msaa_2d = Viewport.MSAA_DISABLED
	# DISABLED between bakes (was UPDATE_ALWAYS, which re-rendered this 3×-res
	# viewport every frame for the whole session). bake() flips it to ALWAYS only
	# while a card is parented, then back to DISABLED once the image is captured.
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_bake_viewport)


func cache_key(card_data: Dictionary) -> String:
	# Keyword devices and rarity furniture are baked. Name, rules text, and all
	# stat numerals are live overlays; id fixes the art/type/frame identity.
	var kws: Array = card_data.get("keywords", []).duplicate()
	kws.sort()
	return "%s|%s|%s|%d|%d" % [
		str(card_data.get("id", "")),
		str(card_data.get("rarity", "common")),
		",".join(kws),
		1 if bool(card_data.get("is_upgraded", false)) else 0,
		int(card_data.get("veteran_kills", 0)),
	]


func has(card_data: Dictionary) -> bool:
	_sync_gameplay_quality()
	return _cache.has(gameplay_cache_key(card_data))


func gameplay_cache_key(card_data: Dictionary) -> String:
	_sync_gameplay_quality()
	return "%s%d|%s" % [
		GAMEPLAY_KEY_PREFIX,
		_active_gameplay_bake_scale,
		cache_key(card_data),
	]


func gallery_cache_key(card_data: Dictionary) -> String:
	return GALLERY_KEY_PREFIX + cache_key(card_data)


func has_gallery(card_data: Dictionary) -> bool:
	return _cache.has(gallery_cache_key(card_data))


func get_texture(card_data: Dictionary) -> Texture2D:
	# Sync read — returns null if not yet baked. Callers that can't await
	# (e.g. Card2D._build_layout) use this and fall back to live layout on
	# miss; pre-bake passes call bake() to populate.
	var key := gameplay_cache_key(card_data)
	if _cache.has(key):
		_touch_key(key)
	return _cache.get(key, null)


func get_gallery_texture(card_data: Dictionary) -> Texture2D:
	var key := gallery_cache_key(card_data)
	if _cache.has(key):
		_touch_key(key)
	return _cache.get(key, null)


func _touch_key(key: String) -> void:
	var old := _cache_order.find(key)
	if old >= 0:
		_cache_order.remove_at(old)
	_cache_order.append(key)


func _trim_cache() -> void:
	_sync_gameplay_quality(false)
	while _cache_order.size() > _active_cache_limit:
		var oldest: String = _cache_order.pop_front()
		_cache.erase(oldest)


func gameplay_bake_scale() -> int:
	_sync_gameplay_quality()
	return _active_gameplay_bake_scale


func gameplay_cache_limit() -> int:
	_sync_gameplay_quality()
	return _active_cache_limit


func _effective_graphics_tier() -> String:
	var settings := get_node_or_null("/root/UserSettings")
	if settings != null and settings.has_method("effective_graphics_tier"):
		var tier := String(settings.effective_graphics_tier())
		if GAMEPLAY_BAKE_SCALE_BY_TIER.has(tier):
			return tier
	return "medium"


func _sync_gameplay_quality(trim_now: bool = true) -> void:
	var tier := _effective_graphics_tier()
	var next_scale: int = int(GAMEPLAY_BAKE_SCALE_BY_TIER.get(tier, 2))
	var next_limit: int = int(GAMEPLAY_MAX_ENTRIES_BY_TIER.get(tier, 32))
	if _active_gameplay_bake_scale >= 0 \
			and _active_gameplay_bake_scale != next_scale:
		# Old-resolution gameplay snapshots must not keep occupying the smaller
		# budget after a live preset change. Gallery and battlefield classes are
		# independent and remain valid.
		for key_variant in _cache.keys():
			var key := String(key_variant)
			if key.begins_with(GAMEPLAY_KEY_PREFIX):
				_cache.erase(key)
				_cache_order.erase(key)
	_active_gameplay_bake_scale = next_scale
	_active_cache_limit = next_limit
	if trim_now:
		_trim_cache()


func battlefield_cache_key(card_data: Dictionary) -> String:
	# The field background paints only resolved art, its dark read-gradient, and
	# the two blank wax seals. Encounter/token ids are per-instance and volatile,
	# so collapse them to the normalized art name; aliases collapse further to
	# the actual shared painting. All live combat state is deliberately excluded.
	var cid := String(card_data.get("id", ""))
	var name_id := String(card_data.get("name", "")).to_lower() \
		.replace(" ", "_").replace("'", "")
	var art_id := cid
	if cid == "" or cid.begins_with("enc_") or cid.begins_with("token_") \
			or bool(card_data.get("is_token", false)):
		art_id = name_id
	if CardArtAliases.ALIASES.has(art_id):
		art_id = String(CardArtAliases.ALIASES[art_id])
	if art_id == "":
		art_id = "kindling_alt"
	return "%s|%s" % [
		String(card_data.get("type", "creature")),
		art_id,
	]


func has_battlefield(card_data: Dictionary) -> bool:
	return _battlefield_cache.has(battlefield_cache_key(card_data))


func get_battlefield_texture(card_data: Dictionary) -> Texture2D:
	var key := battlefield_cache_key(card_data)
	if _battlefield_cache.has(key):
		_touch_battlefield_key(key)
	return _battlefield_cache.get(key, null)


func _touch_battlefield_key(key: String) -> void:
	var old := _battlefield_order.find(key)
	if old >= 0:
		_battlefield_order.remove_at(old)
	_battlefield_order.append(key)


func _trim_battlefield_cache() -> void:
	while _battlefield_order.size() > MAX_BATTLEFIELD_ENTRIES:
		var oldest: String = _battlefield_order.pop_front()
		_battlefield_cache.erase(oldest)


func bake(card_data: Dictionary) -> Texture2D:
	_sync_gameplay_quality()
	var bake_scale := _active_gameplay_bake_scale
	var prefix := "%s%d|" % [GAMEPLAY_KEY_PREFIX, bake_scale]
	return await _bake_scaled(card_data, bake_scale, true, prefix)


func bake_gallery(card_data: Dictionary,
		validity: Callable = Callable()) -> Texture2D:
	# Collection cards are never lifted above their native 225x300 tile. A 1x
	# snapshot is therefore pixel-for-pixel at display size and uses about one
	# twelfth the memory of the 3x+mipmapped hand-card bake. Its prefixed cache
	# class prevents a gallery snapshot from satisfying a gameplay bake.
	return await _bake_scaled(
		card_data, 1, false, GALLERY_KEY_PREFIX, validity)


func _bake_scaled(card_data: Dictionary, bake_scale: int,
		make_mipmaps: bool, key_prefix: String,
		validity: Callable = Callable()) -> Texture2D:
	# Async (`await`). Idempotent: returns the cached texture immediately on
	# cache hit, otherwise spins up a transient Card2D in the shared
	# viewport, waits 2 frames for layout + render, and snapshots the result
	# into a standalone ImageTexture (so the viewport can be reused for the
	# next bake without affecting this texture).
	if not _can_bake() or not _bake_valid(validity):
		return null
	var key := key_prefix + cache_key(card_data)
	if _cache.has(key):
		_touch_key(key)
		return _cache[key]
	# One card in the viewport at a time. While waiting, the other baker may
	# finish this very key — re-check before claiming the viewport.
	var waited := 0
	while _bake_busy:
		if waited >= BAKE_QUEUE_MAX_FRAMES:
			return _abandon_bake_wait(key)
		waited += 1
		await get_tree().process_frame
		if not _bake_valid(validity):
			return null
		if _cache.has(key):
			_touch_key(key)
			return _cache[key]
	_bake_busy = true
	bake_scale = maxi(1, bake_scale)
	# Assigning size reallocates the render target — only pay it on a change.
	var want := Vector2i(TEX_W * bake_scale, TEX_H * bake_scale)
	if _bake_viewport.size != want:
		_bake_viewport.size = want

	var card := _make_bake_card(card_data, false)
	# Wake the viewport for the duration of this bake only (it sits DISABLED
	# between bakes so it isn't re-rendered every frame all session long).
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bake_viewport.add_child(card)
	# Card2D._ready sets size = (225, 300). The viewport is 12 px larger on
	# each axis so the cost/ATK/HP orbs that hang -9 px past the silhouette
	# get captured instead of clipped. Everything scales by bake_scale so the card
	# fills the quality-sized viewport and its fonts/art rasterize at higher res.
	card.scale = Vector2(bake_scale, bake_scale)
	card.position = Vector2(BAKE_PAD, BAKE_PAD) * bake_scale
	# Use frame_post_draw — process_frame is too early. Dynamic fonts
	# rasterize glyphs into an atlas asynchronously; capturing on
	# process_frame fires BEFORE the first glyph atlas pass completes, so the
	# bake captures fallback-font glyphs or partial rasterization. This is
	# the cause of "the font loads but the bake still shows the old font"
	# bugs (godotengine/godot#106957). 2x frame_post_draw waits for the
	# atlas to fill on the first pass and stabilizes on the second.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if _bake_viewport == null or not is_instance_valid(_bake_viewport):
		# Scene shut down mid-bake (player exited combat etc.) — give up.
		_bake_busy = false
		return null
	var image: Image = _bake_viewport.get_texture().get_image()
	# Image captured — put the viewport back to sleep until the next bake.
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Sync detach before checking cancellation so an abandoned gallery request
	# cannot leave its Card2D inside the shared viewport.
	_bake_viewport.remove_child(card)
	card.queue_free()
	if not _bake_valid(validity):
		_bake_busy = false
		return null
	# Mipmaps so the supersampled bake minifies cleanly when the card is shown small
	# (compact tokens / tight hands) — without them a 498px texture at ~120px aliases.
	if make_mipmaps:
		image.generate_mipmaps()
	var tex: ImageTexture = ImageTexture.create_from_image(image)
	# A settings change can happen across the two render awaits. Never publish
	# that now-stale gameplay resolution under the new tier.
	if key_prefix.begins_with(GAMEPLAY_KEY_PREFIX):
		_sync_gameplay_quality()
		var current_prefix := "%s%d|" % [
			GAMEPLAY_KEY_PREFIX, _active_gameplay_bake_scale]
		if key_prefix != current_prefix:
			_bake_busy = false
			return tex
	_cache[key] = tex
	_touch_key(key)
	_trim_cache()
	_bake_busy = false
	return tex


func _bake_valid(validity: Callable) -> bool:
	return validity.is_null() or (validity.is_valid() and bool(validity.call()))


## Every bake path parks on `RenderingServer.frame_post_draw`, and under the
## headless/dummy display server that signal NEVER FIRES: `can_any_window_draw()`
## is false, so the main loop skips `RenderingServer::draw()` entirely and no
## frame is ever posted. A bake started here does not fail — it suspends forever.
##
## That is worse than it sounds, because the first one to park holds `_bake_busy`
## for the rest of the process, so every later caller parks too, in the queue
## loop below. On 2026-09-03 that was the cause of the UI gates' exit crash:
## _probe_input_reach drove 91 screen states, leaked 141 suspended
## GDScriptFunctionStates (140 queued + 1 mid-bake), and Godot segfaulted
## dereferencing them during `cleanup` after the probe had printed a correct
## verdict.
##
## THIS IS THE ONLY PLACE THAT DECIDES IT. The fact was previously re-derived at
## three call sites (Combat._prebake_hand_textures, Collection.
## _hydrate_visible_card_tiles, _bake_batch) and the single-card paths — bake(),
## bake_gallery(), bake_battlefield() — were simply missed, which is how a
## per-call-site guard fails. Nothing downstream breaks on a cold cache: an
## unbaked card falls back to Card2D's live layout path, which is what the
## texture is a snapshot of.
func _can_bake() -> bool:
	return DisplayServer.get_name() != "headless"


## The escape hatch for the `while _bake_busy` queue.
##
## `_bake_busy` is a plain bool with no owner and no deadline, so any bake that
## dies between claiming it and clearing it wedges the cache for the whole
## session: card art quietly stops updating everywhere, and each new request adds
## another permanently suspended coroutine. That is what turned one parked
## headless bake into 140 leaked function states above.
##
## Giving up is the only safe response. Stealing the lock instead would let two
## bakers parent cards into the shared viewport at once and snapshot each other's
## overlap, which is the exact corruption `_bake_busy` exists to prevent — and
## the abandoned baker may still be mid-await, holding a card in there. A null
## return is already a supported outcome at every call site: the card renders
## through Card2D's live layout instead of its snapshot, which looks the same.
func _abandon_bake_wait(key: String) -> Texture2D:
	push_warning(("CardTextureCache: gave up waiting for the bake viewport after "
		+ "%d frames (key=%s). A previous bake never released _bake_busy; "
		+ "cards render through the live layout path until one does.")
		% [BAKE_QUEUE_MAX_FRAMES, key])
	return null


func bake_battlefield(card_data: Dictionary) -> Texture2D:
	if not _can_bake():
		return null
	if String(card_data.get("type", "creature")) != "creature":
		return null
	var key := battlefield_cache_key(card_data)
	if _battlefield_cache.has(key):
		_touch_battlefield_key(key)
		return _battlefield_cache[key]
	var waited := 0
	while _bake_busy:
		if waited >= BAKE_QUEUE_MAX_FRAMES:
			return _abandon_bake_wait(key)
		waited += 1
		await get_tree().process_frame
		if _battlefield_cache.has(key):
			_touch_battlefield_key(key)
			return _battlefield_cache[key]
	_bake_busy = true
	var want := Vector2i(
		BATTLEFIELD_TEX_W * BATTLEFIELD_SUPERSAMPLE,
		BATTLEFIELD_TEX_H * BATTLEFIELD_SUPERSAMPLE)
	if _bake_viewport.size != want:
		_bake_viewport.size = want

	var card := _make_bake_card(card_data, true)
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bake_viewport.add_child(card)
	card.scale = Vector2(BATTLEFIELD_SUPERSAMPLE, BATTLEFIELD_SUPERSAMPLE)
	card.position = Vector2(BATTLEFIELD_PAD, BATTLEFIELD_PAD) \
		* BATTLEFIELD_SUPERSAMPLE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if _bake_viewport == null or not is_instance_valid(_bake_viewport):
		_bake_busy = false
		return null
	var image: Image = _bake_viewport.get_texture().get_image()
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	image.generate_mipmaps()
	var tex: ImageTexture = ImageTexture.create_from_image(image)
	_bake_viewport.remove_child(card)
	card.queue_free()
	_battlefield_cache[key] = tex
	_touch_battlefield_key(key)
	_trim_battlefield_cache()
	_bake_busy = false
	battlefield_texture_ready.emit(key)
	return tex


func bake_battlefield_many(card_datas: Array,
		validity: Callable = Callable()) -> void:
	await _bake_batch(card_datas, true, validity)


func bake_many(card_datas: Array, validity: Callable = Callable()) -> void:
	# Pre-bake a whole deck in as few render passes as the budget allows. Cached
	# cards cost nothing; `validity` is polled between passes so a speculative
	# warm can be stood down mid-job (ScenePreload.cancel_deck_warm).
	await _bake_batch(card_datas, false, validity)


func _make_bake_card(card_data: Dictionary, battlefield: bool) -> Node:
	# The one place that decides what a bakeable Card2D looks like. static_display
	# kills the per-frame animations and cosmetic depth layers we don't want
	# frozen into the texture; bake_strip_stats blanks the cost/ATK/HP numerals so
	# the live overlay Labels can paint them on top of the orb spheres. Hand cards
	# additionally strip the NAME and RULES TEXT so the font renderer draws those
	# live (StS model) instead of shipping a downscaled bitmap of them.
	var card = CARD_SCENE.instantiate()
	if battlefield:
		var bake_data := card_data.duplicate(true)
		# Spawn-name prewarms pass art-only dicts ({name, type}) with no stats;
		# the bake strips stats anyway, but Card2D._ready reads hp/atk directly.
		if not bake_data.has("hp"):
			bake_data["hp"] = 1
		if not bake_data.has("atk"):
			bake_data["atk"] = 0
		card.card_data = bake_data
		card.compact_mode = true
		card.compact_static_bake = true
	else:
		card.card_data = card_data.duplicate(true)
		card.bake_strip_desc = true
		card.bake_strip_name = true
	card.card_id = card_data.get("id", "")
	card.is_on_battlefield = true
	card.static_display = true
	card.bake_strip_stats = true
	return card


func _batch_grid(cell_w: int, cell_h: int) -> Vector2i:
	# Biggest cols x rows of cell_w x cell_h cells that fits BOTH the dimension
	# cap and the pixel budget, shrinking the longer axis first so the render
	# target stays roughly square. Always at least 1x1 — an oversized cell simply
	# degrades to the old one-card-per-pass behaviour.
	var cols: int = maxi(1, BATCH_MAX_DIM / maxi(1, cell_w))
	var rows: int = maxi(1, BATCH_MAX_DIM / maxi(1, cell_h))
	while cols * rows > 1 and cols * cell_w * rows * cell_h > BATCH_MAX_PIXELS:
		if rows > 1 and (rows * cell_h >= cols * cell_w or cols <= 1):
			rows -= 1
		elif cols > 1:
			cols -= 1
		else:
			break
	return Vector2i(cols, rows)


func _bake_batch(card_datas: Array, battlefield: bool,
		validity: Callable = Callable()) -> void:
	# See the BATCH_* constants for why this is a grid and not a loop over bake().
	if not _can_bake():
		return
	var scale := BATTLEFIELD_SUPERSAMPLE
	var pad := BATTLEFIELD_PAD
	var cell := Vector2i(BATTLEFIELD_TEX_W, BATTLEFIELD_TEX_H)
	var key_prefix := ""
	if not battlefield:
		_sync_gameplay_quality()
		scale = maxi(1, _active_gameplay_bake_scale)
		pad = BAKE_PAD
		cell = Vector2i(TEX_W, TEX_H)
		key_prefix = "%s%d|" % [GAMEPLAY_KEY_PREFIX, scale]

	# Unique, still-uncached entries only — a warm re-entry does no passes at all.
	var jobs: Array = []
	var seen := {}
	for cd in card_datas:
		if typeof(cd) != TYPE_DICTIONARY or cd.is_empty():
			continue
		if battlefield and String(cd.get("type", "creature")) != "creature":
			continue
		var key: String = battlefield_cache_key(cd) if battlefield \
			else key_prefix + cache_key(cd)
		if seen.has(key):
			continue
		seen[key] = true
		if battlefield:
			if _battlefield_cache.has(key):
				_touch_battlefield_key(key)
				continue
		elif _cache.has(key):
			_touch_key(key)
			continue
		jobs.append([cd, key])
	if jobs.is_empty():
		return
	# Same one-card-at-a-time contract bake() honours: two bakers interleaving
	# their awaits would both parent into the shared viewport and capture each
	# other's overlap.
	while _bake_busy:
		await get_tree().process_frame
		if not _bake_valid(validity):
			return
	_bake_busy = true

	var cell_px := cell * scale
	var stride := Vector2i(
		(cell.x + BATCH_GUTTER) * scale, (cell.y + BATCH_GUTTER) * scale)
	var grid := _batch_grid(stride.x, stride.y)
	var per_pass: int = maxi(1, mini(BATCH_MAX_CARDS, grid.x * grid.y))
	var i := 0
	while i < jobs.size():
		if not _bake_valid(validity) or not is_instance_valid(_bake_viewport):
			break
		var chunk: Array = jobs.slice(i, mini(i + per_pass, jobs.size()))
		i += chunk.size()
		# Keep the render target squarish — a 1xN strip of tall cards wastes the
		# dimension cap and reads back a worse-shaped image than a block does.
		var cols: int = mini(grid.x, maxi(1, ceili(sqrt(float(chunk.size())))))
		var rows: int = ceili(float(chunk.size()) / float(cols))
		if rows > grid.y:
			cols = mini(grid.x, chunk.size())
			rows = ceili(float(chunk.size()) / float(cols))
		var want := Vector2i(cols * stride.x, rows * stride.y)
		# Assigning size reallocates the render target — only pay it on a change.
		if _bake_viewport.size != want:
			_bake_viewport.size = want
		var nodes: Array = []
		for j in range(chunk.size()):
			# Constructing 20+ Card2D nodes inside one frame is its own hitch,
			# and the FIRST batch of them would otherwise run synchronously
			# inside the caller (Combat._ready) before this coroutine ever
			# yields — which is how a fire-and-forget prebake still cost the
			# opening 90 ms. The viewport is asleep until the whole pass is
			# parented, so spreading construction costs no extra render passes.
			if j % BATCH_BUILD_PER_FRAME == 0:
				await get_tree().process_frame
				if not is_instance_valid(_bake_viewport):
					break
			var card := _make_bake_card(chunk[j][0], battlefield)
			_bake_viewport.add_child(card)
			card.scale = Vector2(scale, scale)
			card.position = Vector2(
				(j % cols) * stride.x + pad * scale,
				floori(float(j) / float(cols)) * stride.y + pad * scale)
			nodes.append(card)
		if not is_instance_valid(_bake_viewport):
			break
		_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# Two frames, once for the WHOLE pass — see _bake_scaled for why
		# frame_post_draw and why twice (dynamic-font glyph atlas fill).
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_instance_valid(_bake_viewport):
			break
		var sheet: Image = _bake_viewport.get_texture().get_image()
		_bake_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		for card in nodes:
			if is_instance_valid(card):
				_bake_viewport.remove_child(card)
				card.queue_free()
		if not _bake_valid(validity):
			break
		# The viewport is released by now, so slicing is pure CPU + upload — and
		# it is the expensive half: mipmapping and uploading twenty cards inside
		# one frame is a worse hitch than the thirty small ones this replaced
		# (measured: a 513 ms frozen frame). Hand the frame back every couple of
		# cards; the render passes are already paid, so this costs wall time the
		# player is spending on the intro banner anyway.
		for j in range(chunk.size()):
			if j > 0 and j % BATCH_SLICE_PER_FRAME == 0:
				await get_tree().process_frame
			var img := sheet.get_region(Rect2i(
				(j % cols) * stride.x,
				floori(float(j) / float(cols)) * stride.y,
				cell_px.x, cell_px.y))
			img.generate_mipmaps()
			var tex: ImageTexture = ImageTexture.create_from_image(img)
			var key: String = chunk[j][1]
			if battlefield:
				_battlefield_cache[key] = tex
				_touch_battlefield_key(key)
				battlefield_texture_ready.emit(key)
				continue
			# A preset change across the render awaits retires this resolution
			# class — never publish a now-stale gameplay snapshot under it.
			_sync_gameplay_quality(false)
			if key_prefix != "%s%d|" % [
					GAMEPLAY_KEY_PREFIX, _active_gameplay_bake_scale]:
				continue
			_cache[key] = tex
			_touch_key(key)
		if battlefield:
			_trim_battlefield_cache()
		else:
			_trim_cache()
	_bake_busy = false


func clear() -> void:
	# Drop all cached textures. Called when the run ends so a new run with
	# different upgrades doesn't reuse stale visuals. The ImageTextures are
	# RefCounted so they free as soon as no Card2D holds a reference.
	_cache.clear()
	_cache_order.clear()
	_battlefield_cache.clear()
	_battlefield_order.clear()
