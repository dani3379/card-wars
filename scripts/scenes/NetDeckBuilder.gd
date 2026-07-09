extends Control
## NetDeckBuilder — shared base for the four online deck-acquisition screens
## (NetQuick / NetConstructed / NetSealed / NetDraft).
##
## Online Skirmish's combat is mode-agnostic, so a "mode" is just a
## deck-acquisition scene plus a MODE_DEFS entry. Those four scenes had drifted
## into carrying their own verbatim copies of the same palette, scene constants,
## sync flags, and (for the pool-based builders) an identical card-thumbnail
## helper. This base owns that shared surface so the modes can't diverge on it;
## each subclass keeps only its bespoke layout + netcode.
##
## Deliberately thin: it holds data + one stateless helper, NOT _ready or the
## scaffold, so it changes no runtime flow. Subclasses still drive their own
## lifecycle and override _on_add where they accept pool clicks.

# ── Shared scene constants ───────────────────────────────────────────────────
const MENU_SCENE := "res://scenes/main_menu.tscn"
const MAX_COPIES: int = 2           # per-id deck cap (Quick/Constructed; Sealed uses its own)
const THUMB_SCALE: float = 0.46     # pool/deck card-thumbnail scale

# Hover-to-enlarge preview: pool/deck thumbnails are small, so hovering one pops
# the full card beside it (the "window showing the card you hover"). Native card
# size; named _hover_* so it doesn't collide with NetDraft's own bespoke preview.
const HOVER_CARD_SCENE := preload("res://scenes/card_2d.tscn")
const HOVER_PREVIEW_W := 225.0
const HOVER_PREVIEW_H := 300.0

# ── Shared palette (the Skirmish lobby family — NOT GameTheme's; the gilt here
# is warmer at (1.0, 0.85, 0.45) vs GameTheme's (1.0, 0.88, 0.35)). ───────────
const GILT_BRIGHT := Color(1.0, 0.85, 0.45, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const ASH := Color(0.62, 0.58, 0.52, 1.0)
const GREEN := Color(0.55, 0.85, 0.45, 1.0)
const RED_WARN := Color(0.90, 0.45, 0.35, 1.0)
const HOST_BLUE := Color(0.45, 0.70, 1.0, 1.0)
const SPELL_BLUE := Color(0.70, 0.88, 1.0, 1.0)

# ── Shared state ─────────────────────────────────────────────────────────────
var _target: int = 20               # SkirmishState.DECK_TARGET (set in each _ready)
var _rng := RandomNumberGenerator.new()
var _local_finished: bool = false
var _remote_finished: bool = false

var _root: VBoxContainer
var _header: Label

# Pool-based builders (Constructed / Sealed) index their clickable pool tiles
# here: id -> {"button": Button, "badge": Label, "card": Card2D}. Unused by the
# Quick/Draft modes, which don't present a browsable pool.
var _pool_rows: Dictionary = {}

# ── Hover preview (shared by the pool-based builders) ─────────────────────────
var _hover_preview: Control = null    # the live enlarged Card2D, or null
var _hover_anchor: Control = null     # the tile it's pinned beside
var _hover_id: String = ""            # card id currently previewed


# Builds one clickable pool tile from a card id and registers it in _pool_rows.
# Identical across the pool-based modes; clicking routes to the subclass _on_add.
func _build_pool_thumb(id: String) -> Control:
	var d := CardDB.get_card_data(id)
	var thumb := GameTheme.make_card_thumb(d, THUMB_SCALE)
	var btn := thumb["button"] as Button
	btn.pressed.connect(_on_add.bind(id))
	btn.tooltip_text = String(d.get("name", id))
	_attach_hover_preview(btn, id)
	_pool_rows[id] = {"button": btn, "badge": thumb["badge"], "card": thumb["card"]}
	return thumb["root"]


# Overridden by pool-based subclasses to add the clicked card to the deck. The
# base no-op lets _build_pool_thumb wire its signal uniformly; modes without a
# pool simply never call it.
func _on_add(_id: String) -> void:
	pass


# ── Shared Esc + settings chrome ─────────────────────────────────────────────
# All four deck screens (Quick / Constructed / Sealed / Draft) inherit this.
# _install_net_chrome() drops the top-left settings gear; each subclass calls it
# from its own _ready (the base deliberately has none). Esc mirrors the BACK
# button: drop the peer connection and return to the menu.
func _install_net_chrome() -> void:
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		NetMatch.leave()
		get_tree().change_scene_to_file(MENU_SCENE)
		get_viewport().set_input_as_handled()


# ─────────────────────────────────────────────────────────────────────────
#  HOVER PREVIEW
#
#  Wire any thumbnail's hover (its full-rect Button, which keeps emitting
#  mouse_entered even when disabled) to pop a full-size card beside it. Used
#  for both pool tiles (via _build_pool_thumb) and the built-deck tiles (the
#  subclasses call _attach_hover_preview on those Buttons too).
# ─────────────────────────────────────────────────────────────────────────

func _attach_hover_preview(anchor: Control, id: String) -> void:
	anchor.mouse_entered.connect(_show_hover_preview.bind(id, anchor))
	anchor.mouse_exited.connect(_hide_hover_preview.bind(id))


func _show_hover_preview(id: String, anchor: Control) -> void:
	if id == _hover_id and is_instance_valid(_hover_preview):
		return
	_clear_hover_preview()
	_hover_id = id
	_hover_anchor = anchor
	var card := HOVER_CARD_SCENE.instantiate()
	card.card_data = CardDB.get_card_data(id).duplicate(true)
	card.card_id = id
	card.is_on_battlefield = true       # full card, no drag / hover-lift
	card.live_baked_mode = true
	CardTextureCache.bake(card.card_data)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)                     # sibling above _root; not clipped by scrolls
	_hover_preview = card
	_place_hover_preview()


func _hide_hover_preview(id: String) -> void:
	# Guard on id so moving tile→tile (new enter fires before the old exit) can't
	# tear down the preview that just opened for the tile we moved onto.
	if id == _hover_id:
		_clear_hover_preview()


func _clear_hover_preview() -> void:
	if is_instance_valid(_hover_preview):
		_hover_preview.queue_free()
	_hover_preview = null
	_hover_anchor = null
	_hover_id = ""


# Drop the preview only if it's pinned to a tile inside `container` — called
# before a panel rebuild frees its tiles, so a stale anchor can't linger while
# a preview pinned to the *other* column survives the refresh untouched.
func _clear_hover_preview_under(container: Node) -> void:
	if container != null and is_instance_valid(_hover_anchor) \
			and container.is_ancestor_of(_hover_anchor):
		_clear_hover_preview()


# Pin the enlarged card beside its tile: prefer the right of the tile, flip to
# the left if that overflows, then clamp fully on-screen. `size` is the scene
# root's rect == the 1600×900 canvas (the stretch space tile rects live in).
func _place_hover_preview() -> void:
	if not is_instance_valid(_hover_preview) or not is_instance_valid(_hover_anchor):
		return
	var bounds: Vector2 = size
	var ar: Rect2 = _hover_anchor.get_global_rect()
	var px: float = ar.position.x + ar.size.x + 14.0
	if px + HOVER_PREVIEW_W > bounds.x - 8.0:
		px = ar.position.x - HOVER_PREVIEW_W - 14.0
	var py: float = ar.position.y + (ar.size.y - HOVER_PREVIEW_H) * 0.5
	px = clampf(px, 8.0, maxf(8.0, bounds.x - HOVER_PREVIEW_W - 8.0))
	py = clampf(py, 8.0, maxf(8.0, bounds.y - HOVER_PREVIEW_H - 8.0))
	_hover_preview.position = Vector2(px, py)
