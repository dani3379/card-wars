extends Control
## MapView.gd — Slay-the-Spire-style procedural map, rendered horizontally
## (left → right). The player starts at the left under a START banner and
## climbs toward the boss icon at the right. The whole act fits comfortably
## in the viewport with a small amount of horizontal scrolling.

const COMBAT_SCENE = "res://scenes/combat.tscn"
const SHOP_SCENE = "res://scenes/shop.tscn"
const REST_SCENE = "res://scenes/rest.tscn"
const EVENT_SCENE = "res://scenes/event.tscn"
const MAIN_MENU = "res://scenes/main_menu.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")

# ── Scroll viewport ──
const SCROLL_POS := Vector2(50.0, 112.0)
const SCROLL_SZ := Vector2(1500.0, 720.0)
const FRAME_W := 8.0

# ── Map content geometry ──
# Horizontal layout: the RunState "row" axis becomes the X axis (start → boss),
# and the "col" axis becomes the Y axis (lane within a row).
# Geometry tuned so a 1-lane-jump diagonal and a same-lane straight path read
# at similar visual length — square-ish steps (gap_x ≈ 1.7×gap_y) keep the
# diagonal hypotenuse close enough to NODE_GAP_X that the eye doesn't notice
# different "road lengths" in the graph.
const NODE_GAP_X := 118.0         # horizontal step between consecutive floors
const LANE_GAP_Y := 70.0          # vertical step between lanes in a floor
const MAP_PAD_LEFT := 170.0       # space for the START banner before row 0
const MAP_PAD_RIGHT := 110.0      # space past the boss icon
const START_BANNER_W := 130.0     # width of the START asset

# ── Node rendering (STS-style compact icons; was 36/64 — too dominant). ──
const ICON_SZ := 26.0
const BOSS_SZ := 46.0
const HIT_R := 20.0
const BOSS_HIT := 30.0
const GLOW_R := 22.0
const BOSS_GLOW := 34.0

# ── Path line styling ──
# STS-style: dashed segments along a slightly wobbly path so the graph reads
# as a hand-drawn route on a parchment rather than a straight wire diagram.
const DASH_LEN := 9.0       # length of each visible dash
const DASH_GAP := 7.0       # gap between dashes
const WOBBLE_AMP := 3.5     # peak wobble offset perpendicular to the path

const ICON_KEY: Dictionary = {
	"combat": "sword", "elite": "skull", "boss": "crown",
	"rest": "campfire", "shop": "diamond", "event": "question",
}

# Painted/antique palette — less neon than primary colors, sits inside the
# parchment instead of fighting it. Each one still reads distinctly but the
# saturation is dialed down so 30+ icons on screen don't compete for attention.
const NODE_INK: Dictionary = {
	"combat": Color(0.42, 0.55, 0.78),
	"elite":  Color(0.85, 0.55, 0.22),
	"boss":   Color(0.82, 0.28, 0.22),
	"rest":   Color(0.45, 0.70, 0.42),
	"shop":   Color(0.85, 0.70, 0.28),
	"event":  Color(0.65, 0.45, 0.78),
}

# Path lines: dashed-ink style. Visited stays brightest cream; "next step"
# lines (leading to an available node) sit between dim and visited so the
# reachable paths read clearly. Dim is bumped up so future paths are still
# obvious on the parchment (previous values washed out under the texture).
const LINE_VIS  := Color(1.00, 0.94, 0.74, 1.00)
const LINE_NEXT := Color(1.00, 0.86, 0.40, 1.00)
const LINE_DIM  := Color(0.55, 0.40, 0.18, 1.00)

const ACT_TINTS: Dictionary = {
	1: {"parch": Color(0.95, 0.90, 0.82), "frame": Color(0.16, 0.12, 0.07)},
	2: {"parch": Color(0.82, 0.86, 0.94), "frame": Color(0.10, 0.12, 0.18)},
	3: {"parch": Color(0.94, 0.80, 0.72), "frame": Color(0.18, 0.08, 0.06)},
}

var _avail: Array = []
var _hovered: Vector2i = Vector2i(-1, -1)
var _canvas_ref: Control = null
var _scroll: ScrollContainer = null
var _map_content_w: float = 0.0
var _map_content_h: float = 0.0


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	var bg = get_node_or_null("Background")
	if bg:
		bg.self_modulate = Color(0.10, 0.08, 0.06, 1.0)
	GameTheme.add_atmosphere(self, "map", false)
	_build_map()


func _build_map() -> void:
	_canvas_ref = null
	_scroll = null
	_hovered = Vector2i(-1, -1)
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()
	var act_map = RunState.get_current_act_map()
	if act_map.is_empty():
		return
	var available = RunState.get_available_nodes()
	_avail.clear()
	for n in available:
		_avail.append(Vector2i(n.row, n.col))
	_build_scroll(act_map)
	_build_top_hud()
	_build_act_banner()


# ═══════════════════════════════════════════
#  SCROLLABLE MAP CONTAINER
# ═══════════════════════════════════════════

func _build_scroll(act_map: Array) -> void:
	var tints: Dictionary = ACT_TINTS.get(RunState.get_act(), ACT_TINTS[1])
	var total_rows: int = act_map.size()

	# Inner viewport size — content height matches viewport (no vertical
	# scroll); content width is wide enough for all floors plus banners.
	var inner_w: float = SCROLL_SZ.x - FRAME_W * 2
	var inner_h: float = SCROLL_SZ.y - FRAME_W * 2
	_map_content_h = inner_h
	_map_content_w = MAP_PAD_LEFT + float(total_rows - 1) * NODE_GAP_X \
		+ MAP_PAD_RIGHT
	if _map_content_w < inner_w:
		_map_content_w = inner_w

	# ── Frame (drop shadow + border) ──
	var shadow = Panel.new()
	shadow.position = SCROLL_POS + Vector2(6, 8)
	shadow.size = SCROLL_SZ
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_rounded(shadow, Color(0, 0, 0, 0.55), Color.TRANSPARENT, 0, 12)
	add_child(shadow)

	var frame = Panel.new()
	frame.position = SCROLL_POS
	frame.size = SCROLL_SZ
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_rounded(frame, tints.frame,
		Color(0.58, 0.44, 0.20, 0.95), 3, 8)
	add_child(frame)

	# ── ScrollContainer (clips the wide map content) ──
	_scroll = ScrollContainer.new()
	_scroll.position = SCROLL_POS + Vector2(FRAME_W, FRAME_W)
	_scroll.size = Vector2(inner_w, inner_h)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = false
	_style_scrollbar(_scroll)
	add_child(_scroll)

	# ── Inner content (wider than the viewport) ──
	var content = Control.new()
	content.name = "MapContent"
	content.custom_minimum_size = Vector2(_map_content_w, inner_h)
	content.size = Vector2(_map_content_w, inner_h)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(content)

	# ── Parchment background (stretched across the whole wide map) ──
	var parch_tex: Texture2D = load("res://assets/backgrounds/map_parchment.jpg")
	var parch = TextureRect.new()
	parch.texture = parch_tex
	parch.size = Vector2(_map_content_w, inner_h)
	parch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	parch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	parch.modulate = tints.parch
	parch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(parch)

	# ── Compute node + line geometry ──
	var nodes: Array = []
	var lines: Array = []
	var player_pos := Vector2.ZERO
	var has_player := false
	for ri in range(total_rows):
		var row = act_map[ri]
		for nd in row:
			var pos = _node_pos(nd.row, nd.col, inner_h)
			var ia = _avail.has(Vector2i(nd.row, nd.col))
			nodes.append({
				"pos": pos, "type": nd.type,
				"vis": nd.visited, "avail": ia,
				"key": Vector2i(nd.row, nd.col),
			})
			if nd.visited:
				player_pos = pos
				has_player = true
			if nd.row + 1 < total_rows:
				var next_row = act_map[nd.row + 1]
				for tc in nd.connections:
					for tn in next_row:
						if tn.col == tc:
							lines.append({
								"from": pos,
								"to": _node_pos(tn.row, tn.col, inner_h),
								"vis": nd.visited,
								"to_avail": _avail.has(
									Vector2i(tn.row, tn.col)),
							})
							break

	# Lines fanning from the START disc to each row-0 node — wires the
	# entrance marker into the graph instead of leaving it stranded. A
	# given line lights up "visited" once that row-0 node has been entered.
	var start_center := Vector2(MAP_PAD_LEFT * 0.5, inner_h * 0.5)
	if total_rows > 0:
		for nd in act_map[0]:
			lines.append({
				"from": start_center,
				"to": _node_pos(nd.row, nd.col, inner_h),
				"vis": nd.visited,
				"to_avail": _avail.has(Vector2i(nd.row, nd.col)),
			})

	# Pulsing glow ring under each available node.
	for nd in nodes:
		if nd.avail and not nd.vis:
			var r: float = BOSS_GLOW if nd.type == "boss" else GLOW_R
			_add_glow(content, nd.pos, r + 6,
				Color(0.95, 0.78, 0.30, 0.18))
			_add_glow(content, nd.pos, r,
				Color(1.0, 0.88, 0.42, 0.30))

	# ── Canvas (draws lines + node icons + player marker) ──
	var canvas = Control.new()
	canvas.name = "MapCanvas"
	canvas.size = Vector2(_map_content_w, inner_h)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_meta("nodes", nodes)
	canvas.set_meta("lines", lines)
	canvas.set_meta("player_pos", player_pos)
	canvas.set_meta("has_player", has_player)
	canvas.draw.connect(_draw_map.bind(canvas))
	content.add_child(canvas)
	_canvas_ref = canvas
	canvas.queue_redraw()

	# ── Click targets (one Button per node) ──
	for ri in range(total_rows):
		for nd in act_map[ri]:
			_add_btn(content, nd, _node_pos(nd.row, nd.col, inner_h))

	# ── START banner at the far left, boss banner past the boss icon ──
	_add_start_banner(content, inner_h)
	_add_boss_banner(content, inner_h, total_rows)

	# ── Scroll so the player + a few floors ahead are visible ──
	call_deferred("_scroll_to_player", has_player, player_pos)

	# ── Entrance animation ──
	shadow.modulate.a = 0.0
	frame.modulate.a = 0.0
	_scroll.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(shadow, "modulate:a", 1.0, 0.3) \
		.set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(frame, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(_scroll, "modulate:a", 1.0, 0.5) \
		.set_delay(0.08).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _scroll_to_player(has_player: bool, player_pos: Vector2) -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var view_w: float = _scroll.size.x
	var max_scroll: float = maxf(0.0, _map_content_w - view_w)
	var target: float
	if has_player:
		# Park the player at ~30% from the left, leaving 70% of the viewport
		# to preview the path ahead.
		target = player_pos.x - view_w * 0.30
	else:
		# Pre-run: show the START banner at the very left.
		target = 0.0
	_scroll.scroll_horizontal = int(clampf(target, 0.0, max_scroll))


# ═══════════════════════════════════════════
#  NODE POSITIONING (horizontal layout)
# ═══════════════════════════════════════════

func _node_pos(row: int, col: int, inner_h: float) -> Vector2:
	var x: float = MAP_PAD_LEFT + float(row) * NODE_GAP_X
	var y: float = _lane_y(col, inner_h)
	# Tiny deterministic jitter so the map feels hand-drawn, not gridlike.
	var h: int = row * 11 + col * 17
	x += fmod(float(h * 13 + 5), 14.0) - 7.0
	y += fmod(float(h * 7 + 3), 10.0) - 5.0
	return Vector2(x, y)


func _lane_y(col: int, inner_h: float) -> float:
	# `col` 0..MAP_WIDTH-1 maps to vertical lanes, centered in the viewport.
	var total_h: float = float(RunState.MAP_WIDTH - 1) * LANE_GAP_Y
	return inner_h * 0.5 - total_h * 0.5 + float(col) * LANE_GAP_Y


# ═══════════════════════════════════════════
#  CANVAS DRAW
# ═══════════════════════════════════════════

func _draw_map(canvas: Control) -> void:
	var nodes: Array = canvas.get_meta("nodes")
	var lines: Array = canvas.get_meta("lines")
	var has_player: bool = canvas.get_meta("has_player")
	var player_pos: Vector2 = canvas.get_meta("player_pos")

	# "Focus x" — the player's current x-coordinate. Path lines that fall far
	# from this point get a faint distance fade for a hint of depth, but node
	# icons stay fully readable wherever they sit on the map.
	var focus_x: float = _focus_x(nodes, has_player, player_pos)

	# ── Terrain decoration (drawn first — sits behind the path graph) ──
	# Hand-drawn map landmarks (mountains, forests, pebbles) scattered across
	# the parchment so it reads like an explorer's chart instead of a grid.
	_draw_terrain(canvas, nodes)

	# ── Path lines (drawn first so nodes overlap them) ──
	# STS-style: dashed ink along a slightly wobbly bezier so the route reads
	# like a hand-drawn trail. Visited paths are bright cream; "next-step"
	# paths get a gold tinge so reachable choices pop; the rest sit in dim
	# ink that still contrasts against the parchment.
	for ln in lines:
		var col: Color = LINE_DIM
		var w: float = 3.2
		if ln.vis:
			col = LINE_VIS
			w = 4.2
		elif ln.get("to_avail", false):
			col = LINE_NEXT
			w = 3.8
		var mid_x: float = (ln.from.x + ln.to.x) * 0.5
		var is_focus: bool = ln.vis or ln.get("to_avail", false)
		var dist_fade: float = _proximity_fade(mid_x, focus_x, is_focus)
		var faded := Color(col.r, col.g, col.b, col.a * dist_fade)
		# Stable per-segment seed so the wobble doesn't shift between frames.
		var seed_h: int = int(ln.from.x * 3.1 + ln.from.y * 7.3
			+ ln.to.x * 11.7 + ln.to.y * 5.9)
		var pts: PackedVector2Array = _wobble_pts(ln.from, ln.to, seed_h)
		# Soft halo behind the dashes adds weight without filling the gaps.
		var halo := Color(faded.r, faded.g, faded.b, faded.a * 0.22)
		_draw_dashed_polyline(canvas, pts, halo, w + 3.0)
		_draw_dashed_polyline(canvas, pts, faded, w)

	# ── Node plates + icons ──
	for nd in nodes:
		var tex = _icon_tex(ICON_KEY.get(nd.type, "question"))
		if not tex:
			continue
		var pos: Vector2 = nd.pos
		var base_sz: float = BOSS_SZ if nd.type == "boss" else ICON_SZ
		var is_hov: bool = _hovered == nd.key
		var sz: float = base_sz * (1.15 if is_hov else 1.0)

		var ink: Color = NODE_INK.get(nd.type, Color(0.3, 0.3, 0.3))
		var plate_alpha: float = 0.82
		if nd.vis:
			# Visited — muted, ghost-like, with a check mark.
			var grey: float = (ink.r + ink.g + ink.b) / 3.0
			ink = Color(
				lerpf(ink.r, grey, 0.70),
				lerpf(ink.g, grey, 0.70),
				lerpf(ink.b, grey, 0.70), 0.55)
			plate_alpha = 0.42
		elif not nd.avail:
			# Future nodes — clearly visible. STS keeps upcoming icons at
			# roughly the same legibility as the row you can click; only the
			# gold halo / pulsing glow signals "this one's reachable next."
			ink = Color(ink.r, ink.g, ink.b, 0.92)
			plate_alpha = 0.70

		# Plate — dark circle behind icon.
		canvas.draw_circle(pos, sz * 0.78,
			Color(0.10, 0.07, 0.04, plate_alpha))
		canvas.draw_arc(pos, sz * 0.78, 0.0, TAU, 48,
			Color(0.62, 0.46, 0.22, plate_alpha * 0.90), 1.4, true)
		if nd.avail and not nd.vis:
			canvas.draw_arc(pos, sz * 0.85, 0.0, TAU, 48,
				Color(1.0, 0.88, 0.42, 0.75), 2.2, true)

		canvas.draw_texture_rect(tex,
			Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)),
			false, ink)

		if nd.vis:
			_draw_check(canvas, pos, base_sz)

	# Player marker — left-pointing chevron beside the current node.
	if has_player:
		var pp: Vector2 = player_pos
		var ox: float = -ICON_SZ * 0.5 - 14.0
		var s: float = 8.0
		var t0: Vector2 = pp + Vector2(ox - s * 1.5, -s)
		var t1: Vector2 = pp + Vector2(ox - s * 1.5, s)
		var t2: Vector2 = pp + Vector2(ox, 0)
		canvas.draw_colored_polygon(PackedVector2Array([
			t0 + Vector2(1.5, 2.0), t1 + Vector2(1.5, 2.0),
			t2 + Vector2(1.5, 2.0)
		]), Color(0, 0, 0, 0.55))
		canvas.draw_colored_polygon(PackedVector2Array([t0, t1, t2]),
			Color(0.95, 0.30, 0.18, 0.95))
		var lbl_pos: Vector2 = pp + Vector2(ox - 32.0, 0)
		var font: Font = GameTheme.font_display
		if font:
			var txt := "YOU"
			var fs := 14
			var ts: Vector2 = font.get_string_size(txt,
				HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			canvas.draw_string_outline(font,
				lbl_pos - Vector2(ts.x, -ts.y * 0.35), txt,
				HORIZONTAL_ALIGNMENT_CENTER, -1, fs, 4, Color(0, 0, 0, 0.95))
			canvas.draw_string(font,
				lbl_pos - Vector2(ts.x, -ts.y * 0.35), txt,
				HORIZONTAL_ALIGNMENT_CENTER, -1, fs,
				Color(1.0, 0.92, 0.55))


## Returns the x-coordinate the player should be paying attention to. If they
## haven't picked a node yet, it's the centroid of the available row; otherwise
## it's the player's current position.
func _focus_x(nodes: Array, has_player: bool, player_pos: Vector2) -> float:
	if has_player:
		return player_pos.x
	var sum := 0.0
	var count := 0
	for nd in nodes:
		if nd.avail:
			sum += nd.pos.x
			count += 1
	if count == 0:
		return MAP_PAD_LEFT
	return sum / float(count)


## Subtle distance-based fade for path lines. Active (visited or "next-step")
## lines never fade; other lines drop to 78% at the far edge for a hint of
## depth without compromising readability — STS shows the whole act clearly.
func _proximity_fade(x: float, focus_x: float, is_active: bool) -> float:
	if is_active:
		return 1.0
	var dx: float = absf(x - focus_x)
	var t: float = clampf(dx / (NODE_GAP_X * 3.5), 0.0, 1.0)
	return lerpf(1.0, 0.78, t)


func _draw_check(canvas: Control, pos: Vector2, icon_sz: float) -> void:
	var ox: float = icon_sz * 0.40
	var oy: float = icon_sz * 0.40
	var s: float = 5.0
	var base: Vector2 = pos + Vector2(ox, oy)
	var c := Color(0.25, 0.55, 0.25, 0.70)
	canvas.draw_line(base + Vector2(-s, 0),
		base + Vector2(-s * 0.2, s * 0.5), c, 2.0)
	canvas.draw_line(base + Vector2(-s * 0.2, s * 0.5),
		base + Vector2(s, -s * 0.4), c, 2.0)


# ═══════════════════════════════════════════
#  TERRAIN DECORATION
# ═══════════════════════════════════════════

## Scatters hand-drawn map symbols (mountain silhouettes, tree clusters, stone
## fields) across the parchment so the background reads like an explorer's
## chart rather than a flat grid. Terrain is deterministic per run + act, and
## any cell falling near a node is skipped so icons stay readable.
func _draw_terrain(canvas: Control, nodes: Array) -> void:
	var w: float = _map_content_w
	var h: float = _map_content_h
	var node_positions := PackedVector2Array()
	for nd in nodes:
		node_positions.append(nd.pos)

	var cell_w := 92.0
	var cell_h := 74.0
	var ncols: int = int(w / cell_w) + 1
	var nrows: int = int(h / cell_h) + 1
	var avoid_sq: float = 58.0 * 58.0

	var seed_base: int = int(RunState.run_seed) + RunState.get_act() * 7919
	var rng := RandomNumberGenerator.new()
	for cy in range(nrows):
		for cx in range(ncols):
			rng.seed = seed_base + cx * 131 + cy * 977
			var jx: float = rng.randf_range(0.12, 0.88) * cell_w
			var jy: float = rng.randf_range(0.12, 0.88) * cell_h
			var pos := Vector2(float(cx) * cell_w + jx,
				float(cy) * cell_h + jy)

			# Skip cells too close to a node — terrain must yield to icons.
			var too_close := false
			for npos in node_positions:
				if pos.distance_squared_to(npos) < avoid_sq:
					too_close = true
					break
			if too_close:
				continue

			var roll: float = rng.randf()
			if roll < 0.32:
				# Empty cell — keeps the map breathing.
				continue
			elif roll < 0.62:
				_draw_terrain_mountain(canvas, pos, rng)
			elif roll < 0.86:
				_draw_terrain_trees(canvas, pos, rng)
			else:
				_draw_terrain_pebbles(canvas, pos, rng)


func _draw_terrain_mountain(canvas: Control, pos: Vector2,
		rng: RandomNumberGenerator) -> void:
	var body_col := Color(0.34, 0.26, 0.16, 0.42)
	var snow_col := Color(0.58, 0.50, 0.36, 0.46)
	var line_col := Color(0.18, 0.13, 0.08, 0.55)
	var count: int = 1 + (rng.randi() % 2)  # 1 or 2 peaks
	for i in range(count):
		var w_sz: float = rng.randf_range(22.0, 32.0)
		var h_sz: float = rng.randf_range(20.0, 30.0)
		var ox: float = (float(i) - float(count) * 0.5 + 0.5) * (w_sz * 0.7)
		var c := pos + Vector2(ox, 0.0)
		var base_l := c + Vector2(-w_sz * 0.5, h_sz * 0.4)
		var base_r := c + Vector2(w_sz * 0.5, h_sz * 0.4)
		var peak := c + Vector2(rng.randf_range(-3.0, 3.0), -h_sz * 0.6)
		canvas.draw_colored_polygon(
			PackedVector2Array([base_l, peak, base_r]), body_col)
		# Snow cap
		var snow_l := c + Vector2(-w_sz * 0.16, -h_sz * 0.28)
		var snow_r := c + Vector2(w_sz * 0.16, -h_sz * 0.28)
		canvas.draw_colored_polygon(
			PackedVector2Array([snow_l, peak, snow_r]), snow_col)
		# Outline
		canvas.draw_polyline(
			PackedVector2Array([base_l, peak, base_r]),
			line_col, 1.2, true)


func _draw_terrain_trees(canvas: Control, pos: Vector2,
		rng: RandomNumberGenerator) -> void:
	var foliage := Color(0.22, 0.28, 0.16, 0.55)
	var foliage_dark := Color(0.16, 0.20, 0.12, 0.55)
	var n: int = 3 + (rng.randi() % 3)  # 3-5 trees
	for i in range(n):
		var ox: float = rng.randf_range(-13.0, 13.0)
		var oy: float = rng.randf_range(-7.0, 7.0)
		var sz: float = rng.randf_range(7.0, 11.0)
		var c := pos + Vector2(ox, oy)
		var col: Color = foliage if (i % 2) == 0 else foliage_dark
		canvas.draw_colored_polygon(PackedVector2Array([
			c + Vector2(-sz * 0.5, sz * 0.4),
			c + Vector2(0.0, -sz * 0.85),
			c + Vector2(sz * 0.5, sz * 0.4),
		]), col)


func _draw_terrain_pebbles(canvas: Control, pos: Vector2,
		rng: RandomNumberGenerator) -> void:
	var dot_col := Color(0.36, 0.28, 0.18, 0.48)
	var n: int = 4 + (rng.randi() % 4)  # 4-7 dots
	for i in range(n):
		var ox: float = rng.randf_range(-13.0, 13.0)
		var oy: float = rng.randf_range(-8.0, 8.0)
		var r: float = rng.randf_range(1.4, 2.6)
		canvas.draw_circle(pos + Vector2(ox, oy), r, dot_col)


# ═══════════════════════════════════════════
#  START / BOSS BANNERS
# ═══════════════════════════════════════════

func _add_start_banner(parent: Control, inner_h: float) -> void:
	# Slay-the-Spire-style entrance marker: a gilded portal disc with the
	# adventurer (horned-helm) icon inside. Path lines fan out from this
	# disc to each row-0 node, so the marker IS part of the graph rather
	# than a floating label. No text — the icon is the indicator.
	var center := Vector2(MAP_PAD_LEFT * 0.5, inner_h * 0.5)
	var disc_sz := 78.0

	# ── Pulsing glow halos (same idiom as available-node markers) ──
	_add_glow(parent, center, disc_sz * 0.78,
		Color(0.95, 0.78, 0.30, 0.18))
	_add_glow(parent, center, disc_sz * 0.58,
		Color(1.0, 0.88, 0.42, 0.32))

	# ── Drop shadow under the disc ──
	var shadow := Panel.new()
	shadow.position = center - Vector2(disc_sz, disc_sz) * 0.5 \
		+ Vector2(2, 4)
	shadow.size = Vector2(disc_sz, disc_sz)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_rounded(shadow, Color(0, 0, 0, 0.60),
		Color.TRANSPARENT, 0, int(disc_sz * 0.5))
	parent.add_child(shadow)

	# ── Dark inked disc with a gilded rim ──
	var disc := Panel.new()
	disc.position = center - Vector2(disc_sz, disc_sz) * 0.5
	disc.size = Vector2(disc_sz, disc_sz)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_rounded(disc, Color(0.12, 0.08, 0.04, 0.96),
		Color(0.95, 0.78, 0.30, 1.0), 3, int(disc_sz * 0.5))
	parent.add_child(disc)

	# ── Inner ornament ring (thin gold accent line inside the rim) ──
	var inner_sz := disc_sz - 14.0
	var inner := Panel.new()
	inner.position = center - Vector2(inner_sz, inner_sz) * 0.5
	inner.size = Vector2(inner_sz, inner_sz)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_rounded(inner, Color(0, 0, 0, 0),
		Color(0.95, 0.78, 0.30, 0.50), 1, int(inner_sz * 0.5))
	parent.add_child(inner)

	# ── Adventurer icon (player avatar) on the disc face ──
	var helm_path := "res://assets/icons/game-icons/horned-helm.svg"
	var helm: TextureRect = null
	if ResourceLoader.exists(helm_path):
		var helm_tex: Texture2D = load(helm_path)
		var icon_sz := 44.0
		helm = TextureRect.new()
		helm.texture = helm_tex
		helm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		helm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		helm.position = center - Vector2(icon_sz, icon_sz) * 0.5
		helm.size = Vector2(icon_sz, icon_sz)
		helm.modulate = Color(0.98, 0.86, 0.50, 1.0)
		helm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(helm)

	# ── Gentle synchronised bob on the whole stack ──
	var bob_targets: Array = [shadow, disc, inner]
	if helm != null:
		bob_targets.append(helm)
	for tgt in bob_targets:
		var node_tgt: Control = tgt as Control
		var tw := node_tgt.create_tween().set_loops()
		var oy: float = node_tgt.position.y
		tw.tween_property(node_tgt, "position:y", oy - 3.0, 1.4) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(node_tgt, "position:y", oy, 1.4) \
			.set_trans(Tween.TRANS_SINE)


func _add_boss_banner(parent: Control, inner_h: float, total_rows: int) -> void:
	# Subtle "BOSS" caption above the boss icon. The icon itself is already
	# oversized so we don't need a big asset here.
	var boss_x: float = MAP_PAD_LEFT + float(total_rows - 1) * NODE_GAP_X
	var lbl := GameTheme.make_label("BOSS",
		GameTheme.FONT_SUBHEADER,
		Color(0.95, 0.25, 0.20), true)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(boss_x - 60.0,
		inner_h * 0.5 - BOSS_SZ * 0.5 - 36.0)
	lbl.size = Vector2(120, 24)
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)


# ═══════════════════════════════════════════
#  PATH GEOMETRY  —  wobble + dashing
# ═══════════════════════════════════════════

# Returns a polyline that runs from `from` to `to` along a slightly wobbly
# bezier. The wobble is a 1.5-cycle sine perpendicular to the line plus a
# per-segment offset on the control points, giving each route a hand-drawn
# kink that's deterministic from the segment's endpoints (no jitter on
# redraw). Sampling is dense (~36 points) so dashing reads as smooth curve
# rather than chained straight chunks.
func _wobble_pts(from: Vector2, to: Vector2, seed_h: int) -> PackedVector2Array:
	var dx: float = to.x - from.x
	var dy: float = to.y - from.y
	var perp: Vector2 = Vector2(-dy, dx).normalized()
	# Macro curve — bezier control points pushed off the line by a small
	# pseudo-random offset so no two segments have the same arc.
	var macro_off: float = (fmod(float(seed_h), 30.0) - 15.0) * 0.45
	var cp1: Vector2 = Vector2(lerpf(from.x, to.x, 0.33),
		lerpf(from.y, to.y, 0.33)) + perp * macro_off
	var cp2: Vector2 = Vector2(lerpf(from.x, to.x, 0.66),
		lerpf(from.y, to.y, 0.66)) + perp * macro_off * 0.55
	# Length-aware wobble: shorter (straight, same-lane) segments get more
	# perpendicular sway so their drawn arc length ends up close to that of
	# the long diagonal segments. The eye then reads every road as roughly
	# the same length, which is what the player asked for. Reference length
	# is the diagonal hypotenuse — the longest typical edge.
	var seg_len: float = sqrt(dx * dx + dy * dy)
	var ref_len: float = sqrt(NODE_GAP_X * NODE_GAP_X
		+ LANE_GAP_Y * LANE_GAP_Y)
	var stretch: float = clampf(ref_len / maxf(seg_len, 1.0), 1.0, 1.7)
	var amp: float = WOBBLE_AMP * stretch
	var phase: float = fmod(float(seed_h), 628.0) * 0.01
	var pts := PackedVector2Array()
	var steps: int = 36
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var u: float = 1.0 - t
		var base: Vector2 = u*u*u*from + 3.0*u*u*t*cp1 \
			+ 3.0*u*t*t*cp2 + t*t*t*to
		# 1.5 wobble cycles along the segment, tapered at the endpoints so
		# lines meet nodes cleanly rather than waving into them.
		var taper: float = sin(t * PI)
		var wobble: float = sin(t * PI * 3.0 + phase) * amp * taper
		pts.append(base + perp * wobble)
	return pts


# Draws a polyline as a series of dashed segments. Tracks accumulated arc
# length so dashes stay uniform across the curve regardless of how many
# sample points the polyline has.
func _draw_dashed_polyline(canvas: Control, pts: PackedVector2Array,
		color: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var stride: float = DASH_LEN + DASH_GAP
	var accum: float = 0.0  # distance walked since the last dash start
	var drawing := true     # currently inside a dash (true) or a gap (false)
	var seg_start: Vector2 = pts[0]
	for i in range(1, pts.size()):
		var seg_end: Vector2 = pts[i]
		var seg_vec: Vector2 = seg_end - seg_start
		var seg_len: float = seg_vec.length()
		if seg_len <= 0.0001:
			seg_start = seg_end
			continue
		var seg_dir: Vector2 = seg_vec / seg_len
		var walked: float = 0.0
		while walked < seg_len:
			var phase_len: float = (DASH_LEN if drawing else DASH_GAP) - accum
			var step: float = minf(phase_len, seg_len - walked)
			var a: Vector2 = seg_start + seg_dir * walked
			var b: Vector2 = seg_start + seg_dir * (walked + step)
			if drawing:
				canvas.draw_line(a, b, color, width, true)
			walked += step
			accum += step
			if accum >= (DASH_LEN if drawing else DASH_GAP) - 0.0001:
				accum = 0.0
				drawing = not drawing
		seg_start = seg_end


# ═══════════════════════════════════════════
#  GLOW + BUTTONS
# ═══════════════════════════════════════════

func _add_glow(parent: Control, pos: Vector2, radius: float,
		color: Color) -> void:
	var d: float = radius * 2.0
	var g = Panel.new()
	g.position = pos - Vector2(radius, radius)
	g.size = Vector2(d, d)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_rounded(g, color, Color.TRANSPARENT, 0, int(radius))
	parent.add_child(g)
	var tw = g.create_tween().set_loops()
	tw.tween_property(g, "modulate:a", 0.4, 0.9) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_property(g, "modulate:a", 1.0, 0.9) \
		.set_trans(Tween.TRANS_SINE)


func _add_btn(parent: Control, node: Dictionary, pos: Vector2) -> void:
	var r: float = BOSS_HIT if node.type == "boss" else HIT_R
	var btn = Button.new()
	btn.position = pos - Vector2(r, r)
	btn.size = Vector2(r * 2, r * 2)
	btn.flat = true
	btn.tooltip_text = _tip(node)
	var empty = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("disabled", empty)
	btn.add_theme_stylebox_override("focus", empty)
	var is_avail: bool = _avail.has(Vector2i(node.row, node.col))
	if node.visited or not is_avail:
		btn.disabled = true
		btn.add_theme_stylebox_override("hover", empty)
	else:
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var hover = StyleBoxFlat.new()
		hover.bg_color = Color(0.95, 0.78, 0.30, 0.18)
		var ir: int = int(r)
		for p in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
			hover.set(p, ir)
		btn.add_theme_stylebox_override("hover", hover)
		btn.mouse_entered.connect(_on_hover.bind(node.row, node.col, true))
		btn.mouse_exited.connect(_on_hover.bind(node.row, node.col, false))
	btn.pressed.connect(_on_node_pressed.bind(node.row, node.col))
	parent.add_child(btn)


func _on_hover(row: int, col: int, entered: bool) -> void:
	if entered:
		_hovered = Vector2i(row, col)
	elif _hovered == Vector2i(row, col):
		_hovered = Vector2i(-1, -1)
	if _canvas_ref and is_instance_valid(_canvas_ref):
		_canvas_ref.queue_redraw()


# ═══════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════

func _icon_tex(key: String) -> Texture2D:
	match key:
		"sword": return GameTheme.tex_node_combat
		"skull": return GameTheme.tex_node_elite
		"crown": return GameTheme.tex_node_boss
		"campfire": return GameTheme.tex_node_rest
		"diamond": return GameTheme.tex_node_shop
		"question": return GameTheme.tex_node_event
	return null


func _tip(node: Dictionary) -> String:
	var t: String = node.type
	var label: String = t.capitalize()
	if t in ["combat", "elite", "boss"] and node.get("encounter_id", "") != "":
		var enc = EncounterDB.get_encounter(node.encounter_id)
		if not enc.is_empty():
			label = enc.name
	return label


func _style_rounded(panel: Panel, bg: Color, border: Color,
		bw: int, cr: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	for p in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		s.set(p, bw)
	for p in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(p, cr)
	panel.add_theme_stylebox_override("panel", s)


## Gilds the horizontal scrollbar so it matches the parchment frame instead of
## looking like the default flat-grey Godot one.
func _style_scrollbar(sc: ScrollContainer) -> void:
	var hb: HScrollBar = sc.get_h_scroll_bar()
	if hb == null:
		return
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.55, 0.40, 0.18, 0.95)
	grabber.border_color = Color(0.85, 0.68, 0.30, 0.80)
	for p in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		grabber.set(p, 1)
	for p in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		grabber.set(p, 5)
	hb.add_theme_stylebox_override("grabber", grabber)
	var hov := grabber.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.75, 0.55, 0.22, 1.0)
	hb.add_theme_stylebox_override("grabber_highlight", hov)
	var pressed := grabber.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.90, 0.70, 0.28, 1.0)
	hb.add_theme_stylebox_override("grabber_pressed", pressed)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.06, 0.04, 0.55)
	for p in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		track.set(p, 4)
	hb.add_theme_stylebox_override("scroll", track)
	hb.custom_minimum_size = Vector2(0, 14)


# ═══════════════════════════════════════════
#  TOP HUD
# ═══════════════════════════════════════════

func _build_top_hud() -> void:
	const ROW_Y := 18.0
	const ROW_H := 40.0
	const ICON := 40.0
	const GAP := 12.0
	const FONT_SZ := 26

	var x := 28.0
	_place_painted_icon(GameTheme.tex_hud_heart, Vector2(x, ROW_Y),
		ICON, Color.WHITE)
	_place_centred_label(
		"%d / %d" % [RunState.hero_hp, RunState.hero_max_hp],
		Rect2(x + ICON + GAP, ROW_Y, 130, ROW_H),
		Color(1.0, 0.95, 0.85), FONT_SZ)
	x += ICON + GAP + 145

	const GOLD_ICON := 50.0
	var gold_y: float = ROW_Y - (GOLD_ICON - ICON) * 0.5
	_place_painted_icon(GameTheme.tex_hud_gold, Vector2(x, gold_y),
		GOLD_ICON, Color.WHITE)
	_place_centred_label(str(RunState.gold),
		Rect2(x + GOLD_ICON + GAP, ROW_Y, 90, ROW_H),
		Color(1.0, 0.95, 0.55), FONT_SZ)
	x += GOLD_ICON + GAP + 105

	_place_centred_label("ACT %d" % RunState.get_act(),
		Rect2(x, ROW_Y, 130, ROW_H),
		Color(0.95, 0.88, 0.70), FONT_SZ)

	if RunState.relics.size() > 0:
		var rx := 640.0
		for r_id in RunState.relics:
			_place_painted_icon(GameTheme.tex_hud_relic,
				Vector2(rx, ROW_Y), ICON - 4,
				Color(0.95, 0.78, 0.30))
			rx += ICON + 4
		_place_centred_label("×%d" % RunState.relics.size(),
			Rect2(rx + 6, ROW_Y, 60, ROW_H),
			Color(0.95, 0.85, 0.55), 22)

	var px := 1110.0
	var potions: int = RunState.potions
	for i in range(3):
		var filled: bool = i < potions
		var pcol: Color = Color.WHITE if filled else \
			Color(0.45, 0.40, 0.35, 0.45)
		_place_painted_icon(GameTheme.tex_hud_potion,
			Vector2(px, ROW_Y), ICON, pcol)
		px += ICON + 4
	if potions > 0:
		var pbtn = GameTheme.make_themed_button("Use Potion",
			Color(0.20, 0.45, 0.20), Vector2(110, ROW_H))
		pbtn.position = Vector2(px + 12, ROW_Y)
		pbtn.pressed.connect(func():
			if RunState.use_potion():
				_build_map()
		)
		add_child(pbtn)
		px += 130

	_place_deck_button(Vector2(px + 24, ROW_Y), ICON, ROW_H, FONT_SZ)


func _place_painted_icon(tex: Texture2D, top_left: Vector2, sz: float,
		tint: Color) -> void:
	if tex == null:
		return
	add_child(_make_constrained_tex(tex, top_left + Vector2(2, 2), sz,
		Color(0, 0, 0, 0.55)))
	add_child(_make_constrained_tex(tex, top_left, sz, tint))


func _make_constrained_tex(tex: Texture2D, top_left: Vector2, sz: float,
		modulate: Color) -> TextureRect:
	var ico := TextureRect.new()
	ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	ico.texture = tex
	ico.custom_minimum_size = Vector2(sz, sz)
	ico.size = Vector2(sz, sz)
	ico.position = top_left
	ico.modulate = modulate
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ico


func _place_centred_label(text: String, rect: Rect2, color: Color,
		size: int = 22) -> void:
	var wrap := Control.new()
	wrap.position = rect.position
	wrap.size = rect.size
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(lbl)


func _place_deck_button(top_left: Vector2, icon_sz: float, row_h: float,
		font_sz: int) -> void:
	const PADDING := 10.0
	const COUNT_W := 50.0
	var btn_w: float = PADDING + icon_sz + 8 + COUNT_W + PADDING
	var btn := Button.new()
	btn.size = Vector2(btn_w, row_h)
	btn.position = top_left
	btn.flat = true
	btn.tooltip_text = "View your deck"
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for sb in ["normal", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(sb, empty)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.95, 0.78, 0.30, 0.15)
	for p in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		hover.set(p, 8)
	btn.add_theme_stylebox_override("hover", hover)
	btn.pressed.connect(_show_deck_viewer)
	add_child(btn)
	_place_painted_icon(GameTheme.tex_hud_deck,
		top_left + Vector2(PADDING, 0), icon_sz,
		Color(0.95, 0.88, 0.72))
	_place_centred_label(str(RunState.deck.size()),
		Rect2(top_left.x + PADDING + icon_sz + 8, top_left.y,
			COUNT_W, row_h),
		Color(1.0, 0.95, 0.80), font_sz)


# ═══════════════════════════════════════════
#  ACT BANNER + LEGEND
# ═══════════════════════════════════════════

func _build_act_banner() -> void:
	var act_map = RunState.get_current_act_map()
	var boss_name := "???"
	for row in act_map:
		for nd in row:
			if nd.type == "boss" and nd.get("encounter_id", "") != "":
				var enc = EncounterDB.get_encounter(nd.encounter_id)
				if not enc.is_empty():
					boss_name = enc.name
				break
	var banner_text := "Act %d  ◆  Boss Ahead: %s" % \
		[RunState.get_act(), boss_name]
	var cur_floor: int = RunState.map_position.row + 1
	cur_floor = maxi(cur_floor, 0)
	var counter_text := "Floor %d / %d" % [cur_floor, act_map.size()]
	var banner_y: float = SCROLL_POS.y - 40
	_place_centred_label(banner_text,
		Rect2(SCROLL_POS.x + 24, banner_y, 900, 32),
		Color(0.98, 0.85, 0.45), 20)
	var wrap := Control.new()
	wrap.position = Vector2(SCROLL_POS.x + SCROLL_SZ.x - 220, banner_y)
	wrap.size = Vector2(200, 32)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)
	var lbl := Label.new()
	lbl.text = counter_text
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.85, 0.62))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(lbl)
	_build_legend_strip()


func _build_legend_strip() -> void:
	var strip_y: float = SCROLL_POS.y + SCROLL_SZ.y + 6
	var entries: Array = [
		["combat", "Combat", NODE_INK["combat"]],
		["elite", "Elite", NODE_INK["elite"]],
		["rest", "Rest", NODE_INK["rest"]],
		["shop", "Shop", NODE_INK["shop"]],
		["event", "Event", NODE_INK["event"]],
		["boss", "Boss", NODE_INK["boss"]],
	]
	const ICON_SZ_LEGEND := 20.0
	const ENTRY_GAP := 16.0
	const LABEL_GAP := 6.0
	var font: Font = GameTheme.font_body
	var total_w: float = 0.0
	var label_widths: Array[float] = []
	for e in entries:
		var lw: float = font.get_string_size(e[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		label_widths.append(lw)
		total_w += ICON_SZ_LEGEND + LABEL_GAP + lw + ENTRY_GAP
	total_w -= ENTRY_GAP
	var x: float = SCROLL_POS.x + (SCROLL_SZ.x - total_w) * 0.5
	for i in range(entries.size()):
		var e = entries[i]
		var ntype: String = e[0]
		var label_text: String = e[1]
		var ink: Color = e[2]
		var tex = _icon_tex(ICON_KEY.get(ntype, "question"))
		if tex:
			add_child(_make_constrained_tex(tex,
				Vector2(x, strip_y), ICON_SZ_LEGEND, ink))
		var wr := Control.new()
		wr.position = Vector2(x + ICON_SZ_LEGEND + LABEL_GAP, strip_y - 2)
		wr.size = Vector2(label_widths[i] + 4, ICON_SZ_LEGEND + 4)
		wr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(wr)
		var lb := Label.new()
		lb.text = label_text
		lb.set_anchors_preset(Control.PRESET_FULL_RECT)
		lb.add_theme_font_size_override("font_size", 14)
		lb.add_theme_color_override("font_color",
			Color(0.92, 0.85, 0.62))
		lb.add_theme_color_override("font_outline_color",
			Color(0, 0, 0, 0.95))
		lb.add_theme_constant_override("outline_size", 4)
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wr.add_child(lb)
		x += ICON_SZ_LEGEND + LABEL_GAP + label_widths[i] + ENTRY_GAP


# ═══════════════════════════════════════════
#  DECK VIEWER
# ═══════════════════════════════════════════

func _show_deck_viewer() -> void:
	var overlay = ColorRect.new()
	overlay.name = "DeckOverlay"
	overlay.color = Color(0.03, 0.02, 0.05, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var title = GameTheme.make_label(
		"YOUR DECK  (%d cards)" % RunState.deck.size(),
		GameTheme.FONT_HEADER, GameTheme.GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 20)
	title.size = Vector2(600, 40)
	overlay.add_child(title)

	var creatures := 0
	var spells := 0
	var rarity_counts := {"starter": 0, "common": 0, "uncommon": 0, "rare": 0}
	for card_id in RunState.deck:
		var cdata = CardDB.get_card_data(card_id)
		if cdata.is_empty():
			continue
		if cdata.get("type", "") == "creature":
			creatures += 1
		else:
			spells += 1
		var r = cdata.get("rarity", "common")
		if rarity_counts.has(r):
			rarity_counts[r] += 1

	var stats_bar = HBoxContainer.new()
	stats_bar.position = Vector2(80, 68)
	stats_bar.size = Vector2(1440, 28)
	stats_bar.add_theme_constant_override("separation", 32)
	overlay.add_child(stats_bar)

	var comp_items = [
		["Creatures: %d" % creatures, Color(0.55, 0.85, 0.55)],
		["Spells: %d" % spells, Color(0.55, 0.70, 0.95)],
		["|", Color(0.4, 0.35, 0.3)],
		["Common: %d" % rarity_counts["common"], Color(0.78, 0.75, 0.68)],
		["Uncommon: %d" % rarity_counts["uncommon"], Color(0.40, 0.75, 0.95)],
		["Rare: %d" % rarity_counts["rare"], Color(0.95, 0.78, 0.25)],
	]
	for item in comp_items:
		var sl = GameTheme.make_label(item[0], GameTheme.FONT_BODY, item[1])
		sl.add_theme_constant_override("outline_size", 3)
		sl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		stats_bar.add_child(sl)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(80, 100)
	scroll.size = Vector2(1440, 690)
	overlay.add_child(scroll)

	var grid = GridContainer.new()
	# 180-wide v4 cards × 7 cols + 6×12 separation = 1332 px, fits 1440 scroll.
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 22)
	scroll.add_child(grid)

	# Same batched-instantiation approach as the Card Gallery — defers
	# card creation across frames so opening the deck viewer doesn't
	# freeze the main thread. 6 per frame keeps the popup responsive
	# while filling top-down. static_display kills the per-frame costs
	# (pulse, shadows, rare halo) so once spawned the cards are cheap.
	var batch_size := 6
	for batch_start in range(0, RunState.deck.size(), batch_size):
		for k in range(batch_size):
			var i := batch_start + k
			if i >= RunState.deck.size():
				break
			var data = RunState.get_upgraded_card_data(i)
			var card = CARD_SCENE.instantiate()
			card.card_data = data.duplicate(true)
			card.card_id = data.get("id", "")
			card.is_on_battlefield = true
			card.static_display = true
			grid.add_child(card)
		await get_tree().process_frame

	var close_btn = GameTheme.make_themed_button("Close",
		Color(0.25, 0.20, 0.15), Vector2(120, 36))
	close_btn.position = Vector2(740, 800)
	close_btn.pressed.connect(func(): overlay.queue_free())
	overlay.add_child(close_btn)


func _on_node_pressed(row: int, col: int) -> void:
	if not _avail.has(Vector2i(row, col)):
		return
	RunState.visit_node(row, col)
	var ntype: String = RunState.current_node_type
	var target := ""
	match ntype:
		"combat", "elite", "boss": target = COMBAT_SCENE
		"shop": target = SHOP_SCENE
		"rest": target = REST_SCENE
		"event": target = EVENT_SCENE
	if target != "":
		var err = get_tree().change_scene_to_file(target)
		if err != OK:
			push_error("MapView: failed to load '%s' (error %d)"
				% [target, err])
