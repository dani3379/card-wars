## StatCaret — extracted from Card2D.gd (backend restructure 2026-07-14).
## A small drawn caret (triangle) marking a buffed (▲) or debuffed (▼) ATK — the
## non-colour redundancy for the gold/red stat recolour, so the buff signal
## survives colour-blindness. Drawn, not a font glyph, so it renders regardless of
## the card font's glyph coverage.
extends Control

var up := true
var col := Color(1.0, 0.8, 0.2)
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var w := size.x
	var h := size.y
	var pts: PackedVector2Array
	if up:
		pts = PackedVector2Array([Vector2(w * 0.5, 0.0), Vector2(w, h), Vector2(0.0, h)])
	else:
		pts = PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w * 0.5, h)])
	# Dark halo (offset copy) first so the caret reads on any background.
	var halo := PackedVector2Array()
	for p in pts:
		halo.append(p + Vector2(0.0, 1.0))
	draw_colored_polygon(halo, Color(0, 0, 0, 0.85))
	draw_colored_polygon(pts, col)
