extends Control
## Procedurally drawn polygon silhouettes used by StatGem.
var fill_color: Color = Color.WHITE
var border_color: Color = Color(0, 0, 0, 0.55)
var border_width: float = 1.5
var shape: String = "hex"   # hex / shield / drop / diamond / peak

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var pts := _build_shape()
	if pts.size() < 3:
		return

	# ── Layer 1: Drop shadow ───────────────────────────────────────────
	# Offset polygon down/right, darkened. Lifts the orb off the card
	# frame the way Hearthstone's stat gems sit "above" the card body.
	var shadow_offset := Vector2(0, 2)
	var shadow_pts := PackedVector2Array()
	for p in pts:
		shadow_pts.append(p + shadow_offset)
	draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.50))

	# ── Layer 2: Gradient fill ─────────────────────────────────────────
	# Per-vertex colors — Godot interpolates across the polygon's
	# triangulation. Top vertices get ~1.25× brightness, bottom ~0.70×.
	# Reads as a directional light source from above (canonical for
	# glossy gems in AAA card art).
	var colors := PackedColorArray()
	for p in pts:
		var t = clampf(p.y / size.y, 0.0, 1.0)
		var brightness = lerpf(1.28, 0.62, t)
		colors.append(Color(
			clampf(fill_color.r * brightness, 0.0, 1.0),
			clampf(fill_color.g * brightness, 0.0, 1.0),
			clampf(fill_color.b * brightness, 0.0, 1.0),
			fill_color.a
		))
	draw_polygon(pts, colors)

	# ── Layer 3: Top-half highlight wedge ──────────────────────────────
	# Translucent white over upper half — boosts the gradient's "light
	# from above" cue with a slight glossy band.
	var hl := PackedVector2Array()
	for p in pts:
		if p.y < size.y * 0.5:
			hl.append(p)
	if hl.size() >= 3:
		hl.append(Vector2(size.x * 0.5, size.y * 0.5))
		draw_colored_polygon(hl, Color(1, 1, 1, 0.18))

	# ── Layer 4: Specular dot ──────────────────────────────────────────
	# Small bright circle near top-left — the "glass highlight" trick
	# every AAA gem orb uses to read as polished/wet. Skipped on very
	# small badges (rarity gem) where it'd just be a fuzzy pixel.
	if minf(size.x, size.y) >= 18.0:
		var spec_pos = Vector2(size.x * 0.34, size.y * 0.24)
		var spec_radius = size.x * 0.12
		draw_circle(spec_pos, spec_radius, Color(1, 1, 1, 0.65),
			true, -1.0, true)
		# Smaller, brighter core for extra glass feel
		draw_circle(spec_pos - Vector2(spec_radius * 0.25, spec_radius * 0.25),
			spec_radius * 0.45, Color(1, 1, 1, 0.85), true, -1.0, true)

	# ── Layer 5: Bottom rim shadow ─────────────────────────────────────
	# Vertices in the lower half get a slight dark overlay — gives the
	# orb a "rim" of darker color at its base, matching how 3D-rendered
	# gems pick up bounce-shadow at their underside.
	var rim := PackedVector2Array()
	for p in pts:
		if p.y > size.y * 0.65:
			rim.append(p)
	if rim.size() >= 3:
		rim.insert(0, Vector2(size.x * 0.5, size.y * 0.65))
		draw_colored_polygon(rim, Color(0, 0, 0, 0.20))

	# ── Layer 6: Beveled outline ───────────────────────────────────────
	# Anti-aliased polyline; slightly darker than fill so the edge reads
	# as a chiseled border, not a sticker outline.
	if border_width > 0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, border_color, border_width, true)

func _build_shape() -> PackedVector2Array:
	match shape:
		"hex":     return _hex(size)
		"shield":  return _shield(size)
		"drop":    return _drop(size)
		"diamond": return _diamond(size)
		"peak":    return _peak(size)
		_:         return _hex(size)

static func _hex(sz: Vector2) -> PackedVector2Array:
	# Pointy-top hexagon (gem-like). 6 vertices.
	var pts := PackedVector2Array()
	var w := sz.x; var h := sz.y
	pts.append(Vector2(w * 0.5, 0.0))        # top
	pts.append(Vector2(w,       h * 0.30))
	pts.append(Vector2(w,       h * 0.70))
	pts.append(Vector2(w * 0.5, h))          # bottom
	pts.append(Vector2(0.0,     h * 0.70))
	pts.append(Vector2(0.0,     h * 0.30))
	return pts

static func _shield(sz: Vector2) -> PackedVector2Array:
	# Heater-shield silhouette: flat top with corners clipped, pointed
	# bottom apex. Reads as "knight's shield" at hand-card scale.
	var pts := PackedVector2Array()
	var w := sz.x; var h := sz.y
	pts.append(Vector2(w * 0.10, 0.0))
	pts.append(Vector2(w * 0.90, 0.0))
	pts.append(Vector2(w,        h * 0.22))
	pts.append(Vector2(w * 0.92, h * 0.66))
	pts.append(Vector2(w * 0.5,  h))
	pts.append(Vector2(w * 0.08, h * 0.66))
	pts.append(Vector2(0.0,      h * 0.22))
	return pts

static func _drop(sz: Vector2) -> PackedVector2Array:
	# Blood-drop silhouette: pointed top, rounded bottom (10-point smooth).
	var pts := PackedVector2Array()
	var w := sz.x; var h := sz.y
	pts.append(Vector2(w * 0.5,  0.0))         # top point
	pts.append(Vector2(w * 0.74, h * 0.18))
	pts.append(Vector2(w * 0.93, h * 0.42))
	pts.append(Vector2(w,        h * 0.62))
	pts.append(Vector2(w * 0.88, h * 0.88))
	pts.append(Vector2(w * 0.5,  h))           # rounded base
	pts.append(Vector2(w * 0.12, h * 0.88))
	pts.append(Vector2(0.0,      h * 0.62))
	pts.append(Vector2(w * 0.07, h * 0.42))
	pts.append(Vector2(w * 0.26, h * 0.18))
	return pts

static func _diamond(sz: Vector2) -> PackedVector2Array:
	# 4-point rhombus — rarity gem at art-bottom (Hearthstone position).
	var pts := PackedVector2Array()
	var w := sz.x; var h := sz.y
	pts.append(Vector2(w * 0.5, 0.0))
	pts.append(Vector2(w,       h * 0.5))
	pts.append(Vector2(w * 0.5, h))
	pts.append(Vector2(0.0,     h * 0.5))
	return pts

static func _peak(sz: Vector2) -> PackedVector2Array:
	# Pentagonal cap pointing up — used on spell cards above the banner so
	# the silhouette differs from creatures (Slay-the-Spire convention).
	var pts := PackedVector2Array()
	var w := sz.x; var h := sz.y
	pts.append(Vector2(w * 0.5, 0.0))      # apex
	pts.append(Vector2(w,       h * 0.62))
	pts.append(Vector2(w * 0.78, h))
	pts.append(Vector2(w * 0.22, h))
	pts.append(Vector2(0.0,     h * 0.62))
	return pts

static func _circle(sz: Vector2, segments: int = 32) -> PackedVector2Array:
	# 32-vertex polygon approximating a circle. Drives the GemOrb's per-
	# vertex shading the same way hex / shield / drop do, but the dense
	# vertex ring makes the silhouette read as a perfect orb at any size.
	# Hearthstone / Marvel Snap / Card Wars all use circles for stat gems
	# — geometric shapes (hex, shield, drop) clash with painted creature
	# art the way the v1 prototype's flat ColorRect circles did. The orb
	# is fantasy-canonical; the polygon-shape detour was a mistake.
	var pts := PackedVector2Array()
	var cx := sz.x * 0.5
	var cy := sz.y * 0.5
	# Slight Y inset (98 %) so the orb isn't perfectly tangent to its
	# bounding box on top and bottom — leaves a hairline of breathing room
	# that lets the drop shadow read against the card body without being
	# clipped by overlapping siblings.
	var rx := sz.x * 0.49
	var ry := sz.y * 0.49
	for i in range(segments):
		var ang = TAU * float(i) / float(segments) - PI * 0.5
		pts.append(Vector2(cx + rx * cos(ang), cy + ry * sin(ang)))
	return pts


# ─────────────────────────────────────────────────────────────────────────
