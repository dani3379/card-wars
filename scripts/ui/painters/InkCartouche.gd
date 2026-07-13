## InkCartouche — extracted from Card2D.gd (backend restructure 2026-07-14).
## The name cartouche: a swallowtail banner — ink field, metal edge,
## notched ribbon-tail ends — replacing the flat full-width bar (the last
## pure UI-rectangle on the card). The name sits on the ink between tails.
extends Control

var metal := Color(0.64, 0.48, 0.27)
var ink := Color(0.137, 0.110, 0.082, 0.985)
var notch := 9.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w - notch, h * 0.5),
		Vector2(w, h), Vector2(0, h), Vector2(notch, h * 0.5),
	])
	# Settle shadow, then the banner, then its metal edge (AA polyline).
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(0, 1.6))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.28))
	draw_colored_polygon(pts, ink)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(metal.r, metal.g, metal.b, 0.92), 1.2, true)
	# Inner hairlines between the tails — the double-rule read.
	var hl := Color(metal.r, metal.g, metal.b, 0.45)
	draw_line(Vector2(notch + 4.0, 2.5), Vector2(w - notch - 4.0, 2.5),
		hl, 1.0, true)
	draw_line(Vector2(notch + 4.0, h - 2.5), Vector2(w - notch - 4.0, h - 2.5),
		hl, 1.0, true)
