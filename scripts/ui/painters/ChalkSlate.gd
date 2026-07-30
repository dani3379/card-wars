## ChalkSlate — a schoolroom slate in a worn wooden frame, for tables of
## law chalked at the gamble stages (the tali rank table, the sappers'
## grading ledger). Draws the BOARD only — frame, slate surface, chalk
## dust, one hanging cord hole — content is overlaid by the engine as
## labels/glyphs so it can live-update. Same school as EventHelm: pure
## painter, seeded wear, cabinet-projection contact shadow.
extends Control

var seed_text := "slate"

const WOOD := Color(0.36, 0.28, 0.19)
const WOOD_LIT := Color(0.46, 0.37, 0.26)
const SLATE := Color(0.165, 0.180, 0.170)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if minf(size.x, size.y) <= 20.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	# Ground shadow — pooled below, wide and flat.
	draw_rect(Rect2(Vector2(6, size.y - 6), Vector2(size.x - 8, 8)),
		Color(0, 0, 0, 0.28))
	# Frame, slightly out of true — a soldier's slate, not a schoolmaster's.
	var skew := rng.randf_range(-2.0, 2.0)
	var frame := PackedVector2Array([
		Vector2(0, 2 + skew), Vector2(size.x, 0),
		Vector2(size.x - 1, size.y - 2), Vector2(2, size.y - skew)])
	draw_colored_polygon(frame, WOOD)
	draw_line(Vector2(1, 3 + skew), Vector2(size.x - 1, 1),
		WOOD_LIT, 2.5, true)
	# The slate itself, inset.
	var inset := 9.0
	draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset * 2, inset * 2)),
		SLATE)
	# Old lessons, badly erased: faint chalk ghosts and dust smears.
	for _i in range(4):
		var p := Vector2(rng.randf_range(inset + 6, size.x - inset - 20),
			rng.randf_range(inset + 6, size.y - inset - 8))
		draw_arc(p, rng.randf_range(4, 11), rng.randf() * TAU,
			rng.randf() * TAU + rng.randf_range(1.5, 3.5), 8,
			Color(0.85, 0.86, 0.82, rng.randf_range(0.03, 0.07)), 2.0, true)
	draw_rect(Rect2(Vector2(inset + 2, size.y - inset - 7),
		Vector2(size.x * 0.4, 4)), Color(0.85, 0.86, 0.82, 0.05))
	# The cord hole, top-center — slates hang from a nail between wars.
	draw_circle(Vector2(size.x * 0.5, 5.0), 2.4, Color(0.10, 0.08, 0.06), true, -1.0, true)
