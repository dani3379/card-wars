## ParchmentPlate — extracted from Card2D.gd (backend restructure 2026-07-14).
## Aged-paper tooth for the card leaf interior: seeded mottling washes,
## lighter sizing patches, foxing specks, fiber hairlines. The leaf's
## organic edge + toast live in WritLeaf (path-locked to the deckle);
## this painter only ages the field inside it. Deterministic per seed —
## bakes are stable.
extends Control

var seed_text := "leaf"
var stain := Color(0.455, 0.341, 0.196)
var lift := Color(0.973, 0.945, 0.851)
var fox := Color(0.408, 0.263, 0.118)
var strength := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if size.x <= 4.0 or size.y <= 4.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	# 1 — mottled sepia washes: the sizing ages unevenly.
	for i in range(11):
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var r := lerpf(size.x * 0.14, size.x * 0.40, rng.randf())
		var a := (0.028 + rng.randf() * 0.036) * strength
		draw_circle(p, r, Color(stain.r, stain.g, stain.b, a),
			true, -1.0, true)
	# 2 — lighter patches where the sizing held.
	for i in range(5):
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var r := lerpf(size.x * 0.10, size.x * 0.28, rng.randf())
		draw_circle(p, r,
			Color(lift.r, lift.g, lift.b, 0.025 + rng.randf() * 0.030),
			true, -1.0, true)
	# 3 — foxing specks.
	for i in range(28):
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		draw_circle(p, 0.6 + rng.randf() * 1.2,
			Color(fox.r, fox.g, fox.b,
			minf((0.055 + rng.randf() * 0.085) * strength, 0.30)),
			true, -1.0, true)
	# 4 — fiber hairlines.
	for i in range(30):
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		draw_line(p, p + dir * (3.0 + rng.randf() * 7.0),
			Color(stain.r, stain.g, stain.b, 0.035 + rng.randf() * 0.045),
			1.0, true)
