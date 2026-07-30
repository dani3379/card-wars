## TouchGlow — the "you may touch this" cue under a clickable stage prop
## (2026-07-20 minigame legibility pass). The stages mix two interaction
## models — some games are played through the left choice column, some by
## clicking props — and a clickable prop looked identical to a decoration
## until you happened to hover it. This is the missing rest-state
## affordance: a chalked gilt ground-ring on the cloth beneath the prop
## (the dead chalk marks under the pieces your hand is allowed on — same
## diegesis as CastPatch's chalk rules).
##
## INFORMATIONAL, not decorative: always visible, no idle motion, so it
## holds steady under Reduce Motion. `hot` (set by the host on hover)
## brightens it; `off` hides it while a prop is temporarily untouchable.
extends Control

var hot := false:
	set(v):
		hot = v
		queue_redraw()
var off := false:
	set(v):
		off = v
		queue_redraw()
var seed_text := "touch"

const GILT := Color(0.95, 0.80, 0.45)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if off or minf(size.x, size.y) <= 6.0:
		return
	var k := 1.7 if hot else 1.0
	var c := Vector2(size.x * 0.5, size.y * 0.80)
	var rx := size.x * 0.56
	var ry := maxf(rx * 0.26, 5.0)
	# Warm pool on the cloth.
	for layer in [[1.0, 0.05], [0.66, 0.05], [0.40, 0.045]]:
		var pts := PackedVector2Array()
		for i in range(20):
			var a := TAU * float(i) / 20.0
			pts.append(c + Vector2(cos(a) * rx * layer[0], sin(a) * ry * layer[0]))
		draw_colored_polygon(pts, Color(GILT.r, GILT.g, GILT.b, layer[1] * k))
	# The chalked gilt ring — dashed, hand-struck, like the cloth's rules.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) + hash(get_instance_id())
	var n := 22
	var prev := c + Vector2(rx * 0.86, 0)
	for i in range(1, n + 1):
		var a := TAU * float(i) / float(n)
		var p := c + Vector2(cos(a) * rx * 0.86, sin(a) * ry * 0.86) \
			+ Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.6, 0.6))
		if rng.randf() > 0.22:
			draw_line(prev, p, Color(GILT.r, GILT.g, GILT.b, 0.30 * k), 1.6, true)
		prev = p
