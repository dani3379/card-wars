## TallyMarks — extracted from Card2D.gd (backend restructure 2026-07-14).
## Campaign memory (docs/CAMPAIGN_MEMORY.md): kill-tally scratches down the
## writ's left margin — the creature's service record inked on the document
## itself. Groups of five (four strokes + a diagonal cross), rust-brown dried
## ink, seeded jitter per card so no two records look machine-made. Display
## caps at 15 scratches; the epithet and veteran rank carry the story past that.
extends Control

var kills := 0
var seed_text := "writ"
## Stroke pitch down the rect, and the ink. Both defaulted rather than
## hardcoded (2026-08-05) so the same painter can run as the title screen's
## campaign ledger: the rust-brown was mixed to sit on a card's PARCHMENT
## margin and all but vanishes on the menu's warm-black, and 5px strokes that
## read at a card's scale read as a smudge at a footer's. Card2D passes
## neither, so its record is unchanged.
var pitch := 5.0
var ink_color := Color(0.42, 0.16, 0.10, 0.78)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if kills <= 0 or size.y <= 8.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) ^ 0x7A11
	var ink := ink_color
	var n: int = mini(kills, 15)
	var y := 2.0
	var i := 0
	while i < n:
		var group: int = mini(n - i, 5)
		var g_top := y
		for s in range(mini(group, 4)):
			var jx := rng.randf_range(-0.8, 0.8)
			var jy := rng.randf_range(-0.6, 0.6)
			draw_line(Vector2(1.5 + jx, y + jy),
				Vector2(size.x - 1.5 + jx, y + jy + rng.randf_range(-0.7, 0.7)),
				ink, maxf(1.2, pitch * 0.24), true)
			y += pitch
		if group == 5:
			# The fifth stroke slashes diagonally across its four fellows.
			draw_line(Vector2(0.5, y - 2.0), Vector2(size.x - 0.5, g_top - 1.0),
				Color(ink.r, ink.g, ink.b, minf(ink.a + 0.07, 1.0)),
				maxf(1.4, pitch * 0.28), true)
		y += pitch * 0.8
		i += group
