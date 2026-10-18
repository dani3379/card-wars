## WaxBar — the HP plaque's fill, drawn as wax actually poured into the
## channel (the StyleBoxFlat it replaces was a solid crimson rectangle with
## a 1px top line — at full HP it read as flat UI, which defeated the whole
## plaque conceit). Same one-light grammar as WaxSeal (top-left):
##   surface   — lighter upper band over a cooled darker body (the pour
##               skins over from the top)
##   meniscus  — thin lit line where the wax meets the channel's top wall
##   settle    — occlusion at the channel floor
##   pour front — the draining right edge: a darker cooling lip with a
##               seeded wobble, so the frontier reads as a material edge,
##               not a clipped rect
## The node's WIDTH is animated by _update_hud's existing "Fill" size:x
## tween; every resize repaints, so the pour front travels with the drain.
extends Control

var wax := Color(0.52, 0.13, 0.10)
var seed_text := "hp"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 2.0 or h < 2.0:
		return
	var body := Color(wax.r * 0.84, wax.g * 0.84, wax.b * 0.86)
	var skin := wax
	var lit := Color(minf(wax.r * 1.40 + 0.05, 1.0),
		minf(wax.g * 1.40 + 0.05, 1.0), minf(wax.b * 1.40 + 0.05, 1.0))
	# Cooled body, then the lighter skinned-over surface band.
	draw_rect(Rect2(0, 0, w, h), body)
	draw_rect(Rect2(0, 0, w, h * 0.52), skin)
	# Meniscus: the lit line where wax meets the channel's top wall.
	draw_rect(Rect2(0, 0, w, 1.5), Color(lit.r, lit.g, lit.b, 0.55))
	# Channel-floor occlusion.
	draw_rect(Rect2(0, h - 2.0, w, 2.0), Color(0, 0, 0, 0.28))
	# The pour front: a seeded wobble edge with a cooling lip — the drain
	# frontier is a material boundary, not a clip. Redrawn per width so the
	# wobble hangs off whatever x the tween has reached.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph := rng.randf() * TAU
	var lip_w := 2.5
	var steps := maxi(int(h / 3.0), 3)
	# The back edge must sit strictly LEFT of the wobble's deepest trough, or the
	# strip self-intersects and draw_colored_polygon fails triangulation (it spammed
	# "Invalid polygon data" every frame the HP plaque redrew). bump bottoms out at
	# -(1.4 + 0.7) = -2.1, so the old -2.0 inset was inside the trough by 0.1px.
	var back_x := w - lip_w - 2.2
	var pts := PackedVector2Array()
	pts.append(Vector2(back_x, 0))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var bump := sin(t * 9.0 + ph) * 1.4 + sin(t * 23.0 + ph * 2.0) * 0.7
		pts.append(Vector2(w - lip_w + bump, t * h))
	pts.append(Vector2(back_x, h))
	draw_colored_polygon(pts, Color(wax.r * 0.62, wax.g * 0.62, wax.b * 0.64))
	# Seeded cooled flecks on the skin — matte pits, not sparkles.
	for i in range(3):
		var fx := rng.randf() * maxf(w - 8.0, 1.0) + 4.0
		var fy := rng.randf() * h * 0.5 + h * 0.15
		draw_circle(Vector2(fx, fy), 0.9 + rng.randf() * 0.8,
			Color(0, 0, 0, 0.10), true, -1.0, true)
