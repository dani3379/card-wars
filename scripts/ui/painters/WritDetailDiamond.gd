## WritDetailDiamond — extracted from Card2D.gd (backend restructure 2026-07-14).
extends Control

var col := Color(1, 1, 1)
var r := 5.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var c := size * 0.5
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(-r, 0), c]), Color(1, 1, 1, 0.18))
