extends Node
# Autoload. Bakes Card2D's heavy static-display visual into a single
# ImageTexture per card identity and caches it for the lifetime of the run.
# Combat / Collection / Reward / Shop all share the same cache: a card baked
# in the gallery is reused next time the same card shows up in hand.
#
# Why bake: Card2D v4's full layout creates ~20 Control nodes per card. At
# the 5-card hand size that's ~100 nodes drawing ~200 sub-draws / frame just
# for the player's hand; the Card Gallery (122 cards) was ~5000 sub-draws —
# enough that the GL Compatibility renderer choked on batching. Baking the
# static layers (frame, art, banner, well, orb spheres) into one quad and
# leaving the dynamic numerals + floop indicator as live Labels collapses
# that to ~5 nodes per card while keeping stat updates instant.
#
# Cache key includes everything that can affect the painted look: id, cost,
# atk, hp, sorted keywords. Stat-modifying upgrades (Sharpen, Fortify) shift
# atk/hp/cost in the card_data dict before bake, so each upgrade variant
# gets its own texture. Mid-fight stat changes (damage, buffs) DO NOT change
# the cache key — those are reflected via the live overlay labels.

const BAKE_PAD := 12
const SLOT_W := 225
const SLOT_H := 300
const TEX_W := SLOT_W + BAKE_PAD * 2  # 249  (LOGICAL display size — overlay keys off this)
const TEX_H := SLOT_H + BAKE_PAD * 2  # 324
# Supersample factor: bake at SUPERSAMPLE× the logical size so the baked art/text
# has enough pixels to stay crisp when a card is lifted/zoomed. The display scales
# the hi-res texture back DOWN into the 249px rect (STRETCH_SCALE + mipmaps = clean).
# Bumped 2→3: the bake is the ONLY place the card's procedurally-drawn frame
# (fillets, gems, wax seals) gets antialiased, and at 2× those curved edges read
# rough once on screen. 3× + MSAA on the bake viewport (see _ready) downsamples
# them to a clean, smooth edge — proper SSAA for the busiest art on screen.
const SUPERSAMPLE := 3
const CARD_SCENE = preload("res://scenes/card_2d.tscn")

var _cache: Dictionary = {}  # String → ImageTexture
var _bake_viewport: SubViewport = null
# Serializes concurrent bakers. Two bake() calls interleaving their awaits would
# both parent a card into the shared viewport and capture each other's overlap —
# possible since the idle deck warm (ScenePreload.warm_run_deck, running behind
# the map) can still be in flight when Combat's _prebake_hand_textures starts.
var _bake_busy := false


func _ready() -> void:
	_bake_viewport = SubViewport.new()
	_bake_viewport.size = Vector2i(TEX_W * SUPERSAMPLE, TEX_H * SUPERSAMPLE)
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
	# baked cards stay crisp purely from SUPERSAMPLE (3× bake) + mipmaps, which is
	# real supersampling and renderer-independent. Setting MSAA here did nothing
	# but emit a "2D MSAA not supported" warning per bake.
	_bake_viewport.msaa_2d = Viewport.MSAA_DISABLED
	# DISABLED between bakes (was UPDATE_ALWAYS, which re-rendered this 3×-res
	# viewport every frame for the whole session). bake() flips it to ALWAYS only
	# while a card is parented, then back to DISABLED once the image is captured.
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_bake_viewport)


func cache_key(card_data: Dictionary) -> String:
	# Stat values + keywords are baked into the visual (description text wraps
	# around keyword tokens; rarity drives frame colour; cost/atk/hp orbs are
	# painted) so the key includes them. Mid-fight buffs / damage live in the
	# overlay labels, not the bake, so they DON'T need a key entry.
	var kws: Array = card_data.get("keywords", []).duplicate()
	kws.sort()
	return "%s|%d|%d|%d|%s" % [
		str(card_data.get("id", "")),
		int(card_data.get("cost", 0)),
		int(card_data.get("atk", 0)),
		int(card_data.get("hp", 0)),
		",".join(kws),
	]


func has(card_data: Dictionary) -> bool:
	return _cache.has(cache_key(card_data))


func get_texture(card_data: Dictionary) -> Texture2D:
	# Sync read — returns null if not yet baked. Callers that can't await
	# (e.g. Card2D._build_layout) use this and fall back to live layout on
	# miss; pre-bake passes call bake() to populate.
	return _cache.get(cache_key(card_data), null)


func bake(card_data: Dictionary) -> Texture2D:
	# Async (`await`). Idempotent: returns the cached texture immediately on
	# cache hit, otherwise spins up a transient Card2D in the shared
	# viewport, waits 2 frames for layout + render, and snapshots the result
	# into a standalone ImageTexture (so the viewport can be reused for the
	# next bake without affecting this texture).
	var key := cache_key(card_data)
	if _cache.has(key):
		return _cache[key]
	# One card in the viewport at a time. While waiting, the other baker may
	# finish this very key — re-check before claiming the viewport.
	while _bake_busy:
		await get_tree().process_frame
		if _cache.has(key):
			return _cache[key]
	_bake_busy = true

	var card = CARD_SCENE.instantiate()
	card.card_data = card_data.duplicate(true)
	card.card_id = card_data.get("id", "")
	card.is_on_battlefield = true
	# static_display kills the per-frame animations + cosmetic depth layers
	# we don't want frozen into the texture. bake_strip_stats blanks the
	# cost/atk/hp numerals so they don't get burned in — the live overlay
	# labels paint the numbers on top of the orb sphere.
	card.static_display = true
	card.bake_strip_stats = true
	# Bake the frame + art but NOT the rules text — the live overlay draws the text
	# with the font renderer (StS model) so it stays crisp at any zoom.
	card.bake_strip_desc = true
	# Same for the NAME: bake the cartouche banner but leave its text blank; the
	# live overlay draws the name with the font renderer so it doesn't show up as
	# a downscaled bitmap (the residual "card names look pixelly" after MSDF).
	card.bake_strip_name = true
	# Wake the viewport for the duration of this bake only (it sits DISABLED
	# between bakes so it isn't re-rendered every frame all session long).
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bake_viewport.add_child(card)
	# Card2D._ready sets size = (225, 300). The viewport is 12 px larger on
	# each axis so the cost/ATK/HP orbs that hang -9 px past the silhouette
	# get captured instead of clipped. Everything scales by SUPERSAMPLE so the card
	# fills the SUPERSAMPLE× viewport and its fonts/art rasterize at higher res.
	card.scale = Vector2(SUPERSAMPLE, SUPERSAMPLE)
	card.position = Vector2(BAKE_PAD, BAKE_PAD) * SUPERSAMPLE
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
	# Mipmaps so the supersampled bake minifies cleanly when the card is shown small
	# (compact tokens / tight hands) — without them a 498px texture at ~120px aliases.
	image.generate_mipmaps()
	var tex: ImageTexture = ImageTexture.create_from_image(image)
	# Sync detach so the next bake starts with an empty viewport. queue_free
	# alone defers to end-of-frame, leaving a brief window where both cards
	# would be parented.
	_bake_viewport.remove_child(card)
	card.queue_free()
	_cache[key] = tex
	_bake_busy = false
	return tex


func bake_many(card_datas: Array) -> void:
	# Convenience for pre-baking a deck at combat start. Caller awaits this
	# once; we serially walk the list. ~2 frames per uncached card; cached
	# cards return instantly (no await yields), so subsequent fights warm
	# only the cards that are new (rewards picked up since last fight).
	for cd in card_datas:
		await bake(cd)


func clear() -> void:
	# Drop all cached textures. Called when the run ends so a new run with
	# different upgrades doesn't reuse stale visuals. The ImageTextures are
	# RefCounted so they free as soon as no Card2D holds a reference.
	_cache.clear()
