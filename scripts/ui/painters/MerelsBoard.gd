## MerelsBoard — the scratched merels board of The Sentry's Board
## (morris_game). A worn flagstone in the cabinet projection: far edge
## tapered and in shadow, near edge showing the slab's thickness, light
## pooled below center. The three men's morris grid is chiselled in — 8
## lines, 9 drilled pits. The engine seats stones and buttons at
## point_pos(i) and sets painter state for every telegraph: threat tints
## (2-in-a-line), the selection halo, legal-move rings, the hover ghost,
## and the winning chalk stroke. Pure painter; Event.gd owns motion and
## hit-testing.
extends Control

## The 8 mills, by point index in reading order (far rank first).
## Rows, columns, then the two diagonals through the middle post.
const LINES := [
	[0, 1, 2], [3, 4, 5], [6, 7, 8],
	[0, 3, 6], [1, 4, 7], [2, 5, 8],
	[0, 4, 8], [2, 4, 6]]

const ROW_Y := [0.20, 0.47, 0.76]
const ROW_SPAN := [0.56, 0.70, 0.84]

var seed_text := "merels"
var hover_point := -1        # a legal placement/destination under the mouse
var select_point := -1       # the player's lifted stone
var dest_points: Array = []  # legal destinations for the lifted stone
var threats: Array = []      # {pts: [a, b, c], col: Color} — live 2-in-a-line tints
var win_pts: Array = []      # the winning mill; a chalk stroke strikes through it

const SLAB := Color(0.28, 0.25, 0.215)
const SLAB_EDGE := Color(0.16, 0.14, 0.12)
const GROOVE := Color(0.10, 0.085, 0.07, 0.9)
const GROOVE_LIT := Color(0.42, 0.38, 0.31, 0.35)
const PIT := Color(0.09, 0.075, 0.06)
const HALO := Color(0.90, 0.76, 0.42, 0.9)
const RING_OK := Color(0.60, 0.80, 0.44, 0.85)
const GHOST := Color(0.92, 0.88, 0.78, 0.55)
const CHALK := Color(0.94, 0.91, 0.83, 0.95)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Projected position of point i (0..8, reading order, far rank first).
## Rows sink toward the viewer and their spans widen — the cabinet recede.
func point_pos(i: int) -> Vector2:
	var col := i % 3
	var row := int(i / 3.0)
	var span: float = size.x * float(ROW_SPAN[row])
	var y: float = size.y * float(ROW_Y[row])
	return Vector2(size.x * 0.5 + span * (float(col) - 1.0) * 0.5, y)


func _slab_poly(rng: RandomNumberGenerator) -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var base := [
		Vector2(w * 0.115, h * 0.055), Vector2(w * 0.5, h * 0.035),
		Vector2(w * 0.885, h * 0.055), Vector2(w * 0.955, h * 0.46),
		Vector2(w * 0.985, h * 0.895), Vector2(w * 0.5, h * 0.925),
		Vector2(w * 0.015, h * 0.895), Vector2(w * 0.045, h * 0.46)]
	var out := PackedVector2Array()
	for p in base:
		out.append(p + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-3.0, 3.0)))
	return out


func _ring(pos: Vector2, r: float, col: Color, width: float) -> void:
	draw_set_transform(pos, 0.0, Vector2(1.0, 0.72))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 26, col, width, true)
	draw_set_transform_matrix(Transform2D())


func _draw() -> void:
	if minf(size.x, size.y) <= 24.0:
		return
	var w := size.x
	var h := size.y
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var poly := _slab_poly(rng)
	# Ground shadow under the near edge, then the slab's thickness lip.
	draw_set_transform(Vector2(w * 0.5, h * 0.965), 0.0, Vector2(1.0, 0.30))
	draw_circle(Vector2.ZERO, w * 0.52, Color(0, 0, 0, 0.30), true, -1.0, true)
	draw_set_transform_matrix(Transform2D())
	var lip := PackedVector2Array()
	for p in poly:
		lip.append(p + Vector2(0, 7))
	draw_colored_polygon(lip, SLAB_EDGE)
	draw_colored_polygon(poly, SLAB)
	# Light pooled below center; the far reach kept in shadow.
	for i in range(3):
		draw_set_transform(Vector2(w * 0.5, h * 0.62), 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, w * (0.16 + 0.11 * float(i)),
			Color(0.93, 0.86, 0.68, 0.05), true, -1.0, true)
		draw_set_transform_matrix(Transform2D())
	var far := PackedVector2Array([poly[0], poly[1], poly[2],
		Vector2(w * 0.88, h * 0.16), Vector2(w * 0.5, h * 0.14),
		Vector2(w * 0.12, h * 0.16)])
	draw_colored_polygon(far, Color(0, 0, 0, 0.14))
	# Stone mottle.
	for _i in range(26):
		var mp := Vector2(rng.randf_range(w * 0.08, w * 0.92),
			rng.randf_range(h * 0.10, h * 0.88))
		draw_circle(mp, rng.randf_range(1.0, 3.2),
			Color(0, 0, 0, 0.05) if rng.randf() < 0.6 else Color(1, 1, 0.9, 0.03), true, -1.0, true)
	# The chiselled grid: each line a groove — dark cut plus a light catch
	# on its lower lip, endpoints wobbled like hand work.
	for ln in LINES:
		var a: Vector2 = point_pos(ln[0]) \
			+ Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		var b: Vector2 = point_pos(ln[2]) \
			+ Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		draw_line(a, b, GROOVE, 3.0, true)
		draw_line(a + Vector2(0, 1.6), b + Vector2(0, 1.6), GROOVE_LIT, 1.2, true)
	# Threat tints ride the grooves (informational — they hold steady).
	for t in threats:
		var pts: Array = t.get("pts", [])
		if pts.size() == 3:
			draw_line(point_pos(int(pts[0])), point_pos(int(pts[2])),
				t.get("col", GHOST), 5.0, true)
	# The 9 pits, drilled deeper toward the viewer.
	for i in range(9):
		var pp := point_pos(i)
		var pr := 4.6 + 0.9 * float(int(i / 3.0))
		draw_set_transform(pp, 0.0, Vector2(1.0, 0.72))
		draw_circle(Vector2.ZERO, pr, PIT, true, -1.0, true)
		draw_arc(Vector2.ZERO, pr + 0.8, 0.35, 2.8, 10, GROOVE_LIT, 1.2, true)
		draw_set_transform_matrix(Transform2D())
	# Telegraph rings: the lifted stone, its legal posts, the hover ghost.
	# The halo must clear the seated stone's edge (stones are ~38px wide
	# and drawn over the board) or the stone swallows it whole.
	if select_point >= 0:
		_ring(point_pos(select_point), 24.0, HALO, 2.6)
	for d in dest_points:
		_ring(point_pos(int(d)), 13.0, RING_OK, 2.0)
	if hover_point >= 0 and hover_point != select_point:
		_ring(point_pos(hover_point), 11.0, GHOST, 1.6)
	# The winning mill: a chalk stroke, double-drawn like a hasty hand.
	if win_pts.size() == 3:
		var a2 := point_pos(int(win_pts[0]))
		var b2 := point_pos(int(win_pts[2]))
		var dir := (b2 - a2).normalized() * 14.0
		draw_line(a2 - dir, b2 + dir, CHALK, 4.5, true)
		draw_line(a2 - dir + Vector2(1.5, 2.0), b2 + dir + Vector2(1.5, 2.0),
			Color(CHALK.r, CHALK.g, CHALK.b, 0.35), 2.0, true)
