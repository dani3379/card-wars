extends Control
# Hex war-board presentation PROTOTYPE (render-only sandbox, 2026-07-11).
# The campaign map as a physical hex-tile board laid on the war table
# (For the King / Dorfromantik register): terrain tiles exist ONLY around
# the war road — no dead paper by construction — with real tile relief
# (extruded sides, taller hill tiles, recessed water, ember-cracked char
# under Etna) and the act's journey staged west→east in the tile palette.
# Site tokens reuse the LIVE MapTerrain medallion painters off-tree so the
# board is judged with the real token kit, not stand-ins.
# No game logic. Open scenes/map_hex_proto.tscn, or shoot the contact
# sheet via tools/_shot_hex_proto.tscn.

const SQ3 := 1.7320508
const HEX_R := 46.0
const TILE_GAP := 1.1
const ROWS := 18
# Kept in step with CampaignMapGenerator by hand — this is a sandbox proto and
# deliberately does not depend on the generator. Row 9 became a mid-act camp on
# 2026-09-19 when the mandatory fight spine went 4 rows to 3.
const FIGHT_ROWS := [0, 3, 15]
const ELITE_ROWS := [6, 12]
const REST_ROW := 16
const MID_REST_ROW := 9
const CAMP_LANE := 3

const AMBER := Color(0.93, 0.72, 0.30)
const CRIMSON := Color(0.72, 0.20, 0.14)

@export var act := 1
@export var seed_v := 11
@export var fog_variant := false   # rows beyond scout range lie face-down
@export var marched := 5           # rows already claimed by the army

var _mt: Control = null            # MapTerrain painter kit, off-tree
var _nodes := []                   # {row, col, type, wayside_id, pos, vis, avail, current}
var _edges := []                   # {a, b, vis, open}
var _tiles := {}                   # Vector2i(q,r) -> {biome:String}
var _node_at := {}                 # Vector2i(q,r) -> node index (site tiles)
var _camp_chains := []             # [{keys, chain, vis}] muster trails out of camp
var _lamp_tex: GradientTexture2D
var _vig_tex: GradientTexture2D
var _soft_tex: GradientTexture2D   # soft white disc — the glow sprite
var _glow_item: Control = null     # additive bloom layer, redrawn per frame
var _t := 0.0
var _current_idx := -1

# Multiplied over the whole scene for material tooth — flat vector fills are
# what reads as "game from 2000". mix-toward-white is the MUL-fade trick
# from the war-table map (raw SRC·DST cannot be faded by modulate).
const GRAIN_SHADER := "
shader_type canvas_item;
render_mode blend_mul;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.16;
uniform float uv_scale = 6.0;
void fragment() {
	float n = texture(noise_tex, vec2(UV.x * 1.778, UV.y) * uv_scale).r;
	vec3 g = vec3(0.86 + n * 0.28);
	COLOR = vec4(mix(vec3(1.0), g, strength), 1.0);
}"


func _ready() -> void:
	var mts := load("res://scripts/scenes/MapTerrain.gd")
	_mt = mts.new()
	_mt.set("bake_mode", "probe")
	_build_run()
	_build_tiles()
	_lamp_tex = _radial_tex([Color(1.0, 0.84, 0.52, 0.27), Color(1.0, 0.8, 0.45, 0.0)], [0.0, 1.0])
	_vig_tex = _radial_tex([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0.02, 0.01, 0.0, 0.58)], [0.0, 0.50, 1.0])
	_soft_tex = _radial_tex([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)], [0.0, 0.35, 1.0])
	_build_fx()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _glow_item != null:
		_glow_item.queue_redraw()


func _exit_tree() -> void:
	if _mt != null:
		_mt.free()
		_mt = null


const SQUASH := 0.92          # diorama tilt: the board leans away from you
const SQUASH_Y := 36.0


func get_focus_pos() -> Vector2:
	# In control space (the board is drawn y-squashed for the table tilt).
	var p := Vector2(800, 450)
	if _current_idx >= 0:
		p = (_nodes[_current_idx].pos as Vector2)
	return Vector2(p.x, p.y * SQUASH + SQUASH_Y)


func _radial_tex(cols: Array, offs: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols)
	g.offsets = PackedFloat32Array(offs)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 512
	t.height = 512
	return t


# ---------------------------------------------------------------- run graph

func _h(a: int, b: int) -> float:
	return fmod(absf(sin(float(a) * 127.1 + float(b) * 311.7 + float(seed_v) * 74.7 + float(act) * 13.3) * 43758.5453), 1.0)


func _hex_center(q: int, r: int) -> Vector2:
	var vp := HEX_R * SQ3
	var x := 100.0 + float(q + 1) * HEX_R * 1.5
	var y := 224.0 + float(r) * vp
	if posmod(q, 2) == 1:
		y += vp * 0.5
	return Vector2(x, y)


func _neighbors(q: int, r: int) -> Array:
	if posmod(q, 2) == 0:
		return [Vector2i(q + 1, r), Vector2i(q + 1, r - 1), Vector2i(q, r - 1),
			Vector2i(q - 1, r - 1), Vector2i(q - 1, r), Vector2i(q, r + 1)]
	return [Vector2i(q + 1, r + 1), Vector2i(q + 1, r), Vector2i(q, r - 1),
		Vector2i(q - 1, r), Vector2i(q - 1, r + 1), Vector2i(q, r + 1)]


func _build_run() -> void:
	_nodes.clear()
	_edges.clear()
	_node_at.clear()
	var pool := ["wayside", "event", "recruit", "wayside", "treasure", "shop", "recruit", "wayside"]
	var wpool := ["drill_yard", "supply_cache", "standard_bearer", "drill_yard", "supply_cache"]
	var cols := [2, 3, 4]
	var walker_paths := [[], [], []]
	for row in range(ROWS):
		# The whole road SNAKES together (Wildfrost trail / Hand of Fate's
		# dealt line): walkers braid ±1 around a shared serpentine target.
		var target := 3 + int(round(1.5 * sin(float(row) * 0.38 + float(seed_v % 7) * 0.8)))
		for w in range(cols.size()):
			var col: int = cols[w]
			if row == ROWS - 1:
				col = 3
			elif row > 0:
				var want := clampi(target + (w - 1), 0, 6)
				var step := clampi(want - col, -1, 1)
				if _h(row * 3 + w, 17) < 0.30:
					step = clampi(step + (1 if _h(row, w * 5) < 0.5 else -1), -1, 1)
				col = clampi(col + step, 0, 6)
			cols[w] = col
			var typ := ""
			if row == ROWS - 1:
				typ = "boss"
			elif row == REST_ROW or row == MID_REST_ROW:
				typ = "rest"
			elif row in FIGHT_ROWS:
				typ = "combat"
			elif row in ELITE_ROWS:
				# One spike, the rest of the band is road — a declinable
				# General, matching the generator since 2026-09-19.
				typ = "elite" if w == 1 else "wayside"
			else:
				typ = pool[(row * 3 + w + int(_h(row, w) * 3.0)) % pool.size()]
			var idx := _find_node(row, col)
			if idx < 0:
				var nd := {
					"row": row, "col": col, "type": typ,
					"wayside_id": wpool[(row + w) % wpool.size()],
					"pos": _hex_center(row, col),
					"vis": false, "avail": false, "current": false,
				}
				_nodes.append(nd)
				idx = _nodes.size() - 1
				_node_at[Vector2i(row, col)] = idx
			(walker_paths[w] as Array).append(idx)
	for w in range(3):
		var path: Array = walker_paths[w]
		for i in range(path.size() - 1):
			if not _has_edge(path[i], path[i + 1]):
				_edges.append({"a": path[i], "b": path[i + 1], "vis": false, "open": false})
	# March state: walker 0 has claimed the first `marched` rows.
	var road: Array = walker_paths[0]
	for i in range(mini(marched, road.size())):
		_nodes[road[i]].vis = true
	_current_idx = road[mini(marched, road.size()) - 1]
	_nodes[_current_idx].current = true
	for e in _edges:
		var a: Dictionary = _nodes[e.a]
		var b: Dictionary = _nodes[e.b]
		e.vis = a.vis and b.vis
		if e.a == _current_idx and int(b.row) == int(a.row) + 1:
			e.open = true
			b.avail = true
	_build_chains()


func _hex_walk(a: Vector2i, b: Vector2i) -> Array:
	# Greedy hex path — the causeway between two stops is hex-contiguous.
	var out := [a]
	var cur := a
	var guard := 0
	while cur != b and guard < 8:
		guard += 1
		var best := cur
		var bd := 1e18
		for n in _neighbors(cur.x, cur.y):
			# Never route the causeway THROUGH another stop's tile — a road
			# across a token's face reads as ink over the piece.
			if n != b and _node_at.has(Vector2i(n.x, n.y)):
				continue
			var d := _hex_center(n.x, n.y).distance_squared_to(_hex_center(b.x, b.y))
			if d < bd:
				bd = d
				best = n
		if best == cur:
			break
		cur = best
		out.append(cur)
	if out[out.size() - 1] != b:
		out.append(b)
	return out


func _build_chains() -> void:
	_camp_chains.clear()
	for e in _edges:
		var ka := Vector2i(int(_nodes[e.a].row), int(_nodes[e.a].col))
		var kb := Vector2i(int(_nodes[e.b].row), int(_nodes[e.b].col))
		var keys := _hex_walk(ka, kb)
		var pts := []
		for k in keys:
			pts.append(_hex_center(k.x, k.y))
		e["chain_keys"] = keys
		e["chain"] = pts
	var ck := Vector2i(-1, CAMP_LANE)
	for nd in _nodes:
		if int(nd.row) != 0:
			continue
		var keys := _hex_walk(ck, Vector2i(0, int(nd.col)))
		var pts := []
		for k in keys:
			pts.append(_hex_center(k.x, k.y))
		_camp_chains.append({"keys": keys, "chain": pts, "vis": bool(nd.vis)})


func _find_node(row: int, col: int) -> int:
	for i in range(_nodes.size()):
		if int(_nodes[i].row) == row and int(_nodes[i].col) == col:
			return i
	return -1


func _has_edge(a: int, b: int) -> bool:
	for e in _edges:
		if int(e.a) == a and int(e.b) == b:
			return true
	return false


# ---------------------------------------------------------------- tiles

func _biome_for(q: int, r: int) -> String:
	# Journey staging west→east: muster meadow → deep woods → high country →
	# ash country → char at Etna's foot. Fringe lanes read as wilder ground.
	# Later acts shift the whole gradient toward the burn — act III is the
	# march INTO the char, with green only a memory at the west edge.
	var t := clampf(float(q) / float(ROWS - 1) + 0.22 * float(act - 1), 0.0, 1.2)
	var n := _h(q * 7 + 3, r * 5 + 1)
	if q >= ROWS:
		return "char"
	if t > 0.86:
		return "char" if n > 0.45 else "ash"
	if t > 0.72:
		return "ash" if n > 0.30 else "hill"
	if (r <= 0 or r >= 6) and t > 0.25 and t < 0.75 and n > 0.35:
		return "hill"
	if t > 0.30 and t < 0.62 and n > 0.42:
		return "woods"
	if t < 0.40 and n < 0.20:
		return "field"
	return "meadow"


func _add_tile(q: int, r: int) -> void:
	if r < -1 or r > 7:
		return
	var key := Vector2i(q, r)
	if _tiles.has(key):
		return
	_tiles[key] = {"biome": _biome_for(q, r)}


func _build_tiles() -> void:
	_tiles.clear()
	# THE DEALT ROAD: terrain exists only along the war road itself — a
	# hex-contiguous causeway with scattered flanking shoulders, the dark
	# table breathing between the branches (Hand of Fate's dealt path).
	for e in _edges:
		for k in e.chain_keys:
			_add_tile(k.x, k.y)
	for ch in _camp_chains:
		for k in ch.keys:
			_add_tile(k.x, k.y)
	for nb in _neighbors(-1, CAMP_LANE):
		_add_tile(nb.x, nb.y)
	# Flanking shoulders so the road reads as country, not a floating ribbon.
	for key in _tiles.keys().duplicate():
		for nb in _neighbors(key.x, key.y):
			if not _tiles.has(Vector2i(nb.x, nb.y)) \
					and _h(nb.x * 13 + 5, nb.y * 7 + 2) < 0.24:
				_add_tile(nb.x, nb.y)
	# Etna's foot: forced char high-ground past the keep.
	for key in [Vector2i(18, 2), Vector2i(18, 3), Vector2i(19, 2), Vector2i(19, 3), Vector2i(19, 4)]:
		_tiles[key] = {"biome": "char"}
	# A ford: one plain causeway tile mid-march turns to water — the road
	# crosses on planks and the stream continues off the path both ways.
	for key in _tiles.keys():
		if key.x < 6 or key.x > 10 or _node_at.has(key):
			continue
		if _h(key.x * 3, key.y * 9) < 0.45:
			continue
		_tiles[key] = {"biome": "water"}
		for dr in [-1, 1]:
			var wk := Vector2i(key.x, key.y + dr)
			if not _node_at.has(wk):
				_tiles[wk] = {"biome": "water"}
		break


func _tile_top(biome: String) -> Color:
	match biome:
		"meadow":
			return Color(0.62, 0.57, 0.33)
		"field":
			return Color(0.70, 0.60, 0.33)
		"woods":
			return Color(0.36, 0.42, 0.24)
		"hill":
			return Color(0.54, 0.47, 0.36)
		"ash":
			return Color(0.33, 0.28, 0.24)
		"char":
			return Color(0.20, 0.16, 0.14)
		"water":
			return Color(0.25, 0.36, 0.37)
	return Color(0.6, 0.55, 0.35)


func _tile_thick(biome: String) -> float:
	match biome:
		"hill":
			return 16.0
		"char":
			return 13.0
		"water":
			return 4.0
	return 9.0


func _hex_corners(c: Vector2, rad: float, drop: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var a := TAU * float(i) / 6.0
		pts.append(c + Vector2(cos(a) * rad, sin(a) * rad + drop))
	return pts


func _fog_cut() -> int:
	# Sketch fog beyond scout range (fog variant only).
	var cur_row := 0
	if _current_idx >= 0:
		cur_row = int(_nodes[_current_idx].row)
	return cur_row + 2


func _tile_state(q: int) -> int:
	# 0 = painted and physical, 1 = watercolor wash (being inked in),
	# 2 = the quartermaster's pen sketch. The wash band between paint and
	# pen is what makes the boundary read as a GRADIENT, not a cliff.
	if not fog_variant:
		return 0
	var cut := _fog_cut()
	if q <= cut:
		return 0
	if q <= cut + 2:
		return 1
	return 2


# ---------------------------------------------------------------- draw

func _draw() -> void:
	var W := size.x
	var H := size.y
	_draw_table(W, H)
	# The board leans away from you on the table — a global y-squash sells
	# the diorama angle (For the King's tilt) without touching any geometry.
	draw_set_transform(Vector2(0.0, SQUASH_Y), 0.0, Vector2(1.0, SQUASH))
	# All tile shadows first, then tiles sorted for the extrusion painter.
	var keys := _tiles.keys()
	keys.sort_custom(func(a, b):
		var ca := _hex_center(a.x, a.y)
		var cb := _hex_center(b.x, b.y)
		return ca.y < cb.y if ca.y != cb.y else ca.x < cb.x)
	# The board sits on a PLINTH — a continuous dark base under every tile,
	# so the pieces stand on an object, not in a void (the floating-tile
	# read was the loudest gap against shipped boards).
	for key in keys:
		var c := _hex_center(key.x, key.y)
		draw_colored_polygon(_hex_corners(c + Vector2(7, 13), HEX_R + 2.5), Color(0, 0, 0, 0.32))
	for key in keys:
		var c := _hex_center(key.x, key.y)
		draw_colored_polygon(_hex_corners(c, HEX_R + 4.5, 16.0), Color(0.066, 0.047, 0.033))
	for key in keys:
		var c := _hex_center(key.x, key.y)
		draw_colored_polygon(_hex_corners(c, HEX_R + 1.5, 9.5), Color(0.108, 0.078, 0.052))
	for key in keys:
		_draw_tile(key)
	_draw_stream_banks()
	_draw_roads()
	_draw_etna()
	_draw_camp()
	_draw_keep()
	_draw_sites_hex()
	_draw_standard()
	# Lamplight pool over the marching front (board space), then back to
	# screen space for the vignette and cartouche.
	var fp := Vector2(800, 450)
	if _current_idx >= 0:
		fp = (_nodes[_current_idx].pos as Vector2)
	draw_texture_rect(_lamp_tex, Rect2(fp - Vector2(620, 560), Vector2(1240, 1120)), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_texture_rect(_vig_tex, Rect2(-W * 0.25, -H * 0.25, W * 1.5, H * 1.5), false)
	_draw_cartouche()


func _draw_table(W: float, H: float) -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.118, 0.088, 0.062))
	# Per-plank tone so the wood reads as boards, not a flat brown void.
	for i in range(9):
		var y := float(i) * 118.0
		var j := (_h(i, 421) - 0.5) * 0.030
		draw_rect(Rect2(0, y, W, 118.0), Color(0.118 + j, 0.088 + j * 0.8, 0.062 + j * 0.6))
		draw_line(Vector2(0, y), Vector2(W, y), Color(0, 0, 0, 0.36), 2.0)
		draw_line(Vector2(0, y + 2), Vector2(W, y + 2), Color(0.42, 0.28, 0.17, 0.10), 1.0)
	for i in range(260):
		var x := _h(i, 999) * W
		var y := _h(i, 555) * H
		var l := 40.0 + _h(i, 333) * 200.0
		var dk := _h(i, 111) < 0.5
		draw_line(Vector2(x, y), Vector2(x + l, y + (_h(i, 77) - 0.5) * 5.0),
			Color(0, 0, 0, 0.06) if dk else Color(0.47, 0.31, 0.18, 0.05), 1.0)
	# Knots in the boards.
	for i in range(7):
		var p := Vector2(_h(i * 3, 71) * W, _h(i * 5, 37) * H)
		draw_colored_polygon(_ellipse_pts(p, 7.0 + _h(i, 3) * 5.0, 4.0 + _h(i, 9) * 3.0),
			Color(0.070, 0.050, 0.034))
		draw_arc(p, 10.0 + _h(i, 13) * 5.0, 0, TAU, 18, Color(0.06, 0.04, 0.03, 0.35), 1.2, true)
	_draw_table_props(W, H)


func _draw_table_props(W: float, H: float) -> void:
	# The war room lives at the table's edges — quiet props in the shadow
	# register, never competing with the board.
	# Coiled rope, NE of the board.
	var rp := Vector2(W * 0.72, 128.0)
	for k in range(3):
		var rr := 26.0 - float(k) * 6.5
		draw_arc(rp, rr, 0, TAU, 26, Color(0.32, 0.24, 0.14, 0.9), 5.0, true)
		draw_arc(rp, rr, PI * 1.1, PI * 1.7, 12, Color(0.45, 0.34, 0.20, 0.75), 2.2, true)
	draw_line(rp + Vector2(20, 14), rp + Vector2(44, 26), Color(0.32, 0.24, 0.14, 0.9), 4.6, true)
	# Two thrown dice beside it.
	for di in [[52.0, -8.0, 0.28], [78.0, 6.0, -0.2]]:
		var dc := rp + Vector2(float(di[0]), float(di[1]))
		var a: float = float(di[2])
		var dx := Vector2(cos(a), sin(a)) * 9.0
		var dy := Vector2(-sin(a), cos(a)) * 9.0
		draw_colored_polygon(PackedVector2Array([dc - dx - dy + Vector2(2, 3), dc + dx - dy + Vector2(2, 3),
			dc + dx + dy + Vector2(2, 3), dc - dx + dy + Vector2(2, 3)]), Color(0, 0, 0, 0.35))
		draw_colored_polygon(PackedVector2Array([dc - dx - dy, dc + dx - dy, dc + dx + dy, dc - dx + dy]),
			Color(0.58, 0.54, 0.45))
		draw_colored_polygon(PackedVector2Array([dc - dx - dy, dc + dx - dy,
			dc + dx - dy * 0.4, dc - dx - dy * 0.4]), Color(0.46, 0.42, 0.34))
		draw_circle(dc + dy * 0.25, 2.0, Color(0.18, 0.13, 0.08))
		draw_circle(dc - dx * 0.45 + dy * 0.55, 1.7, Color(0.18, 0.13, 0.08))
		draw_circle(dc + dx * 0.45 - dy * 0.15, 1.7, Color(0.18, 0.13, 0.08))
	# Candle dish, quill and inkwell, SW corner — the light's excuse.
	var cd := Vector2(150.0, H - 92.0)
	draw_colored_polygon(_ellipse_pts(cd + Vector2(4, 8), 40.0, 11.0), Color(0, 0, 0, 0.4))
	draw_colored_polygon(_ellipse_pts(cd + Vector2(0, 5), 34.0, 10.0), Color(0.36, 0.28, 0.14))
	draw_colored_polygon(_ellipse_pts(cd + Vector2(0, 3), 28.0, 8.0), Color(0.52, 0.41, 0.20))
	# A squat wax stub, not a white pillar — shaded, melted, dripping.
	draw_rect(Rect2(cd.x - 7, cd.y - 24, 14, 26), Color(0.66, 0.58, 0.42))
	draw_rect(Rect2(cd.x - 7, cd.y - 24, 5, 26), Color(0.76, 0.68, 0.52))
	draw_rect(Rect2(cd.x + 3, cd.y - 24, 4, 26), Color(0.52, 0.45, 0.32))
	draw_colored_polygon(_ellipse_pts(cd + Vector2(0, -24), 7.0, 3.0), Color(0.80, 0.72, 0.55))
	draw_line(cd + Vector2(-6, -18), cd + Vector2(-7.5, -4), Color(0.82, 0.75, 0.58), 2.6, true)
	draw_texture_rect(_soft_tex, Rect2(cd + Vector2(-27, -66), Vector2(54, 54)), false,
		Color(1.0, 0.80, 0.42, 0.40))
	draw_colored_polygon(_ellipse_pts(cd + Vector2(0, -33), 3.6, 7.5), Color(1.0, 0.84, 0.45))
	draw_colored_polygon(_ellipse_pts(cd + Vector2(0, -31), 1.9, 4.2), Color(1.0, 0.96, 0.80))
	var iw := cd + Vector2(74.0, -6.0)
	draw_colored_polygon(_ellipse_pts(iw + Vector2(3, 8), 15.0, 5.0), Color(0, 0, 0, 0.38))
	draw_rect(Rect2(iw.x - 11, iw.y - 14, 22, 20), Color(0.16, 0.14, 0.18))
	draw_colored_polygon(_ellipse_pts(iw + Vector2(0, -14), 11.0, 4.0), Color(0.09, 0.08, 0.11))
	draw_line(iw + Vector2(6, -12), iw + Vector2(42, -34), Color(0.80, 0.74, 0.62, 0.9), 2.6, true)
	draw_line(iw + Vector2(30, -27), iw + Vector2(46, -30), Color(0.80, 0.74, 0.62, 0.6), 1.4, true)
	# A compass rose inlaid in the wood, lower centre — barely there.
	var cp := Vector2(W * 0.545, H - 74.0)
	draw_arc(cp, 40.0, 0, TAU, 40, Color(0.55, 0.42, 0.22, 0.22), 1.4, true)
	draw_arc(cp, 30.0, 0, TAU, 36, Color(0.55, 0.42, 0.22, 0.14), 1.0, true)
	for k in range(8):
		var a := float(k) * TAU / 8.0
		var lr := 38.0 if k % 2 == 0 else 20.0
		draw_line(cp, cp + Vector2(cos(a), sin(a)) * lr, Color(0.55, 0.42, 0.22, 0.20 if k % 2 == 0 else 0.12), 1.4, true)
	draw_circle(cp, 3.0, Color(0.55, 0.42, 0.22, 0.28))


func _site_drop(nd: Dictionary) -> float:
	# Reachable stops (and the army's own tile) stand PROUD of the board —
	# "you can step here" is physical, not a painted ring. The keep's tile
	# is the highest ground on the board.
	if String(nd.type) == "boss":
		return -8.0
	if bool(nd.avail) or bool(nd.current):
		return -5.0
	return 0.0


func _draw_tile(key: Vector2i) -> void:
	var biome: String = _tiles[key].biome
	var c := _hex_center(key.x, key.y)
	var rad := HEX_R - TILE_GAP
	var state := _tile_state(key.x)
	var nidx: int = _node_at.get(key, -1)
	if state == 2:
		# The road ahead is only the quartermaster's SKETCH: a flat paper
		# tile with ink hatching — full route intel, none of the world's
		# body. The land turns painted and physical as the army marches in
		# (Trials of Fire's page-to-diorama edge, Civ's pen-and-ink fog).
		_draw_tile_sketch(key, c, rad, biome, nidx)
		return
	var top := _tile_top(biome)
	var thick := _tile_thick(biome)
	# Relief: hills stand PROUD of the board, water sits recessed.
	var drop := 0.0
	if nidx >= 0:
		drop = _site_drop(_nodes[nidx])
	elif biome == "water":
		drop = 3.0
	elif biome == "hill":
		drop = -6.0
	elif biome == "char":
		drop = -3.0
	thick += absf(minf(drop, 0.0))
	if nidx >= 0:
		# A site tile IS the token — but the metal is ONE pewter family for
		# every type (the reference boards hold a narrow palette; eight
		# bezel metals at tile scale read as candy, not mood).
		var nd: Dictionary = _nodes[nidx]
		var mats: Dictionary = _mt.SITE_MAT
		var mat: Dictionary = mats.get(String(nd.type), mats["wayside"])
		top = (mat.bezel as Color).lerp(Color(0.45, 0.41, 0.36), 0.55)
		if bool(nd.vis) and not bool(nd.current):
			top = top.darkened(0.34)
		elif not (bool(nd.avail) or bool(nd.current)):
			# Locked pieces sit QUIET — reachable pop is what makes routing read.
			top = top.darkened(0.34)
	else:
		# Per-tile value jitter so the field never reads as flat fill.
		var j := (_h(key.x * 31, key.y * 17) - 0.5) * 0.07
		top = Color(top.r + j, top.g + j, top.b + j)
	# Value hierarchy (the reference-board lesson): the world falls away
	# from the marching front — the army's ground is the brightest thing
	# on the table, the road ahead darkens into the unknown.
	var cur_q := 0
	if _current_idx >= 0:
		cur_q = int(_nodes[_current_idx].row)
	var ahead := key.x - cur_q
	if ahead > 2:
		top = top.darkened(minf(0.16, float(ahead - 2) * 0.022))
	elif ahead < -1:
		top = top.darkened(minf(0.10, float(-ahead - 1) * 0.02))
	var corners := _hex_corners(c, rad, drop)
	# Extruded side skirt: bottom chain (corners 0..3) pulled down by thick.
	var skirt := PackedVector2Array([corners[0], corners[1], corners[2], corners[3],
		corners[3] + Vector2(0, thick), corners[2] + Vector2(0, thick),
		corners[1] + Vector2(0, thick), corners[0] + Vector2(0, thick)])
	_poly_shaded(skirt, top.darkened(0.52), 0.12)
	_poly_shaded(corners, top, 0.09)
	# Bevel: NW edges lit, SE edges shaded — sells "physical tile" at a glance.
	for i in [3, 4, 5]:
		draw_line(corners[i], corners[(i + 1) % 6], top.lightened(0.16), 2.0, true)
	for i in [0, 1, 2]:
		draw_line(corners[i], corners[(i + 1) % 6], top.darkened(0.28), 2.0, true)
	if nidx >= 0:
		_draw_site_face(nidx, c, rad, drop)
	else:
		_draw_tile_decor(key, c, rad, biome, top)
	if state == 1:
		# Watercolor wash: the tile is painted but not yet lived — a paper
		# veil and a whisper of the pen still on it.
		draw_colored_polygon(corners, Color(0.775, 0.70, 0.54, 0.32))
		for k in range(3):
			var yy := -14.0 + float(k) * 13.0
			var hw := rad - absf(yy) / SQ3 - 4.0
			if hw > 5.0:
				draw_line(Vector2(c.x - hw, c.y + drop + yy + 1.5),
					Vector2(c.x + hw, c.y + drop + yy - 1.5),
					Color(0.40, 0.30, 0.19, 0.10), 1.1, true)


func _draw_fight_device(c: Vector2, s: float, tone: float) -> void:
	# The hero device: crossed war-swords forged properly — split-shaded
	# blades with fullers and edge glints, gilt quillons, wrapped grips —
	# replacing the two-capsules-and-a-tick mark. One symbol, done right.
	var steel_l := Color(0.97, 0.955, 0.90).darkened((1.0 - tone) * 0.5)
	var steel_d := Color(0.70, 0.71, 0.71).darkened((1.0 - tone) * 0.5)
	var gold := Color(0.87, 0.67, 0.27).darkened((1.0 - tone) * 0.5)
	var gold_d := Color(0.56, 0.40, 0.15).darkened((1.0 - tone) * 0.5)
	var leather := Color(0.31, 0.20, 0.12).darkened((1.0 - tone) * 0.4)
	var shade := Color(0.05, 0.04, 0.03, 0.80 * tone)
	# Silhouette shadow first, then the lower sword, a crossing shadow, the
	# upper sword — the overlap is what makes it read as two real objects.
	_draw_sword(c + Vector2(1.7, 2.1), s, -1.0, shade, shade, shade, shade, shade, true)
	_draw_sword(c + Vector2(1.7, 2.1), s, 1.0, shade, shade, shade, shade, shade, true)
	_draw_sword(c, s, -1.0, steel_l, steel_d, gold, gold_d, leather, false)
	var ud := Vector2(0.7071, -0.7071)
	var un := ud.orthogonal()
	draw_colored_polygon(PackedVector2Array([
		c + ud * (-s * 0.20) - un * s * 0.16, c + ud * (-s * 0.20) + un * s * 0.16,
		c + ud * (s * 0.20) + un * s * 0.16, c + ud * (s * 0.20) - un * s * 0.16]),
		Color(0.05, 0.04, 0.03, 0.28 * tone))
	_draw_sword(c, s, 1.0, steel_l, steel_d, gold, gold_d, leather, false)


func _draw_sword(c: Vector2, s: float, side: float, steel_l: Color, steel_d: Color,
		gold: Color, gold_d: Color, leather: Color, flat: bool) -> void:
	var d := Vector2(0.7071 * side, -0.7071)   # along the blade, tip up
	var n := d.orthogonal()
	var ug := -s * 0.16                        # guard face along the blade
	var tip := s * 0.98
	var lb := tip - s * 0.17                   # where the taper turns to the point
	var w0 := s * 0.115
	var w1 := s * 0.075
	# Blade in two mirror halves — the split shading is what says "steel".
	draw_colored_polygon(PackedVector2Array([
		c + d * ug, c + d * ug - n * w0, c + d * lb - n * w1, c + d * tip]),
		steel_l if not flat else steel_l)
	draw_colored_polygon(PackedVector2Array([
		c + d * ug, c + d * ug + n * w0, c + d * lb + n * w1, c + d * tip]),
		steel_d if not flat else steel_d)
	if not flat:
		# Fuller down the middle, edge glint up the light side.
		draw_line(c + d * (ug + s * 0.06), c + d * (lb - s * 0.02),
			steel_d.darkened(0.30), 1.4, true)
		draw_line(c + d * (ug + s * 0.04) - n * w0 * 0.72,
			c + d * lb - n * w1 * 0.80, Color(1, 1, 1, 0.75), 1.1, true)
	# Quillons: a gilt bar with dropped tips.
	var qw := s * 0.335
	var qt := s * 0.115
	draw_colored_polygon(PackedVector2Array([
		c + d * ug - n * qw, c + d * (ug - qt) - n * (qw * 1.05),
		c + d * (ug - qt) + n * (qw * 1.05), c + d * ug + n * qw]),
		gold if not flat else gold)
	if not flat:
		draw_line(c + d * (ug - qt) - n * qw, c + d * (ug - qt) + n * qw,
			gold_d, 1.3, true)
		draw_circle(c + d * (ug - qt * 0.4) - n * qw, s * 0.052, gold_d)
		draw_circle(c + d * (ug - qt * 0.4) + n * qw, s * 0.052, gold_d)
	# Wrapped grip and pommel.
	var g0 := ug - qt
	var gl := s * 0.30
	var gw := s * 0.070
	draw_colored_polygon(PackedVector2Array([
		c + d * g0 - n * gw, c + d * (g0 - gl) - n * gw * 0.9,
		c + d * (g0 - gl) + n * gw * 0.9, c + d * g0 + n * gw]),
		leather if not flat else leather)
	if not flat:
		for k in range(3):
			var u := g0 - gl * (0.25 + float(k) * 0.25)
			draw_line(c + d * u - n * gw * 0.85, c + d * u + n * gw * 0.85,
				leather.darkened(0.35), 1.1, true)
	var pp := c + d * (g0 - gl - s * 0.055)
	draw_circle(pp, s * 0.085, gold if not flat else gold)
	if not flat:
		draw_circle(pp + Vector2(-s * 0.02, -s * 0.025), s * 0.030, Color(1, 0.95, 0.8, 0.8))


# -------- forged device kit: shared bones --------

func _tn(col: Color, tone: float) -> Color:
	return col.darkened((1.0 - tone) * 0.5)


func _pt(c: Vector2, s: float, x: float, y: float) -> Vector2:
	return c + Vector2(x * s, y * s)


func _dev_poly(c: Vector2, s: float, pts: Array, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_pt(c, s, p[0], p[1]))
	draw_colored_polygon(out, col)


func _dev_shadow_color(tone: float) -> Color:
	return Color(0.05, 0.04, 0.03, 0.80 * tone)


# -------- GENERAL: crested great-helm --------

func _draw_helm_device(c: Vector2, s: float, tone: float) -> void:
	_helm_shapes(c + Vector2(1.7, 2.1), s, tone, true)
	_helm_shapes(c, s, tone, false)


func _helm_shapes(c: Vector2, s: float, tone: float, flat: bool) -> void:
	var F := _dev_shadow_color(tone)
	var steel_l := F if flat else _tn(Color(0.88, 0.87, 0.84), tone)
	var steel_d := F if flat else _tn(Color(0.60, 0.61, 0.62), tone)
	var gold := F if flat else _tn(Color(0.86, 0.66, 0.27), tone)
	var crest := F if flat else _tn(Color(0.72, 0.20, 0.15), tone)
	var crest_l := F if flat else _tn(Color(0.88, 0.34, 0.24), tone)
	# Horsehair crest first — it arcs behind the bowl.
	_dev_poly(c, s, [[-0.02, -0.70], [0.05, -1.02], [0.26, -1.14], [0.46, -1.06],
		[0.40, -0.88], [0.46, -0.70], [0.26, -0.62], [0.06, -0.62]], crest)
	if not flat:
		_dev_poly(c, s, [[0.02, -0.72], [0.08, -0.98], [0.24, -1.08], [0.30, -1.02],
			[0.24, -0.86], [0.26, -0.70], [0.10, -0.66]], crest_l)
	# Bowl: full dome in shade steel, then the lit west half.
	var bowl := [[-0.56, 0.52], [-0.60, 0.06], [-0.48, -0.40], [-0.24, -0.66],
		[0.0, -0.72], [0.24, -0.66], [0.48, -0.40], [0.60, 0.06], [0.56, 0.52]]
	_dev_poly(c, s, bowl, steel_d)
	if not flat:
		_dev_poly(c, s, [[0.0, -0.72], [-0.24, -0.66], [-0.48, -0.40], [-0.60, 0.06],
			[-0.56, 0.52], [0.0, 0.52]], steel_l)
		# Eye slit, breath holes, centre ridge, gilt brow band with rivets.
		_dev_poly(c, s, [[-0.44, -0.16], [0.44, -0.16], [0.40, -0.05], [-0.40, -0.05]],
			Color(0.07, 0.06, 0.05, 0.95))
		draw_line(_pt(c, s, 0.0, -0.72), _pt(c, s, 0.0, -0.16),
			steel_l.lightened(0.18), 1.6, true)
		_dev_poly(c, s, [[-0.58, 0.06], [0.58, 0.06], [0.55, 0.17], [-0.55, 0.17]], gold)
		for gx in [-0.42, 0.0, 0.42]:
			draw_circle(_pt(c, s, gx, 0.115), s * 0.035, _tn(Color(0.55, 0.40, 0.16), tone))
		for hx in [-0.14, 0.0, 0.14]:
			draw_circle(_pt(c, s, hx, 0.32), s * 0.028, Color(0.07, 0.06, 0.05, 0.9))


# -------- REST: campfire --------

func _draw_fire_device(c: Vector2, s: float, tone: float) -> void:
	_fire_shapes(c + Vector2(1.7, 2.1), s, tone, true)
	_fire_shapes(c, s, tone, false)


func _fire_shapes(c: Vector2, s: float, tone: float, flat: bool) -> void:
	var F := _dev_shadow_color(tone)
	var wood := F if flat else _tn(Color(0.36, 0.23, 0.13), tone)
	var wood_end := F if flat else _tn(Color(0.62, 0.46, 0.28), tone)
	var ember := F if flat else _tn(Color(0.80, 0.28, 0.08), tone)
	var orange := F if flat else _tn(Color(1.0, 0.55, 0.13), tone)
	var core := F if flat else _tn(Color(1.0, 0.86, 0.46), tone)
	# Crossed logs with pale cut ends.
	for side in [-1.0, 1.0]:
		var d := Vector2(0.92 * side, -0.26).normalized()
		var n := d.orthogonal()
		var a := c - d * s * 0.62 + Vector2(0, s * 0.52)
		var b := c + d * s * 0.62 + Vector2(0, s * 0.52)
		var w := s * 0.085
		draw_colored_polygon(PackedVector2Array([a - n * w, b - n * w, b + n * w, a + n * w]), wood)
		if not flat:
			draw_circle(b, w * 0.95, wood_end)
			draw_line(a + n * w * 0.4, b + n * w * 0.4, wood.darkened(0.30), 1.1, true)
	# Three nested flame tongues.
	var fl := [[0.0, -0.98], [0.24, -0.55], [0.14, -0.34], [0.42, 0.02],
		[0.28, 0.36], [0.0, 0.48], [-0.28, 0.36], [-0.38, 0.0], [-0.14, -0.32], [-0.22, -0.56]]
	_dev_poly(c, s, fl, ember)
	if not flat:
		var mid := []
		for p in fl:
			mid.append([p[0] * 0.66, p[1] * 0.62 + 0.14])
		_dev_poly(c, s, mid, orange)
		var inner := []
		for p in fl:
			inner.append([p[0] * 0.36, p[1] * 0.34 + 0.26])
		_dev_poly(c, s, inner, core)
		for gx in [-0.16, 0.04, 0.20]:
			draw_circle(_pt(c, s, gx, 0.50), s * 0.045, orange.lightened(0.20))
		draw_circle(_pt(c, s, 0.26, -0.70), s * 0.030, core)
		draw_circle(_pt(c, s, -0.20, -0.80), s * 0.024, orange)


# -------- SHOP: market stall --------

func _draw_stall_device(c: Vector2, s: float, tone: float) -> void:
	_stall_shapes(c + Vector2(1.7, 2.1), s, tone, true)
	_stall_shapes(c, s, tone, false)


func _stall_shapes(c: Vector2, s: float, tone: float, flat: bool) -> void:
	var F := _dev_shadow_color(tone)
	var cream := F if flat else _tn(Color(0.93, 0.88, 0.74), tone)
	var stripe := F if flat else _tn(Color(0.66, 0.24, 0.18), tone)
	var wood := F if flat else _tn(Color(0.40, 0.27, 0.15), tone)
	var gold := F if flat else _tn(Color(0.87, 0.67, 0.27), tone)
	# Posts, then counter with a lit top edge.
	for px in [-0.50, 0.50]:
		_dev_poly(c, s, [[px - 0.035, -0.30], [px + 0.035, -0.30], [px + 0.035, 0.38], [px - 0.035, 0.38]], wood)
	_dev_poly(c, s, [[-0.60, 0.38], [0.60, 0.38], [0.60, 0.62], [-0.60, 0.62]], wood)
	if not flat:
		draw_line(_pt(c, s, -0.60, 0.40), _pt(c, s, 0.60, 0.40), wood.lightened(0.35), 1.4, true)
		draw_line(_pt(c, s, -0.55, 0.52), _pt(c, s, 0.55, 0.52), wood.darkened(0.30), 1.1, true)
	# Scalloped awning: five hanging stripes.
	for i in range(5):
		var x0 := -0.62 + float(i) * 0.248
		var col := stripe if i % 2 == 0 else cream
		_dev_poly(c, s, [[x0, -0.66], [x0 + 0.248, -0.66], [x0 + 0.21, -0.22], [x0 + 0.038, -0.22]], col)
		draw_circle(_pt(c, s, x0 + 0.124, -0.22), s * 0.098, col)
	if not flat:
		# Awning shade + ridge pole.
		_dev_poly(c, s, [[-0.62, -0.40], [0.62, -0.40], [0.58, -0.22], [-0.58, -0.22]],
			Color(0.08, 0.05, 0.03, 0.18))
		draw_line(_pt(c, s, -0.66, -0.66), _pt(c, s, 0.66, -0.66), wood, 2.6, true)
		# Goods on the counter: coin stack and a stoppered jar.
		for k in range(3):
			draw_colored_polygon(_ellipse_pts(_pt(c, s, -0.22, 0.335 - float(k) * 0.055), s * 0.10, s * 0.038), gold)
		draw_colored_polygon(_ellipse_pts(_pt(c, s, -0.22, 0.335 - 0.11), s * 0.10, s * 0.038),
			gold.lightened(0.25))
		_dev_poly(c, s, [[0.14, 0.16], [0.30, 0.16], [0.32, 0.38], [0.12, 0.38]],
			_tn(Color(0.24, 0.36, 0.28), tone))
		draw_line(_pt(c, s, 0.17, 0.16), _pt(c, s, 0.27, 0.16),
			_tn(Color(0.62, 0.46, 0.28), tone), 2.4, true)


# -------- TREASURE: chest ajar --------

func _draw_chest_device(c: Vector2, s: float, tone: float) -> void:
	_chest_shapes(c + Vector2(1.7, 2.1), s, tone, true)
	_chest_shapes(c, s, tone, false)


func _chest_shapes(c: Vector2, s: float, tone: float, flat: bool) -> void:
	var F := _dev_shadow_color(tone)
	var wood := F if flat else _tn(Color(0.44, 0.29, 0.16), tone)
	var wood_l := F if flat else _tn(Color(0.55, 0.38, 0.21), tone)
	var gold := F if flat else _tn(Color(0.88, 0.68, 0.28), tone)
	var gold_d := F if flat else _tn(Color(0.58, 0.42, 0.16), tone)
	var glowc := F if flat else Color(1.0, 0.84, 0.45, 0.95 * tone)
	# Lid, tilted open a crack.
	_dev_poly(c, s, [[-0.58, -0.10], [-0.34, -0.44], [0.30, -0.50], [0.58, -0.20], [0.55, -0.08], [-0.55, 0.0]], wood)
	if not flat:
		_dev_poly(c, s, [[-0.58, -0.10], [-0.34, -0.44], [-0.06, -0.47], [-0.10, -0.04]], wood_l)
		# The light escaping the crack — what makes it TREASURE.
		draw_line(_pt(c, s, -0.52, 0.02), _pt(c, s, 0.52, -0.06), glowc, 2.8, true)
	# Body with plank seams, gilt straps and banding, hasp and keyhole.
	_dev_poly(c, s, [[-0.55, 0.02], [0.55, -0.06], [0.55, 0.52], [-0.55, 0.56]], wood)
	if not flat:
		_dev_poly(c, s, [[-0.55, 0.02], [-0.28, 0.0], [-0.28, 0.55], [-0.55, 0.56]], wood_l)
		draw_line(_pt(c, s, -0.55, 0.22), _pt(c, s, 0.55, 0.16), wood.darkened(0.28), 1.2, true)
		draw_line(_pt(c, s, -0.55, 0.40), _pt(c, s, 0.55, 0.34), wood.darkened(0.28), 1.2, true)
		for sx in [-0.34, 0.34]:
			_dev_poly(c, s, [[sx - 0.045, 0.0], [sx + 0.045, 0.0], [sx + 0.045, 0.545], [sx - 0.045, 0.545]], gold_d)
		_dev_poly(c, s, [[-0.07, -0.02], [0.07, -0.02], [0.07, 0.24], [-0.07, 0.24]], gold)
		draw_circle(_pt(c, s, 0.0, 0.10), s * 0.030, Color(0.10, 0.07, 0.04))
		# Spilled coins with glints.
		for co in [[-0.40, 0.62], [-0.16, 0.66], [0.24, 0.62]]:
			draw_colored_polygon(_ellipse_pts(_pt(c, s, co[0], co[1]), s * 0.085, s * 0.055), gold)
			draw_circle(_pt(c, s, co[0] - 0.025, co[1] - 0.015), s * 0.022, Color(1.0, 0.95, 0.75, 0.9))


# -------- EVENT: the gilded question --------

func _draw_query_device(c: Vector2, s: float, tone: float) -> void:
	if GameTheme.font_display == null:
		return
	var fsz := int(round(s * 2.2))
	var qs := GameTheme.font_display.get_string_size("?", HORIZONTAL_ALIGNMENT_CENTER, -1, fsz)
	var qp := c + Vector2(-qs.x * 0.5, qs.y * 0.36)
	# Faint arcane ring with compass ticks behind the mark.
	var ring := Color(0.92, 0.86, 1.0, 0.28 * tone)
	draw_arc(c, s * 0.72, 0, TAU, 40, ring, 1.4, true)
	for k in range(4):
		var a := float(k) * TAU / 4.0 + TAU / 8.0
		var rp := c + Vector2(cos(a), sin(a)) * s * 0.72
		_dev_poly(rp, s, [[0.0, -0.05], [0.035, 0.0], [0.0, 0.05], [-0.035, 0.0]], ring)
	# Bevelled gilt glyph: shadow → dark bronze → gold → top light.
	draw_string(GameTheme.font_display, qp + Vector2(2.0, 2.6), "?",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, _dev_shadow_color(tone))
	draw_string(GameTheme.font_display, qp + Vector2(1.0, 1.2), "?",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, _tn(Color(0.52, 0.36, 0.14), tone))
	draw_string(GameTheme.font_display, qp, "?",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, _tn(Color(0.90, 0.72, 0.34), tone))
	draw_string(GameTheme.font_display, qp + Vector2(-0.8, -1.0), "?",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(1.0, 0.94, 0.72, 0.55 * tone))
	# Two hanging star-sparks.
	for sp in [[0.46, -0.42, 0.05], [-0.50, 0.30, 0.038]]:
		var p := _pt(c, s, sp[0], sp[1])
		var r: float = s * float(sp[2])
		draw_line(p + Vector2(-r * 2.0, 0), p + Vector2(r * 2.0, 0), Color(1, 0.96, 0.8, 0.75 * tone), 1.2, true)
		draw_line(p + Vector2(0, -r * 2.0), p + Vector2(0, r * 2.0), Color(1, 0.96, 0.8, 0.75 * tone), 1.2, true)


# -------- RECRUIT: the dealt hand --------

func _draw_cards_device(c: Vector2, s: float, tone: float) -> void:
	_cards_shapes(c + Vector2(1.7, 2.1), s, tone, true)
	_cards_shapes(c, s, tone, false)


func _cards_shapes(c: Vector2, s: float, tone: float, flat: bool) -> void:
	var F := _dev_shadow_color(tone)
	var pivot := _pt(c, s, 0.0, 0.72)
	for i in range(3):
		var ang := (float(i) - 1.0) * 0.30
		var up := Vector2(sin(ang), -cos(ang))
		var right := Vector2(cos(ang), sin(ang))
		var cc := pivot + up * s * 0.62
		var hw := s * 0.255
		var hh := s * 0.375
		var face := F
		if not flat:
			face = _tn(Color(0.90, 0.85, 0.70) if i == 2 else Color(0.78, 0.72, 0.58), tone)
		var corners := PackedVector2Array([
			cc - right * hw - up * hh, cc + right * hw - up * hh,
			cc + right * hw + up * hh, cc - right * hw + up * hh])
		draw_colored_polygon(corners, face)
		if flat:
			continue
		# Ink border; shadow crease along the edge overlapped by the next card.
		var pts := corners.duplicate()
		pts.append(pts[0])
		draw_polyline(pts, _tn(Color(0.32, 0.24, 0.14), tone), 1.3, true)
		if i < 2:
			draw_line(cc + right * hw * 0.94 - up * hh, cc + right * hw * 0.94 + up * hh,
				Color(0.08, 0.06, 0.04, 0.30), 2.0, true)
		if i == 2:
			# The front card: rules lines and a crimson wax seal with a "+".
			for k in range(2):
				var ly := -hh * 0.30 + float(k) * hh * 0.30
				draw_line(cc + up * (-ly) - right * hw * 0.55, cc + up * (-ly) + right * hw * 0.55,
					_tn(Color(0.45, 0.38, 0.26, 0.8), tone), 1.1, true)
			var wp := cc + up * (-hh * 0.42)
			draw_circle(wp, s * 0.115, _tn(Color(0.62, 0.16, 0.12), tone))
			draw_circle(wp, s * 0.085, _tn(Color(0.74, 0.24, 0.17), tone))
			var pl := s * 0.058
			draw_line(wp + Vector2(-pl, 0), wp + Vector2(pl, 0), Color(0.97, 0.92, 0.80), 2.0, true)
			draw_line(wp + Vector2(0, -pl), wp + Vector2(0, pl), Color(0.97, 0.92, 0.80), 2.0, true)


# -------- DRILL YARD: the anvil --------

func _draw_anvil_device(c: Vector2, s: float, tone: float) -> void:
	_anvil_shapes(c + Vector2(1.7, 2.1), s, tone, true)
	_anvil_shapes(c, s, tone, false)


func _anvil_shapes(c: Vector2, s: float, tone: float, flat: bool) -> void:
	var F := _dev_shadow_color(tone)
	var steel_l := F if flat else _tn(Color(0.80, 0.80, 0.78), tone)
	var steel := F if flat else _tn(Color(0.55, 0.56, 0.57), tone)
	var steel_d := F if flat else _tn(Color(0.38, 0.39, 0.40), tone)
	var wood := F if flat else _tn(Color(0.36, 0.24, 0.13), tone)
	var gold := F if flat else _tn(Color(1.0, 0.80, 0.30), tone)
	# Face and horn, waist, base, stump.
	_dev_poly(c, s, [[-0.62, -0.30], [0.34, -0.30], [0.30, -0.12], [-0.56, -0.12]], steel_l)
	_dev_poly(c, s, [[0.34, -0.30], [0.74, -0.20], [0.30, -0.12]], steel)
	_dev_poly(c, s, [[-0.30, -0.12], [0.14, -0.12], [0.08, 0.18], [-0.22, 0.18]], steel_d)
	_dev_poly(c, s, [[-0.38, 0.18], [0.24, 0.18], [0.32, 0.40], [-0.46, 0.40]], steel)
	_dev_poly(c, s, [[-0.52, 0.40], [0.38, 0.40], [0.38, 0.56], [-0.52, 0.56]], wood)
	if flat:
		return
	draw_line(_pt(c, s, -0.62, -0.30), _pt(c, s, 0.34, -0.30), Color(1, 1, 1, 0.55), 1.3, true)
	draw_line(_pt(c, s, -0.52, 0.56), _pt(c, s, 0.38, 0.56), wood.darkened(0.35), 1.2, true)
	# The strike: a star of sparks off the face.
	var sp := _pt(c, s, -0.06, -0.44)
	for k in range(5):
		var a := -PI * 0.5 + (float(k) - 2.0) * 0.55
		draw_line(sp, sp + Vector2(cos(a), sin(a)) * s * (0.16 + 0.05 * float(k % 2)), gold, 1.6, true)
	draw_circle(sp, s * 0.045, Color(1.0, 0.92, 0.60, 0.95 * tone))


# -------- BANNER: the standard --------

func _draw_banner_device(c: Vector2, s: float, tone: float) -> void:
	_banner_shapes(c + Vector2(1.7, 2.1), s, tone, true)
	_banner_shapes(c, s, tone, false)


func _banner_shapes(c: Vector2, s: float, tone: float, flat: bool) -> void:
	var F := _dev_shadow_color(tone)
	var wood := F if flat else _tn(Color(0.33, 0.22, 0.12), tone)
	var cloth := F if flat else _tn(Color(0.90, 0.66, 0.24), tone)
	var cloth_d := F if flat else _tn(Color(0.72, 0.50, 0.16), tone)
	var gold := F if flat else _tn(Color(0.88, 0.70, 0.30), tone)
	# Pole with a spear finial.
	_dev_poly(c, s, [[-0.44, -0.86], [-0.36, -0.86], [-0.36, 0.62], [-0.44, 0.62]], wood)
	_dev_poly(c, s, [[-0.40, -1.02], [-0.32, -0.86], [-0.48, -0.86]], gold)
	# The cloth in two waving panels, swallowtail cut.
	_dev_poly(c, s, [[-0.36, -0.82], [0.14, -0.72], [0.10, -0.36], [-0.36, -0.28]], cloth)
	_dev_poly(c, s, [[0.14, -0.72], [0.58, -0.62], [0.34, -0.50], [0.56, -0.40], [0.10, -0.36]], cloth_d)
	if flat:
		return
	draw_line(_pt(c, s, -0.36, -0.82), _pt(c, s, 0.14, -0.72), cloth.lightened(0.25), 1.4, true)
	draw_line(_pt(c, s, 0.14, -0.72), _pt(c, s, 0.10, -0.36), Color(0.08, 0.06, 0.04, 0.30), 1.8, true)
	# The company's mark stitched on the fly.
	var mp := _pt(c, s, -0.13, -0.55)
	draw_circle(mp, s * 0.075, _tn(Color(0.30, 0.18, 0.10), tone))
	draw_circle(mp, s * 0.045, cloth.lightened(0.3))
	# Cord and tassel.
	draw_line(_pt(c, s, -0.40, -0.84), _pt(c, s, -0.50, -0.62), gold, 1.3, true)
	draw_circle(_pt(c, s, -0.50, -0.60), s * 0.038, gold)


# -------- CACHE: crate and sack --------

func _draw_cache_device(c: Vector2, s: float, tone: float) -> void:
	_cache_shapes(c + Vector2(1.7, 2.1), s, tone, true)
	_cache_shapes(c, s, tone, false)


func _cache_shapes(c: Vector2, s: float, tone: float, flat: bool) -> void:
	var F := _dev_shadow_color(tone)
	var wood := F if flat else _tn(Color(0.46, 0.32, 0.18), tone)
	var wood_l := F if flat else _tn(Color(0.58, 0.42, 0.24), tone)
	var rope := F if flat else _tn(Color(0.78, 0.68, 0.48), tone)
	var burlap := F if flat else _tn(Color(0.62, 0.52, 0.35), tone)
	var burlap_d := F if flat else _tn(Color(0.48, 0.40, 0.26), tone)
	# Crate: lit top face, front face with plank seams, rope lashing.
	_dev_poly(c, s, [[-0.60, -0.16], [-0.24, -0.34], [0.18, -0.20], [-0.18, -0.02]], wood_l)
	_dev_poly(c, s, [[-0.60, -0.16], [-0.18, -0.02], [-0.18, 0.52], [-0.60, 0.38]], wood)
	if not flat:
		draw_line(_pt(c, s, -0.60, 0.02), _pt(c, s, -0.18, 0.16), wood.darkened(0.28), 1.2, true)
		draw_line(_pt(c, s, -0.60, 0.20), _pt(c, s, -0.18, 0.34), wood.darkened(0.28), 1.2, true)
		draw_line(_pt(c, s, -0.56, -0.10), _pt(c, s, -0.22, 0.44), rope, 2.0, true)
		draw_line(_pt(c, s, -0.22, -0.06), _pt(c, s, -0.56, 0.34), rope, 2.0, true)
		draw_circle(_pt(c, s, -0.39, 0.17), s * 0.045, rope.darkened(0.25))
	# Grain sack leaning on the crate, neck tied and flopped.
	draw_colored_polygon(_ellipse_pts(_pt(c, s, 0.28, 0.26), s * 0.30, s * 0.34), burlap)
	if flat:
		return
	draw_colored_polygon(_ellipse_pts(_pt(c, s, 0.20, 0.30), s * 0.16, s * 0.24), burlap_d)
	_dev_poly(c, s, [[0.20, -0.14], [0.36, -0.14], [0.40, -0.02], [0.16, -0.02]], burlap)
	draw_line(_pt(c, s, 0.17, -0.03), _pt(c, s, 0.39, -0.03), _tn(Color(0.30, 0.20, 0.10), tone), 2.2, true)
	_dev_poly(c, s, [[0.22, -0.26], [0.38, -0.20], [0.30, -0.12]], burlap_d)
	draw_arc(_pt(c, s, 0.28, 0.30), s * 0.22, 0.6, 2.2, 10, burlap_d.darkened(0.2), 1.2, true)


func _draw_tile_sketch(key: Vector2i, c: Vector2, rad: float, biome: String, nidx: int) -> void:
	var ink := Color(0.40, 0.30, 0.19)
	var paper := Color(0.775, 0.700, 0.540)
	var j := (_h(key.x * 31, key.y * 17) - 0.5) * 0.045
	paper = Color(paper.r + j, paper.g + j, paper.b + j)
	var corners := _hex_corners(c, rad)
	# Paper-thin: the sketched road has no body yet.
	var skirt := PackedVector2Array([corners[0], corners[1], corners[2], corners[3],
		corners[3] + Vector2(0, 3.5), corners[2] + Vector2(0, 3.5),
		corners[1] + Vector2(0, 3.5), corners[0] + Vector2(0, 3.5)])
	draw_colored_polygon(skirt, paper.darkened(0.42))
	_poly_shaded(corners, paper, 0.05)
	_hex_outline(c, rad - 1.6, 0.0, Color(ink.r, ink.g, ink.b, 0.42), 1.2)
	# Pen hatching, denser where the land is darker.
	var den := 0.12
	match biome:
		"woods":
			den = 0.20
		"hill":
			den = 0.16
		"ash":
			den = 0.24
		"char":
			den = 0.32
		"water":
			den = 0.15
	var vp := rad * SQ3 * 0.5
	var yy := -vp + 6.0
	var row := 0
	while yy < vp - 5.0:
		var hw := rad - absf(yy) / SQ3 - 3.5
		if hw > 5.0:
			var x0 := c.x - hw + _h(key.x * 7 + row, key.y * 3) * 3.0
			draw_line(Vector2(x0, c.y + yy + 2.0), Vector2(c.x + hw, c.y + yy - 2.0),
				Color(ink.r, ink.g, ink.b, den), 1.1, true)
		yy += 6.5
		row += 1
	# Outline-only biome marks — drawn things, not painted things.
	var s0 := key.x * 101 + key.y * 61
	var mink := Color(ink.r, ink.g, ink.b, 0.50)
	match biome:
		"woods":
			for i in range(2):
				var p := c + Vector2((_h(s0, i * 7) - 0.5) * rad * 0.8, (_h(s0, i * 7 + 1) - 0.5) * rad * 0.6)
				var s := 8.0 + _h(s0, i * 7 + 2) * 4.0
				draw_polyline(PackedVector2Array([p + Vector2(-s * 0.5, s * 0.35),
					p + Vector2(0, -s), p + Vector2(s * 0.5, s * 0.35),
					p + Vector2(-s * 0.5, s * 0.35)]), mink, 1.2, true)
		"hill":
			var p := c + Vector2((_h(s0, 1) - 0.5) * 8.0, 3.0)
			var s := rad * 0.42
			draw_polyline(PackedVector2Array([p + Vector2(-s * 0.85, s * 0.4),
				p + Vector2(0, -s), p + Vector2(s * 0.95, s * 0.4)]), mink, 1.3, true)
		"water":
			for i in range(2):
				draw_arc(c + Vector2((_h(s0, i * 4) - 0.5) * rad * 0.5, float(i) * 9.0 - 4.0),
					7.0, PI * 1.15, PI * 1.85, 8, mink, 1.2, true)
		"char", "ash":
			for i in range(3):
				var p := c + Vector2((_h(s0, i * 5) - 0.5) * rad * 0.8, (_h(s0, i * 5 + 1) - 0.5) * rad * 0.6)
				draw_line(p, p + Vector2(3.0, -1.5), mink, 1.1, true)
	if nidx >= 0:
		_draw_site_sketch(nidx, c, rad, ink)


func _draw_site_sketch(nidx: int, c: Vector2, rad: float, ink: Color) -> void:
	# The site as the quartermaster drew it: an ink ring and the glyph in
	# line-work — you can PLAN on it, you just can't feel it yet.
	var nd: Dictionary = _nodes[nidx]
	var typ := String(nd.type)
	if typ == "boss":
		return
	var sink := Color(ink.r, ink.g, ink.b, 0.66)
	_hex_outline(c, rad - 4.5, 0.0, Color(ink.r, ink.g, ink.b, 0.55), 1.5)
	var s := rad * 0.56
	if typ in ["combat", "elite", "rest", "shop", "treasure"]:
		_mt._draw_core_site_glyph_shape(self, c, s, sink, typ)
	elif typ == "event":
		if GameTheme.font_display != null:
			var qs := GameTheme.font_display.get_string_size("?", HORIZONTAL_ALIGNMENT_CENTER, -1, 30)
			draw_string(GameTheme.font_display, c + Vector2(-qs.x * 0.5, qs.y * 0.34), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 30, sink)
	elif typ == "recruit":
		draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.5), Vector2(s * 0.9, s * 1.1)), sink, false, 1.4)
		draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.65), Vector2(s * 0.9, s * 1.1)), sink, false, 1.4)
	elif typ == "wayside":
		_mt._draw_wayside_glyph(self, c, s * 0.9, sink, String(nd.wayside_id))
	if typ == "elite":
		_mt._draw_star(self, c + Vector2(rad * 0.5, -rad * 0.54), 5.5,
			Color(ink.r, ink.g, ink.b, 0.6))
	# Names in the same pen for the stops worth planning around.
	var ltxt := _label_text(typ, nd)
	if ltxt != "" and (typ in ["elite", "rest", "shop", "treasure"] \
			or (typ == "wayside" and String(nd.wayside_id) in ["supply_cache", "drill_yard"])):
		if GameTheme.font_display != null:
			var lw := GameTheme.font_display.get_string_size(ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(GameTheme.font_display, Vector2(c.x - lw * 0.5, c.y + rad * 0.72 + 9.0),
				ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ink.r, ink.g, ink.b, 0.80))


func _draw_site_face(nidx: int, c: Vector2, rad: float, drop: float) -> void:
	# The enamel face fills the hex inside the metal bevel, and the glyph
	# is printed BIG across it — the tile is the medallion now.
	var nd: Dictionary = _nodes[nidx]
	var typ := String(nd.type)
	var mats: Dictionary = _mt.SITE_MAT
	var mat: Dictionary = mats.get(typ, mats["wayside"])
	var open_now: bool = bool(nd.avail) or bool(nd.current)
	var visited: bool = bool(nd.vis) and not bool(nd.current)
	var face: Color = mat.face
	# Palette discipline (the reference-board lesson): the enamel WHISPERS
	# its hue over a shared leather ground — the forged glyph and a small
	# gem at the crown carry the type; colour stays reserved for STATE.
	# Common stops sit quietest; decision stops keep a little more chroma.
	var mute := 0.55 if typ in ["combat", "wayside"] else 0.46
	face = face.lerp(Color(0.33, 0.28, 0.22), mute)
	if visited:
		face = face.darkened(0.32)
	elif not open_now:
		face = face.darkened(0.30)
	var fr := rad - 4.5
	var fc := _hex_corners(c, fr, drop)
	_poly_shaded(fc, face, 0.13)
	# Ambient occlusion just inside the bevel, and a lit whisper top-left.
	var ao := _hex_corners(c, fr - 1.0, drop)
	ao.append(ao[0])
	draw_polyline(ao, face.darkened(0.50), 1.8, true)
	for i in [3, 4]:
		draw_line(fc[i], fc[(i + 1) % 6], face.lightened(0.22), 1.6, true)
	if typ == "boss":
		return   # the keep art stands on its own tile
	# The forged device set: every site symbol is a small OBJECT — silhouette
	# underdraw, split shading, one material accent — never a line-mark.
	var gc := c + Vector2(0, drop)
	var s := rad * 0.60
	var tone := 1.0
	if visited:
		tone = 0.55
	elif not open_now:
		tone = 0.86
	match typ:
		"combat":
			_draw_fight_device(gc, s * 1.04, tone)
		"elite":
			_draw_helm_device(gc, s * 1.02, tone)
		"rest":
			_draw_fire_device(gc, s * 1.02, tone)
		"shop":
			_draw_stall_device(gc, s * 1.04, tone)
		"treasure":
			_draw_chest_device(gc, s * 1.04, tone)
		"event":
			_draw_query_device(gc, s, tone)
		"recruit":
			_draw_cards_device(gc, s * 1.02, tone)
		"wayside":
			match String(nd.wayside_id):
				"drill_yard":
					_draw_anvil_device(gc, s * 1.04, tone)
				"standard_bearer":
					_draw_banner_device(gc, s * 1.04, tone)
				_:
					_draw_cache_device(gc, s * 1.04, tone)
	# The type's colour survives as JEWELRY: a small enamel gem set at the
	# tile's crown — glanceable coding without flooding the piece.
	var gem := c + Vector2(0, drop - rad * 0.74)
	var gcol := (mat.face as Color)
	if visited or not open_now:
		gcol = gcol.darkened(0.25)
	draw_circle(gem + Vector2(0.8, 1.2), 5.2, Color(0.05, 0.04, 0.03, 0.7))
	draw_circle(gem, 4.8, Color(0.16, 0.13, 0.10))
	draw_circle(gem, 3.5, gcol.lightened(0.10))
	draw_circle(gem + Vector2(-1.0, -1.1), 1.3, gcol.lightened(0.55))


func _hex_outline(c: Vector2, rad: float, drop: float, col: Color, w: float) -> void:
	var pts := _hex_corners(c, rad, drop)
	pts.append(pts[0])
	draw_polyline(pts, col, w, true)


func _poly_shaded(pts: PackedVector2Array, base: Color, amt: float = 0.09) -> void:
	# Per-vertex NW-lit gradient — the single cheapest thing separating
	# "flat 2000 vectors" from a lit surface.
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var span := (hi - lo).max(Vector2(0.001, 0.001))
	var cols := PackedColorArray()
	for p in pts:
		var t := ((p.x - lo.x) / span.x + (p.y - lo.y) / span.y) * 0.5
		var f := amt - t * amt * 2.0
		cols.append(base.lightened(f) if f >= 0.0 else base.darkened(-f))
	draw_polygon(pts, cols)


func _draw_tile_decor(key: Vector2i, c: Vector2, rad: float, biome: String, top: Color) -> void:
	var s0 := key.x * 101 + key.y * 61
	match biome:
		"meadow":
			# Grass as small tufts (paired blades), not lone scratches.
			for i in range(3):
				var p := c + Vector2((_h(s0, i * 3) - 0.5) * rad * 1.0, (_h(s0, i * 3 + 1) - 0.5) * rad * 0.85)
				var g := top.darkened(0.28)
				draw_line(p, p + Vector2(-2.4, -4.6), g, 1.4, true)
				draw_line(p, p + Vector2(2.2, -5.2), g, 1.4, true)
				draw_line(p + Vector2(0.4, 0), p + Vector2(0.2, -6.0), g, 1.4, true)
			if _h(s0, 55) > 0.70:
				# The odd shrub keeps big meadow spans alive.
				var sp := c + Vector2((_h(s0, 56) - 0.5) * rad * 0.7, (_h(s0, 57) - 0.5) * rad * 0.6)
				draw_colored_polygon(_ellipse_pts(sp + Vector2(1.5, 2.0), 5.5, 2.0), Color(0, 0, 0, 0.18))
				draw_circle(sp, 4.6, Color(0.31, 0.35, 0.19))
				draw_circle(sp + Vector2(-1.3, -1.4), 2.4, Color(0.43, 0.47, 0.27))
		"field":
			# Furrows follow a per-tile heading so fields read ploughed, not ruled.
			var ang := PI / 3.0 * floorf(_h(s0, 41) * 3.0)
			var dir := Vector2(cos(ang), sin(ang))
			var n := dir.orthogonal()
			for i in range(4):
				var off := n * (-rad * 0.45 + float(i) * rad * 0.30)
				draw_line(c + off - dir * rad * 0.52, c + off + dir * rad * 0.52,
					top.darkened(0.22), 1.6, true)
			if _h(s0, 66) > 0.62:
				# A haystack — worked land, not just lines.
				var hp := c + Vector2((_h(s0, 67) - 0.5) * rad * 0.6, (_h(s0, 68) - 0.5) * rad * 0.45)
				draw_colored_polygon(_ellipse_pts(hp + Vector2(1.5, 3.5), 7.0, 2.4), Color(0, 0, 0, 0.20))
				draw_circle(hp, 6.0, Color(0.64, 0.53, 0.28))
				draw_circle(hp + Vector2(-1.6, -1.8), 3.4, Color(0.76, 0.65, 0.38))
				draw_line(hp + Vector2(0, -6.0), hp + Vector2(0, -9.0), Color(0.40, 0.30, 0.15), 1.6, true)
		"woods":
			# A wood is a CROWD of trees (Dorfromantik density), y-sorted so
			# the near ones overlap the far ones.
			var trees := []
			for i in range(5 + int(_h(s0, 90) * 2.0)):
				trees.append(Vector3(
					(_h(s0, i * 7) - 0.5) * rad * 1.05,
					(_h(s0, i * 7 + 1) - 0.5) * rad * 0.80,
					6.0 + _h(s0, i * 7 + 2) * 7.0))
			trees.sort_custom(func(a, b): return a.y < b.y)
			for t in trees:
				_draw_pine(c + Vector2(t.x, t.y), t.z, top)
		"hill":
			_draw_peak(c + Vector2(rad * 0.34, rad * 0.24), rad * 0.34, top)
			_draw_peak(c + Vector2((_h(s0, 1) - 0.5) * 10.0 - 4.0, 2.0), rad * 0.54, top)
		"ash":
			for i in range(4):
				var p := c + Vector2((_h(s0, i * 5) - 0.5) * rad * 1.1, (_h(s0, i * 5 + 1) - 0.5) * rad * 0.9)
				draw_rect(Rect2(p, Vector2(1.6, 1.6)), Color(0.80, 0.77, 0.73, 0.14 + _h(s0, i) * 0.12))
			if _h(s0, 31) > 0.55:
				_draw_dead_tree(c + Vector2((_h(s0, 33) - 0.5) * rad * 0.7, 2.0), 10.0)
		"char":
			for i in range(2):
				var a := c + Vector2((_h(s0, i * 9) - 0.5) * rad * 0.9, (_h(s0, i * 9 + 1) - 0.5) * rad * 0.7)
				var b := a + Vector2((_h(s0, i * 9 + 2) - 0.5) * rad * 0.8, (_h(s0, i * 9 + 3) - 0.5) * rad * 0.5)
				draw_line(a, b, Color(0.88, 0.36 + _h(s0, i) * 0.14, 0.10, 0.48), 1.5, true)
				draw_circle(a, 4.0, Color(0.95, 0.42, 0.10, 0.08))
			if _h(s0, 77) > 0.55:
				# A smoldering pit, crusted dark with an ember eye.
				var pp := c + Vector2((_h(s0, 78) - 0.5) * rad * 0.6, (_h(s0, 79) - 0.5) * rad * 0.5)
				draw_colored_polygon(_ellipse_pts(pp, 5.5, 3.2), Color(0.08, 0.055, 0.045))
				draw_arc(pp, 3.0, 0.4, 2.6, 8, Color(1.0, 0.46, 0.12, 0.55), 1.4, true)
				draw_circle(pp + Vector2(0.8, 0.4), 1.2, Color(1.0, 0.62, 0.20, 0.75))
		"water":
			# Sand banks along every shore edge, then ripples and a glint.
			var wc := _hex_corners(c, rad - 1.0, 3.0)
			for nb in _neighbors(key.x, key.y):
				if not _tiles.has(nb) or String(_tiles[nb].biome) == "water":
					continue
				var nc := _hex_center(nb.x, nb.y)
				var em := (c + nc) * 0.5
				var bi := 0
				var bd := 1e9
				for i in range(6):
					var m := (wc[i] + wc[(i + 1) % 6]) * 0.5
					var d := m.distance_squared_to(em)
					if d < bd:
						bd = d
						bi = i
				draw_line(wc[bi].lerp(c, 0.05), wc[(bi + 1) % 6].lerp(c, 0.05),
					Color(0.71, 0.64, 0.46, 0.60), 2.4, true)
			for i in range(2):
				var p := c + Vector2((_h(s0, i * 4) - 0.5) * rad * 0.6, 2.0 + float(i) * 8.0 - 4.0)
				draw_arc(p, 7.0, PI * 1.15, PI * 1.85, 8, Color(0.85, 0.92, 0.90, 0.35), 1.4, true)
			draw_line(c + Vector2(-rad * 0.5, -rad * 0.38), c + Vector2(rad * 0.25, -rad * 0.52),
				Color(0.9, 0.96, 0.94, 0.30), 1.4, true)


func _draw_pine(p: Vector2, s: float, ground: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(2.0, s * 0.5),
		p + Vector2(s * 0.7, s * 0.62), p + Vector2(-s * 0.2, s * 0.62)]),
		Color(0, 0, 0, 0.18))
	draw_rect(Rect2(p + Vector2(-1.0, s * 0.28), Vector2(2.0, s * 0.26)), Color(0.24, 0.16, 0.09))
	var dark := Color(0.16, 0.24, 0.12)
	var lit := Color(0.30, 0.40, 0.20)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s),
		p + Vector2(s * 0.52, s * 0.35), p + Vector2(-s * 0.52, s * 0.35)]), dark)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s),
		p + Vector2(-s * 0.52, s * 0.35), p + Vector2(-s * 0.05, s * 0.35)]), lit)


func _draw_peak(p: Vector2, s: float, ground: Color) -> void:
	# Rock reads as ROCK — mostly fixed stone grays, only tinted a whisper
	# by the ground (pure ground-derived tans read as tents from afar).
	var rock := ground.lerp(Color(0.46, 0.41, 0.35), 0.75)
	var shadow := rock.darkened(0.38)
	var lit := rock.lightened(0.26)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s),
		p + Vector2(s * 0.95, s * 0.42), p + Vector2(0, s * 0.42)]), shadow)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s),
		p + Vector2(-s * 0.85, s * 0.42), p + Vector2(0, s * 0.42)]), lit)
	draw_polyline(PackedVector2Array([p + Vector2(-s * 0.85, s * 0.42),
		p + Vector2(0, -s), p + Vector2(s * 0.95, s * 0.42)]),
		Color(0.20, 0.15, 0.09, 0.65), 1.3, true)
	# Hatching on the shadow face — engraved rock, not a flat triangle.
	for k in range(2):
		var t := 0.42 + float(k) * 0.26
		draw_line(p + Vector2(s * 0.95 * t, -s + s * 1.42 * t),
			p + Vector2(0, -s + s * 1.42 * t * 0.92), shadow.darkened(0.30), 1.0, true)


func _draw_dead_tree(p: Vector2, s: float) -> void:
	var ink := Color(0.16, 0.12, 0.09, 0.9)
	draw_line(p + Vector2(0, s * 0.5), p + Vector2(0, -s * 0.6), ink, 1.8, true)
	draw_line(p + Vector2(0, -s * 0.2), p + Vector2(s * 0.4, -s * 0.55), ink, 1.3, true)
	draw_line(p + Vector2(0, -s * 0.05), p + Vector2(-s * 0.35, -s * 0.4), ink, 1.3, true)


func _draw_stream_banks() -> void:
	# Plank bridge wherever the causeway chain passes over a water tile.
	for e in _edges:
		var chain: Array = e.chain
		for i in range(chain.size()):
			var p0: Vector2 = chain[i]
			var key := _nearest_tile(p0)
			if key == Vector2i(99, 99) or String(_tiles[key].biome) != "water":
				continue
			var dir := Vector2(1, 0)
			if i > 0:
				dir = (chain[i] - chain[i - 1]).normalized()
			elif chain.size() > 1:
				dir = (chain[1] - chain[0]).normalized()
			var n := dir.orthogonal()
			# Planks, rope rails, and posts — a built crossing, not marks.
			for k in range(6):
				var p := p0 + dir * (float(k) - 2.5) * 5.6
				draw_line(p - n * 10.0 + Vector2(1, 2), p + n * 10.0 + Vector2(1, 2),
					Color(0, 0, 0, 0.25), 4.0, true)
				draw_line(p - n * 10.0, p + n * 10.0,
					Color(0.44, 0.30, 0.16) if k % 2 == 0 else Color(0.38, 0.26, 0.14), 4.0, true)
			for rside: float in [-1.0, 1.0]:
				var r0: Vector2 = p0 - dir * 16.0 + n * 11.0 * rside
				var r1: Vector2 = p0 + dir * 16.0 + n * 11.0 * rside
				draw_line(r0, r1, Color(0.72, 0.62, 0.42, 0.85), 1.8, true)
				for rp2 in [r0, r1]:
					draw_line(rp2, rp2 + Vector2(0, -6.0), Color(0.30, 0.21, 0.12), 2.2, true)
			break


func _nearest_tile(p: Vector2) -> Vector2i:
	var best := Vector2i(99, 99)
	var bd := 1e9
	for key in _tiles.keys():
		var d := _hex_center(key.x, key.y).distance_squared_to(p)
		if d < bd:
			bd = d
			best = key
	return best


func catmull(pts: PackedVector2Array, res: int) -> PackedVector2Array:
	# Catmull-Rom through the chain centers — the road flows, never elbows.
	var out := PackedVector2Array()
	var n := pts.size()
	if n < 2:
		return pts
	for i in range(n - 1):
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[mini(i + 1, n - 1)]
		var p3 := pts[mini(i + 2, n - 1)]
		for j in range(res):
			var t := float(j) / float(res)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out


func _edge_pts(e: Dictionary) -> PackedVector2Array:
	# The road threads the causeway tile-center to tile-center, smoothed,
	# then trimmed off both site tiles so it never stabs a token's face.
	var raw := PackedVector2Array()
	for p in e.chain:
		raw.append(p)
	return _trim_pts(catmull(raw, 10), HEX_R - 4.0)


func _trim_pts(pts: PackedVector2Array, cut: float) -> PackedVector2Array:
	var a0 := pts[0]
	var b0 := pts[pts.size() - 1]
	var out := PackedVector2Array()
	for p in pts:
		if p.distance_to(a0) >= cut and p.distance_to(b0) >= cut:
			out.append(p)
	return out if out.size() >= 2 else pts


func _road_leg(pts: PackedVector2Array, vis: bool, open: bool, fogged: bool, salt: int) -> void:
	if fogged:
		# The planned road, in the same pen as the sketch tiles.
		_dash(pts, Color(0.42, 0.32, 0.20, 0.55), 2.6, 7.0, 7.0)
		return
	# A war-road is BUILT: engraved bed, paved floor, worn center, and
	# paving ticks — not a string laid over the tiles.
	draw_polyline(pts, Color(0.12, 0.075, 0.045, 0.60), 9.0, true)
	if vis:
		# The marched road is burnt behind the army.
		draw_polyline(pts, Color(0.23, 0.125, 0.085, 0.95), 5.4, true)
		for i in range(1, pts.size(), 4):
			var hp := pts[i] + Vector2((_h(salt, i) - 0.5) * 5.0, (_h(salt * 3, i) - 0.5) * 5.0)
			draw_circle(hp, 1.4, Color(1.0, 0.5 + _h(salt * 5, i) * 0.25, 0.15, 0.5))
	else:
		draw_polyline(pts, Color(0.575, 0.465, 0.305, 0.92), 5.4, true)
		draw_polyline(pts, Color(0.70, 0.59, 0.40, 0.45), 1.7, true)
		for i in range(2, pts.size() - 2, 3):
			var d := (pts[i + 1] - pts[i - 1]).normalized().orthogonal()
			draw_line(pts[i] - d * 2.5, pts[i] + d * 2.5, Color(0.30, 0.22, 0.13, 0.35), 1.2, true)
	if open:
		_dash(pts, AMBER, 4.6, 10.0, 7.0)


func _draw_roads() -> void:
	# Muster trails out of camp to every row-0 hold; the army's own first
	# leg is already burnt behind it.
	var ci := 0
	for ch in _camp_chains:
		var raw := PackedVector2Array()
		for p in ch.chain:
			raw.append(p)
		var pts := _trim_pts(catmull(raw, 7), HEX_R * 0.55)
		_road_leg(pts, bool(ch.vis), false, false, 40 + ci)
		ci += 1
	for e in _edges:
		var pts := _edge_pts(e)
		var fogged := _tile_state(int(_nodes[e.b].row)) == 2
		_road_leg(pts, bool(e.vis), bool(e.open), fogged, int(e.a) * 31 + int(e.b))


func _dash(pts: PackedVector2Array, col: Color, w: float, dash: float, gap: float) -> void:
	_dash_on(self, pts, col, w, dash, gap, 0.0)


func _draw_etna() -> void:
	# The volcano is built FROM the medium: a ziggurat of stacked char
	# tiles, ember seams glowing between the tiers, the crater tile on top.
	var bc := _hex_center(19, 3) + Vector2(2.0, -8.0)
	var heat := 0.5 + float(act) * 0.17
	for i in range(3):
		draw_circle(bc + Vector2(0, -34.0), 200.0 - float(i) * 58.0,
			Color(1.0, 0.38, 0.12, 0.030 + float(i) * 0.016))
	var tiers := [
		{"r": HEX_R * 1.85, "lift": -2.0, "th": 22.0, "col": Color(0.175, 0.145, 0.125)},
		{"r": HEX_R * 1.30, "lift": -26.0, "th": 22.0, "col": Color(0.15, 0.12, 0.108)},
		{"r": HEX_R * 0.80, "lift": -48.0, "th": 20.0, "col": Color(0.125, 0.10, 0.092)},
	]
	for t in tiers:
		var cc := bc + Vector2(0.0, float(t.lift))
		var col: Color = t.col
		var th: float = t.th
		var corners := _hex_corners(cc, float(t.r))
		var skirt := PackedVector2Array([corners[0], corners[1], corners[2], corners[3],
			corners[3] + Vector2(0, th), corners[2] + Vector2(0, th),
			corners[1] + Vector2(0, th), corners[0] + Vector2(0, th)])
		_poly_shaded(skirt, col.darkened(0.48), 0.14)
		_poly_shaded(corners, col, 0.12)
		for i in [3, 4, 5]:
			draw_line(corners[i], corners[(i + 1) % 6], col.lightened(0.22), 2.2, true)
		for i in [0, 1, 2]:
			draw_line(corners[i], corners[(i + 1) % 6], col.darkened(0.35), 2.0, true)
		# Ember seam glowing along the tier's base.
		draw_polyline(PackedVector2Array([corners[0] + Vector2(0, th),
			corners[1] + Vector2(0, th), corners[2] + Vector2(0, th),
			corners[3] + Vector2(0, th)]),
			Color(1.0, 0.44, 0.13, 0.30 + heat * 0.22), 2.2, true)
		# Ash mottle on the tier face.
		for i in range(8):
			var mp := cc + Vector2((_h(int(t.r) * 7, i) - 0.5) * float(t.r) * 1.3,
				(_h(int(t.r) * 3, i) - 0.5) * float(t.r) * 0.7)
			draw_rect(Rect2(mp, Vector2(1.8, 1.8)), Color(0.62, 0.58, 0.54, 0.14))
	# Crater: a dark mouth with stacked glow.
	var cp := bc + Vector2(0, -56.0)
	draw_colored_polygon(_ellipse_pts(cp, 15.0, 8.0), Color(0.05, 0.03, 0.03))
	for i in range(3):
		draw_circle(cp, 34.0 - float(i) * 10.0,
			Color(1.0, 0.56 - float(i) * 0.10, 0.15, 0.10 + float(i) * 0.13))
	# Lava threads stepping down the tier faces, pooling at each seam.
	for i in range(4):
		var lp := PackedVector2Array([cp + Vector2((_h(i, 5) - 0.5) * 22.0, 6.0)])
		for k in range(5):
			lp.append(lp[k] + Vector2((_h(i * 3, k) - 0.5) * 22.0, 15.0 + _h(i, k) * 6.0))
		draw_polyline(lp, Color(0.88, 0.38, 0.11, 0.78), 2.4, true)
		draw_circle(lp[lp.size() - 1], 2.6, Color(1.0, 0.5, 0.14, 0.65))
	# Smoke drifting west, kept inside frame.
	for i in range(6):
		var t := float(i) / 6.0
		draw_circle(cp + Vector2(-26.0 - t * 150.0, -24.0 - t * 66.0),
			14.0 + t * 24.0, Color(0.40, 0.36, 0.34, 0.36 - t * 0.29))


func _draw_camp() -> void:
	# The muster camp is a DIORAMA: command tent under its pennant, two
	# soldier tents, palisade stakes, a supply barrel, and a cookfire —
	# the run's opening image, not a lone triangle.
	var p := _hex_center(-1, CAMP_LANE) + Vector2(-4.0, -2.0)
	var s := 22.0
	draw_colored_polygon(_ellipse_pts(p + Vector2(4, s * 0.62), s * 2.15, s * 0.55), Color(0, 0, 0, 0.26))
	for i in range(5):
		var sp := p + Vector2(-s * 1.7 + float(i) * s * 0.42, -s * 0.74 + sin(float(i) * 1.3) * 3.0)
		draw_line(sp + Vector2(0, s * 0.5), sp, Color(0.30, 0.21, 0.12), 3.4, true)
		draw_colored_polygon(PackedVector2Array([sp + Vector2(-1.7, 0), sp + Vector2(1.7, 0),
			sp + Vector2(0, -s * 0.22)]), Color(0.38, 0.27, 0.16))
	for tp in [[-s * 1.05, -s * 0.06, 0.60], [s * 1.02, -s * 0.14, 0.54]]:
		var tc := p + Vector2(float(tp[0]), float(tp[1]))
		var ts: float = s * float(tp[2])
		draw_colored_polygon(PackedVector2Array([tc + Vector2(0, -ts),
			tc + Vector2(ts * 1.05, ts * 0.5), tc + Vector2(-ts * 1.05, ts * 0.5)]), Color(0.30, 0.25, 0.18))
		draw_colored_polygon(PackedVector2Array([tc + Vector2(0, -ts),
			tc + Vector2(-ts * 1.05, ts * 0.5), tc + Vector2(-ts * 0.15, ts * 0.5)]), Color(0.42, 0.34, 0.23))
	var ct := p + Vector2(0, -s * 0.15)
	draw_colored_polygon(PackedVector2Array([ct + Vector2(0, -s),
		ct + Vector2(s * 1.15, s * 0.5), ct + Vector2(-s * 1.15, s * 0.5)]), Color(0.33, 0.27, 0.19))
	draw_colored_polygon(PackedVector2Array([ct + Vector2(0, -s),
		ct + Vector2(-s * 1.15, s * 0.5), ct + Vector2(-s * 0.2, s * 0.5)]), Color(0.47, 0.38, 0.26))
	draw_colored_polygon(PackedVector2Array([ct + Vector2(0, -s * 0.16),
		ct + Vector2(s * 0.30, s * 0.5), ct + Vector2(-s * 0.30, s * 0.5)]), Color(0.12, 0.08, 0.05))
	draw_line(ct + Vector2(0, -s), ct + Vector2(0, -s * 1.55), Color(0.30, 0.21, 0.12), 2.0, true)
	draw_colored_polygon(PackedVector2Array([ct + Vector2(0, -s * 1.55),
		ct + Vector2(s * 0.5, -s * 1.40), ct + Vector2(0, -s * 1.26)]), AMBER)
	_draw_fire_device(p + Vector2(s * 1.75, s * 0.16), s * 0.5, 1.0)
	var bp := p + Vector2(-s * 1.85, s * 0.24)
	draw_rect(Rect2(bp + Vector2(-s * 0.20, -s * 0.30), Vector2(s * 0.40, s * 0.56)), Color(0.42, 0.30, 0.17))
	draw_colored_polygon(_ellipse_pts(bp + Vector2(0, -s * 0.30), s * 0.20, s * 0.07), Color(0.52, 0.39, 0.23))
	for by in [-s * 0.12, s * 0.14]:
		draw_line(bp + Vector2(-s * 0.20, by), bp + Vector2(s * 0.20, by), Color(0.20, 0.15, 0.09), 1.6, true)
	_label(p + Vector2(0, s * 1.35), "YOUR CAMP", true)


func _ellipse_pts(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(18):
		var a := TAU * float(i) / 18.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_keep() -> void:
	# The destination deserves the best prop on the board: a raised tile,
	# a two-tower silhouette, lamplit windows, and a long evening shadow.
	var kp := _hex_center(ROWS - 1, 3) + Vector2(0, -16.0)
	var s := 36.0
	draw_colored_polygon(PackedVector2Array([kp + Vector2(-s * 0.8, s * 0.55),
		kp + Vector2(s * 0.9, s * 0.55), kp + Vector2(s * 2.6, s * 1.15),
		kp + Vector2(s * 0.4, s * 1.15)]), Color(0, 0, 0, 0.26))
	draw_colored_polygon(_ellipse_pts(kp + Vector2(3, s * 0.60), s * 1.35, s * 0.28), Color(0, 0, 0, 0.35))
	# Curtain wall.
	draw_rect(Rect2(kp + Vector2(-s * 0.95, -s * 0.30), Vector2(s * 1.9, s * 0.9)), Color(0.175, 0.155, 0.135))
	draw_rect(Rect2(kp + Vector2(-s * 0.95, -s * 0.30), Vector2(s * 0.85, s * 0.9)), Color(0.27, 0.235, 0.205))
	# Main tower (west, lit face) + second tower (east).
	draw_rect(Rect2(kp + Vector2(-s * 0.72, -s * 1.05), Vector2(s * 0.62, s * 1.65)), Color(0.30, 0.26, 0.225))
	draw_rect(Rect2(kp + Vector2(-s * 0.34, -s * 1.05), Vector2(s * 0.24, s * 1.65)), Color(0.20, 0.175, 0.15))
	draw_rect(Rect2(kp + Vector2(s * 0.30, -s * 0.78), Vector2(s * 0.5, s * 1.38)), Color(0.22, 0.19, 0.165))
	# Crenellations.
	for i in range(3):
		draw_rect(Rect2(kp + Vector2(-s * 0.72 + float(i) * s * 0.24, -s * 1.20),
			Vector2(s * 0.14, s * 0.16)), Color(0.30, 0.26, 0.225))
	for i in range(2):
		draw_rect(Rect2(kp + Vector2(s * 0.32 + float(i) * s * 0.26, -s * 0.92),
			Vector2(s * 0.13, s * 0.15)), Color(0.22, 0.19, 0.165))
	# Gate arch + portcullis.
	draw_colored_polygon(PackedVector2Array([
		kp + Vector2(-s * 0.16, s * 0.6), kp + Vector2(-s * 0.16, s * 0.10),
		kp + Vector2(0, -s * 0.10), kp + Vector2(s * 0.16, s * 0.10),
		kp + Vector2(s * 0.16, s * 0.6)]), Color(0.05, 0.035, 0.028))
	for i in range(3):
		draw_line(kp + Vector2(-s * 0.10 + float(i) * s * 0.10, s * 0.02),
			kp + Vector2(-s * 0.10 + float(i) * s * 0.10, s * 0.55), Color(0.24, 0.20, 0.16, 0.8), 1.2, true)
	# Lamplit arrow-slit windows — someone is home, and afraid.
	for w in [Vector2(-s * 0.48, -s * 0.72), Vector2(-s * 0.52, -s * 0.30), Vector2(s * 0.52, -s * 0.48)]:
		draw_rect(Rect2(kp + w, Vector2(3.2, 7.0)), Color(1.0, 0.72, 0.30, 0.9))
	# Banner.
	draw_line(kp + Vector2(-s * 0.42, -s * 1.20), kp + Vector2(-s * 0.42, -s * 1.95), Color(0.35, 0.31, 0.25), 2.4, true)
	draw_colored_polygon(PackedVector2Array([kp + Vector2(-s * 0.42, -s * 1.95),
		kp + Vector2(s * 0.38, -s * 1.72), kp + Vector2(-s * 0.42, -s * 1.50)]), Color(0.55, 0.18, 0.13))
	_label(kp + Vector2(0, s + 22.0), "THE PASS GATE", true)


func _draw_sites_hex() -> void:
	# Overlay pass: everything the site TILE (drawn in the tile pass) can't
	# carry itself — reachability rims that ride the hex silhouette, claimed
	# pennants, the General's star, engraved names on the board below.
	var rad := HEX_R - TILE_GAP
	for nd in _nodes:
		var typ := String(nd.type)
		if typ == "boss":
			continue
		if _tile_state(int(nd.row)) == 2:
			continue   # sketch tiles carry their own ink label and glyph
		var drop := _site_drop(nd)
		var p: Vector2 = nd.pos
		var pc := p + Vector2(0, drop)
		var vis: bool = bool(nd.vis) and not bool(nd.current)
		var open_now: bool = bool(nd.avail)
		if vis:
			# Claimed: the amber pennant planted in the struck tile.
			draw_line(p + Vector2(0, 1), p + Vector2(0, -24), Color(0.07, 0.06, 0.04), 2.2, true)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -24),
				p + Vector2(16, -19), p + Vector2(0, -14)]), AMBER)
			continue
		if typ == "elite":
			_hex_outline(p, rad + 0.6, drop, Color(CRIMSON.r, CRIMSON.g, CRIMSON.b, 0.95),
				2.8 if open_now else 2.2)
			_mt._draw_star(self, pc + Vector2(rad * 0.50, -rad * 0.54), 6.5,
				Color(1.0, 0.84, 0.30, 0.95))
		if open_now:
			# Reachability rides the hex: bright rim + a soft outer halo edge.
			_hex_outline(p, rad + 0.8, drop, AMBER, 3.0)
			_hex_outline(p, rad + 5.5, drop, Color(AMBER.r, AMBER.g, AMBER.b, 0.20), 5.0)
		# Engraved site name (live label policy: open stops + decision stops).
		var ltxt := _label_text(typ, nd)
		if ltxt != "" and (open_now or typ in ["elite", "rest", "shop", "treasure"] \
				or (typ == "wayside" and String(nd.wayside_id) in ["supply_cache", "drill_yard"])):
			_label(p + Vector2(0, drop + rad * 0.72 + (6.0 if open_now else 2.0)), ltxt, open_now)


func _label_text(typ: String, nd: Dictionary) -> String:
	match typ:
		"combat":
			return "FIGHT"
		"elite":
			return "GENERAL"
		"rest":
			return "REST"
		"shop":
			return "SHOP"
		"event":
			return "EVENT"
		"treasure":
			return "TREASURE"
		"recruit":
			return "RECRUIT"
		"wayside":
			match String(nd.wayside_id):
				"drill_yard":
					return "DRILL YARD"
				"standard_bearer":
					return "BANNER"
				"supply_cache":
					return "CACHE"
	return ""


func _label(base: Vector2, txt: String, bright: bool) -> void:
	if GameTheme.font_display == null:
		return
	var lsz := 11 if bright else 10
	var lcol := Color(0.94, 0.86, 0.66, 1.0) if bright else Color(0.78, 0.70, 0.54, 0.92)
	var lw := GameTheme.font_display.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz).x
	var lpos := Vector2(base.x - lw * 0.5, base.y + 8.0)
	draw_string_outline(GameTheme.font_display, lpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz, 4,
		Color(0.03, 0.025, 0.02, 0.88))
	draw_string(GameTheme.font_display, lpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz, lcol)


func _draw_standard() -> void:
	if _current_idx < 0:
		return
	var nd: Dictionary = _nodes[_current_idx]
	var drop := _site_drop(nd)
	var p: Vector2 = (nd.pos as Vector2) + Vector2(0, drop)
	# Warm camp-light pooling around the piece, then the army's light
	# riding the tile silhouette.
	draw_circle(p, 92.0, Color(1.0, 0.78, 0.45, 0.06))
	draw_circle(p, 52.0, Color(1.0, 0.78, 0.45, 0.07))
	_hex_outline(nd.pos, HEX_R - TILE_GAP + 0.8, drop, Color(AMBER.r, AMBER.g, AMBER.b, 0.85), 3.0)
	_hex_outline(nd.pos, HEX_R - TILE_GAP + 6.5, drop, Color(AMBER.r, AMBER.g, AMBER.b, 0.28), 5.5)
	_hex_outline(nd.pos, HEX_R - TILE_GAP + 12.0, drop, Color(AMBER.r, AMBER.g, AMBER.b, 0.10), 6.0)
	# The army as a painted-pewter standee, not a flat flag (For the King).
	draw_colored_polygon(_ellipse_pts(p + Vector2(2, 5), 16.0, 5.0), Color(0, 0, 0, 0.35))
	draw_colored_polygon(_ellipse_pts(p + Vector2(0, 3), 11.0, 4.0), Color(0.12, 0.10, 0.09))
	draw_colored_polygon(_ellipse_pts(p + Vector2(0, 1.2), 9.6, 3.3), Color(0.25, 0.22, 0.20))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 1), p + Vector2(-4.5, -17),
		p + Vector2(0, -21.5), p + Vector2(4.5, -17), p + Vector2(7, 1)]), Color(0.21, 0.19, 0.175))
	draw_line(p + Vector2(-5.2, -3), p + Vector2(-2.6, -16.5), Color(0.38, 0.35, 0.32), 1.6, true)
	draw_circle(p + Vector2(0, -24.5), 4.4, Color(0.27, 0.24, 0.22))
	draw_arc(p + Vector2(0, -24.5), 3.2, PI * 1.05, PI * 1.6, 8, Color(0.46, 0.43, 0.40), 1.4, true)
	draw_line(p + Vector2(7, 3), p + Vector2(11.5, -38), Color(0.10, 0.08, 0.06), 2.4, true)
	draw_colored_polygon(PackedVector2Array([p + Vector2(11.5, -38), p + Vector2(25, -32.5),
		p + Vector2(11.5, -27)]), AMBER)
	draw_polyline(PackedVector2Array([p + Vector2(11.5, -38), p + Vector2(25, -32.5),
		p + Vector2(11.5, -27), p + Vector2(11.5, -38)]), Color(0.30, 0.16, 0.05, 0.9), 1.1, true)


func _draw_cartouche() -> void:
	if GameTheme.font_display == null:
		return
	var acts := ["I", "II", "III"]
	var title := "ACT %s · THE BURNING ISLE" % acts[clampi(act - 1, 0, 2)]
	draw_rect(Rect2(34, 30, 420, 64), Color(0.05, 0.035, 0.02, 0.78))
	draw_rect(Rect2(34, 30, 420, 64), Color(0.62, 0.48, 0.22, 0.5), false, 1.5)
	draw_string(GameTheme.font_display, Vector2(52, 60), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(0.93, 0.84, 0.62))
	draw_string(GameTheme.font_display, Vector2(52, 82),
		"HEX WAR-BOARD · PRESENTATION PROTOTYPE" + ("  ·  QUARTERMASTER'S SKETCH" if fog_variant else ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.55, 0.42))


# ---------------------------------------------------------------- live FX

func _grad(cols: Array, offs: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols)
	g.offsets = PackedFloat32Array(offs)
	return g


func _build_fx() -> void:
	# Material grain multiplied over everything.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.seed = seed_v
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var sh := Shader.new()
	sh.code = GRAIN_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("noise_tex", nt)
	sm.set_shader_parameter("strength", 0.20)
	sm.set_shader_parameter("uv_scale", 9.0)
	var grain := ColorRect.new()
	grain.material = sm
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grain.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grain)
	# Additive bloom layer — everything that EMITS light draws here.
	_glow_item = Control.new()
	_glow_item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_item.set_anchors_preset(Control.PRESET_FULL_RECT)
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_item.material = cm
	_glow_item.draw.connect(_draw_glow)
	add_child(_glow_item)
	# Particles ride a root that carries the board squash.
	var fx := Node2D.new()
	fx.position = Vector2(0, SQUASH_Y)
	fx.scale = Vector2(1.0, SQUASH)
	add_child(fx)
	var crater := _hex_center(19, 3) + Vector2(2.0, -64.0)
	# Etna smoke.
	var smoke := CPUParticles2D.new()
	smoke.position = crater
	smoke.amount = 22
	smoke.lifetime = 7.0
	smoke.preprocess = 7.0
	smoke.texture = _soft_tex
	smoke.direction = Vector2(-0.6, -1.0)
	smoke.spread = 14.0
	smoke.initial_velocity_min = 10.0
	smoke.initial_velocity_max = 20.0
	smoke.gravity = Vector2(-7.0, -11.0)
	smoke.scale_amount_min = 0.10
	smoke.scale_amount_max = 0.16
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(1.0, 2.6))
	smoke.scale_amount_curve = sc
	smoke.color_ramp = _grad([Color(0.5, 0.46, 0.44, 0.0), Color(0.48, 0.44, 0.42, 0.30),
		Color(0.42, 0.39, 0.37, 0.0)], [0.0, 0.22, 1.0])
	fx.add_child(smoke)
	# Ember sparks drifting up off the char country.
	var emb := CPUParticles2D.new()
	emb.position = _hex_center(16, 3) + Vector2(60.0, 0.0)
	emb.amount = 34
	emb.lifetime = 3.2
	emb.preprocess = 3.2
	emb.texture = _soft_tex
	emb.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emb.emission_rect_extents = Vector2(300.0, 200.0)
	emb.direction = Vector2(0, -1)
	emb.spread = 30.0
	emb.initial_velocity_min = 6.0
	emb.initial_velocity_max = 16.0
	emb.gravity = Vector2(4.0, -14.0)
	emb.scale_amount_min = 0.020
	emb.scale_amount_max = 0.045
	emb.color_ramp = _grad([Color(1.0, 0.62, 0.20, 0.0), Color(1.0, 0.52, 0.16, 0.85),
		Color(0.9, 0.30, 0.08, 0.0)], [0.0, 0.25, 1.0])
	var ecm := CanvasItemMaterial.new()
	ecm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	emb.material = ecm
	fx.add_child(emb)
	# Dust motes in the lamplight over the marching front.
	var motes := CPUParticles2D.new()
	motes.position = (get_focus_pos() - Vector2(0, SQUASH_Y)) / Vector2(1.0, SQUASH)
	motes.amount = 12
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.texture = _soft_tex
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(150.0, 100.0)
	motes.direction = Vector2(1, 0)
	motes.spread = 180.0
	motes.initial_velocity_min = 2.0
	motes.initial_velocity_max = 5.0
	motes.gravity = Vector2(0, -1.0)
	motes.scale_amount_min = 0.015
	motes.scale_amount_max = 0.030
	motes.color_ramp = _grad([Color(1.0, 0.85, 0.55, 0.0), Color(1.0, 0.85, 0.55, 0.35),
		Color(1.0, 0.85, 0.55, 0.0)], [0.0, 0.5, 1.0])
	var mcm := CanvasItemMaterial.new()
	mcm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = mcm
	fx.add_child(motes)
	# The camp cookfire breathes a thin smoke thread.
	var csmoke := CPUParticles2D.new()
	csmoke.position = _hex_center(-1, CAMP_LANE) + Vector2(-4.0 + 22.0 * 1.75, -2.0 - 4.0)
	csmoke.amount = 8
	csmoke.lifetime = 5.0
	csmoke.preprocess = 5.0
	csmoke.texture = _soft_tex
	csmoke.direction = Vector2(-0.3, -1.0)
	csmoke.spread = 12.0
	csmoke.initial_velocity_min = 6.0
	csmoke.initial_velocity_max = 11.0
	csmoke.gravity = Vector2(-3.0, -8.0)
	csmoke.scale_amount_min = 0.05
	csmoke.scale_amount_max = 0.09
	var csc := Curve.new()
	csc.add_point(Vector2(0.0, 0.5))
	csc.add_point(Vector2(1.0, 1.8))
	csmoke.scale_amount_curve = csc
	csmoke.color_ramp = _grad([Color(0.55, 0.51, 0.48, 0.0), Color(0.52, 0.48, 0.45, 0.22),
		Color(0.45, 0.42, 0.40, 0.0)], [0.0, 0.25, 1.0])
	fx.add_child(csmoke)


func _glow_spot(p: Vector2, r: float, col: Color) -> void:
	_glow_item.draw_texture_rect(_soft_tex, Rect2(p - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, col)


func _draw_glow() -> void:
	# Everything luminous, drawn additively so it BLOOMS off the dark board.
	var g := _glow_item
	g.draw_set_transform(Vector2(0.0, SQUASH_Y), 0.0, Vector2(1.0, SQUASH))
	var rad := HEX_R - TILE_GAP
	var breathe := 0.5 + 0.5 * sin(_t * 2.2)
	for nd in _nodes:
		if _tile_state(int(nd.row)) == 2:
			continue
		var drop := _site_drop(nd)
		var pc: Vector2 = (nd.pos as Vector2) + Vector2(0, drop)
		if bool(nd.avail):
			_glow_spot(pc, 74.0, Color(1.0, 0.70, 0.30, 0.07 + 0.06 * breathe))
			var pts := _hex_corners(nd.pos, rad + 1.5, drop)
			pts.append(pts[0])
			g.draw_polyline(pts, Color(1.0, 0.74, 0.34, 0.16 + 0.16 * breathe), 3.5, true)
			if String(nd.type) == "combat":
				# A glint sweeping the upper blade of the war-swords device.
				var bd := Vector2(0.7071, -0.7071)
				var ph := fmod(_t * 0.55 + _h(int(nd.row), int(nd.col)), 1.0)
				var gp := pc + bd * lerpf(-24.0, 26.0, ph)
				_glow_spot(gp, 11.0, Color(1.0, 1.0, 0.94, 0.40 * sin(ph * PI)))
		if bool(nd.current):
			var flick := 0.85 + 0.11 * sin(_t * 7.3) + 0.04 * sin(_t * 13.1)
			_glow_spot(pc, 165.0, Color(1.0, 0.72, 0.36, 0.11 * flick))
			_glow_spot(pc, 66.0, Color(1.0, 0.80, 0.45, 0.14 * flick))
		if String(nd.type) == "rest" and not bool(nd.vis):
			_glow_spot(pc, 34.0, Color(1.0, 0.58, 0.22, 0.12 + 0.05 * sin(_t * 3.1 + pc.x)))
		if String(nd.type) == "elite" and not bool(nd.vis):
			# The General's rim breathes crimson — danger has a pulse.
			var ep2 := _hex_corners(nd.pos, rad + 1.0, drop)
			ep2.append(ep2[0])
			g.draw_polyline(ep2, Color(0.95, 0.26, 0.16,
				0.08 + 0.10 * (0.5 + 0.5 * sin(_t * 1.9 + pc.x * 0.02))), 3.0, true)
		if String(nd.type) == "treasure" and not bool(nd.vis):
			_glow_spot(pc, 24.0, Color(1.0, 0.85, 0.35, 0.06 + 0.05 * sin(_t * 2.1 + pc.y)))
	# The marching order: bright ants running the open legs.
	for e in _edges:
		if not bool(e.open):
			continue
		var pts := _edge_pts(e)
		_dash_on(g, pts, Color(1.0, 0.76, 0.34, 0.55), 3.0, 9.0, 8.0, fmod(_t * 26.0, 17.0))
	# Ember glow twinkling along the burnt road behind the army.
	for e in _edges:
		if not bool(e.vis):
			continue
		var pts := _edge_pts(e)
		for i in range(1, pts.size(), 4):
			var tw := 0.5 + 0.5 * sin(_t * 2.6 + float(i) * 1.7 + pts[i].x * 0.05)
			_glow_spot(pts[i], 9.0, Color(1.0, 0.45, 0.12, 0.10 + 0.12 * tw))
	# Etna: crater bloom, tier seams, keep windows.
	var heat := 0.5 + float(act) * 0.17
	var bc := _hex_center(19, 3) + Vector2(2.0, -8.0)
	var cp := bc + Vector2(0, -56.0)
	var surge := 0.8 + 0.2 * sin(_t * 1.6) + 0.06 * sin(_t * 5.7)
	_glow_spot(cp, 210.0, Color(1.0, 0.40, 0.12, 0.10 * heat * surge))
	_glow_spot(cp, 90.0, Color(1.0, 0.50, 0.15, 0.16 * heat * surge))
	_glow_spot(cp, 34.0, Color(1.0, 0.66, 0.24, 0.30 * surge))
	for t in [{"r": HEX_R * 1.85, "lift": -2.0}, {"r": HEX_R * 1.30, "lift": -26.0}]:
		var cc := bc + Vector2(0.0, float(t.lift))
		var corners := _hex_corners(cc, float(t.r))
		g.draw_polyline(PackedVector2Array([corners[0] + Vector2(0, 22.0),
			corners[1] + Vector2(0, 22.0), corners[2] + Vector2(0, 22.0),
			corners[3] + Vector2(0, 22.0)]),
			Color(1.0, 0.42, 0.12, (0.10 + 0.10 * surge) * heat), 3.0, true)
	var kp := _hex_center(ROWS - 1, 3) + Vector2(0, -16.0)
	var ks := 36.0
	for w in [Vector2(-ks * 0.48, -ks * 0.72), Vector2(-ks * 0.52, -ks * 0.30), Vector2(ks * 0.52, -ks * 0.48)]:
		var wf := 0.8 + 0.2 * sin(_t * 4.0 + w.x)
		_glow_spot(kp + w + Vector2(1.6, 3.5), 13.0, Color(1.0, 0.68, 0.28, 0.30 * wf))
	# Water shimmer, woodland fireflies, and the camp's cookfire.
	for key in _tiles.keys():
		var biome := String(_tiles[key].biome)
		if _tile_state(key.x) == 2:
			continue
		if biome == "water":
			var c := _hex_center(key.x, key.y)
			var ph := fmod(_t * 0.5 + _h(key.x, key.y), 1.0)
			var gx := lerpf(-rad * 0.5, rad * 0.4, ph)
			g.draw_line(c + Vector2(gx, -rad * 0.30), c + Vector2(gx + 13.0, -rad * 0.42),
				Color(0.95, 1.0, 0.98, 0.18 * sin(ph * PI)), 1.6, true)
		elif biome == "woods" and _h(key.x * 5, key.y * 3) > 0.62:
			var c := _hex_center(key.x, key.y)
			var fph := _t * (0.35 + _h(key.x, key.y) * 0.25) + _h(key.y, key.x) * 9.0
			var fp := c + Vector2(cos(fph) * 15.0, sin(fph * 1.7) * 9.0 - 7.0)
			_glow_spot(fp, 6.5, Color(1.0, 0.86, 0.42, 0.20 + 0.13 * sin(fph * 3.1)))
	var cfp := _hex_center(-1, CAMP_LANE) + Vector2(-4.0 + 22.0 * 1.75, -2.0 + 22.0 * 0.16)
	var cfl := 0.8 + 0.2 * sin(_t * 6.1) * sin(_t * 2.3)
	_glow_spot(cfp, 42.0, Color(1.0, 0.62, 0.22, 0.15 * cfl))
	_glow_spot(cfp, 16.0, Color(1.0, 0.78, 0.35, 0.22 * cfl))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _dash_on(item: CanvasItem, pts: PackedVector2Array, col: Color, w: float,
		dash: float, gap: float, phase: float = 0.0) -> void:
	var acc := fmod(phase, dash + gap)
	var on := acc < dash
	if not on:
		acc -= dash
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg_len := a.distance_to(b)
		var t := 0.0
		while t < seg_len:
			var span := (dash if on else gap) - acc
			var step := minf(span, seg_len - t)
			if on:
				item.draw_line(a.lerp(b, t / seg_len), a.lerp(b, (t + step) / seg_len), col, w, true)
			acc += step
			t += step
			if acc >= (dash if on else gap) - 0.01:
				acc = 0.0
				on = not on
