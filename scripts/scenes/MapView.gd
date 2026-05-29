extends Control
## MapView.gd — Slay-the-Spire-style procedural map, rendered horizontally
## (left → right). The player starts at the left under a START banner and
## climbs toward the boss icon at the right. The whole act fits comfortably
## in the viewport with a small amount of horizontal scrolling.

const COMBAT_SCENE = "res://scenes/combat.tscn"
const SHOP_SCENE = "res://scenes/shop.tscn"
const REST_SCENE = "res://scenes/rest.tscn"
const EVENT_SCENE = "res://scenes/event.tscn"
const TREASURE_SCENE = "res://scenes/treasure.tscn"
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

# ── Node rendering (embossed metal tokens — coin-like, beveled, stamped). ──
const ICON_SZ := 26.0
const BOSS_SZ := 46.0
const NODE_R := 25.0          # embossed token radius (normal node)
const BOSS_R := 42.0          # embossed token radius (boss node)
const HIT_R := 24.0
const BOSS_HIT := 38.0
const GLOW_R := 27.0
const BOSS_GLOW := 46.0

# ── Path line styling ──
# STS-style: dashed segments along a slightly wobbly path so the graph reads
# as a hand-drawn route on a parchment rather than a straight wire diagram.
const DASH_LEN := 9.0       # length of each visible dash
const DASH_GAP := 7.0       # gap between dashes
const WOBBLE_AMP := 3.5     # peak wobble offset perpendicular to the path

const ICON_KEY: Dictionary = {
	"combat": "sword", "elite": "skull", "boss": "crown",
	"rest": "campfire", "shop": "diamond", "event": "question",
	"treasure": "coins-pile",
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
	"treasure": Color(0.90, 0.75, 0.20),
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

# Per-act multiply tint applied to the painted base gradient behind the
# parchment — keeps Act 1 warm, cools Act 2 toward blue-grey, scorches Act 3.
const ACT_BG_TINT: Dictionary = {
	1: Color(1.00, 1.00, 1.00),
	2: Color(0.80, 0.88, 1.06),
	3: Color(1.12, 0.82, 0.72),
}

var _avail: Array = []
var _grain_tex: ImageTexture = null
var _hovered: Vector2i = Vector2i(-1, -1)
var _canvas_ref: Control = null
var _scroll: ScrollContainer = null
var _map_content_w: float = 0.0
var _map_content_h: float = 0.0


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	AudioBank.play_music("map")
	var bg = get_node_or_null("Background")
	if bg:
		bg.self_modulate = Color(0.10, 0.08, 0.06, 1.0)
	GameTheme.add_atmosphere(self, "map", false)
	_build_map()
	GameTheme.make_settings_gear(self)
	# Checkpoint: every return to the map captures post-room state (HP, gold,
	# deck changes, relics earned). Clear the room-in-progress fields first so a
	# later resume lands on the map rather than re-entering the room the player
	# just finished. visit_node still saves on entry, so a quit *during* a room
	# resumes back into that room.
	RunState.current_node_type = ""
	RunState.current_encounter_id = ""
	# Resolve any pending "choice" relics before saving so the picks persist:
	# Bottled Talisman bind (Event-granted catch-all + rebind), and the per-act
	# Totem Pole / Bone Hourglass choices.
	await _resolve_meta_pickers()
	RunState.save_run()


func _resolve_meta_pickers() -> void:
	# Bottled Talisman: catch-all bind. Reward/Shop/Treasure bind inline at
	# acquire; this covers Event-granted copies and rebinds if the bound card
	# was later removed. The helper no-ops when a valid binding already exists.
	if RunState.has_relic("bottled_talisman"):
		await GameTheme.bind_bottled_talisman(self)
	# Totem Pole: pick a keyword once per act.
	if RunState.has_relic("totem_pole") and RunState.totem_pole_act != RunState.get_act():
		var kw_opts := [
			{"label": "Thorns", "desc": "Friendlies deal 1 damage back when hit.",
				"color": Color(0.30, 0.45, 0.22)},
			{"label": "Swift", "desc": "Friendlies strike in the pre-combat Swift phase.",
				"color": Color(0.25, 0.40, 0.55)},
			{"label": "Regenerate", "desc": "Friendlies heal 1 HP at the start of each round.",
				"color": Color(0.45, 0.35, 0.20)},
			{"label": "Armored", "desc": "Friendlies take 1 less damage from each hit.",
				"color": Color(0.35, 0.35, 0.42)},
		]
		var kw_vals := ["thorns", "swift", "regenerate", "armored"]
		var pick: int = await GameTheme.show_option_picker(self,
			"Totem Pole — keyword for Act %d" % RunState.get_act(), kw_opts)
		if pick >= 0:
			RunState.totem_pole_keyword = kw_vals[pick]
			RunState.totem_pole_act = RunState.get_act()
	# Bone Hourglass: pick a ramp boon once per act.
	if RunState.has_relic("bone_hourglass") and RunState.bone_hourglass_act != RunState.get_act():
		var ramp_opts := [
			{"label": "Front Line", "desc": "+1 ATK to creatures you place in the front row.",
				"color": Color(0.45, 0.25, 0.20)},
			{"label": "Back Line", "desc": "+1 HP to creatures you place in the back row.",
				"color": Color(0.25, 0.35, 0.45)},
			{"label": "Mana Well", "desc": "+1 max mana while both center lanes are full.",
				"color": Color(0.35, 0.30, 0.50)},
		]
		var ramp_vals := ["front_atk", "back_hp", "mana_center"]
		var pick2: int = await GameTheme.show_option_picker(self,
			"Bone Hourglass — boon for Act %d" % RunState.get_act(), ramp_opts)
		if pick2 >= 0:
			RunState.bone_hourglass_choice = ramp_vals[pick2]
			RunState.bone_hourglass_act = RunState.get_act()


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

	# ── Painted base gradient (behind the parchment; parchment multiplies over
	# it so the paper picks up a warm-lit center corridor + toasted edges). ──
	var bg_canvas = Control.new()
	bg_canvas.name = "MapBG"
	bg_canvas.size = Vector2(_map_content_w, inner_h)
	bg_canvas.modulate = ACT_BG_TINT.get(RunState.get_act(), Color.WHITE)
	bg_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_canvas.draw.connect(_draw_map_bg.bind(bg_canvas))
	content.add_child(bg_canvas)
	bg_canvas.queue_redraw()

	# ── Parchment fiber, multiplied over the painted gradient — adds vellum
	# detail the math gradient can't fake. Brightened so MUL doesn't darken. ──
	var parch_tex: Texture2D = load("res://assets/backgrounds/map_parchment.jpg")
	var parch = TextureRect.new()
	parch.texture = parch_tex
	parch.size = Vector2(_map_content_w, inner_h)
	parch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	parch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	parch.modulate = Color(tints.parch.r * 1.25, tints.parch.g * 1.22,
		tints.parch.b * 1.16)
	parch.material = _mul_mat()
	parch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(parch)

	# ── Film grain over the paper for cohesion (subtle multiply). ──
	var grain = TextureRect.new()
	grain.texture = _get_grain()
	grain.size = Vector2(_map_content_w, inner_h)
	grain.stretch_mode = TextureRect.STRETCH_TILE
	grain.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	grain.material = _mul_mat()
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(grain)

	# ── Compute node + line geometry ──
	var nodes: Array = []
	var lines: Array = []
	var player_pos := Vector2.ZERO
	var player_key := Vector2i(-1, -1)
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
				"mutator_id": nd.get("mutator_id", ""),
			})
			if nd.visited:
				player_pos = pos
				player_key = Vector2i(nd.row, nd.col)
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
	canvas.set_meta("player_key", player_key)
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
	var player_key: Vector2i = canvas.get_meta("player_key", Vector2i(-1, -1))

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
		var mid_x: float = (ln.from.x + ln.to.x) * 0.5
		var is_focus: bool = ln.vis or ln.get("to_avail", false)
		var dist_fade: float = _proximity_fade(mid_x, focus_x, is_focus)
		# Stable per-segment seed so the wobble doesn't shift between frames.
		var seed_h: int = int(ln.from.x * 3.1 + ln.from.y * 7.3
			+ ln.to.x * 11.7 + ln.to.y * 5.9)
		var pts: PackedVector2Array = _wobble_pts(ln.from, ln.to, seed_h)
		if ln.vis:
			# Travelled road — confident solid brown ink with a soft halo.
			canvas.draw_polyline(pts,
				Color(0.16, 0.09, 0.04, 0.50 * dist_fade), 8.0, true)
			canvas.draw_polyline(pts,
				Color(0.30, 0.16, 0.07, dist_fade), 5.0, true)
		elif ln.get("to_avail", false):
			# Road to a reachable node — crimson "choose me" ink.
			canvas.draw_polyline(pts, Color(0.20, 0.06, 0.02, 0.45), 9.0, true)
			canvas.draw_polyline(pts, Color(0.82, 0.28, 0.12, 1.0), 6.0, true)
		else:
			# Roads beyond — dashed sepia, the classic "route ahead" map idiom.
			_draw_dashed_polyline(canvas, pts,
				Color(0.34, 0.21, 0.10, 0.9 * dist_fade), 3.6)

	# ── Node tokens (embossed metal coins with a stamped emblem) ──
	for nd in nodes:
		var typ: String = nd.type
		var tex = _icon_tex(ICON_KEY.get(typ, "question"))
		var pos: Vector2 = nd.pos
		var is_boss: bool = typ == "boss"
		var is_hov: bool = _hovered == nd.key
		var hov: float = 1.15 if is_hov else 1.0
		var r: float = (BOSS_R if is_boss else NODE_R) * hov
		var is_current: bool = has_player and nd.key == player_key
		var dim: bool = nd.vis and not is_current
		var avail: bool = nd.avail and not nd.vis

		# Enamel face colour (per node type), greyed when it's a spent node.
		var face: Color = NODE_INK.get(typ, Color(0.4, 0.4, 0.4))
		if dim:
			var grey: float = (face.r + face.g + face.b) / 3.0
			face = Color(lerpf(face.r, grey, 0.60), lerpf(face.g, grey, 0.60),
				lerpf(face.b, grey, 0.60))

		# Rim tone: bright gilt for the current/reachable tokens, plain bronze
		# for the road ahead, dull pewter for spent nodes.
		var rim_base := Color(0.50, 0.38, 0.20)
		var rim_light := Color(0.82, 0.66, 0.34)
		var rim_dark := Color(0.26, 0.18, 0.09)
		if avail or is_current:
			rim_base = Color(0.78, 0.60, 0.24)
			rim_light = Color(1.0, 0.88, 0.48)
			rim_dark = Color(0.46, 0.32, 0.12)
		elif dim:
			rim_base = Color(0.40, 0.36, 0.30)
			rim_light = Color(0.52, 0.48, 0.40)
			rim_dark = Color(0.24, 0.20, 0.16)

		var fr: float = _draw_token(canvas, pos, r, face,
			rim_base, rim_light, rim_dark, dim, not dim)

		# Stamped emblem — dark drop within the well + the icon raised on top,
		# tinted dark or cream for contrast against its enamel face.
		if tex:
			var isz: float = fr * (1.5 if is_boss else 1.38)
			var lum: float = 0.299 * face.r + 0.587 * face.g + 0.114 * face.b
			var itint := Color(0.10, 0.07, 0.05, 0.95) if lum > 0.5 \
				else Color(0.97, 0.93, 0.82, 0.96)
			if dim:
				itint.a = 0.70
			var rect := Rect2(pos - Vector2(isz, isz) * 0.5, Vector2(isz, isz))
			canvas.draw_texture_rect(tex,
				Rect2(rect.position + Vector2(1.5, 1.5), rect.size), false,
				Color(0, 0, 0, 0.30))
			canvas.draw_texture_rect(tex, rect, false, itint)

		if dim:
			_draw_check(canvas, pos, r)

		# Mutator star — a small asterisk above the token when the node carries
		# a per-fight modifier. Drawn AFTER the token so it stays legible.
		# Positive (gift) mutators read mint green; the common tax variants amber.
		var mut_id: String = String(nd.get("mutator_id", ""))
		if mut_id != "" and MutatorDB.exists(mut_id) and not nd.vis:
			var mut = MutatorDB.get_mutator(mut_id)
			var is_gift: bool = int(mut.get("gold_bonus", 0)) == 0
			var star_col := Color(0.55, 1.0, 0.70) if is_gift else Color(1.0, 0.62, 0.20)
			var star_pos: Vector2 = pos + Vector2(r * 0.36, -r * 0.5)
			var star_font: Font = GameTheme.font_display
			if star_font:
				var sfs: int = 22
				canvas.draw_string_outline(star_font,
					star_pos, "★", HORIZONTAL_ALIGNMENT_CENTER, -1, sfs, 4,
					Color(0, 0, 0, 0.95))
				canvas.draw_string(star_font,
					star_pos, "★", HORIZONTAL_ALIGNMENT_CENTER, -1, sfs,
					star_col)

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

## Hand-drawn cartographer's landmarks — an atmospheric mountain range along the
## top margin, a meandering river + lake along the bottom margin, clustered tree
## groves tucked into the margins, a compass rose, and a ruled chart border. The
## node band sits in the vertical center, so the top/bottom margins stay clear
## and the terrain never fights the icons. Deterministic per run + act.
func _draw_terrain(canvas: Control, nodes: Array) -> void:
	var w: float = _map_content_w
	var h: float = _map_content_h
	var band_top: float = _lane_y(0, h)
	var band_bot: float = _lane_y(RunState.MAP_WIDTH - 1, h)
	_draw_border_rule(canvas, w, h)
	_draw_mountains(canvas, w, band_top - 34.0)
	_draw_river(canvas, w, band_bot + 50.0)
	_draw_forest(canvas, w, h, band_top, band_bot, nodes)
	_draw_compass(canvas, h)


## Three receding ridges → atmospheric depth instead of one heavy brown band.
## Far is hazy/cool/low-contrast; near is warmer, taller, with subtle snow.
func _draw_mountains(canvas: Control, w: float, near_base_y: float) -> void:
	var s: int = int(RunState.run_seed) + RunState.get_act() * 7919
	_ridge(canvas, w, near_base_y - 30.0, 18.0, 40.0, 54.0, 84.0, s + 0x3A71,
		Color(0.62, 0.56, 0.48, 0.26), Color(0.56, 0.50, 0.42, 0.26), false)
	_ridge(canvas, w, near_base_y - 14.0, 34.0, 66.0, 64.0, 104.0, s + 0x6B23,
		Color(0.56, 0.47, 0.34, 0.52), Color(0.43, 0.34, 0.21, 0.54), false)
	_ridge(canvas, w, near_base_y, 46.0, 86.0, 78.0, 122.0, s + 0x9C17,
		Color(0.55, 0.44, 0.29, 0.82), Color(0.36, 0.27, 0.15, 0.84), true)


## A continuous, overlapping range. Peaks vary in height and overlap
## (advance < width) so the silhouette reads as a range, not a sawtooth of
## identical triangles. Each peak splits into a lit left face and a shadowed
## right face for consistent top-left lighting; no hard black outline.
func _ridge(canvas: Control, w: float, base_y: float, hmin: float, hmax: float,
		gmin: float, gmax: float, seed_v: int, lit: Color, shadow: Color,
		snow: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var x: float = -30.0
	while x < w + 50.0:
		var hh: float = rng.randf_range(hmin, hmax)
		var half: float = rng.randf_range(gmin, gmax) * 0.5
		var apex := Vector2(x + rng.randf_range(-half * 0.18, half * 0.18),
			base_y - hh)
		var mid := Vector2(x, base_y)
		var bl := Vector2(x - half, base_y)
		var br := Vector2(x + half, base_y)
		canvas.draw_colored_polygon(PackedVector2Array([bl, apex, mid]), lit)
		canvas.draw_colored_polygon(PackedVector2Array([apex, br, mid]), shadow)
		canvas.draw_line(bl, apex, lit.lightened(0.18), 1.2, true)
		if snow and hh > (hmin + hmax) * 0.52:
			var sn: float = hh * 0.16
			canvas.draw_colored_polygon(PackedVector2Array([apex,
				apex + Vector2(-sn * 0.7, sn), apex + Vector2(0.0, sn * 1.3),
				apex + Vector2(sn * 0.7, sn)]), Color(0.88, 0.84, 0.72, 0.72))
		x += rng.randf_range(gmin * 0.46, gmax * 0.58)


## A meandering river (Catmull-Rom through jittered waypoints) with a small
## lake — damp bank, water body, then a bright meltwater core so the brown
## palette gets a cool accent without a hard line.
func _draw_river(canvas: Control, w: float, base_y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(RunState.run_seed) + RunState.get_act() * 53 + 13
	var n: int = maxi(6, int(w / 230.0))
	var wp: Array = []
	for i in range(n + 1):
		wp.append(Vector2(float(i) / float(n) * w,
			base_y + rng.randf_range(-20.0, 20.0)))
	var ext: Array = [wp[0]]
	ext.append_array(wp)
	ext.append(wp[wp.size() - 1])
	var pts := PackedVector2Array()
	for i in range(1, ext.size() - 2):
		for sgn in range(14):
			pts.append(_catmull(ext[i - 1], ext[i], ext[i + 1], ext[i + 2],
				float(sgn) / 14.0))
	pts.append(wp[wp.size() - 1])
	var lake: Vector2 = wp[int(n * 0.5)]
	canvas.draw_polyline(pts, Color(0.40, 0.43, 0.36, 0.16), 24.0, true)
	canvas.draw_circle(lake, 30.0, Color(0.40, 0.43, 0.36, 0.16))
	canvas.draw_polyline(pts, Color(0.36, 0.55, 0.62, 0.42), 13.0, true)
	canvas.draw_circle(lake, 24.0, Color(0.36, 0.55, 0.62, 0.42))
	canvas.draw_polyline(pts, Color(0.66, 0.78, 0.80, 0.40), 4.0, true)
	canvas.draw_circle(lake, 14.0, Color(0.62, 0.74, 0.78, 0.38))


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## A few clustered groves tucked into the margins (alternating top/bottom),
## rather than an edge-to-edge band of identical trees (amateur "confetti").
## Any grove landing too near a node is skipped so icons stay clean.
func _draw_forest(canvas: Control, w: float, h: float, band_top: float,
		band_bot: float, nodes: Array) -> void:
	var node_pos := PackedVector2Array()
	for nd in nodes:
		node_pos.append(nd.pos)
	var count: int = maxi(3, int(w / 360.0))
	var rng := RandomNumberGenerator.new()
	for i in range(count):
		rng.seed = int(RunState.run_seed) + RunState.get_act() * 31 + i * 617
		var top_margin: bool = (i % 2) == 0
		var gx: float = (float(i) + 0.5) / float(count) * w \
			+ rng.randf_range(-50.0, 50.0)
		var gy: float = (band_top * 0.45) if top_margin \
			else lerpf(band_bot, h, 0.72)
		var ctr := Vector2(gx, gy)
		var too_close := false
		for np in node_pos:
			if ctr.distance_squared_to(np) < 64.0 * 64.0:
				too_close = true
				break
		if too_close:
			continue
		_grove(canvas, ctr, rng.randf_range(0.85, 1.1), int(rng.randi()))


func _grove(canvas: Control, ctr: Vector2, scale: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	# Soft canopy underglow so the cluster reads as one grove.
	for _k in range(6):
		var o := Vector2(rng.randf_range(-30.0, 30.0),
			rng.randf_range(-8.0, 8.0)) * scale
		canvas.draw_circle(ctr + o, rng.randf_range(13.0, 20.0) * scale,
			Color(0.27, 0.32, 0.17, 0.14))
	# Individual canopies, back-to-front by y for slight overlap depth.
	var trees: Array = []
	for _k in range(7):
		trees.append(ctr + Vector2(rng.randf_range(-32.0, 32.0),
			rng.randf_range(-6.0, 10.0)) * scale)
	trees.sort_custom(func(a, b): return a.y < b.y)
	for t in trees:
		_tree_glyph(canvas, t, rng.randf_range(12.0, 17.0) * scale)


func _tree_glyph(canvas: Control, base: Vector2, sz: float) -> void:
	# Conifer silhouette: two stacked tiers + a short trunk, soft-shaded.
	canvas.draw_line(base, base + Vector2(0, sz * 0.28),
		Color(0.26, 0.17, 0.09, 0.6), maxf(1.5, sz * 0.12), true)
	var lower := PackedVector2Array([
		base + Vector2(-sz * 0.5, 0.0),
		base + Vector2(0.0, -sz * 0.7),
		base + Vector2(sz * 0.5, 0.0)])
	var upper := PackedVector2Array([
		base + Vector2(-sz * 0.34, -sz * 0.4),
		base + Vector2(0.0, -sz * 1.05),
		base + Vector2(sz * 0.34, -sz * 0.4)])
	canvas.draw_colored_polygon(lower, Color(0.24, 0.30, 0.15, 0.62))
	canvas.draw_colored_polygon(upper, Color(0.30, 0.37, 0.19, 0.66))
	canvas.draw_line(base + Vector2(-sz * 0.34, -sz * 0.4),
		base + Vector2(0.0, -sz * 1.05), Color(0.42, 0.50, 0.28, 0.5), 1.0, true)


func _draw_compass(canvas: Control, h: float) -> void:
	var ctr := Vector2(86.0, h - 50.0)
	var rr := 30.0
	var ink := Color(0.32, 0.20, 0.09, 0.74)
	var ink2 := Color(0.30, 0.18, 0.08, 0.58)
	canvas.draw_arc(ctr, rr + 4.0, 0.0, TAU, 48, ink2, 1.0, true)
	canvas.draw_arc(ctr, rr, 0.0, TAU, 44, ink, 1.8, true)
	canvas.draw_arc(ctr, rr * 0.64, 0.0, TAU, 36, ink2, 1.2, true)
	canvas.draw_circle(ctr, 2.4, ink)
	for a in [-PI * 0.5, 0.0, PI * 0.5, PI]:
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		canvas.draw_colored_polygon(PackedVector2Array([
			ctr + dir * rr * 1.12, ctr + perp * rr * 0.15,
			ctr - perp * rr * 0.15]), ink)
	for a in [-PI * 0.75, -PI * 0.25, PI * 0.25, PI * 0.75]:
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		canvas.draw_colored_polygon(PackedVector2Array([
			ctr + dir * rr * 0.68, ctr + perp * rr * 0.11,
			ctr - perp * rr * 0.11]), ink2)


func _draw_border_rule(canvas: Control, w: float, h: float) -> void:
	var ink := Color(0.34, 0.22, 0.10, 0.5)
	var inset := 13.0
	var r := Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0)
	canvas.draw_rect(r, ink, false, 2.0)
	canvas.draw_rect(r.grow(-5.0), ink, false, 1.0)
	for cn in [r.position, Vector2(r.end.x, r.position.y),
			Vector2(r.position.x, r.end.y), r.end]:
		canvas.draw_colored_polygon(PackedVector2Array([
			cn + Vector2(0, -5), cn + Vector2(5, 0),
			cn + Vector2(0, 5), cn + Vector2(-5, 0)]), ink)


## Draws an embossed coin/token: soft shadow, beveled metal rim (lit from the
## top-left), a recessed well, and the colored enamel face. Returns the face
## radius so the caller can size the stamped icon.
func _draw_token(canvas: Control, pos: Vector2, r: float, face: Color,
		rim_base: Color, rim_light: Color, rim_dark: Color,
		dim: bool, gloss: bool) -> float:
	for k in range(4):
		canvas.draw_circle(pos + Vector2(2.5, 4.0), r + 1.0 + float(k) * 1.6,
			Color(0.10, 0.06, 0.03, 0.06 if not dim else 0.03))
	canvas.draw_circle(pos, r, Color(0.08, 0.06, 0.04))
	canvas.draw_circle(pos, r - 1.0, rim_base)
	var bw: float = maxf(2.5, r * 0.12)
	canvas.draw_arc(pos, r - 1.0 - bw * 0.5, deg_to_rad(168), deg_to_rad(288),
		28, rim_light, bw, true)
	canvas.draw_arc(pos, r - 1.0 - bw * 0.5, deg_to_rad(-12), deg_to_rad(108),
		28, rim_dark, bw, true)
	canvas.draw_circle(pos, r - bw - 2.0, Color(0.06, 0.05, 0.03))
	var fr: float = r - bw - 3.5
	canvas.draw_circle(pos, fr, face)
	canvas.draw_arc(pos, fr - 1.0, deg_to_rad(190), deg_to_rad(350), 24,
		Color(0, 0, 0, 0.22), maxf(2.0, fr * 0.16), true)
	canvas.draw_arc(pos, fr - 1.0, deg_to_rad(20), deg_to_rad(160), 24,
		Color(1, 1, 1, 0.10), maxf(1.5, fr * 0.10), true)
	if gloss:
		canvas.draw_circle(pos - Vector2(0, fr * 0.34), fr * 0.55,
			Color(1, 1, 1, 0.08))
	return fr


## Painted base gradient drawn behind the parchment: a warm lit corridor through
## the vertical-center node band, toasted at top/bottom, with a few warm pools
## spaced along the scroll length and an edge vignette. Tinted per act via the
## bg_canvas modulate (ACT_BG_TINT).
func _draw_map_bg(canvas: Control) -> void:
	var w: float = _map_content_w
	var h: float = _map_content_h
	var center_col := Color(0.91, 0.84, 0.65)
	var edge_col := Color(0.46, 0.35, 0.20)
	var bands: int = 80
	for i in range(bands):
		var t: float = float(i) / float(bands - 1)
		var d: float = absf(t - 0.5) * 2.0
		var k: float = pow(1.0 - d, 1.4)
		canvas.draw_rect(Rect2(0.0, t * h, w, h / float(bands) + 1.5),
			edge_col.lerp(center_col, k))
	var rng := RandomNumberGenerator.new()
	var pools: int = int(w / 460.0) + 2
	for i in range(pools):
		rng.seed = 7000 + i * 131
		var px: float = (float(i) + 0.5) * (w / float(pools)) \
			+ rng.randf_range(-60.0, 60.0)
		var py: float = h * 0.5 + rng.randf_range(-40.0, 40.0)
		for k in range(10):
			canvas.draw_circle(Vector2(px, py),
				lerpf(300.0, 30.0, float(k) / 9.0),
				Color(0.93, 0.86, 0.66, 0.05))
	var vig := Color(0.24, 0.16, 0.08, 0.10)
	for k in range(6):
		var ins: float = float(k) * 26.0
		canvas.draw_rect(Rect2(0, ins, w, 4.0), vig)
		canvas.draw_rect(Rect2(0, h - ins - 4.0, w, 4.0), vig)
		canvas.draw_rect(Rect2(ins, 0, 4.0, h), vig)
		canvas.draw_rect(Rect2(w - ins - 4.0, 0, 4.0, h), vig)


func _mul_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	return m


func _get_grain() -> ImageTexture:
	if _grain_tex == null:
		_grain_tex = _make_grain()
	return _grain_tex


func _make_grain() -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xBEEF
	for y in range(s):
		for x in range(s):
			var v: float = rng.randf_range(0.90, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


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
	# Mutator tag — surfaces "Stormy: enemies gain Swift" etc. so the player
	# can route around a fight they don't want without entering it first.
	var mut_id: String = String(node.get("mutator_id", ""))
	if mut_id != "" and MutatorDB.exists(mut_id):
		var mut: Dictionary = MutatorDB.get_mutator(mut_id)
		label += "\n★ %s: %s" % [mut.get("name", mut_id), mut.get("desc", "")]
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

	# Start AFTER the top-left settings gear (gear occupies x=14..62 from
	# GameTheme.make_settings_gear). Previously the heart icon started at
	# x=28, overlapping the right half of the gear and partially covering it.
	var x := 80.0
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
	for i in range(RunState.MAX_POTIONS):
		var pid: String = RunState.potions[i] if i < RunState.potions.size() else ""
		_place_potion_slot(pid, i, Vector2(px, ROW_Y), ICON)
		px += ICON + 4

	_place_deck_button(Vector2(px + 24, ROW_Y), ICON, ROW_H, FONT_SZ)


func _place_potion_slot(pid: String, index: int, top_left: Vector2, sz: float) -> void:
	# Empty slot: shaded placeholder icon, not clickable.
	if pid == "":
		_place_painted_icon(GameTheme.tex_hud_potion, top_left, sz,
			Color(0.45, 0.40, 0.35, 0.45))
		return
	var data: Dictionary = PotionDB.get_potion(pid)
	var icon: Texture2D = PotionDB.icon_for(pid)
	var tint: Color = data.get("color", Color.WHITE) if not data.is_empty() else Color.WHITE
	# Drop shadow + icon, same render as other HUD chips.
	_place_painted_icon(icon, top_left, sz, tint)
	# Invisible button overlay handles clicks + tooltip.
	var btn := Button.new()
	btn.flat = true
	btn.position = top_left
	btn.size = Vector2(sz, sz)
	var usable_in: String = data.get("usable_in", "combat")
	var map_usable: bool = usable_in == "map" or usable_in == "both"
	var label: String = "%s\n%s" % [data.get("name", pid), data.get("desc", "")]
	if not map_usable:
		label += "\n(Combat use only)"
	btn.tooltip_text = label
	if map_usable:
		btn.pressed.connect(func():
			_use_map_potion(index)
		)
	add_child(btn)


func _use_map_potion(index: int) -> void:
	var pid: String = RunState.potions[index] if index < RunState.potions.size() else ""
	if pid == "":
		return
	var data: Dictionary = PotionDB.get_potion(pid)
	var effect: String = data.get("effect", "")
	match effect:
		"heal_hp":
			RunState.consume_potion(index)
			RunState.heal_hero(8)
		_:
			# Combat-only effects shouldn't even be wired up here, but be safe.
			return
	_build_map()


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
	var banner_text := "Act %d  ·  Boss Ahead: %s" % \
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
	# 225-wide cards at compact scale (0.483) × 7 cols + 6×18 separation = ~870 px, fits 1440 scroll.
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

	var close_btn = GameTheme.make_back_button("CLOSE", Vector2(140, 40))
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
		"treasure": target = TREASURE_SCENE
	if target != "":
		GameTheme.fade_out_then_change_scene(self, target, 0.30)
