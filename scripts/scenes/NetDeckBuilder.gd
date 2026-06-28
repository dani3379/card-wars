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


# Builds one clickable pool tile from a card id and registers it in _pool_rows.
# Identical across the pool-based modes; clicking routes to the subclass _on_add.
func _build_pool_thumb(id: String) -> Control:
	var d := CardDB.get_card_data(id)
	var thumb := GameTheme.make_card_thumb(d, THUMB_SCALE)
	var btn := thumb["button"] as Button
	btn.pressed.connect(_on_add.bind(id))
	btn.tooltip_text = String(d.get("name", id))
	_pool_rows[id] = {"button": btn, "badge": thumb["badge"], "card": thumb["card"]}
	return thumb["root"]


# Overridden by pool-based subclasses to add the clicked card to the deck. The
# base no-op lets _build_pool_thumb wire its signal uniformly; modes without a
# pool simply never call it.
func _on_add(_id: String) -> void:
	pass
