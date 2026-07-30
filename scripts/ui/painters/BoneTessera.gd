## BoneTessera — the dead sentry's gaming piece in The Sentry's Board
## (morris_game): a squared bone tile, an old soldier's tessera with the
## Fourth's IV scratched into its face. Draws its own lying squash, edge
## thickness, and ground pool (the CoinProp cabinet contract — never also
## scale/rotate the node).
extends Control

var seed_text := "tessera"

const BONE := Color(0.86, 0.82, 0.71)
const BONE_DIM := Color(0.74, 0.69, 0.58)
const BONE_EDGE := Color(0.52, 0.47, 0.38)
const SCRATCH := Color(0.36, 0.31, 0.24, 0.9)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A squared tile with cut corners, chipped by seed — bone, not machined.
func _face_poly(r: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var base := [
		Vector2(-r, -r * 0.55), Vector2(-r * 0.55, -r), Vector2(r * 0.55, -r),
		Vector2(r, -r * 0.55), Vector2(r, r * 0.55), Vector2(r * 0.55, r),
		Vector2(-r * 0.55, r), Vector2(-r, r * 0.55)]
	var pts := PackedVector2Array()
	for p in base:
		pts.append(p + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2)))
	return pts


func _draw() -> void:
	if minf(size.x, size.y) <= 10.0:
		return
	var c := Vector2(size.x * 0.5, size.y * 0.52)
	var r := minf(size.x, size.y) * 0.42
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	# Ground pool.
	draw_set_transform(Vector2(c.x, c.y + r * 0.55), 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, r * 1.25, Color(0, 0, 0, 0.28), true, -1.0, true)
	draw_set_transform_matrix(Transform2D())
	# The lying tile: squashed by the cabinet, thickness below the face.
	draw_set_transform(c, 0.0, Vector2(1.0, 0.74))
	var face := _face_poly(r, rng)
	var lip := PackedVector2Array()
	for p in face:
		lip.append(p + Vector2(0, 4.5))
	draw_colored_polygon(lip, BONE_EDGE)
	draw_colored_polygon(face, BONE)
	# Age: a dim band along the near edge, pores by seed.
	draw_line(Vector2(-r * 0.62, r * 0.58), Vector2(r * 0.62, r * 0.58),
		Color(BONE_DIM.r, BONE_DIM.g, BONE_DIM.b, 0.55), 4.0, true)
	for _i in range(4):
		draw_circle(Vector2(rng.randf_range(-r * 0.6, r * 0.6),
			rng.randf_range(-r * 0.6, r * 0.55)), rng.randf_range(0.6, 1.3),
			Color(BONE_DIM.r, BONE_DIM.g, BONE_DIM.b, 0.6), true, -1.0, true)
	# The Fourth's brand: IV, scratched deep.
	var sw := r * 0.30
	draw_line(Vector2(-sw, -sw), Vector2(-sw, sw), SCRATCH, 2.0, true)
	draw_line(Vector2(-sw * 0.1, -sw), Vector2(sw * 0.45, sw), SCRATCH, 2.0, true)
	draw_line(Vector2(sw * 1.0, -sw), Vector2(sw * 0.45, sw), SCRATCH, 2.0, true)
	draw_set_transform_matrix(Transform2D())
