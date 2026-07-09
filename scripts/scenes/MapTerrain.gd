extends Control

# ── MAP TERRAIN — the campaign-map renderer (real geography: Sicily) ────────
# The act map drawn as a chart of a real island at local scale: the boss
# domain IS the volcano, the Ash March its lava country, the strait + mainland
# sliver anchor the world. Antique-chart furniture (waterline rings, shoal
# stipple, graticule, hachures, harbour marks); roads carved into the plate
# (incised groove: NW rim shadow / SE lit rim). Per-act dressing: palette
# tint, terrain reseed, scorch radius.
# Pipeline: jittered Voronoi mesh → land from the real coast polygon
# (noise-ragged) → elevation = BFS-from-coast × noise + anchored massifs →
# journey carve → rivers → biomes → hillshade → provinces/politics.
#
# This file is RENDER-ONLY and draws once (static plate). The live map screen
# is MapView.gd, which extends this and layers interaction + HUD on top.
# Render sandbox: scenes/map_proto.tscn via tools/screenshot/_probe_map_proto.
# The earlier procedural-island version of this renderer is preserved at
# tools/screenshot/MapProto_v5_procedural.gd.bak.

const OCEAN_DEEP := Color(0.045, 0.075, 0.095)
const OCEAN_SHALLOW := Color(0.085, 0.150, 0.165)
const COAST_INK := Color(0.02, 0.03, 0.03, 0.85)
const RIVER_COL := Color(0.110, 0.190, 0.205, 0.95)
const PLAYER_AMBER := Color(0.85, 0.64, 0.26)
const CRIMSON := Color(0.62, 0.15, 0.10)
const FOAM := Color(0.55, 0.62, 0.60)
# Warm chart-paper base. The land is rendered as an AGED MAP (high value, low
# saturation), not a saturated relief sim — biomes only tint this a step so the
# atmosphere light pool has clean paper to fall on. Was muddy mid-tones per cell
# (the "kid drew it" tell); the figure/ground now comes from light, not hue.
const CHART_PAPER := Color(0.760, 0.638, 0.430)

const CELL := 20.0            # mesh spacing (px) — fine mesh for chart detail
const MARGIN_L := 300.0
const MARGIN_R := 380.0
const MARGIN_T := 225.0
const MARGIN_B := 205.0

# ── Real-geography plate: Sicily, equirectangular lon/lat → px ──
const GEO_LON0 := 12.25
const GEO_LAT0 := 38.62
const GEO_KX := 460.0         # px per degree longitude
const GEO_KY := 415.0         # px per degree latitude
const GEO_OX := 150.0
const GEO_OY := 95.0

# Hand-traced, simplified Sicily coastline (lon, lat), clockwise from Capo
# Peloro (NE tip). Recognisable beats precise — the Voronoi cells re-rag it.
const SICILY_LL := [
	Vector2(15.650, 38.265), Vector2(15.570, 38.190), Vector2(15.520, 38.020),
	Vector2(15.400, 37.800), Vector2(15.220, 37.620), Vector2(15.155, 37.510),
	Vector2(15.210, 37.400), Vector2(15.295, 37.340), Vector2(15.300, 37.210),
	Vector2(15.225, 37.060), Vector2(15.160, 36.920), Vector2(15.135, 36.690),
	Vector2(14.930, 36.720), Vector2(14.500, 36.790), Vector2(14.360, 37.000),
	Vector2(14.250, 37.060), Vector2(13.940, 37.100), Vector2(13.580, 37.250),
	Vector2(13.270, 37.390), Vector2(13.080, 37.490), Vector2(12.860, 37.570),
	Vector2(12.660, 37.560), Vector2(12.420, 37.790), Vector2(12.470, 37.910),
	Vector2(12.500, 38.010), Vector2(12.630, 38.110), Vector2(12.730, 38.170),
	Vector2(12.900, 38.030), Vector2(13.050, 38.040), Vector2(13.300, 38.200),
	Vector2(13.370, 38.115), Vector2(13.540, 38.110), Vector2(13.710, 38.030),
	Vector2(13.990, 38.040), Vector2(14.270, 38.080), Vector2(14.630, 38.100),
	Vector2(14.740, 38.160), Vector2(14.900, 38.190), Vector2(15.070, 38.150),
	Vector2(15.240, 38.310), Vector2(15.330, 38.220), Vector2(15.500, 38.270),
]

# Calabria's toe across the strait — bleeds off the chart's east edge. The
# strait is widened ~0.06° so it survives cell quantisation.
const CALABRIA_LL := [
	Vector2(15.740, 38.620), Vector2(15.740, 38.300), Vector2(15.755, 38.230),
	Vector2(15.760, 38.100), Vector2(15.800, 37.950), Vector2(15.940, 37.920),
	Vector2(16.100, 37.930), Vector2(16.200, 38.050), Vector2(16.400, 38.200),
	Vector2(16.500, 38.620),
]

# Offshore islands: (lon, lat, radius px). Aeolians NE, Egadi W.
const ISLES_LLR := [
	Vector3(14.960, 38.400, 12.0),   # Vulcano
	Vector3(14.950, 38.475, 14.0),   # Lipari
	Vector3(14.830, 38.560, 11.0),   # Salina
	Vector3(12.320, 37.920, 13.0),   # Favignana
	Vector3(12.340, 38.005, 9.0),    # Levanzo
	Vector3(12.060, 37.970, 11.0),   # Marettimo
]

# Anchored massifs: (lon, lat) + strength + radius px. Etna is the boss seat;
# the north-coast chain (Peloritani→Nebrodi→Madonie) frames the upper road.
const MASSIFS := [
	[Vector2(14.995, 37.751), 1.05, 105.0],   # Etna
	[Vector2(14.580, 37.900), 0.88, 130.0],   # Nebrodi
	[Vector2(14.020, 37.875), 0.90, 110.0],   # Madonie
	[Vector2(15.300, 38.100), 0.86, 80.0],    # Peloritani
	[Vector2(13.400, 37.620), 0.66, 100.0],   # Sicani
	[Vector2(14.300, 37.470), 0.45, 90.0],    # Erei
	[Vector2(14.880, 37.020), 0.62, 95.0],    # Hyblaean hills
]

# Cells: parallel arrays (faster + simpler than dict-per-cell at this count).
var _seed_pts: PackedVector2Array = PackedVector2Array()
var _polys: Array[PackedVector2Array] = []
var _nbrs: Array[PackedInt32Array] = []
var _land: Array[bool] = []
var _region: PackedInt32Array = PackedInt32Array()  # 0 sea, 1 sicily, 2 mainland, 3 isle
var _elev: PackedFloat32Array = PackedFloat32Array()
var _moist: PackedFloat32Array = PackedFloat32Array()
var _biome: PackedInt32Array = PackedInt32Array()   # see B_* enum below
var _prov: PackedInt32Array = PackedInt32Array()    # node index, -1 = none
var _zone: PackedInt32Array = PackedInt32Array()    # rival realm 0-2, -1 = none
var _shade: PackedFloat32Array = PackedFloat32Array()
var _grad: PackedVector2Array = PackedVector2Array()   # uphill gradient (hachures)
var _road_d: PackedFloat32Array = PackedFloat32Array() # px to nearest road
var _wdepth: PackedInt32Array = PackedInt32Array()     # water hops from land
var _gx := 0
var _gy := 0

# Screen-space geography (built in _build_geo).
var _poly_sicily: PackedVector2Array = PackedVector2Array()
var _poly_calabria: PackedVector2Array = PackedVector2Array()
var _isles: Array = []        # {pos: Vector2, r: float}
var _etna_peak := Vector2.ZERO
var _sicily_centroid := Vector2.ZERO
# SIMPLE_BACKDROP staging: the deckled paper sheet the chart is drawn on
# (built per act in _build_simple_coast; empty in the full painted mode).
var _sheet_poly: PackedVector2Array = PackedVector2Array()

enum { B_DEEP, B_SHALLOW, B_BEACH, B_GRASS, B_FOREST, B_HILLS, B_ROCK,
	B_SNOW, B_SCORCH }

var _rivers: Array[PackedVector2Array] = []
var _nodes: Array = []      # {pos, type, vis, avail, encounter_id}
var _edges: Array = []      # {a, b, from_vis, to_vis, to_avail}
var _edge_curves: Array[PackedVector2Array] = []   # terrain-bent road curves
var _bridges: Array = []    # {pos: Vector2, dirv: Vector2}
var _labels: Array = []     # {pos, text, size, crimson}
var _boss_name: String = ""
var _boss_pos := Vector2.ZERO
var _camp_pos := Vector2.ZERO
var _player_pos := Vector2.ZERO
var _has_player := false
var _island_center := Vector2.ZERO
var _island_rad := Vector2.ONE
var _rng := RandomNumberGenerator.new()
# MapView's animated overlay replaces the static player standard; the
# render-only sandbox (map_proto.tscn) leaves this false.
var overlay_handles_standard := false

# ── View transform (zoom & pan) ──────────────────────────────────────────
# Every plate layer draws through this transform — the chart can be leaned
# into like a real table map. Wheel zooms toward the cursor, dragging pans
# (any mouse button; only when zoomed in). The screen furniture (_draw_ui
# cartouche/legend/counters) resets to identity and stays put. MapView
# focuses the view on the army standard when the map opens; the sandbox
# keeps the full-island view until scrolled.
const VIEW_ZOOM_MIN := 1.0
const VIEW_ZOOM_MAX := 2.4
# The zoom band where the plate changes DRESS (the Paradox map-mode move —
# never show the strategic theater and the decision ladder at full strength
# together). Zoomed in past HI = march dress: roads, chips, your claimed
# amber, quiet ground. Zoomed out past LO = campaign dress: rival dyes,
# province borders, kingdom names, chart furniture. Crossfaded between.
const DRESS_ZOOM_LO := 1.10
const DRESS_ZOOM_HI := 1.30
var _view_zoom := 1.0
var _view_pan := Vector2.ZERO
var _view_drag := false
var _view_drag_last := Vector2.ZERO
var _last_dress_mix := -1.0

# ── Plate item + bakes + per-act cache ───────────────────────────────────
# Three layers of structure keep the map fast (the plate used to lag both
# on every scroll AND as a constant per-frame GPU replay of thousands of
# primitives):
#  1. The whole plate is painted on _plate_item, a child canvas item that
#     re-records ONLY when content changes. Zoom and pan just move its
#     transform — view changes cost ~zero script time.
#  2. Two offscreen 2× bakes collapse the plate to ONE textured quad:
#     the GEOGRAPHY (ocean/terrain/coast/rivers/decorations — constant per
#     act, ~22k primitives) bakes once per act and is cached; the COMPLETE
#     plate (geo quad + the campaign ink: political wash, roads, chips,
#     keep/camp, labels) bakes once per OPEN — ink depends on claims, and
#     a few thousand live AA ink commands cost ~12ms of GPU replay every
#     frame if left vector. While bakes are in flight the vector path
#     still paints, so the map is never blank.
#  3. The generated mesh + geo texture park per act in
#     RunState.map_plate_cache: only the FIRST open of an act pays
#     generation + geo bake; later opens restore in a frame, and their
#     plate bake re-records ink over the cached quad in a few frames.
# The pipeline is fully seeded (run map + act), so clones bake
# pixel-identical plates.
const PLATE_BAKE_SCALE := 2.5
var _plate_item = null   # untyped: typed Control fails on script-only members
var _paper_item = null   # live paper-fiber multiply layer (war-table mode)
var _vignette_tex: GradientTexture2D = null   # lazy lamplight vignette
var _geo_tex: ImageTexture = null     # per act, cached in RunState
var _march_tex: ImageTexture = null   # per open — the clean march dress
var _plate_tex: ImageTexture = null   # campaign dress; stale copy cache-seeded
var _plate_bake_pending := false
var _bake_gen := 0
# "" = the live map · "geo" = clone baking geography only · "plate" = clone
# baking the complete plate (geo quad + ink). Clones never bake or draw UI.
var bake_mode := ""

signal plate_baked   # fired when the per-open bake lands (or fails) —
                     # MapView gates the opening focus ease on it so the
                     # ease never plays over heavy frames


var _act := 1
# Successor Wars skin — the kingdom this act invades, resolved from the run's
# rival deal in build_map(). Empty/neutral on legacy saves and in the render
# sandbox (map_proto.tscn), where every surface keeps the old war-crimson
# dressing. Resolved once per build: this is static-plate state, never
# re-read per frame (the animated overlay stays faction-blind).
var _faction_id := ""
var _faction_name := ""
var _faction_color: Color = CRIMSON

# The three act keeps (lon/lat) — each rival lord's seat, and the anchor the
# island's realm partition is carved around. Shared by _read_run_map (camp →
# keep march legs) and _assign_zones (nearest-seat kingdom zones).
# The grain-country keep sits a step inland: on the coast the lane clamp
# compressed act 3's opening chips onto their own camp.
const KEEP_LLS := [Vector2(13.58, 37.88), Vector2(14.26, 37.32),
	Vector2(14.90, 37.66)]
# Authored waypoints (lon/lat) winding each act's march between camp and keep.
# The legs sweep through the island's country instead of cutting the crow
# line — that lengthens the road under the 12-row ladder by ~50%, which is
# what gives the sites room to read as separate stops.
const LEG_WAYPOINTS := [
	[Vector2(12.90, 37.62), Vector2(13.30, 37.55), Vector2(13.66, 37.66)],
	[Vector2(13.98, 37.72), Vector2(14.52, 37.55), Vector2(14.48, 37.40)],
	[Vector2(14.62, 37.12), Vector2(14.95, 37.27), Vector2(15.05, 37.50)],
]
# Perpendicular spacing between adjacent map columns on the lane grid.
const LANE_W := 52.0
# ── Simple chart mode ────────────────────────────────────────────────────
# The map as a clean war-table: nodes on a fixed grid, dead-straight roads,
# and a calm flat-parchment backdrop (faint inked coast + Etna only) instead
# of the full painted island. The path graph is ALREADY no-crossing by
# construction (RunState._would_cross); the old winding-spine layout warped
# that clean ladder into visual tangles. This renders the ladder straight.
# Flip to false to restore the painted-geography campaign chart (all the
# generation still runs and caches — only what gets PAINTED changes).
const SIMPLE_BACKDROP := true
var _spine_pts: PackedVector2Array = PackedVector2Array()
var _spine_cum: PackedFloat32Array = PackedFloat32Array()
# The run's three rival realms over those seats, resolved per build by
# _resolve_kingdoms(): {name, color, centroid, state} where state is
# "taken" (acts already won — wears your gold), "front" (this act), or
# "future". Empty on legacy runs with no rival deal — no realm overlay.
var _kingdoms: Array = []


func _ready() -> void:
	await get_tree().process_frame
	build_map()


func _gui_input(event: InputEvent) -> void:
	# Chart navigation. Site buttons sit on top and consume their own clicks,
	# so a drag that starts on open plate can never fire a site; wheel events
	# bubble up from the buttons (Button doesn't consume scroll).
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.18)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.18)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT,
				MOUSE_BUTTON_MIDDLE]:
			_view_drag = event.pressed and _view_zoom > 1.001
			_view_drag_last = event.position
	elif event is InputEventMouseMotion and _view_drag:
		_set_view(_view_zoom, _view_pan + event.position - _view_drag_last)
		_view_drag_last = event.position


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var nz := clampf(_view_zoom * factor, VIEW_ZOOM_MIN, VIEW_ZOOM_MAX)
	if is_equal_approx(nz, _view_zoom):
		return
	# Keep the plate point under the cursor fixed while the scale changes.
	var world := (screen_pos - _view_pan) / _view_zoom
	_set_view(nz, screen_pos - world * nz)


func _set_view(z: float, pan: Vector2) -> void:
	_view_zoom = clampf(z, VIEW_ZOOM_MIN, VIEW_ZOOM_MAX)
	# pan ≤ 0 and ≥ size·(1-z): the scaled plate always covers the canvas, so
	# zooming can never expose void past an edge.
	var lim := size * (1.0 - _view_zoom)
	_view_pan = Vector2(clampf(pan.x, lim.x, 0.0), clampf(pan.y, lim.y, 0.0))
	# View changes only move the plate item's transform — nothing re-records
	# EXCEPT a dress-mix change, which re-records the (2-3 quad) plate item
	# so the campaign layer's crossfade alpha tracks the zoom.
	if _plate_item != null:
		_plate_item.position = _view_pan
		_plate_item.scale = Vector2(_view_zoom, _view_zoom)
		if _paper_item != null:
			_paper_item.position = _view_pan
			_paper_item.scale = Vector2(_view_zoom, _view_zoom)
		var mix := _campaign_mix()
		if not is_equal_approx(mix, _last_dress_mix):
			_last_dress_mix = mix
			_plate_item.queue_redraw()
	_on_view_changed()


## 0 = pure march dress (zoomed in, the default), 1 = full campaign dress
## (zoomed out to the war table). Crossfaded across the DRESS_ZOOM band.
func _campaign_mix() -> float:
	return clampf((DRESS_ZOOM_HI - _view_zoom) / (DRESS_ZOOM_HI - DRESS_ZOOM_LO),
		0.0, 1.0)


## Which dress the VECTOR ink path paints (bake clones pin theirs; the live
## fallback — cold opens, failed readbacks — picks the nearer dress).
func _ink_campaign() -> bool:
	if bake_mode == "plate":
		return true
	if bake_mode == "march":
		return false
	return _campaign_mix() > 0.5


func _on_view_changed() -> void:
	pass   # MapView re-seats its site buttons here.


func build_map() -> void:
	# Shared by the render sandbox (map_proto.tscn) and the live map screen.
	# Draws once into a static plate; dynamic UI lives in child controls.
	if bake_mode == "":
		# Bake clones keep their hand-set 1600×900 size — full-rect anchors
		# inside the 2× SubViewport would balloon them to the viewport rect.
		set_anchors_preset(Control.PRESET_FULL_RECT)
	# Mipmapped sampling so the baked plate stays calm when panned at 1×
	# (2× texture minified without mips would shimmer). Vectors unaffected.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_act = clampi(RunState.get_act(), 1, 3)
	_resolve_faction()
	_rng.seed = 1207 + _act * 101
	# _read_run_map rebuilds these by APPENDING on every open; on a fresh instance
	# they start empty, but clearing here stops a hypothetical second build_map() on
	# a live instance from doubling them (and the per-node button/province work that
	# scales with _nodes.size()). The cache-managed mesh arrays are reassigned wholesale
	# by _mesh_restore, so they don't need this.
	_nodes.clear()
	_edges.clear()
	_build_geo()
	if _plate_item == null:
		# The plate's own canvas item: drawn behind the root item so the
		# screen-fixed UI band (root _draw) stays on top of the chart.
		_plate_item = PlateItem.new()
		_plate_item.map = self
		_plate_item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_plate_item.show_behind_parent = true
		# A zero-size Control gets CULLED whenever its transform isn't
		# identity (custom draws ignore size, the renderer's rect cull
		# doesn't) — give it the real plate rect.
		_plate_item.size = size
		add_child(_plate_item)
	if _paper_item == null and bake_mode == "" and SIMPLE_BACKDROP:
		# Real paper fiber multiplied LIVE over the baked plate — texture is
		# the one material cue vector fills can't fake. Live only: a full-
		# rect alpha layer bakes OPAQUE in the clone path (the 2026-06-29
		# gotcha), and riding the view transform means the grain scales like
		# real fiber when the player leans in. Canvas MUL blend is a raw
		# SRC·DST (modulate can only darken it further), so strength comes
		# from a shader lerping the fiber toward white.
		var ptex: Texture2D = load("res://assets/backgrounds/map_parchment.jpg")
		if ptex != null:
			var paper := TextureRect.new()
			paper.texture = ptex
			paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			paper.stretch_mode = TextureRect.STRETCH_SCALE
			paper.size = size
			paper.show_behind_parent = true
			paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pshader := Shader.new()
			pshader.code = """
shader_type canvas_item;
render_mode blend_mul;
uniform float strength : hint_range(0.0, 1.0) = 0.45;
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(mix(vec3(1.0), t.rgb, strength), 1.0);
}
"""
			var pmat := ShaderMaterial.new()
			pmat.shader = pshader
			paper.material = pmat
			add_child(paper)
			_paper_item = paper
	# Per-act cache: every open after the first restores the mesh + baked
	# geography in one frame; only run state (vis/avail/player) is re-read.
	var cache: Dictionary = RunState.map_plate_cache.get(_act, {})
	if cache.has("mesh"):
		_mesh_restore(cache.mesh)
		_read_run_map()
		_resolve_kingdoms()
		_derive_terrain_tags()
		_geo_tex = cache.get("geo", null)
		# Last open's campaign plate: at most one visit stale, which only
		# shows for the ~150ms until this open's bakes land — a silent hold,
		# never a pop.
		_plate_tex = cache.get("plate_prev", null)
		_redraw_plate()
		if bake_mode == "":
			_ensure_plate_bake()
		return
	_read_run_map()
	_build_mesh()
	_assign_land()
	_assign_elevation()
	_carve_rivers()
	_assign_moisture_biomes()
	_assign_provinces()
	_assign_zones()
	_compute_hillshade()
	_build_roads()
	_place_labels()
	_resolve_kingdoms()
	_derive_terrain_tags()
	_redraw_plate()
	if bake_mode != "":
		return
	RunState.map_plate_cache[_act] = {"mesh": _mesh_snapshot()}
	_ensure_plate_bake()


## Content changed (build, bake landing, state flip) — re-record the plate
## item and the root UI band. View changes never come through here.
func _redraw_plate() -> void:
	if _plate_item != null:
		_plate_item.queue_redraw()
	queue_redraw()


## Everything the generation pipeline computes that is constant for the act.
## Run state (_nodes/_edges vis·avail, player/camp/boss) is NOT here — it is
## re-read on every open. References are shared with the cache, not copied:
## nothing mutates these after build (draw code only reads them), and
## _edge_curves stays index-paired with the deterministically rebuilt _edges.
func _mesh_snapshot() -> Dictionary:
	return {"seed_pts": _seed_pts, "polys": _polys, "nbrs": _nbrs,
		"land": _land, "region": _region, "elev": _elev, "moist": _moist,
		"biome": _biome, "prov": _prov, "zone": _zone, "shade": _shade,
		"grad": _grad, "road_d": _road_d, "wdepth": _wdepth, "gx": _gx,
		"gy": _gy, "rivers": _rivers, "edge_curves": _edge_curves,
		"bridges": _bridges, "labels": _labels}


func _mesh_restore(m: Dictionary) -> void:
	_seed_pts = m.seed_pts
	_polys.assign(m.polys)
	_nbrs.assign(m.nbrs)
	_land.assign(m.land)
	_region = m.region
	_elev = m.elev
	_moist = m.moist
	_biome = m.biome
	_prov = m.prov
	_zone = m.zone
	_shade = m.shade
	_grad = m.grad
	_road_d = m.road_d
	_wdepth = m.wdepth
	_gx = m.gx
	_gy = m.gy
	_rivers.assign(m.rivers)
	_edge_curves.assign(m.edge_curves)
	_bridges = m.bridges
	_labels = m.labels


## The per-open bake chain (live map only). Ensures the act's geography
## texture exists (baking + caching it on the act's first open), bakes the
## MARCH plate (geo + decision ink — the dress the map opens in; this is
## what gates MapView's opening ease), then bakes the CAMPAIGN plate in the
## background for the zoomed-out dress. The campaign texture is also cached
## per act so the next open can hold a one-visit-stale dressed island during
## its own bake instead of popping. Fire-and-forget coroutine; any failed
## readback leaves the (correct, just slower) vector path in place, and
## plate_baked fires in every outcome so MapView's gate can't hang.
func _ensure_plate_bake() -> void:
	_bake_gen += 1
	var gen := _bake_gen
	_plate_bake_pending = true
	if _geo_tex == null:
		var g: ImageTexture = await _bake_via_clone("geo")
		# A node commit during the bake frees MapView (and us) — bail before
		# touching our own members/signals on a freed instance.
		if not is_inside_tree():
			return
		if gen == _bake_gen and g != null:
			_geo_tex = g
			if RunState.map_plate_cache.has(_act):
				RunState.map_plate_cache[_act]["geo"] = g
			_redraw_plate()
	if gen == _bake_gen:
		var m: ImageTexture = await _bake_via_clone("march")
		if not is_inside_tree():
			return
		if gen == _bake_gen and m != null:
			_march_tex = m
			_redraw_plate()
	if gen == _bake_gen:
		_plate_bake_pending = false
	plate_baked.emit()
	if gen == _bake_gen:
		var p: ImageTexture = await _bake_via_clone("plate")
		if not is_inside_tree():
			return
		if gen == _bake_gen and p != null:
			_plate_tex = p
			if RunState.map_plate_cache.has(_act):
				RunState.map_plate_cache[_act]["plate_prev"] = p
			_redraw_plate()


## Render this map once through an offscreen clone in a 2× SubViewport and
## return the readback as a mipmapped texture (null on failure). The clone
## hits the mesh/geo cache, so its build is cheap; "geo" mode paints the
## geography layers only, "plate" mode paints geo (quad if cached) + ink.
func _bake_via_clone(mode: String) -> ImageTexture:
	# A zero/tiny plate (the first frames of an embedded F5 window, before the
	# stretch canvas has sized us) would make a 0×0 SubViewport whose render-
	# target readback is undefined — skip the bake and let the vector path
	# paint until we have a real rect.
	if size.x < 4.0 or size.y < 4.0:
		return null
	var sub := SubViewport.new()
	sub.size = Vector2i(size * PLATE_BAKE_SCALE)
	sub.disable_3d = true
	# DISABLED while the clone builds and records its canvas (CanvasItem _draw
	# is CPU-side and runs regardless of target update mode), then flipped to
	# UPDATE_ONCE below for a single GPU render right before readback. The old
	# UPDATE_ALWAYS re-rendered this (size × 2.5) target on every one of the
	# wait frames — ~5 full-res GPU passes per bake, ×3 bakes per map open.
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var clone: Control = (load("res://scripts/scenes/MapTerrain.gd")
		as GDScript).new()
	clone.bake_mode = mode
	# Without this the "plate" clone would bake a STATIC standard under the
	# live overlay's animated one (geo mode never reaches _draw_camp).
	clone.overlay_handles_standard = overlay_handles_standard
	clone.size = size
	sub.add_child(clone)
	add_child(sub)
	# canvas_transform MUST be set AFTER the SubViewport enters the tree: only
	# on enter does its canvas attach to its viewport. Setting it earlier makes
	# the RenderingServer reject the call ("!viewport->canvas_map.has(p_canvas)")
	# — Godot re-applies the stored value on enter so the bake still scaled, but
	# the rejected call spammed an error on every single map open.
	sub.canvas_transform = Transform2D().scaled(
		Vector2(PLATE_BAKE_SCALE, PLATE_BAKE_SCALE))
	# Clone _ready waits a frame, builds, paints the frame after — wait those
	# out (plus margin), then read the render target back.
	for _i in 4:
		await get_tree().process_frame
		# If the scene changed mid-bake we (and our child SubViewport) are
		# freed — stop before the next get_tree() errors on a freed node.
		if not is_inside_tree():
			return null
	# The clone's canvas is fully recorded by now — render it exactly once.
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or not is_instance_valid(sub):
		return null
	# Guard the readback: a SubViewport whose render target never came up (a
	# possibility in the embedded editor's shared GL context) returns a null
	# texture — calling get_image() on that would hard-crash the whole game.
	var vp_tex: Texture2D = sub.get_texture()
	if vp_tex == null:
		sub.queue_free()
		return null
	var img: Image = vp_tex.get_image()
	sub.queue_free()
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The kingdom this act marches into, off the run's rival deal. Legacy saves
## and the sandbox have no deal — get_act_faction() returns "" there and the
## plate keeps its neutral dressing (must never crash without run data).
func _resolve_faction() -> void:
	_faction_id = ""
	_faction_name = ""
	_faction_color = CRIMSON
	var fid: String = RunState.get_act_faction()
	if fid == "" or not HeroDB.FACTIONS.has(fid):
		return
	var info: Dictionary = HeroDB.faction_info(fid)
	_faction_id = fid
	_faction_name = String(info.get("name", "")).to_upper()
	_faction_color = info.get("color", CRIMSON)


## The rival's banner color as dyed cloth: desaturated a step and deepened so
## it sits in the plate's earth palette instead of floating as a pure hue.
## Falls back to the old war-crimson when no kingdom rules the act.
func _banner_color() -> Color:
	if _faction_id == "":
		return CRIMSON
	var g := (_faction_color.r + _faction_color.g + _faction_color.b) / 3.0
	return Color(lerpf(g, _faction_color.r, 0.85) * 0.92,
		lerpf(g, _faction_color.g, 0.85) * 0.92,
		lerpf(g, _faction_color.b, 0.85) * 0.92)


## The same dye thinned into a political wash — desaturated, darkened and
## translucent, so the invaded kingdom reads clearly as HIS land while the
## antique plate still shows through. (Was 0.13 alpha — too shy to read as
## territory; the player asked for kingdoms they can actually see flip.)
func _faction_wash() -> Color:
	return _realm_wash(_faction_color, 0.20)


## A banner dye thinned into a territory wash — desaturated a step and
## darkened so a kingdom tints the plate without flooding the terrain art.
func _realm_wash(col: Color, a: float) -> Color:
	var g := (col.r + col.g + col.b) / 3.0
	return Color(lerpf(g, col.r, 0.62) * 0.90,
		lerpf(g, col.g, 0.62) * 0.90,
		lerpf(g, col.b, 0.62) * 0.90, a)


## The island carved into the run's three rival realms (the player asked for
## unclaimed land to wear ALL the kingdoms' colors, not just the active
## front's). Whole zones flip to your gold once their act is won — the
## conquest spreads across the chart march by march.
func _resolve_kingdoms() -> void:
	_kingdoms = []
	if RunState.act_faction.size() < 3 or _zone.is_empty():
		return
	for a in range(3):
		var fid := String(RunState.act_faction[a])
		if not HeroDB.FACTIONS.has(fid):
			_kingdoms = []   # broken deal — all realms or none
			return
		var info: Dictionary = HeroDB.faction_info(fid)
		var cen := Vector2.ZERO
		var n := 0
		for i in range(_zone.size()):
			if _zone[i] == a:
				cen += _seed_pts[i]
				n += 1
		var state := "front"
		if a < _act - 1:
			state = "taken"
		elif a > _act - 1:
			state = "future"
		_kingdoms.append({"name": String(info.get("name", "")).to_upper(),
			"color": info.get("color", CRIMSON) as Color,
			"centroid": cen / maxf(float(n), 1.0), "state": state})


# ═══════════════════ GEOGRAPHY ═══════════════════

func _geo(lon: float, lat: float) -> Vector2:
	return Vector2(GEO_OX + (lon - GEO_LON0) * GEO_KX,
		GEO_OY + (GEO_LAT0 - lat) * GEO_KY)


func _build_geo() -> void:
	_poly_sicily = PackedVector2Array()   # append-built — see _build_mesh
	_poly_calabria = PackedVector2Array()
	_isles = []
	for v in SICILY_LL:
		_poly_sicily.append(_geo(v.x, v.y))
	for v2 in CALABRIA_LL:
		_poly_calabria.append(_geo(v2.x, v2.y))
	for v3 in ISLES_LLR:
		_isles.append({"pos": _geo(v3.x, v3.y), "r": v3.z})
	_etna_peak = _geo(14.995, 37.751)
	var cen := Vector2.ZERO
	for pv in _poly_sicily:
		cen += pv
	_sicily_centroid = cen / float(_poly_sicily.size())


func _inside_island(p: Vector2, inset: float = 0.0) -> bool:
	# Inside the Sicily polygon, with an approximate inward inset tested by
	# probing 8 compass directions — keeps sites off the surf line.
	if not Geometry2D.is_point_in_polygon(p, _poly_sicily):
		return false
	if inset <= 0.0:
		return true
	for k in range(8):
		var ang := TAU * float(k) / 8.0
		if not Geometry2D.is_point_in_polygon(
				p + Vector2(cos(ang), sin(ang)) * inset, _poly_sicily):
			return false
	return true


## Inside the pinned sheet, with an approximate inward inset (4 compass
## probes — the sheet is near-rectangular, so 4 suffice where the ragged
## island needs 8). Always true when no sheet exists (full painted mode).
func _inside_sheet(p: Vector2, inset: float = 0.0) -> bool:
	if _sheet_poly.size() < 3:
		return true
	if not Geometry2D.is_point_in_polygon(p, _sheet_poly):
		return false
	if inset <= 0.0:
		return true
	for k in range(4):
		var ang := TAU * float(k) / 4.0
		if not Geometry2D.is_point_in_polygon(
				p + Vector2(cos(ang), sin(ang)) * inset, _sheet_poly):
			return false
	return true


func _clamp_into_island(p: Vector2, inset: float = 26.0) -> Vector2:
	var q := p
	for _i in range(28):
		if _inside_island(q, inset):
			return q
		q = q.lerp(_sicily_centroid, 0.07)
	return q


func _perp_extent(base: Vector2, dirv: Vector2) -> float:
	# Contiguous on-island distance from `base` along `dirv`, inset from the
	# surf — measures the usable cross-spine band for lane fanning.
	var d := 0.0
	while d < 240.0 and _inside_island(base + dirv * (d + 10.0), 30.0):
		d += 10.0
	return d


## Catmull-Rom spine through camp → authored waypoints → keep, sampled dense
## and arc-length tabulated. Deterministic (no rng) — node stations re-derive
## identically on every open, which the per-act plate cache relies on.
func _build_spine(camp: Vector2, keep: Vector2) -> void:
	var ctrl: Array[Vector2] = [camp]
	for wp in LEG_WAYPOINTS[clampi(_act - 1, 0, 2)]:
		var wv: Vector2 = wp
		ctrl.append(_clamp_into_island(_geo(wv.x, wv.y), 30.0))
	ctrl.append(keep)
	_spine_pts = PackedVector2Array()
	for si in range(ctrl.size() - 1):
		var p0: Vector2 = ctrl[maxi(si - 1, 0)]
		var p1: Vector2 = ctrl[si]
		var p2: Vector2 = ctrl[si + 1]
		var p3: Vector2 = ctrl[mini(si + 2, ctrl.size() - 1)]
		for k in range(14):
			var t: float = float(k) / 14.0
			var pt: Vector2 = ((p1 * 2.0) + (p2 - p0) * t \
				+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * (t * t) \
				+ (p1 * 3.0 - p0 - p2 * 3.0 + p3) * (t * t * t)) * 0.5
			# Safety clamp: the curve can belly off-island between two
			# clamped controls hugging a coast.
			_spine_pts.append(_clamp_into_island(pt, 20.0))
	_spine_pts.append(keep)
	_spine_cum = PackedFloat32Array()
	_spine_cum.append(0.0)
	var run := 0.0
	for i in range(1, _spine_pts.size()):
		run += _spine_pts[i - 1].distance_to(_spine_pts[i])
		_spine_cum.append(run)


## March direction at arc-distance d — central difference over the spine.
func _spine_tangent(d: float) -> Vector2:
	var top: float = _spine_cum[_spine_cum.size() - 1]
	var a: Vector2 = _route_arc_point(_spine_pts, _spine_cum, maxf(d - 8.0, 0.0))
	var b: Vector2 = _route_arc_point(_spine_pts, _spine_cum, minf(d + 8.0, top))
	var v: Vector2 = b - a
	return v.normalized() if v.length() > 0.001 else Vector2.RIGHT


# ═══════════════════ RUN DATA ═══════════════════

func _read_run_map() -> void:
	var act_map: Array = RunState.get_current_act_map()
	if act_map.is_empty():
		return
	var avail: Array[Vector2i] = []
	for n in RunState.get_available_nodes():
		avail.append(Vector2i(n.row, n.col))
	var total_rows: int = act_map.size()
	# The war sweeps the island — one leg per act, and each act's camp is
	# pitched where the last keep fell: west landing → a keep in the northern
	# passes (act 1) → down through the southern grain country (act 2) → up
	# into the lava country at Etna's foot (act 3). Keeps are clamped well
	# inland so the boss pin never lands in the surf.
	var act_i: int = clampi(_act - 1, 0, 2)
	var camp: Vector2 = _geo(12.55, 37.72) if act_i == 0 else \
		_clamp_into_island(_geo(KEEP_LLS[act_i - 1].x, KEEP_LLS[act_i - 1].y), 34.0)
	var keep: Vector2 = _clamp_into_island(
		_geo(KEEP_LLS[act_i].x, KEEP_LLS[act_i].y), 34.0)
	# The path graph is already no-crossing by construction
	# (RunState._would_cross). How it gets LAID OUT decides whether that clean
	# ladder reads or tangles.
	var pos_lut: Dictionary = {}
	var row0: Array = []   # {pos, avail, vis} — for camp trails
	var entries: Array = []
	if SIMPLE_BACKDROP:
		# Clean war-table ladder: rows march left→right (camp→keep), columns
		# are a FIXED vertical lane grid (col 3 = the centre line). No winding
		# spine, no min-spacing relaxation, no coast clamp — so the graph's
		# own no-crossing guarantee carries straight to the screen, untangled.
		# cy sits below the canvas midline and the lane pitch is trimmed so the
		# top lane clears the act cartouche + standing-order chip and the bottom
		# lane clears the legend band — at the old 0.49/0.118 the outer lanes
		# ran straight through both.
		var cy: float = size.y * 0.535
		camp = Vector2(size.x * 0.075, cy)
		keep = Vector2(size.x * 0.80, cy)
		# Etna looms EAST of the keep, out past the last row — geography is
		# abstracted in this mode, and the story reads west→east: you land on
		# the western shore and march inland toward the volcano country. Beside
		# the keep it also can never collide with a top-lane stop (its old
		# above-the-gate seat sat right on lane 0).
		_etna_peak = Vector2(size.x * 0.905, size.y * 0.315)
		var lane_h: float = size.y * 0.100
		for ri in range(total_rows):
			for nd in act_map[ri]:
				var gt: float = float(nd.row) / float(maxi(total_rows - 1, 1))
				var gp := Vector2(lerpf(size.x * 0.17, keep.x, gt),
					cy + (float(nd.col) - 3.0) * lane_h)
				# Deterministic scatter: unstiffens the grid the way StS
				# staggers its floors — ±8px x / ±7px y is ~10% of the
				# ~84/100px pitches, organic to the eye but far too small to
				# reorder or cross a lane. (Was ±5/±3 — the tighter jitter
				# still read as a drafting board once the roads straightened.)
				var gh: int = nd.row * 31 + nd.col * 47
				gp += Vector2(fmod(float(gh * 13 + 5), 16.0) - 8.0,
					fmod(float(gh * 7 + 3), 14.0) - 7.0)
				if String(nd.type) == "boss":
					gp = keep
				entries.append({"pos": gp, "nd": nd})
	else:
		# The march SPINE is a winding road, not the crow line. Rows sit at
		# equal arc-length stations along it; lanes are a fixed perpendicular
		# grid (col 3 = the spine itself). Straight legs ran ~430px for 12
		# rows and the relaxation pass wove the chips into a cluster — the
		# legacy painted-campaign layout.
		_build_spine(camp, keep)
		var total_len: float = _spine_cum[_spine_cum.size() - 1]
		var pad_a: float = minf(78.0, total_len * 0.11)
		var pad_b: float = 112.0   # the keep's forecourt — walls + plaque need air
		var span: float = total_len - pad_a - pad_b
		# Pass 1 — every site at its row's arc station, offset to its lane. The
		# lane grid compresses where the island narrows (perp extent capped).
		for ri in range(total_rows):
			for nd in act_map[ri]:
				var t: float = float(nd.row) / float(total_rows - 1)
				var d: float = pad_a + span * t
				var base: Vector2 = _route_arc_point(_spine_pts, _spine_cum, d)
				var tang: Vector2 = _spine_tangent(d)
				var perp: Vector2 = tang.orthogonal()
				var en: float = _perp_extent(base, -perp)
				var ep: float = _perp_extent(base, perp)
				var foff: float = clampf((float(nd.col) - 3.0) * LANE_W,
					-en * 0.88, ep * 0.88)
				# Hash jitter, small: enough to unstiffen the grid, never enough
				# to reorder rows or weave lanes.
				var hsh: int = nd.row * 31 + nd.col * 47
				var j_a: float = fmod(float(hsh * 13 + 5), 20.0) - 10.0
				var j_p: float = fmod(float(hsh * 7 + 3), 16.0) - 8.0
				var p: Vector2 = base + tang * j_a + perp * (foff + j_p)
				if String(nd.type) == "boss":
					p = keep
				else:
					p = _clamp_into_island(p)
				entries.append({"pos": p, "nd": nd})
		# Pass 2 — minimum-spacing relaxation so chips never overlap (boss
		# pinned to the keep; everything stays clamped on the island).
		for _it in range(6):
			for ai in range(entries.size()):
				for bi in range(ai + 1, entries.size()):
					var ea: Dictionary = entries[ai]
					var eb: Dictionary = entries[bi]
					var dv := (eb.pos as Vector2) - (ea.pos as Vector2)
					var dl := dv.length()
					if dl < 50.0 and dl > 0.01:
						var push := dv.normalized() * (50.0 - dl) * 0.5
						if String((ea.nd as Dictionary).type) != "boss":
							ea.pos = _clamp_into_island((ea.pos as Vector2) - push)
						if String((eb.nd as Dictionary).type) != "boss":
							eb.pos = _clamp_into_island((eb.pos as Vector2) + push)
	# Pass 3 — commit positions.
	var vis_lut: Dictionary = {}   # (row,col) → visited, for edge to_vis
	for ent in entries:
		var nd: Dictionary = ent.nd
		var p: Vector2 = ent.pos
		pos_lut[Vector2i(nd.row, nd.col)] = p
		vis_lut[Vector2i(nd.row, nd.col)] = bool(nd.visited)
		_nodes.append({"pos": p, "type": String(nd.type),
			"vis": bool(nd.visited),
			"avail": avail.has(Vector2i(nd.row, nd.col)),
			"encounter_id": String(nd.get("encounter_id", "")),
			"row": int(nd.row), "col": int(nd.col),
			"mutator_id": String(nd.get("mutator_id", "")),
			"terrain": String(nd.get("terrain", "")),
			"bridge": bool(nd.get("bridge", false)),
			"wayside_id": String(nd.get("wayside_id", ""))})
		if nd.row == 0:
			row0.append({"pos": p, "vis": bool(nd.visited),
				"avail": avail.has(Vector2i(nd.row, nd.col))})
		if bool(nd.visited):
			_player_pos = p
			_has_player = true
		if String(nd.type) == "boss":
			_boss_pos = p
			var enc: Dictionary = EncounterDB.get_encounter(
				String(nd.get("encounter_id", "")))
			_boss_name = String(enc.get("name", "THE WARDEN")).to_upper()
	for ri2 in range(total_rows - 1):
		for nd2 in act_map[ri2]:
			var a: Vector2 = pos_lut[Vector2i(nd2.row, nd2.col)]
			for tc in nd2.connections:
				var tk := Vector2i(nd2.row + 1, int(tc))
				if pos_lut.has(tk):
					_edges.append({"a": a, "b": pos_lut[tk],
						"from_vis": bool(nd2.visited),
						"to_vis": bool(vis_lut.get(tk, false)),
						"to_avail": bool(nd2.visited) and avail.has(tk)})
	_camp_pos = camp
	# Camp trails: the journey starts AT the camp, not floating beside it.
	# These ride the normal edge pipeline (valley carve, terrain bend, state
	# tint) — marched once its start node is visited, amber while available.
	for r0 in row0:
		# Camp legs: the army "came from" the camp, so the leg to a visited
		# row-0 site is marched ink (from_vis true by construction).
		_edges.append({"a": _camp_pos, "b": r0.pos,
			"from_vis": true, "to_vis": bool(r0.vis),
			"to_avail": bool(r0.avail)})
	# Island footprint from everything that must be on land.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for ndd in _nodes:
		lo = lo.min(ndd.pos)
		hi = hi.max(ndd.pos)
	lo = lo.min(_camp_pos)
	hi = hi.max(_camp_pos)
	_island_center = (lo + hi) * 0.5
	_island_rad = (hi - lo) * 0.5 + Vector2(120.0, 105.0)
	if SIMPLE_BACKDROP:
		_build_simple_coast()


## SIMPLE_BACKDROP coastline — the island is drawn AROUND the campaign, not
## the campaign squeezed onto real geography. A convex hull over every stop
## (plus the camp and Etna's foot) is inflated into a rounded landmass and its
## outline re-sampled with seeded noise into a hand-drawn, deckled coast — so
## every stop stands on land BY CONSTRUCTION (the old fixed grid dropped whole
## lanes into the sea) and each act's chart is its own stretch of country.
## Deterministic per act (hash-free of open state): the mesh cache re-derives
## an identical coast on every open and every bake clone.
func _build_simple_coast() -> void:
	if _nodes.is_empty():
		return
	var anchors := PackedVector2Array()
	for nd in _nodes:
		anchors.append(nd.pos)
	anchors.append(_camp_pos)
	# Etna's footprint — the volcano must stand on the same landmass.
	anchors.append(_etna_peak + Vector2(-118.0, 62.0))
	anchors.append(_etna_peak + Vector2(120.0, 68.0))
	anchors.append(_etna_peak + Vector2(6.0, -44.0))
	var hull := Geometry2D.convex_hull(anchors)
	# +96 not +86: the smoothing passes below sag inward ~12px at the
	# tightest rounded corners; the margin covers it so no stop ever sits
	# closer than ~48px to the surf.
	var grown: Array = Geometry2D.offset_polygon(hull, 96.0,
		Geometry2D.JOIN_ROUND)
	if grown.is_empty():
		return   # degenerate field — keep the traced island
	var base: PackedVector2Array = grown[0]
	# Arc-length resample first.
	var cum := PackedFloat32Array()
	cum.append(0.0)
	var total := 0.0
	for i in range(1, base.size()):
		total += base[i - 1].distance_to(base[i])
		cum.append(total)
	total += base[base.size() - 1].distance_to(base[0])
	var closed := base.duplicate()
	closed.append(base[0])
	var ccum := cum.duplicate()
	ccum.append(total)
	var n_pts := maxi(int(total / 22.0), 32)
	var pts := PackedVector2Array()
	for k in range(n_pts):
		pts.append(_route_arc_point(closed, ccum,
			total * float(k) / float(n_pts)))
	# Heavy smoothing: the inflated hull's corner arcs become LONG CONFIDENT
	# CURVES — a drawn line, not a computed one. (Uniform-frequency wobble was
	# the loudest "procedural" tell on the old coast.)
	for _pass in range(3):
		var sm := PackedVector2Array()
		sm.resize(n_pts)
		for i2 in range(n_pts):
			sm[i2] = (pts[(i2 - 1 + n_pts) % n_pts] + pts[i2] * 2.0
				+ pts[(i2 + 1) % n_pts]) / 4.0
		pts = sm
	# Then displacement the way a hand lays a coast: 3-5 broad headlands and
	# bays (low-frequency swell) over a barely-there waviness. Noise sampled
	# on a circle, so the loop closes with no seam-step.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 5207 + _act * 131
	noise.frequency = 1.0
	var cen := Vector2.ZERO
	for v in pts:
		cen += v
	cen /= float(n_pts)
	var out := PackedVector2Array()
	for k2 in range(n_pts):
		var th := TAU * float(k2) / float(n_pts)
		var p := pts[k2]
		var outward := (p - cen).normalized()
		var swell: float = noise.get_noise_2d(cos(th) * 1.35 + 7.0,
			sin(th) * 1.35) * 42.0
		var wave: float = noise.get_noise_2d(cos(th) * 11.0 + 53.0,
			sin(th) * 11.0) * 4.5
		var d := maxf(swell + wave, -34.0)
		var q := p + outward * d
		# Clamped WELL inside the canvas: the island must stay on the pinned
		# SHEET (inset 28 + deckle) with room for the waterline rings (+25).
		out.append(Vector2(clampf(q.x, 60.0, size.x - 60.0),
			clampf(q.y, 58.0, size.y - 58.0)))
	_poly_sicily = out
	# The sheet itself — the deckled paper rectangle the chart is drawn on,
	# pinned to the war table. Rect inset 28, edges wobbled a hair (paper
	# deckle, far quieter than the coastline's).
	_sheet_poly = PackedVector2Array()
	var ins := 28.0
	var c0 := Vector2(ins, ins)
	var c1 := Vector2(size.x - ins, ins)
	var c2 := Vector2(size.x - ins, size.y - ins)
	var c3 := Vector2(ins, size.y - ins)
	var edges: Array = [[c0, c1], [c1, c2], [c2, c3], [c3, c0]]
	var s_run := 0.0
	for ed in edges:
		var ea: Vector2 = ed[0]
		var eb: Vector2 = ed[1]
		var elen := ea.distance_to(eb)
		var en := int(elen / 30.0)
		var nrm := (eb - ea).normalized().orthogonal()
		for kk in range(en):
			var t := float(kk) / float(en)
			var sp := ea.lerp(eb, t)
			var wob: float = noise.get_noise_1d((s_run + t * elen) * 0.05
				+ 731.0) * 4.5
			_sheet_poly.append(sp + nrm * wob)
		s_run += elen
	_poly_calabria = PackedVector2Array()
	# Two quiet decorative islets west of the landing — chart interest, never
	# gameplay. The coast is generated, so each candidate is kept only when it
	# clears the deckled outline with real water around it.
	_isles = []
	for cand in [[Vector2(size.x * 0.036, size.y * 0.150), 11.0],
			[Vector2(size.x * 0.033, size.y * 0.800), 14.0]]:
		var ip: Vector2 = cand[0]
		var ir: float = cand[1]
		if Geometry2D.is_point_in_polygon(ip, _poly_sicily):
			continue
		var clear := true
		for pv2 in _poly_sicily:
			if pv2.distance_to(ip) < ir + 34.0:
				clear = false
				break
		if clear:
			_isles.append({"pos": ip, "r": ir})
	cen = Vector2.ZERO
	for pv in _poly_sicily:
		cen += pv
	_sicily_centroid = cen / float(_poly_sicily.size())


# ═══════════════════ MESH ═══════════════════

func _build_mesh() -> void:
	# Rebuild from empty: these are append-built, and a second cold build on
	# a live instance (nothing does this today, but probes have) would double
	# the mesh and desync every index-paired array after it.
	_seed_pts = PackedVector2Array()
	_polys = []
	_nbrs = []
	var w: float = size.x
	var h: float = size.y
	_gx = int(ceil(w / CELL)) + 2
	_gy = int(ceil(h / CELL)) + 2
	for gy in range(_gy):
		for gx in range(_gx):
			var base := Vector2((float(gx) - 0.5) * CELL,
				(float(gy) - 0.5) * CELL)
			_seed_pts.append(base + Vector2(
				_rng.randf_range(-0.38, 0.38) * CELL,
				_rng.randf_range(-0.38, 0.38) * CELL))
	var count := _seed_pts.size()
	_polys.resize(count)
	_nbrs.resize(count)
	for i in range(count):
		var gx2 := i % _gx
		var gy2 := i / _gx
		var nb := PackedInt32Array()
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := gx2 + dx
				var ny := gy2 + dy
				if nx >= 0 and nx < _gx and ny >= 0 and ny < _gy:
					nb.append(ny * _gx + nx)
		_nbrs[i] = nb
		# Voronoi cell ≈ clip against grid neighbours only.
		var poly := PackedVector2Array([
			_seed_pts[i] + Vector2(-CELL * 1.6, -CELL * 1.6),
			_seed_pts[i] + Vector2(CELL * 1.6, -CELL * 1.6),
			_seed_pts[i] + Vector2(CELL * 1.6, CELL * 1.6),
			_seed_pts[i] + Vector2(-CELL * 1.6, CELL * 1.6)])
		for j in nb:
			poly = _clip_halfplane(poly, _seed_pts[i], _seed_pts[j])
			if poly.size() < 3:
				break
		_polys[i] = poly


func _clip_halfplane(poly: PackedVector2Array, a: Vector2,
		b: Vector2) -> PackedVector2Array:
	var n := b - a
	var mid := (a + b) * 0.5
	var out := PackedVector2Array()
	var cnt := poly.size()
	for i in range(cnt):
		var p := poly[i]
		var q := poly[(i + 1) % cnt]
		var fp := n.dot(p - mid)
		var fq := n.dot(q - mid)
		if fp <= 0.0:
			out.append(p)
			if fq > 0.0:
				out.append(p.lerp(q, fp / (fp - fq)))
		elif fq <= 0.0:
			out.append(p.lerp(q, fp / (fp - fq)))
	return out


func _shared_edge(i: int, j: int) -> PackedVector2Array:
	# Vertices of cell i lying on the i/j bisector = the border segment.
	var n := _seed_pts[j] - _seed_pts[i]
	var mid := (_seed_pts[i] + _seed_pts[j]) * 0.5
	var hits := PackedVector2Array()
	for v in _polys[i]:
		if absf(n.dot(v - mid)) < 0.8:
			hits.append(v)
	return hits


# ═══════════════════ TERRAIN FIELDS ═══════════════════

func _assign_land() -> void:
	# Land = the real coast polygons, noise-jittered so the Voronoi coastline
	# stays ragged and hand-drawn instead of tracing the source line exactly.
	var noise := FastNoiseLite.new()
	noise.seed = 9341 + _act * 77   # per-act coast raggedness
	noise.frequency = 0.012
	var count := _seed_pts.size()
	_land.resize(count)
	_region.resize(count)
	for i in range(count):
		var p := _seed_pts[i]
		var jit := Vector2(noise.get_noise_2dv(p) * 11.0,
			noise.get_noise_2dv(p + Vector2(913.0, 311.0)) * 11.0)
		var pp := p + jit
		var reg := 0
		if Geometry2D.is_point_in_polygon(pp, _poly_sicily):
			reg = 1
		elif Geometry2D.is_point_in_polygon(pp, _poly_calabria):
			reg = 2
		else:
			for isle in _isles:
				var dr: float = p.distance_to(isle.pos)
				var r_eff: float = float(isle.r) \
					* (0.85 + 0.5 * (noise.get_noise_2dv(p) + 1.0) * 0.5)
				if dr < r_eff + 7.0:
					reg = 3
					break
		_region[i] = reg
		_land[i] = reg > 0
	# Everything gameplay-critical is land (node cells + their neighbours).
	var musts: Array[Vector2] = [_camp_pos]
	for nd in _nodes:
		musts.append(nd.pos)
	for m in musts:
		var ci := _cell_at(m)
		if ci >= 0:
			_land[ci] = true
			_region[ci] = 1
			for j in _nbrs[ci]:
				_land[j] = true
				_region[j] = 1


func _cell_at(p: Vector2) -> int:
	var gx := clampi(int(round(p.x / CELL + 0.5)), 0, _gx - 1)
	var gy := clampi(int(round(p.y / CELL + 0.5)), 0, _gy - 1)
	var best := -1
	var best_d := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := gx + dx
			var ny := gy + dy
			if nx < 0 or nx >= _gx or ny < 0 or ny >= _gy:
				continue
			var idx := ny * _gx + nx
			var d := _seed_pts[idx].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = idx
	return best


func _assign_elevation() -> void:
	# BFS hop-distance from the sea; normalise; noise-modulate.
	var count := _seed_pts.size()
	_elev.resize(count)
	_road_d.resize(count)
	_road_d.fill(99999.0)
	var dist := PackedInt32Array()
	dist.resize(count)
	dist.fill(-1)
	var queue: Array[int] = []
	for i in range(count):
		if not _land[i]:
			dist[i] = 0
			queue.append(i)
	var head := 0
	var maxd := 1
	while head < queue.size():
		var c := queue[head]
		head += 1
		for j in _nbrs[c]:
			if dist[j] == -1:
				dist[j] = dist[c] + 1
				maxd = maxi(maxd, dist[j])
				queue.append(j)
	var noise := FastNoiseLite.new()
	noise.seed = 5512 + _act * 77   # per-act relief variation
	noise.frequency = 0.007
	# Macro noise breaks the "snow spine" artifact: pure distance-from-coast
	# always ridges along the island's long axis; multiplying by a very low
	# frequency field sinks parts of the interior so ranges become massifs.
	var macro := FastNoiseLite.new()
	macro.seed = 7733 + _act * 77
	macro.frequency = 0.0016
	for i2 in range(count):
		if not _land[i2]:
			_elev[i2] = 0.0
			continue
		var base := pow(float(dist[i2]) / float(maxd), 1.05)
		var nz := (noise.get_noise_2dv(_seed_pts[i2]) + 1.0) * 0.5
		var mz := (macro.get_noise_2dv(_seed_pts[i2]) + 1.0) * 0.5
		# Macro range kept moderate — fully binary highlands produce one
		# island-dominating massif instead of distinct framing ranges.
		var e := clampf(base * (0.62 + 0.76 * nz) * (0.52 + 0.82 * mz),
			0.0, 1.0)
		# Real ranges: anchored gaussian massifs (Etna, the north-coast
		# chain, the southern hills) on top of the generic relief. The core
		# weight also shields the range from the journey carve below.
		var massif_core := 0.0
		for ms in MASSIFS:
			var mp := _geo((ms[0] as Vector2).x, (ms[0] as Vector2).y)
			var md := _seed_pts[i2].distance_to(mp)
			var mr := float(ms[2])
			if md < mr * 2.4:
				e = maxf(e, float(ms[1]) * exp(-(md * md) / (mr * mr)))
				massif_core = maxf(massif_core,
					exp(-(md * md) / pow(mr * 0.62, 2.0)))
		e = clampf(e, 0.0, 1.0)
		# Carve the journey: terrain sinks toward the route corridor, so the
		# road network runs through a valley system and the ranges frame the
		# path instead of sitting on top of it. Massif cores resist the
		# carve — where a road meets a range it reads as a mountain pass,
		# not a deleted mountain.
		var road_d := INF
		for ed in _edges:
			road_d = minf(road_d,
				_dist_to_seg(_seed_pts[i2], ed.a, ed.b))
		_road_d[i2] = road_d
		var carved := e * (0.30 + 0.78 * clampf(road_d / 95.0, 0.0, 1.0))
		_elev[i2] = lerpf(carved, e, clampf(massif_core * 1.1, 0.0, 0.85))
	# Water depth (hops from the nearest land) — drives the ocean's depth
	# banding and the shoal stipple along the coasts.
	_wdepth.resize(count)
	_wdepth.fill(99)
	var wq: Array[int] = []
	for iw in range(count):
		if _land[iw]:
			continue
		for jw in _nbrs[iw]:
			if _land[jw]:
				_wdepth[iw] = 1
				wq.append(iw)
				break
	var whead := 0
	while whead < wq.size():
		var wc := wq[whead]
		whead += 1
		for jw2 in _nbrs[wc]:
			if not _land[jw2] and _wdepth[jw2] > _wdepth[wc] + 1:
				_wdepth[jw2] = _wdepth[wc] + 1
				wq.append(jw2)
	# Offshore islets are one BFS hop from the sea everywhere, which leaves
	# them near-black — floor their elevation so they render as real ground.
	for ii in range(count):
		if _land[ii] and _region[ii] == 3:
			_elev[ii] = maxf(_elev[ii], 0.30)


func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Chaikin corner-cutting — turns a raw mesh-walk polyline into a confident
## drawn stroke (endpoints pinned). Used for the river INK only; gameplay
## reads (bridge detection, moisture) stay on the raw points.
func _chaikin(pts: PackedVector2Array, passes: int) -> PackedVector2Array:
	var cur := pts
	for _p in range(passes):
		if cur.size() < 3:
			return cur
		var out := PackedVector2Array()
		out.append(cur[0])
		for i in range(cur.size() - 1):
			out.append(cur[i].lerp(cur[i + 1], 0.25))
			out.append(cur[i].lerp(cur[i + 1], 0.75))
		out.append(cur[cur.size() - 1])
		cur = out
	return cur


func _carve_rivers() -> void:
	# Two springs on high ground, each descending to the sea.
	_rivers.clear()   # append-built — see _build_mesh
	var count := _seed_pts.size()
	var springs: Array[int] = []
	var tries := 0
	while springs.size() < 2 and tries < 400:
		tries += 1
		var i := _rng.randi_range(0, count - 1)
		if not _land[i] or _region[i] != 1 or _elev[i] < 0.55:
			continue
		if _boss_pos != Vector2.ZERO \
				and _seed_pts[i].distance_to(_boss_pos) < 240.0:
			continue
		var ok := true
		for s in springs:
			if _seed_pts[s].distance_to(_seed_pts[i]) < 260.0:
				ok = false
		if ok:
			springs.append(i)
	for s2 in springs:
		var path := PackedVector2Array()
		var cur := s2
		var guard := 0
		var seen: Dictionary = {}
		while _land[cur] and guard < 260:
			guard += 1
			path.append(_seed_pts[cur])
			seen[cur] = true
			# Lowest unvisited neighbour — allowed to climb out of local
			# pits (the standard escape hack), the visited set stops loops.
			# CORRIDOR REPULSION (2026-07-07): the journey carve makes the
			# march corridor the island's lowland, so raw lowest-neighbour
			# descent SNAKED RIVERS ALONG THE ROADS — at the 18-row density
			# that read as scribble all over the chart. Descending on the
			# DE-CARVED elevation (invert the 0.30+0.78·t carve factor from
			# _assign_elevation) routes water as if the valley system never
			# existed: it shoulders around the march country and crosses it
			# briskly, transversally — which is exactly where bridges live.
			var lowest := -1
			var low_e := INF
			for j in _nbrs[cur]:
				if seen.has(j):
					continue
				var t_r := 1.0
				if j < _road_d.size():
					t_r = clampf(_road_d[j] / 95.0, 0.0, 1.0)
				var cand_e: float = _elev[j] / (0.30 + 0.78 * t_r)
				if cand_e < low_e:
					low_e = cand_e
					lowest = j
			if lowest == -1:
				break
			cur = lowest
		if not _land[cur]:
			path.append(_seed_pts[cur])
		if path.size() >= 4:
			_rivers.append(path)
	# Tributaries — each big river gets a thin branch joining a third of the
	# way down. Pure cosmetics, but rivers without branches read fake.
	var mains: Array = _rivers.duplicate()
	for rv_v in mains:
		var rv2: PackedVector2Array = rv_v
		if rv2.size() < 10:
			continue
		var ji: int = rv2.size() / 3
		var join: Vector2 = rv2[ji]
		# No tributaries in the march corridor — they're pure cosmetics, and
		# at chart density a cosmetic squiggle beside the road reads as a
		# broken road (2026-07-07).
		var jd := INF
		for ed2 in _edges:
			jd = minf(jd, _dist_to_seg(join, ed2.a, ed2.b))
		if jd < 110.0:
			continue
		var flow: Vector2 = (rv2[mini(ji + 1, rv2.size() - 1)]
			- rv2[maxi(ji - 1, 0)]).normalized()
		var perp: Vector2 = flow.orthogonal()
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var start: Vector2 = join + (perp * side - flow).normalized() \
			* _rng.randf_range(55.0, 80.0)
		var ci := _cell_at(start)
		if ci < 0 or not _land[ci] or _region[ci] != 1:
			continue
		var tpath := PackedVector2Array()
		for k in range(5):
			var t := float(k) / 4.0
			tpath.append(start.lerp(join, t)
				+ perp * side * sin(t * PI) * 7.0
				+ Vector2(_rng.randf_range(-2.5, 2.5),
					_rng.randf_range(-2.5, 2.5)))
		_rivers.append(tpath)


func _assign_moisture_biomes() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 2210 + _act * 77   # per-act forest/moisture layout
	noise.frequency = 0.006
	var count := _seed_pts.size()
	_moist.resize(count)
	_biome.resize(count)
	# Journey staging: the land changes as the road goes east — open meadow
	# out of camp, deep woods mid-journey, bare highlands before the scorch.
	# Games stage biomes along the intended path; pure noise feels random.
	var x0 := _camp_pos.x
	var x1 := _boss_pos.x if _boss_pos != Vector2.ZERO else size.x - MARGIN_R
	for i in range(count):
		var m := (noise.get_noise_2dv(_seed_pts[i]) + 1.0) * 0.5
		var t := clampf((_seed_pts[i].x - x0) / maxf(x1 - x0, 1.0), 0.0, 1.0)
		if t < 0.30:
			m -= 0.14                                   # meadow country
		else:
			m += 0.22 * exp(-pow((t - 0.55) / 0.16, 2)) # the deep woods
		for rv in _rivers:
			for k in range(0, rv.size(), 2):
				if _seed_pts[i].distance_to(rv[k]) < 60.0:
					m = minf(m + 0.28, 1.0)
					break
		_moist[i] = clampf(m, 0.0, 1.0)
	for i2 in range(count):
		if not _land[i2]:
			var coastal := false
			for j in _nbrs[i2]:
				if _land[j]:
					coastal = true
					break
			_biome[i2] = B_SHALLOW if coastal else B_DEEP
			continue
		var e := _elev[i2]
		var m2 := _moist[i2]
		# Scorch = the volcano's lava country, centered on Etna itself (NOT
		# whichever keep this act besieges — acts 1–2 fight far from the
		# mountain; act 3 marches into it). It grows by act: the deeper the
		# run, the more of the land has burned.
		var scorch_r: float = [0.0, 175.0, 205.0, 235.0][_act]
		var scorched := _seed_pts[i2].distance_to(_etna_peak) < scorch_r
		if scorched:
			_biome[i2] = B_SCORCH
		elif e < 0.06:
			_biome[i2] = B_BEACH
		elif e > 0.94:
			_biome[i2] = B_SNOW
		elif e > 0.73:
			_biome[i2] = B_ROCK
		elif e > 0.50:
			_biome[i2] = B_HILLS if m2 < 0.62 else B_FOREST
		else:
			_biome[i2] = B_FOREST if m2 > 0.60 else B_GRASS


func _assign_provinces() -> void:
	# Provinces only on Sicily proper — the mainland sliver and the offshore
	# isles are scenery, not claimable territory.
	var count := _seed_pts.size()
	_prov.resize(count)
	for i in range(count):
		if not _land[i] or _region[i] != 1:
			_prov[i] = -1
			continue
		var best := -1
		var best_d := INF
		for n in range(_nodes.size()):
			var d: float = _seed_pts[i].distance_squared_to(_nodes[n].pos)
			if d < best_d:
				best_d = d
				best = n
		# The political layer hugs the campaign corridor: land farther than
		# ~240px from any site is wilds, not someone's province — with one
		# leg per act, the rest of the island is past or future marches.
		_prov[i] = best if best_d < 240.0 * 240.0 else -1


## Successor Wars realms: every Sicilian land cell belongs to the rival
## kingdom whose keep seat is nearest. Pure geometry (the seats are fixed
## constants), so it caches with the mesh — which lord owns a zone, and in
## what state, is resolved per act by _resolve_kingdoms.
func _assign_zones() -> void:
	var seats: Array = []
	for ll in KEEP_LLS:
		seats.append(_clamp_into_island(_geo(ll.x, ll.y), 34.0))
	var count := _seed_pts.size()
	_zone.resize(count)
	for i in range(count):
		var z := -1
		if _land[i] and _region[i] == 1:
			var best := INF
			for s in range(seats.size()):
				var d: float = _seed_pts[i].distance_squared_to(seats[s])
				if d < best:
					best = d
					z = s
		_zone[i] = z


func _compute_hillshade() -> void:
	# Per-cell normal from neighbour elevation differences, lit from NW.
	var count := _seed_pts.size()
	_shade.resize(count)
	_grad.resize(count)
	var light := Vector2(-0.707, -0.707)
	for i in range(count):
		if not _land[i]:
			_shade[i] = 1.0
			_grad[i] = Vector2.ZERO
			continue
		var grad := Vector2.ZERO
		for j in _nbrs[i]:
			var dirv := (_seed_pts[j] - _seed_pts[i])
			var dl := dirv.length()
			if dl > 0.001:
				grad += dirv / dl * (_elev[j] - _elev[i])
		# Downhill-facing-light = lit slope; opposite = shadow.
		var lit := -grad.normalized().dot(light) if grad.length() > 0.0001 \
			else 0.0
		var strength := clampf(grad.length() * 9.0, 0.0, 1.0)
		_grad[i] = grad
		_shade[i] = 1.0 + lit * strength * 0.50 + _elev[i] * 0.12


## Stable dictionary key for a road station position (node/camp/keep) —
## endpoint positions are exact floats shared by every leg touching the
## station, so rounding to the pixel is collision-safe.
func _station_key(p: Vector2) -> String:
	return "%d_%d" % [int(round(p.x)), int(round(p.y))]


func _build_roads() -> void:
	# Roads bend toward low ground: of three candidate midpoints, take the
	# lowest-elevation one, so paths visibly skirt hills instead of crossing.
	_edge_curves.clear()   # append-built, index-paired with _edges
	_bridges = []
	if SIMPLE_BACKDROP:
		# Roads FLOW THROUGH the stations instead of elbowing at them — the
		# single biggest "looks like other games" lever (StS trails, HoMM
		# roads). Each station gets an average through-tangent (mean flow
		# direction of every leg touching it); each leg is then a cubic
		# Bezier whose handles leave/enter along those tangents, blended 35%
		# toward the leg's own direction so wide fans (the camp spray) can't
		# loop. A route running straight stays straight; a route turning at a
		# stop takes a smooth S — the old polyline X-weave at merge/split
		# stations read as tangled wire. A small seeded half-sine wobble
		# (pure endpoint sin-hash, so every bake/cache re-derivation lays the
		# identical curve) keeps flat runs hand-drawn. Dashes, bridges,
		# glints, and the march all follow _edge_curves and inherit the
		# shape for free. Bridge detection still runs (rivers are painted in
		# this mode too): without it the whole bridge layer — planks, tooltip
		# warnings, The Crossing event — silently never fired on the chart.
		var tang := {}   # "x_y" station key → summed leg flow directions
		for e0 in _edges:
			var d0 := ((e0.b as Vector2) - (e0.a as Vector2)).normalized()
			for ke in [e0.a, e0.b]:
				var kk := _station_key(ke)
				tang[kk] = (tang.get(kk, Vector2.ZERO) as Vector2) + d0
		for e in _edges:
			var a: Vector2 = e.a
			var b: Vector2 = e.b
			var seg_l := a.distance_to(b)
			var dirn := (b - a).normalized()
			var ta := (tang.get(_station_key(a), dirn) as Vector2).normalized()
			var tb := (tang.get(_station_key(b), dirn) as Vector2).normalized()
			ta = ta.lerp(dirn, 0.35).normalized()
			tb = tb.lerp(dirn, 0.35).normalized()
			# The camp fan (2026-07-07): three trails diverge from ONE point,
			# so the summed station tangent is their average — every trail
			# hooked sideways out of camp before bending back, and the dashed
			# chains read as broken. Camp legs leave along their own chord,
			# dead straight-tangented and wobble-free.
			var is_camp_leg := a.distance_to(_camp_pos) < 1.0
			if is_camp_leg:
				ta = dirn
				tb = dirn
			var hl := minf(seg_l * 0.34, 70.0)
			var p1 := a + ta * hl
			var p2 := b - tb * hl
			var hv := sin(a.x * 12.9898 + a.y * 78.233
				+ b.x * 3.7 + b.y * 24.11) * 43758.5453
			hv = hv - floor(hv)
			var amp := 0.0
			if seg_l > 90.0 and not is_camp_leg:
				amp = clampf(seg_l * 0.022, 2.0, 6.0) * (1.0 if hv < 0.5 else -1.0)
			var perp := dirn.orthogonal()
			var sp := PackedVector2Array()
			# Sample count follows leg length — the fixed 15 left ~23px facets
			# on the long steep legs, and the dash stamping showed the corners.
			var ns := clampi(int(seg_l / 16.0) + 1, 15, 27)
			for i in range(ns):
				var t := float(i) / float(ns - 1)
				var omt := 1.0 - t
				var bez: Vector2 = a * (omt * omt * omt) \
					+ p1 * (3.0 * omt * omt * t) + p2 * (3.0 * omt * t * t) \
					+ b * (t * t * t)
				sp.append(bez + perp * amp * sin(PI * t))
			_edge_curves.append(sp)
			for k in range(1, sp.size() - 1):
				var hit := false
				for rv in _rivers:
					for r in range(rv.size()):
						if sp[k].distance_to(rv[r]) < 10.0:
							hit = true
							break
					if hit:
						break
				if hit:
					_bridges.append({"pos": sp[k],
						"dirv": (sp[k + 1] - sp[k - 1]).normalized()})
					break
		return
	for e in _edges:
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		var m0 := (a + b) * 0.5
		var perp := (b - a).orthogonal().normalized()
		var best_mid := m0
		var best_e := INF
		for off in [-30.0, 0.0, 30.0]:
			var cand: Vector2 = m0 + perp * float(off)
			var ci := _cell_at(cand)
			if ci < 0 or not _land[ci]:
				continue
			if _elev[ci] < best_e:
				best_e = _elev[ci]
				best_mid = cand
		var pts := PackedVector2Array()
		for i in range(17):
			var t := float(i) / 16.0
			pts.append(a.lerp(best_mid, t).lerp(best_mid.lerp(b, t), t))
		_edge_curves.append(pts)
		# Bridge where this road meets a river.
		for k in range(0, pts.size() - 1, 2):
			var hit := false
			for rv in _rivers:
				for r in range(rv.size()):
					if pts[k].distance_to(rv[r]) < 10.0:
						hit = true
						break
				if hit:
					break
			if hit:
				_bridges.append({"pos": pts[k],
					"dirv": (pts[k + 1] - pts[maxi(k - 1, 0)]).normalized()})
				break


## The carved-road curve between two site positions (camp trails included),
## for marching the army standard along on commit. Falls back to a straight
## segment if no edge matches — the march still reads, just unbent.
func road_path_between(from_p: Vector2, to_p: Vector2) -> PackedVector2Array:
	for ei in range(_edges.size()):
		var e: Dictionary = _edges[ei]
		if (e.a as Vector2).distance_to(from_p) < 1.0 \
				and (e.b as Vector2).distance_to(to_p) < 1.0:
			return _edge_curves[ei]
	return PackedVector2Array([from_p, to_p])


## Phase 2.5 — geography becomes the difficulty dial. On the act's first
## open (tags absent from the run map), classify every hold by the ground
## it sits on and the road that reaches it, write the tags into the run-map
## node dicts (live references — they persist with the save), flag bridge
## crossings, and let RunState re-deal the dealt fights onto matching
## ground. Idempotent: tagged acts — including bake clones, which build
## after the live plate has tagged — skip straight out, and _read_run_map
## already copied their tags into _nodes.
func _derive_terrain_tags() -> void:
	var act_map: Array = RunState.get_current_act_map()
	if act_map.is_empty() or _nodes.is_empty():
		return
	var untagged: Array = []
	for row in act_map:
		for nd in row:
			if String(nd.get("terrain", "")) == "":
				untagged.append(nd)
	if untagged.is_empty():
		return
	var pos_by_rc: Dictionary = {}
	for m in _nodes:
		pos_by_rc[Vector2i(int(m.row), int(m.col))] = m.pos
	for nd in untagged:
		var key := Vector2i(int(nd.row), int(nd.col))
		if not pos_by_rc.has(key):
			continue
		nd["terrain"] = _classify_site(pos_by_rc[key])
		nd["bridge"] = false
	# Bridge flags: a river bridge on the road INTO a hold marks the hold —
	# its event rolls the crossing, its tooltip warns about the water.
	for br in _bridges:
		for ei in range(_edge_curves.size()):
			# Tight radius: at 12 a single river crossing flagged every edge
			# threading the same valley (act 3 hit 5 bridge holds of ~13).
			if not _curve_hits(_edge_curves[ei], br.pos, 9.0):
				continue
			var dest: Vector2 = _edges[ei].b
			for nd2 in untagged:
				var key2 := Vector2i(int(nd2.row), int(nd2.col))
				if pos_by_rc.has(key2) \
						and (pos_by_rc[key2] as Vector2).distance_to(dest) < 2.0:
					nd2["bridge"] = true
			break
	RunState.apply_terrain_redeal()
	if RunState.run_active:
		# Defer the disk write off this frame: _derive_terrain_tags runs inside
		# build_map during the act's first (and heaviest) open. The in-memory
		# re-deal above is already applied, so the paint below reads correct data
		# and only the save slips to frame-end. Idempotent — if it never lands, the
		# tags are simply re-derived on the next load.
		RunState.save_run.call_deferred()
	# _read_run_map built _nodes before tagging ran — refresh its snapshot
	# (terrain/bridge for tooltips + ink, encounter_id after the re-deal).
	var by_rc: Dictionary = {}
	for row in act_map:
		for nd3 in row:
			by_rc[Vector2i(int(nd3.row), int(nd3.col))] = nd3
	for m in _nodes:
		var k := Vector2i(int(m.row), int(m.col))
		if not by_rc.has(k):
			continue
		var src: Dictionary = by_rc[k]
		m["terrain"] = String(src.get("terrain", ""))
		m["bridge"] = bool(src.get("bridge", false))
		m["encounter_id"] = String(src.get("encounter_id", ""))


## Dominant ground around a site plus the last stretch of its approach
## road — a clearing chip at the end of a forest road still reads (and
## now fights) as woods. Sampled off the biome mesh; priority runs
## scarcest-first so ash and the pass never drown in surrounding grass.
func _classify_site(p: Vector2) -> String:
	var tally: Dictionary = {B_FOREST: 0, B_SCORCH: 0, B_ROCK: 0, B_SNOW: 0,
		B_HILLS: 0, B_GRASS: 0, B_BEACH: 0}
	var samples: Array = [p]
	for k in range(8):
		var a := TAU * float(k) / 8.0
		samples.append(p + Vector2(cos(a), sin(a)) * 30.0)
		if k % 2 == 0:
			samples.append(p + Vector2(cos(a), sin(a)) * 16.0)
	for ei in range(_edge_curves.size()):
		if (_edges[ei].b as Vector2).distance_to(p) >= 2.0:
			continue
		var pts := _edge_curves[ei]
		for t in [0.45, 0.6, 0.75, 0.9]:
			samples.append(pts[int(float(pts.size() - 1) * t)])
		break
	for s in samples:
		var ci := _cell_at(s)
		if ci < 0 or not _land[ci]:
			continue
		var b: int = _biome[ci]
		if tally.has(b):
			tally[b] += 1
	if tally[B_SCORCH] >= 2:
		return "ash"
	if tally[B_ROCK] + tally[B_SNOW] >= 2 or tally[B_HILLS] >= 6:
		return "pass"
	# Forest must be ~40% of the read (7 of ~17 samples) to call the hold
	# wooded — at the looser 4 the forest-heavy west leg tagged 11 of 15
	# sites "woods" and the label stopped meaning anything. Terrain reads
	# are features of a route, not the act's wallpaper.
	if tally[B_FOREST] >= 7:
		return "woods"
	return "meadow"


func _curve_hits(pts: PackedVector2Array, p: Vector2, r: float) -> bool:
	for q in pts:
		if q.distance_to(p) <= r:
			return true
	return false


## Push a label anchor out of the march corridor — a terrain name laid under
## the site chips turns both into mush. Walks away from the nearest site
## until clear. _nodes is already built when labels place (build order) and
## when kingdom names draw (live ink).
func _dodge_corridor(p: Vector2, clearance: float = 96.0) -> Vector2:
	for _i in range(10):
		var best_d := INF
		var best_n := Vector2.ZERO
		for nd in _nodes:
			var dd: float = (nd.pos as Vector2).distance_to(p)
			if dd < best_d:
				best_d = dd
				best_n = nd.pos
		if best_d >= clearance or best_d < 0.01:
			return p
		p += (p - best_n).normalized() * (clearance - best_d + 6.0)
	return p


func _place_labels() -> void:
	_labels = []   # append-built — see _build_mesh
	# Landmark names on the biggest terrain features — map furniture is half
	# of what makes a game map read as a place. Descriptive common-noun names
	# only (the lore bible forbids proper nouns for the world itself).
	# Pinned to the north-coast chain (real geography beats cluster-hunting —
	# the largest rock cluster can land in the south-east hills).
	# Region names sized up (18-19px) and given heavy outlines in _draw_labels:
	# they orient the player to the terrain bands that matter (ash = the boss's
	# lava country). The decorative sea/strait/mainland labels below were CUT —
	# pure flavour the player can't read that added to the "overcomplicated" feel.
	_labels.append({"pos": _geo(14.300, 37.940) + Vector2(0, -18.0),
		"text": "T H E   H I G H   F E L L S", "size": 18,
		"crimson": false})
	var wood_c := _largest_cluster([B_FOREST])
	if wood_c.z >= 12.0:
		_labels.append({"pos": _dodge_corridor(Vector2(wood_c.x, wood_c.y)),
			"text": "T H E   B L A C K   P I N E S", "size": 18,
			"crimson": false})
	var ash_c := _largest_cluster([B_SCORCH])
	if ash_c.z >= 8.0:
		_labels.append({"pos": Vector2(ash_c.x, ash_c.y - 90.0),
			"text": "T H E   A S H   M A R C H", "size": 19,
			"crimson": true})
	# (Sea / strait / mainland chart labels were cut here: at 15-16px over the
	# dark ocean they read as unreadable clutter, and naming empty water added
	# nothing the player acts on. The compass rose still says "this is a chart".)
	# (The three tiny harbour-town labels — SALT HAVEN / NORTH HAVEN / THE OLD
	# CITY — were cut: pure 10px flavour with no gameplay signal, they read as
	# unreadable clutter rather than chart decoration.)


func _largest_cluster(biomes: Array) -> Vector3:
	# Returns (centroid.x, centroid.y, cell_count) of the largest connected
	# cluster whose biome is in `biomes`.
	var count := _seed_pts.size()
	var visited: Dictionary = {}
	var best_n := 0
	var best_c := Vector2.ZERO
	for i in range(count):
		if visited.has(i) or not (_biome[i] in biomes):
			continue
		var queue: Array[int] = [i]
		visited[i] = true
		var members: Array[int] = []
		var head := 0
		while head < queue.size():
			var c := queue[head]
			head += 1
			members.append(c)
			for j in _nbrs[c]:
				if not visited.has(j) and (_biome[j] in biomes):
					visited[j] = true
					queue.append(j)
		if members.size() > best_n:
			best_n = members.size()
			var cen := Vector2.ZERO
			for m in members:
				cen += _seed_pts[m]
			best_c = cen / float(members.size())
	return Vector3(best_c.x, best_c.y, float(best_n))


# ═══════════════════ DRAW ═══════════════════

func _biome_color(i: int) -> Color:
	var c := _biome_color_base(i)
	# Per-act mood: the same island, deeper into the war.
	if _land[i] and _act > 1:
		if _act == 2:
			c = c.lerp(Color(0.14, 0.20, 0.19), 0.16)   # colder, wetter
		else:
			c = c.lerp(Color(0.24, 0.16, 0.11), 0.20)   # ash-choked
	return c


func _biome_color_base(i: int) -> Color:
	var e := _elev[i]
	match _biome[i]:
		B_DEEP:
			# Depth banding: the sea darkens as it leaves the coast.
			var dt := clampf((float(_wdepth[i]) - 2.0) / 5.0, 0.0, 1.0)
			return OCEAN_SHALLOW.lerp(
				Color(0.030, 0.055, 0.075), 0.45 + 0.55 * dt)
		B_SHALLOW:
			return OCEAN_SHALLOW
		B_BEACH:
			return Color(0.500, 0.420, 0.270)
		B_GRASS:
			# Sun-baked meadow — warm golden-brown. Mid-DARK and rich: dark
			# enough that the light pool + light ink read against it, harmonized
			# enough that it never reads as patchy olive mud.
			return Color(0.400, 0.345, 0.195).lerp(Color(0.460, 0.390, 0.220), e)
		B_FOREST:
			# Wooded country: a dark greyed olive, kept CLOSE in value to the
			# meadow so the boundary is a whisper, not a hard patchwork seam.
			return Color(0.280, 0.315, 0.180).lerp(Color(0.235, 0.275, 0.160), e)
		B_HILLS:
			return Color(0.400, 0.320, 0.205).lerp(Color(0.455, 0.375, 0.240), e)
		B_ROCK:
			return Color(0.395, 0.360, 0.305).lerp(Color(0.450, 0.415, 0.355), e)
		B_SNOW:
			return Color(0.720, 0.705, 0.655)
		B_SCORCH:
			# Ash country — rich burnt umber toward Etna's reach.
			return Color(0.345, 0.185, 0.120).lerp(Color(0.270, 0.140, 0.095), e)
	return Color.MAGENTA


func _draw() -> void:
	# The plate lives on _plate_item (drawn behind this item); the root item
	# carries only the screen-fixed UI band, so it never rides the view
	# transform and only re-records via _redraw_plate.
	if bake_mode != "" or _nodes.is_empty() or _polys.is_empty():
		return
	_draw_ui()


## The plate's canvas item. Steady state is the march quad with the campaign
## quad crossfaded over it by zoom (the dress system); until the bakes land
## it paints geography (cached quad or vectors) + the nearer dress's ink.
## Re-records only when _redraw_plate fires or the dress mix changes —
## zoom/pan otherwise just move this item's transform.
class PlateItem extends Control:
	# Untyped on purpose: hard-typed vars fail compile on script-only members.
	var map = null

	func _draw() -> void:
		if map == null or map._nodes.is_empty() or map._polys.is_empty():
			return
		if map.bake_mode == "":
			var mix: float = map._campaign_mix()
			if map._march_tex != null:
				draw_texture_rect(map._march_tex,
					Rect2(Vector2.ZERO, map.size), false)
				if mix > 0.0 and map._plate_tex != null:
					draw_texture_rect(map._plate_tex,
						Rect2(Vector2.ZERO, map.size), false,
						Color(1, 1, 1, mix))
				return
			if map._plate_tex != null:
				# March bake still in flight — hold the (possibly one-visit
				# stale) campaign plate rather than flash the vector path.
				draw_texture_rect(map._plate_tex,
					Rect2(Vector2.ZERO, map.size), false)
				return
		var count: int = map._seed_pts.size()
		if map._geo_tex != null:
			# Baked geography: ocean/terrain/coast/rivers/decorations in one
			# quad. The vector path runs only while the act's one-time bake
			# is in flight (or if its readback failed).
			draw_texture_rect(map._geo_tex,
				Rect2(Vector2.ZERO, map.size), false)
		else:
			map._paint_geo(self, count)
		if map.bake_mode == "geo":
			return   # geography-bake clone: no ink in the cached texture
		if map.SIMPLE_BACKDROP:
			# War-table chart: the lit parchment + inked coast are already
			# down. Stamp the quiet sea furniture, the claimed-land warmth,
			# Etna, the straight roads, the site chips and the camp/keep —
			# no political dye, kingdom names or site labels (the "no
			# clutter" read).
			map._draw_simple_furniture(self)
			map._draw_claimed_glow(self)
			map._draw_etna(self)
			map._draw_routes(self)
			map._draw_sites(self)
			map._draw_keep(self)
			map._draw_camp(self)
			return
		# Campaign ink, dress-gated: the march dress is the decision screen
		# (roads, chips, keep/camp, your amber); the campaign dress adds the
		# political theater (rival dyes, borders, kingdom + chart names).
		var campaign: bool = map._ink_campaign()
		map._draw_political(self, count, campaign)
		map._draw_etna(self)
		map._draw_routes(self)
		map._draw_sites(self)
		map._draw_keep(self)
		map._draw_camp(self)
		if campaign:
			map._draw_kingdom_names(self)
			map._draw_labels(self)
		map._draw_furniture(self)


## SIMPLE_BACKDROP geography — the war-table sheet as a LIT PHYSICAL OBJECT,
## not a flat fill: a dark sea frame falling off to the corners, the island a
## warm parchment plate floating on it (cast shadow + waterline rings, the
## antique-chart cut-paper read), per-cell tonal mottle + a lamplight pool at
## the heart of the chart, and quiet engraved terrain marks (pines, peaks,
## furrows) keyed to the SAME biome mesh the terrain tooltips read — the
## country the intel names is the country the eye sees. Baked into _geo_tex
## once per act, so all of it costs nothing per frame.
func _paint_simple_backdrop(tgt: CanvasItem, count: int) -> void:
	# STAGING: the chart is a physical object — a deckled parchment sheet
	# pinned to the same dark war table Combat plays on, under the same lamp.
	# One material world: wood beneath, paper above, ink on the paper. The
	# water is PAPER (antique charts indicate sea with rings and ruling, not
	# a colour) — the old saturated-teal sea was the last element living
	# outside the sepia register.
	var wood := Color(0.118, 0.088, 0.062)          # Combat's table brown
	var paper_sea := Color(0.560, 0.482, 0.352)     # the wash the sea wears
	var land := Color(0.752, 0.642, 0.452)
	var ink_wash := Color(0.36, 0.28, 0.185)        # rings/graticule/furniture
	var pool_c := Vector2(0.46, 0.50)   # lamplight centre, uv
	# 1 — the table: seeded plank seams + long faint grain strokes. Only the
	# margin shows at chart zoom, but that margin is what stages the object.
	tgt.draw_rect(Rect2(Vector2.ZERO, size), wood)
	var wrng := RandomNumberGenerator.new()
	wrng.seed = 77 + _act
	for sy in [0.18, 0.44, 0.68, 0.90]:
		var yy: float = size.y * float(sy) + wrng.randf_range(-16.0, 16.0)
		tgt.draw_line(Vector2(0, yy), Vector2(size.x, yy),
			Color(0, 0, 0, 0.32), 1.6, true)
		tgt.draw_line(Vector2(0, yy + 1.6), Vector2(size.x, yy + 1.6),
			Color(0.36, 0.27, 0.18, 0.16), 1.0, true)
	for _g in range(46):
		var gy0 := wrng.randf_range(0.0, size.y)
		var gx0 := wrng.randf_range(-80.0, size.x)
		var gl := wrng.randf_range(90.0, 320.0)
		tgt.draw_line(Vector2(gx0, gy0),
			Vector2(gx0 + gl, gy0 + wrng.randf_range(-2.5, 2.5)),
			Color(0, 0, 0, 0.055) if wrng.randf() < 0.6
			else Color(0.42, 0.31, 0.20, 0.05), 1.0, true)
	# 2 — the sheet: cast shadow onto the wood, then the paper. The shadow is
	# what makes it an OBJECT and not a background.
	if _sheet_poly.size() >= 3:
		for shd in [[Vector2(9.0, 12.0), 0.26], [Vector2(4.0, 6.0), 0.28]]:
			var sp0 := PackedVector2Array()
			for v0 in _sheet_poly:
				sp0.append(v0 + (shd[0] as Vector2))
			tgt.draw_colored_polygon(sp0, Color(0, 0, 0, float(shd[1])))
		tgt.draw_colored_polygon(_sheet_poly, paper_sea)
	else:
		tgt.draw_rect(Rect2(Vector2.ZERO, size), paper_sea)
	var mottle := FastNoiseLite.new()
	mottle.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mottle.frequency = 0.010
	mottle.fractal_octaves = 3
	mottle.seed = 1771 + _act
	# 3 — sea-wash cells: gentle mottle + vignette on the paper water, kept
	# clear of the sheet edge so no ragged cell ever pokes onto the wood.
	for i in range(count):
		if _land[i] or _polys[i].size() < 3:
			continue
		if not _inside_sheet(_seed_pts[i], 17.0):
			continue
		var uv := _seed_pts[i] / size
		# Anisotropic pool: x compressed / y stretched — the light is a BAND
		# along the march corridor, serving the decision structure.
		var dv := uv - pool_c
		var d := Vector2(dv.x * 0.80, dv.y * 1.18).length()
		var vg := 1.0 - smoothstep(0.28, 0.86, d) * 0.30
		var mf := 1.0 + mottle.get_noise_2d(_seed_pts[i].x, _seed_pts[i].y) * 0.075
		var sc := Color(paper_sea.r * vg * mf, paper_sea.g * vg * mf,
			paper_sea.b * vg * mf)
		var lift := (1.0 - smoothstep(0.0, 0.44, d)) * 0.06
		if lift > 0.0:
			sc = sc.lerp(Color(0.97, 0.88, 0.66), lift)
		tgt.draw_colored_polygon(_polys[i], sc)
	if _poly_sicily.size() < 3:
		return
	# 4 — graticule ruled over open water (charts rule the sea, not the land).
	var grat := Color(ink_wash.r, ink_wash.g, ink_wash.b, 0.14)
	var gx := 90.0
	while gx < size.x:
		_draw_sea_segments(tgt, Vector2(gx, 0), Vector2(gx, size.y), grat)
		gx += 176.0
	var gy := 70.0
	while gy < size.y:
		_draw_sea_segments(tgt, Vector2(0, gy), Vector2(size.x, gy), grat)
		gy += 176.0
	# 5 — a tight pigment pool at the coast (paint settling at the line), not
	# an object shadow — the island is INK ON the sheet, not a separate cut.
	var csp := PackedVector2Array()
	for v in _poly_sicily:
		csp.append(v + Vector2(2.5, 3.5))
	tgt.draw_colored_polygon(csp, Color(0.22, 0.15, 0.08, 0.16))
	# 6 — waterline rings fading seaward, the signature of engraved charts.
	for ring_def in [[8.0, 0.34, 1.3], [16.0, 0.20, 1.1], [25.0, 0.11, 1.0]]:
		var rings: Array = Geometry2D.offset_polygon(_poly_sicily,
			float(ring_def[0]), Geometry2D.JOIN_ROUND)
		for ring in rings:
			var rl := (ring as PackedVector2Array).duplicate()
			if rl.size() < 3:
				continue
			rl.append(rl[0])
			tgt.draw_polyline(rl, Color(ink_wash.r, ink_wash.g, ink_wash.b,
				float(ring_def[1])), float(ring_def[2]), true)
	# 5 — the land plate: flat fill first (so ragged cell edges never show at
	# the coast), then per-cell parchment mottle + the baked lamplight pool on
	# cells comfortably inside the outline. Biomes tint the paper a whisper —
	# enough that the woods read greener and the burn reads charred, never so
	# much that it turns back into painted terrain.
	# Pale shore rim first, then the interior tone — the outer ~14px of land
	# reads as sand shelf under the coast ink (the classic engraved-chart
	# beach rim; also hides any ragged cell edge at the coast).
	tgt.draw_colored_polygon(_poly_sicily, Color(0.786, 0.682, 0.502))
	var core: Array = Geometry2D.offset_polygon(_poly_sicily, -14.0,
		Geometry2D.JOIN_ROUND)
	for cpoly in core:
		if (cpoly as PackedVector2Array).size() >= 3:
			tgt.draw_colored_polygon(cpoly, land)
	for i2 in range(count):
		if not _land[i2] or _polys[i2].size() < 3:
			continue
		if not _inside_island(_seed_pts[i2], 13.0):
			continue
		var col := land
		match _biome[i2]:
			B_FOREST:
				col = col.lerp(Color(0.560, 0.565, 0.360), 0.16)
			B_SCORCH:
				col = col.lerp(Color(0.340, 0.235, 0.165), 0.34)
			B_ROCK, B_SNOW:
				col = col.lerp(Color(0.585, 0.545, 0.470), 0.16)
			B_HILLS:
				col = col.lerp(Color(0.660, 0.520, 0.330), 0.10)
		var mf2 := 1.0 + mottle.get_noise_2d(_seed_pts[i2].x,
			_seed_pts[i2].y) * 0.075
		col = Color(col.r * mf2, col.g * mf2, col.b * mf2)
		# Settled road-country: the corridor lifts a touch toward pale packed
		# earth, so the campaign's band reads warmer than the wilds.
		if i2 < _road_d.size() and _road_d[i2] < 110.0:
			col = col.lerp(Color(0.790, 0.690, 0.500),
				(1.0 - _road_d[i2] / 110.0) * 0.30)
		var uv2 := _seed_pts[i2] / size
		var dv2 := uv2 - pool_c
		var d2 := Vector2(dv2.x * 0.80, dv2.y * 1.18).length()
		var vg2 := 1.0 - smoothstep(0.34, 0.80, d2) * 0.18
		col = Color(col.r * vg2, col.g * vg2, col.b * vg2)
		var lift2 := (1.0 - smoothstep(0.0, 0.50, d2)) * 0.15
		if lift2 > 0.0:
			col = col.lerp(Color(1.0, 0.94, 0.74), lift2)
		tgt.draw_colored_polygon(_polys[i2], col)
	# 5.5 — foxing: a few broad, faint age-stains soaked into the sheet.
	# Rejection-sampled well inside the coast with a seeded rng, so every
	# bake lays the same stains. Stacked discs keep the edges soft.
	var frng := RandomNumberGenerator.new()
	frng.seed = 3121 + _act * 41
	var placed := 0
	var attempts := 0
	while placed < 5 and attempts < 60:
		attempts += 1
		var fp := Vector2(frng.randf_range(size.x * 0.08, size.x * 0.92),
			frng.randf_range(size.y * 0.12, size.y * 0.88))
		if not _inside_island(fp, 46.0):
			continue
		placed += 1
		var fr := frng.randf_range(34.0, 78.0)
		for fk in range(3):
			tgt.draw_circle(fp + Vector2(frng.randf_range(-9.0, 9.0),
				frng.randf_range(-7.0, 7.0)),
				fr * (1.0 - float(fk) * 0.28),
				Color(0.42, 0.30, 0.16, 0.028))
	# 6 — rivers: thin engraved threads, widening downstream.
	var rcol := Color(0.235, 0.350, 0.360, 0.72)
	for rv in _rivers:
		var wmax := minf(2.6, float(rv.size()) * 0.20)
		for k in range(rv.size() - 1):
			var t := float(k) / float(maxi(rv.size() - 1, 1))
			tgt.draw_line(rv[k], rv[k + 1], rcol, 0.9 + t * wmax, true)
	# 7 — engraved terrain marks off the biome mesh.
	_draw_simple_marks(tgt, count)
	# 8 — islets: painted in miniature with a single waterline ring.
	var coast := Color(0.115, 0.085, 0.055, 0.82)
	for isle in _isles:
		var ip: Vector2 = isle.pos
		var ir := float(isle.r)
		tgt.draw_circle(ip + Vector2(1.5, 2.2), ir, Color(0.22, 0.15, 0.08, 0.16))
		tgt.draw_circle(ip, ir, land.darkened(0.06))
		tgt.draw_arc(ip, ir + 6.0, 0, TAU, 22,
			Color(ink_wash.r, ink_wash.g, ink_wash.b, 0.26), 1.1, true)
		tgt.draw_arc(ip, ir, 0, TAU, 22, coast, 1.5, true)
	# 9 — the coast ink: a firm engraved rule on the deckled outline, with a
	# thin inner hairline (the double-ruled coast of old charts).
	var loop := _poly_sicily.duplicate()
	loop.append(_poly_sicily[0])
	tgt.draw_polyline(loop, coast, 2.6, true)
	var inner: Array = Geometry2D.offset_polygon(_poly_sicily, -5.0,
		Geometry2D.JOIN_ROUND)
	for ip2 in inner:
		var il := (ip2 as PackedVector2Array).duplicate()
		if il.size() < 3:
			continue
		il.append(il[0])
		tgt.draw_polyline(il, Color(0.115, 0.085, 0.055, 0.30), 1.0, true)
	# 10 — the sheet's own edge: a paper-thickness highlight up-left, a quiet
	# ink rule, and four iron tacks pinning the chart to the table (the same
	# aged-metal vocabulary as the medallion bezels).
	if _sheet_poly.size() >= 3:
		var srim := _sheet_poly.duplicate()
		srim.append(_sheet_poly[0])
		var srim_hi := PackedVector2Array()
		for v2 in srim:
			srim_hi.append(v2 + Vector2(-1.0, -1.0))
		tgt.draw_polyline(srim_hi, Color(1.0, 0.96, 0.86, 0.20), 1.2, true)
		tgt.draw_polyline(srim, Color(0.20, 0.14, 0.085, 0.55), 1.3, true)
		for tc in [Vector2(46.0, 46.0), Vector2(size.x - 46.0, 46.0),
				Vector2(46.0, size.y - 46.0),
				Vector2(size.x - 46.0, size.y - 46.0)]:
			tgt.draw_circle(tc + Vector2(1.6, 2.4), 5.2, Color(0, 0, 0, 0.35))
			tgt.draw_circle(tc, 4.6, Color(0.09, 0.07, 0.05))
			tgt.draw_circle(tc, 3.4, Color(0.46, 0.41, 0.34))
			tgt.draw_arc(tc, 2.6, PI * 1.05, PI * 1.6, 8,
				Color(0.82, 0.78, 0.68, 0.9), 1.3, true)


## Engraved terrain symbols on the parchment — sparse, stroke-only, sepia ink:
## pine stands in the woods, peak strokes on the high ground, hill humps,
## furrowed fields along the settled road, ash flecks in the burn. Densities
## run far below the painted-campaign mode — these are an engraver's marks on
## a chart, not terrain art — and every mark keeps a cleared verge off the
## roads and the surf so the campaign ink stays the loudest thing on the land.
func _draw_simple_marks(tgt: CanvasItem, count: int) -> void:
	var drng := RandomNumberGenerator.new()
	drng.seed = 909 + _act * 17
	var ink := Color(0.30, 0.235, 0.155, 0.55)
	for i in range(count):
		if not _land[i]:
			continue
		var p := _seed_pts[i]
		if _road_d[i] < 46.0 or not _inside_island(p, 30.0):
			continue
		match _biome[i]:
			B_FOREST:
				if drng.randf() < 0.34:
					for _t in range(1 if drng.randf() < 0.62 else 2):
						var tp := p + Vector2(drng.randf_range(-8.0, 8.0),
							drng.randf_range(-7.0, 7.0))
						var s := drng.randf_range(3.2, 4.6)
						# Engraved pine: trunk + two chevron tiers.
						tgt.draw_line(tp + Vector2(0, s * 0.7),
							tp + Vector2(0, s * 1.3), ink, 1.1, true)
						tgt.draw_polyline(PackedVector2Array([
							tp + Vector2(-s, s * 0.7), tp + Vector2(0, -s * 0.5),
							tp + Vector2(s, s * 0.7)]), ink, 1.2, true)
						tgt.draw_polyline(PackedVector2Array([
							tp + Vector2(-s * 0.62, 0), tp + Vector2(0, -s * 1.3),
							tp + Vector2(s * 0.62, 0)]), ink, 1.2, true)
			B_ROCK, B_SNOW:
				if drng.randf() < 0.26:
					var pc := p + Vector2(drng.randf_range(-6.0, 6.0),
						drng.randf_range(-5.0, 5.0))
					var s2 := drng.randf_range(4.2, 6.8)
					tgt.draw_polyline(PackedVector2Array([
						pc + Vector2(-s2, s2 * 0.6), pc + Vector2(0, -s2),
						pc + Vector2(s2, s2 * 0.6)]), ink, 1.3, true)
					# Shade stroke down the east face.
					tgt.draw_line(pc + Vector2(0, -s2),
						pc + Vector2(s2 * 0.45, -s2 * 0.1),
						Color(ink.r, ink.g, ink.b, 0.38), 1.1, true)
			B_HILLS:
				if drng.randf() < 0.13:
					tgt.draw_arc(p, drng.randf_range(3.8, 5.6), PI + 0.15,
						TAU - 0.15, 10, ink, 1.2, true)
			B_SCORCH:
				if drng.randf() < 0.16:
					var ca := drng.randf_range(0.0, TAU)
					var cv := Vector2(cos(ca), sin(ca))
					var cp2 := p + Vector2(drng.randf_range(-6.0, 6.0),
						drng.randf_range(-6.0, 6.0))
					tgt.draw_line(cp2 - cv * drng.randf_range(2.5, 5.0),
						cp2 + cv * drng.randf_range(2.5, 5.0),
						Color(0.10, 0.055, 0.035, 0.50), 1.2, true)
			B_GRASS:
				if _road_d[i] > 60.0 and _road_d[i] < 185.0 \
						and drng.randf() < 0.15:
					# Furrowed fields along the settled road.
					var fa := float((i * 7) % 4) * PI * 0.25
					var ax := Vector2(cos(fa), sin(fa))
					for fk in range(3):
						var fp := p + ax.orthogonal() * (float(fk) - 1.0) * 3.8
						tgt.draw_line(fp - ax * 5.0, fp + ax * 5.0,
							Color(0.26, 0.20, 0.11, 0.13), 1.0, true)
				elif drng.randf() < 0.05:
					tgt.draw_circle(p + Vector2(drng.randf_range(-6.0, 6.0),
						drng.randf_range(-5.0, 5.0)),
						drng.randf_range(0.8, 1.3),
						Color(0.24, 0.20, 0.11, 0.30))


## Geography — every layer that is constant for the act, baked once per act
## into _geo_tex. NOTE: decorations (trees/hachures/furrows) moved UNDER the
## political wash with the bake split — territory dye now tints them too,
## which reads as a coherent realm rather than stickers over the wash.
func _paint_geo(tgt: CanvasItem, count: int) -> void:
	if SIMPLE_BACKDROP:
		_paint_simple_backdrop(tgt, count)
		return
	# 1 — ocean base (rect, then shallow/deep cells refine it).
	tgt.draw_rect(Rect2(Vector2.ZERO, size), OCEAN_DEEP)
	var mottle := FastNoiseLite.new()
	mottle.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mottle.frequency = 0.011
	mottle.fractal_octaves = 3
	mottle.seed = 1771
	# 2 — every cell, hillshaded. Cells near the march corridor are lifted
	# toward pale road-country: the campaign layer needs quiet ground under
	# it, and the lightened band doubles as "settled land along the road".
	# Scorch keeps its char (act 3 marches THROUGH the lava country) and
	# snow stays snow.
	for i in range(count):
		if _polys[i].size() < 3:
			continue
		var col := _biome_color(i)
		if _land[i]:
			# Moderate hillshade for FORM (full strength was the blotchy patchwork
			# that read as "kid's coloring"; killing it entirely went flat/bland).
			var s := lerpf(1.0, _shade[i], 0.58)
			col = Color(col.r * s, col.g * s, col.b * s)
			# Large-scale tonal mottle — low-freq noise sampled at the cell, so
			# neighbouring cells drift TOGETHER (sun-dappled ground), never a
			# random per-cell checker. This is the "tooth" the flat fill lacked;
			# done in-fill (not a full-rect alpha overlay, which baked opaque).
			var mf := 1.0 + mottle.get_noise_2d(_seed_pts[i].x, _seed_pts[i].y) \
				* 0.15
			col = Color(clampf(col.r * mf, 0.0, 1.0),
				clampf(col.g * mf, 0.0, 1.0), clampf(col.b * mf, 0.0, 1.0))
			if i < _road_d.size() and _road_d[i] < 120.0 \
					and _biome[i] != B_SCORCH and _biome[i] != B_SNOW:
				col = col.lerp(Color(0.620, 0.545, 0.380),
					(1.0 - _road_d[i] / 120.0) * 0.26)
		# Baked light model (per-cell so it composites correctly — the full-rect
		# texture version baked OPAQUE). A warm pool lifts the chart's heart; the
		# edges fall to dark. This is the lit-artifact read (Inscryption), applied
		# to terrain AND sea so the whole plate sits in one pool of light.
		var uv := _seed_pts[i] / size
		var d := uv.distance_to(Vector2(0.47, 0.47))
		var vg := 1.0 - smoothstep(0.40, 0.94, d) * 0.74
		col = Color(col.r * vg, col.g * vg, col.b * vg)
		var lift := (1.0 - smoothstep(0.0, 0.56, d)) * 0.17
		if lift > 0.0:
			col = col.lerp(Color(1.0, 0.93, 0.73), lift)
		tgt.draw_colored_polygon(_polys[i], col)
	# 2.5 — graticule ruled over open water only (charts rule the sea, not
	# the land); land cells were drawn already, so we sample and skip them.
	var grat := Color(FOAM.r, FOAM.g, FOAM.b, 0.07)
	var glon := GEO_LON0
	while glon < GEO_LON0 + 4.3:
		var gp := _geo(glon, GEO_LAT0)
		_draw_sea_segments(tgt, Vector2(gp.x, 0), Vector2(gp.x, size.y), grat)
		glon += 0.5
	var glat := GEO_LAT0
	while glat > GEO_LAT0 - 2.6:
		var gp2 := _geo(GEO_LON0, glat)
		_draw_sea_segments(tgt, Vector2(0, gp2.y), Vector2(size.x, gp2.y), grat)
		glat -= 0.5
	# 3 — coastline ink along true land/water cell edges: double-ruled (thick
	# outer + thin inner, like engraved charts) with waterline rings fading
	# seaward — the signature of old nautical charts.
	for i2 in range(count):
		if not _land[i2]:
			continue
		for j in _nbrs[i2]:
			if j > i2 and not _land[j]:
				var seg := _shared_edge(i2, j)
				if seg.size() >= 2:
					var sea_dir := (_seed_pts[j] - _seed_pts[i2]).normalized()
					tgt.draw_line(seg[0] + sea_dir * 7.0, seg[1] + sea_dir * 7.0,
						Color(FOAM.r, FOAM.g, FOAM.b, 0.34), 1.1, true)
					if _region[i2] != 3:
						# Tiny islets keep a single ring — the full set
						# overlaps itself and turns them to stripes.
						tgt.draw_line(seg[0] + sea_dir * 14.0,
							seg[1] + sea_dir * 14.0,
							Color(FOAM.r, FOAM.g, FOAM.b, 0.20), 1.0, true)
						tgt.draw_line(seg[0] + sea_dir * 22.0,
							seg[1] + sea_dir * 22.0,
							Color(FOAM.r, FOAM.g, FOAM.b, 0.10), 1.0, true)
					tgt.draw_line(seg[0] - sea_dir * 3.2, seg[1] - sea_dir * 3.2,
						Color(0.02, 0.03, 0.03, 0.30), 1.2, true)
					tgt.draw_line(seg[0], seg[1], COAST_INK, 2.4, true)
	# 3.5 — shoal stipple in the shallows + sparse wave ticks on open water.
	var wrng := RandomNumberGenerator.new()
	wrng.seed = 4117
	for iw in range(count):
		if _land[iw]:
			continue
		if _wdepth[iw] <= 2:
			if wrng.randf() < 0.5:
				for _d in range(wrng.randi_range(2, 4)):
					tgt.draw_circle(_seed_pts[iw] + Vector2(
						wrng.randf_range(-9.0, 9.0),
						wrng.randf_range(-8.0, 8.0)),
						wrng.randf_range(0.6, 1.2),
						Color(FOAM.r, FOAM.g, FOAM.b, 0.13))
		elif _biome[iw] == B_DEEP and wrng.randf() < 0.035:
			var wp := _seed_pts[iw] + Vector2(wrng.randf_range(-9.0, 9.0),
				wrng.randf_range(-7.0, 7.0))
			tgt.draw_arc(wp, wrng.randf_range(4.5, 7.5), PI + 0.45, TAU - 0.45,
				8, Color(FOAM.r, FOAM.g, FOAM.b, 0.15), 1.1, true)
	# 4 — rivers (widening downstream; width scales with length so
	# tributaries stay thin where they join). Two Chaikin passes turn the
	# raw ~20px mesh-walk segments into one confident drawn stroke — the
	# jagged cell-hop elbows were the loudest "broken chart" tell at the
	# 18-row density (2026-07-07). Detection layers (bridges, moisture)
	# keep reading the RAW _rivers points; only the ink smooths.
	for rv in _rivers:
		var sm := _chaikin(rv, 2)
		var wmax := minf(3.4, float(rv.size()) * 0.22)
		for k in range(sm.size() - 1):
			var t := float(k) / float(maxi(sm.size() - 1, 1))
			tgt.draw_line(sm[k], sm[k + 1], RIVER_COL, 1.2 + t * wmax, true)
	# 5 — terrain decorations (part of the geography bake).
	_draw_decorations(tgt, count)
	# 6 — the realms: all unclaimed Sicilian land wears its kingdom's dye,
	# not just the active front. Faint washes — the front's corridor gets
	# the strong wash in the ink layer on top — with conquered kingdoms
	# turned to your gold, so the campaign reads across the whole chart.
	# Legacy runs carry no rival deal and skip the overlay entirely.
	if not _kingdoms.is_empty():
		for i in range(count):
			var z := _zone[i]
			if z < 0 or _prov[i] >= 0 or _polys[i].size() < 3:
				continue
			var k: Dictionary = _kingdoms[z]
			var wash: Color
			if String(k.state) == "taken":
				wash = Color(PLAYER_AMBER.r, PLAYER_AMBER.g,
					PLAYER_AMBER.b, 0.13)
			else:
				wash = _realm_wash(k.color, 0.15)
			tgt.draw_colored_polygon(_polys[i], wash)
		# Realm borders along true cell edges — quiet ink, beneath the
		# corridor's brighter dyed province rims.
		for i2 in range(count):
			if _zone[i2] < 0:
				continue
			for j in _nbrs[i2]:
				if j > i2 and _zone[j] >= 0 and _zone[j] != _zone[i2]:
					var seg := _shared_edge(i2, j)
					if seg.size() >= 2:
						tgt.draw_line(seg[0], seg[1],
							Color(0.05, 0.05, 0.04, 0.38), 1.6, true)


## Realm names over their land — your gold once an act is won, the lord's
## brightened dye while he waits his turn. The active FRONT skips its land
## name: the cartouche already names it, and its zone is busy with the
## corridor's sites — the name would fight the chips and the keep plaque.
func _draw_kingdom_names(tgt: CanvasItem) -> void:
	if _kingdoms.is_empty() or GameTheme.font_display == null:
		return
	for k in _kingdoms:
		var col: Color
		if String(k.state) == "front":
			continue
		elif String(k.state) == "taken":
			col = Color(PLAYER_AMBER.r, PLAYER_AMBER.g, PLAYER_AMBER.b, 0.95)
		else:
			var c: Color = k.color
			col = Color(minf(c.r * 1.4, 1.0), minf(c.g * 1.4, 1.0),
				minf(c.b * 1.4, 1.0), 0.95)
		# Real dark outline (was a faint half-alpha shadow that washed out over
		# the dyed land) at 18px so the realm names read as labels, not noise.
		var name_p: Vector2 = _dodge_corridor(k.centroid as Vector2, 116.0) \
			+ Vector2(-150.0, 4.0)
		var name_txt := _letterspace(String(k.name))
		tgt.draw_string_outline(GameTheme.font_display, name_p, name_txt,
			HORIZONTAL_ALIGNMENT_CENTER, 300, 18, 5, Color(0, 0, 0, 0.85))
		tgt.draw_string(GameTheme.font_display, name_p, name_txt,
			HORIZONTAL_ALIGNMENT_CENTER, 300, 18, col)


func _draw_labels(tgt: CanvasItem) -> void:
	if GameTheme.font_display == null:
		return
	for lb in _labels:
		var p: Vector2 = lb.pos
		var txt: String = lb.text
		# Floor place-name labels at a legible size — many were authored at 10-12px,
		# which read as unreadable clutter rather than the chart flavour intended.
		var sz: int = maxi(17, int(lb.size))
		if bool(lb.get("harbor", false)):
			# Harbour mark: a tiny town cluster + ring, name set off right.
			tgt.draw_rect(Rect2(p + Vector2(-9.0, -10.0), Vector2(5.0, 4.5)),
				Color(0.17, 0.13, 0.10, 0.92))
			tgt.draw_rect(Rect2(p + Vector2(-3.0, -12.5), Vector2(4.0, 6.5)),
				Color(0.20, 0.155, 0.115, 0.92))
			tgt.draw_rect(Rect2(p + Vector2(2.5, -9.5), Vector2(4.5, 4.0)),
				Color(0.14, 0.11, 0.085, 0.92))
			tgt.draw_arc(p, 4.2, 0, TAU, 14, Color(0.85, 0.80, 0.66, 0.65),
				1.2, true)
			tgt.draw_circle(p, 1.6, Color(0.85, 0.80, 0.66, 0.8))
			tgt.draw_string(GameTheme.font_display, p + Vector2(9, 4), txt,
				HORIZONTAL_ALIGNMENT_LEFT, 160, sz,
				Color(0.86, 0.80, 0.66, 0.82))
			continue
		# Real dark outline (was a faint 2px shadow that washed out over busy
		# terrain) and fuller alpha so the region names read at a glance.
		var col := Color(0.95, 0.89, 0.73, 0.95)
		if bool(lb.crimson):
			col = Color(0.97, 0.60, 0.44, 0.97)
		tgt.draw_string_outline(GameTheme.font_display, p + Vector2(-200, 0),
			txt, HORIZONTAL_ALIGNMENT_CENTER, 400, sz, 5, Color(0, 0, 0, 0.9))
		tgt.draw_string(GameTheme.font_display, p + Vector2(-200, 0),
			txt, HORIZONTAL_ALIGNMENT_CENTER, 400, sz, col)


func _draw_furniture(tgt: CanvasItem) -> void:
	var w: float = size.x
	var h: float = size.y
	# Compass rose — top-left ocean.
	var cp := Vector2(108.0, 132.0)
	tgt.draw_arc(cp, 26.0, 0, TAU, 40, Color(0.62, 0.66, 0.62, 0.45), 1.4, true)
	tgt.draw_arc(cp, 20.0, 0, TAU, 40, Color(0.62, 0.66, 0.62, 0.25), 1.0, true)
	for k in range(8):
		var ang := TAU * float(k) / 8.0
		var lng: float = 24.0 if k % 2 == 0 else 12.0
		tgt.draw_line(cp, cp + Vector2(cos(ang), sin(ang)) * lng,
			Color(0.70, 0.74, 0.68, 0.55 if k % 2 == 0 else 0.30),
			1.6 if k % 2 == 0 else 1.0, true)
	tgt.draw_colored_polygon(PackedVector2Array([cp + Vector2(0, -26),
		cp + Vector2(4, -8), cp + Vector2(-4, -8)]),
		Color(0.85, 0.80, 0.66, 0.8))
	if GameTheme.font_display != null:
		tgt.draw_string(GameTheme.font_display, cp + Vector2(-8, -32), "N",
			HORIZONTAL_ALIGNMENT_CENTER, 16, 13, Color(0.85, 0.80, 0.66, 0.8))
	# Scale bar removed: it implied a distance mechanic the game doesn't have, and
	# its 11px "TWELVE LEAGUES" was unreadable clutter in the corner. Compass kept.
	# Sea serpent — every honest chart has one.
	var sp := Vector2(w * 0.155, h * 0.815)
	var scol := Color(0.16, 0.30, 0.28, 0.85)
	for hump in range(3):
		var hc := sp + Vector2(float(hump) * 30.0, 0)
		tgt.draw_arc(hc, 13.0, PI, TAU, 16, scol, 4.0, true)
	var head := sp + Vector2(-22.0, -4.0)
	tgt.draw_colored_polygon(PackedVector2Array([head + Vector2(6, -8),
		head + Vector2(-12, -2), head + Vector2(6, 4)]), scol)
	tgt.draw_circle(head + Vector2(-1, -3), 1.4, Color(0.9, 0.85, 0.6, 0.9))


func _draw_political(tgt: CanvasItem, count: int, campaign: bool = true) -> void:
	# Claimed wash — and, on conquest runs, the rival's wash on every province
	# you haven't taken yet: the kingdom starts in his colors and your amber
	# eats them site by site. The dye is thinned (_faction_wash) so the
	# antique plate holds; wilds beyond the corridor stay unwashed.
	# The march dress keeps only the PLAYER's side of this — claimed amber
	# and the frontier rim. Rival dye + province borders are campaign-only:
	# they were the densest noise sitting directly behind the site chips.
	var rival_wash := _faction_wash()
	for i in range(count):
		var p := _prov[i]
		if p < 0 or _polys[i].size() < 3:
			continue
		if bool(_nodes[p].vis):
			tgt.draw_colored_polygon(_polys[i], Color(PLAYER_AMBER.r,
				PLAYER_AMBER.g, PLAYER_AMBER.b, 0.30))
		elif campaign and _faction_id != "":
			tgt.draw_colored_polygon(_polys[i], rival_wash)
	# Province borders along true cell edges; frontier rim bright.
	for i2 in range(count):
		if _prov[i2] < 0:
			continue
		for j in _nbrs[i2]:
			if j <= i2 or _prov[j] == _prov[i2]:
				continue
			var seg := _shared_edge(i2, j)
			if seg.size() < 2:
				continue
			if _prov[j] < 0:
				continue
			var a_avail: bool = _nodes[_prov[i2]].avail or _nodes[_prov[j]].avail
			var a_vis: bool = _nodes[_prov[i2]].vis or _nodes[_prov[j]].vis
			if a_avail and a_vis:
				tgt.draw_line(seg[0], seg[1], PLAYER_AMBER, 2.6, true)
			elif a_vis:
				tgt.draw_line(seg[0], seg[1], Color(PLAYER_AMBER.r,
					PLAYER_AMBER.g, PLAYER_AMBER.b, 0.55), 1.8, true)
			elif not campaign:
				continue
			elif _faction_id != "":
				# Interior borders of the unconquered kingdom carry his dye —
				# the land reads as provinces of HIS realm, not neutral ink.
				# Kept faint: these run right through the site corridor.
				tgt.draw_line(seg[0], seg[1], Color(_faction_color.r * 0.6,
					_faction_color.g * 0.6, _faction_color.b * 0.6, 0.38),
					1.2, true)
			else:
				tgt.draw_line(seg[0], seg[1],
					Color(0.05, 0.05, 0.04, 0.38), 1.4, true)


func _draw_decorations(tgt: CanvasItem, count: int) -> void:
	var drng := RandomNumberGenerator.new()
	drng.seed = 808
	for i in range(count):
		if not _land[i]:
			continue
		var p := _seed_pts[i]
		# Hachures — Lehmann-style short downslope strokes; steeper slopes
		# get more and darker strokes, flat country is left blank. This is
		# the engraved-map relief texture under the symbol layer.
		var g := _grad[i]
		var slope := g.length() * 9.0
		# Hachures stop short of the corridor — relief strokes under the
		# campaign ink read as clutter, not relief.
		if slope > 0.30 and _road_d[i] > 70.0 \
				and _biome[i] in [B_GRASS, B_HILLS, B_ROCK, B_BEACH]:
			var down := -g.normalized()
			var n_h := 2 if slope > 0.75 else 1
			for hk in range(n_h):
				var hp := p + down.orthogonal() \
					* (float(hk) - float(n_h - 1) * 0.5) * 5.0 \
					+ Vector2(drng.randf_range(-2.5, 2.5),
						drng.randf_range(-2.5, 2.5))
				tgt.draw_line(hp, hp + down * drng.randf_range(5.0, 8.5),
					Color(0.05, 0.04, 0.03,
						clampf(0.05 + slope * 0.11, 0.0, 0.20)), 1.0, true)
		match _biome[i]:
			B_FOREST:
				# Dense stands of small trees with canopy shadows — woods
				# should read as a texture mass at full-map zoom. The road
				# keeps a cleared verge through them (and the chips with it).
				if _road_d[i] > 48.0 and drng.randf() < 0.72:
					for _t in range(drng.randi_range(1, 3)):
						var tp := p + Vector2(drng.randf_range(-9.0, 9.0),
							drng.randf_range(-8.0, 8.0))
						var s := drng.randf_range(2.6, 4.4)
						var shade := drng.randf_range(0.80, 1.22)
						var col := Color(0.085 * shade, 0.140 * shade,
							0.075 * shade, 0.95)
						tgt.draw_circle(tp + Vector2(1.4, 1.6), s * 0.85,
							Color(0.02, 0.04, 0.02, 0.30))
						tgt.draw_colored_polygon(PackedVector2Array([
							tp + Vector2(0, -s * 1.5),
							tp + Vector2(s * 0.8, s * 0.5),
							tp + Vector2(-s * 0.8, s * 0.5)]), col)
						tgt.draw_line(tp + Vector2(0, s * 0.5),
							tp + Vector2(0, s * 1.0),
							Color(0.07, 0.06, 0.04, 0.8), 1.0, true)
			B_ROCK, B_SNOW:
				# Ridge chains: offset peaks so ranges read as continuous
				# chains, the way painted maps draw them. Never ON the road —
				# a peak glyph over a chip kills both.
				if _road_d[i] > 40.0 and drng.randf() < 0.55:
					for _pk in range(drng.randi_range(1, 2)):
						var pc := p + Vector2(drng.randf_range(-8.0, 8.0),
							drng.randf_range(-6.0, 6.0))
						var s2 := drng.randf_range(4.0, 7.5)
						var apex := pc + Vector2(0, -s2 * 1.3)
						tgt.draw_colored_polygon(PackedVector2Array([apex,
							pc + Vector2(s2, s2 * 0.6),
							pc + Vector2(-s2, s2 * 0.6)]),
							Color(0.30, 0.28, 0.25, 0.9))
						tgt.draw_colored_polygon(PackedVector2Array([apex,
							pc + Vector2(s2, s2 * 0.6),
							pc + Vector2(s2 * 0.1, s2 * 0.6)]),
							Color(0.16, 0.14, 0.12, 0.9))
						if _biome[i] == B_SNOW:
							tgt.draw_colored_polygon(PackedVector2Array([apex,
								apex + Vector2(s2 * 0.45, s2 * 0.75),
								apex + Vector2(-s2 * 0.45, s2 * 0.75)]),
								Color(0.88, 0.90, 0.92, 0.95))
			B_SCORCH:
				if drng.randf() < 0.20:
					tgt.draw_circle(p + Vector2(drng.randf_range(-8, 8),
						drng.randf_range(-8, 8)), drng.randf_range(1.0, 2.0),
						Color(1.0, 0.50, 0.15, 0.6))
				if drng.randf() < 0.22:
					# Cracked lava ground — short dark fissures.
					var ca := drng.randf_range(0.0, TAU)
					var cv := Vector2(cos(ca), sin(ca))
					var cp2 := p + Vector2(drng.randf_range(-7.0, 7.0),
						drng.randf_range(-7.0, 7.0))
					tgt.draw_line(cp2 - cv * drng.randf_range(3.0, 6.0),
						cp2 + cv * drng.randf_range(3.0, 6.0),
						Color(0.05, 0.02, 0.015, 0.55), 1.2, true)
			B_HILLS:
				if _elev[i] > 0.58 and drng.randf() < 0.30:
					# Foothill peak — bridges the hills into the ranges.
					var s3 := drng.randf_range(3.2, 5.2)
					var apex3 := p + Vector2(0, -s3 * 1.2)
					tgt.draw_colored_polygon(PackedVector2Array([apex3,
						p + Vector2(s3, s3 * 0.55),
						p + Vector2(-s3, s3 * 0.55)]),
						Color(0.26, 0.23, 0.17, 0.85))
					tgt.draw_colored_polygon(PackedVector2Array([apex3,
						p + Vector2(s3, s3 * 0.55),
						p + Vector2(s3 * 0.1, s3 * 0.55)]),
						Color(0.15, 0.13, 0.10, 0.85))
				elif drng.randf() < 0.22:
					tgt.draw_arc(p, drng.randf_range(4.0, 6.5), PI, TAU, 10,
						Color(0.18, 0.15, 0.09, 0.5), 1.5, true)
			B_GRASS:
				if _road_d[i] > 55.0 and _road_d[i] < 170.0 and slope < 0.45 \
						and drng.randf() < 0.38:
					# Tilled fields along the roads — settled country reads
					# as furrow strokes on a quantised axis.
					var fa := float((i * 7) % 4) * PI * 0.25
					var ax := Vector2(cos(fa), sin(fa))
					for fk in range(3):
						var fp := p + ax.orthogonal() \
							* (float(fk) - 1.0) * 4.2
						tgt.draw_line(fp - ax * 5.5, fp + ax * 5.5,
							Color(0.22, 0.19, 0.10, 0.16), 1.0, true)
				elif drng.randf() < 0.13:
					# Scrub dots in the open meadow.
					tgt.draw_circle(p + Vector2(drng.randf_range(-7.0, 7.0),
						drng.randf_range(-6.0, 6.0)),
						drng.randf_range(0.9, 1.6),
						Color(0.20, 0.20, 0.10, 0.35))


func _draw_routes(tgt: CanvasItem) -> void:
	# Two layers, two jobs (the genre split — StS, HoMM, every war-room map):
	#
	# 1. The road NETWORK is terrain — a quiet incised groove (NW light:
	#    shadow lip / lit lip / dark channel / packed-earth floor). It says
	#    "the island has roads", nothing about your war.
	# 2. The CAMPAIGN is ink stamped OVER the roads — cased dashes, the
	#    dashed-line journey convention of antique charts:
	#      amber dashes + chevron → legs you can march NOW (the decision)
	#      crimson dashes         → legs the army actually marched
	#      bare groove            → passed-by doors and the far future
	#
	# The old uniform treatment (full groove everywhere + a 1.9px state
	# thread riding inside it) gave every leg equal weight and the state
	# color died on olive terrain at chart zoom — the run's decision
	# structure didn't read. Dark iron-gall casings under the dashes keep
	# the ink alive on any biome (cartographic route casing).
	var lightv := Vector2(-0.707, -0.707)
	# Road hierarchy — quartermaster grammar: legs whose BOTH ends sit on the
	# centre lane are the trunk road (the 3× merge bias parks most of the act
	# there) and get a wider groove with a cased DOUBLE floor thread; branch
	# legs keep the single thread. The act's structure — one main road, side
	# loops — now reads in a single look. Endpoint test, not edge metadata:
	# curve ends ARE the station positions (the bow only moves the middle).
	# Tolerance 12px: node scatter is ±7 vertical, lane pitch ~100 — still
	# unambiguous, only true centre-lane stops land inside it.
	var lane_cy := size.y * 0.535
	for ei in range(_edge_curves.size()):
		var pts: PackedVector2Array = _edge_curves[ei]
		var trunk: bool = pts.size() >= 2 \
			and absf(pts[0].y - lane_cy) < 12.0 \
			and absf(pts[pts.size() - 1].y - lane_cy) < 12.0
		var wmul := 1.22 if trunk else 1.0
		var network_alpha := 1.0
		if ei < _edges.size():
			var edge_state: Dictionary = _edges[ei]
			var active: bool = bool(edge_state.to_avail) \
				or (bool(edge_state.from_vis) and bool(edge_state.get("to_vis", false)))
			if not active:
				network_alpha = 0.58
				wmul *= 0.90
		tgt.draw_polyline(_offset_pts(pts, lightv * 1.9),
			Color(0.020, 0.015, 0.010, 0.42 * network_alpha),
			5.2 * wmul, true)
		tgt.draw_polyline(_offset_pts(pts, lightv * -1.9),
			Color(0.88, 0.80, 0.60, 0.22 * network_alpha),
			4.6 * wmul, true)
		tgt.draw_polyline(pts,
			Color(0.055, 0.045, 0.032, 0.72 * network_alpha),
			4.0 * wmul, true)
		if trunk:
			var pv := Vector2(0, 1.5)
			tgt.draw_polyline(_offset_pts(pts, pv),
				Color(0.47, 0.395, 0.262, 0.80 * network_alpha),
				1.5, true)
			tgt.draw_polyline(_offset_pts(pts, -pv),
				Color(0.47, 0.395, 0.262, 0.80 * network_alpha),
				1.5, true)
		else:
			tgt.draw_polyline(pts,
				Color(0.47, 0.395, 0.262, 0.80 * network_alpha),
				1.9, true)
	# Campaign ink in a second pass so no groove ever carves through a
	# neighbouring leg's dashes.
	for ei in range(_edge_curves.size()):
		var e: Dictionary = _edges[ei]
		if bool(e.to_avail):
			# Soft lamplight underglow along the whole open leg — the
			# frontier outranks the marched history in the hierarchy, and
			# short legs (2-3 dashes) keep presence even at chart zoom.
			tgt.draw_polyline(_edge_curves[ei],
				Color(PLAYER_AMBER.r, PLAYER_AMBER.g, PLAYER_AMBER.b, 0.16),
				9.0, true)
			_stamp_route_dashes(tgt, _edge_curves[ei], ei,
				PLAYER_AMBER, 4.2, 11.0, 7.5, true)
			_stamp_terrain_glyph(tgt, _edge_curves[ei], _edges[ei].b)
		elif bool(e.from_vis) and bool(e.get("to_vis", false)):
			# Brighter than the political CRIMSON wash — the marched line
			# sits over a dark casing and must not silt into it.
			_stamp_route_dashes(tgt, _edge_curves[ei], ei,
				Color(0.80, 0.24, 0.16, 0.97), 3.6, 9.0, 6.5, false)
	for br in _bridges:
		var p: Vector2 = br.pos
		var dirv: Vector2 = br.dirv
		var pp := dirv.orthogonal()
		for k in range(-2, 3):
			var c := p + dirv * float(k) * 3.6
			tgt.draw_line(c + pp * 7.0, c - pp * 7.0,
				Color(0.24, 0.17, 0.10, 0.95), 2.2, true)


func _offset_pts(pts: PackedVector2Array, v: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + v)
	return out


## Campaign-ink dash run along a road curve: short strokes with a dark
## iron-gall casing, hand-jittered (seeded per edge, so every bake of the
## same act lays the same ink). Dashes inset from both chip ends; `arrow`
## caps the destination end with a march chevron just short of the chip.
func _stamp_route_dashes(tgt: CanvasItem, pts: PackedVector2Array, seed_i: int,
		ink: Color, w: float, dash: float, gap: float, arrow: bool) -> void:
	if pts.size() < 2:
		return
	var cum := PackedFloat32Array()
	cum.append(0.0)
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
		cum.append(total)
	var inset_a := 19.0
	var inset_b := 30.0 if arrow else 19.0
	var casing := Color(0.06, 0.045, 0.025, 0.78)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("campaign_ink") * 31 + seed_i
	var d := inset_a + rng.randf() * 2.5
	while d + dash <= total - inset_b:
		var a := _route_arc_point(pts, cum, d)
		var b := _route_arc_point(pts, cum, d + dash)
		var jit: Vector2 = (b - a).normalized().orthogonal() \
			* rng.randf_range(-0.7, 0.7)
		tgt.draw_line(a + jit, b + jit, casing, w + 3.2, true)
		tgt.draw_line(a + jit, b + jit, ink, w, true)
		d += dash + gap + rng.randf_range(-0.8, 1.2)
	if arrow and total > inset_a + 32.0:
		# Chevron at the door: tip ~20px short of the chip center so it
		# kisses the ring without crossing it; wings sweep back along the
		# road tangent (HoMM's "you can reach this" arrow, chart-inked).
		var tip := _route_arc_point(pts, cum, total - 20.0)
		var back := _route_arc_point(pts, cum, total - 29.0)
		var tv := (tip - back).normalized()
		var nv := tv.orthogonal()
		for s in [1.0, -1.0]:
			var wing: Vector2 = tip - tv * 11.0 + nv * 8.0 * s
			tgt.draw_line(tip, wing, casing, w + 3.2, true)
			tgt.draw_line(tip, wing, ink, w, true)


## Phase 2.5 — terrain badge on an open leg: a small inked roundel at
## mid-road telling you what country the march crosses (pine = woods,
## peaks = the pass, flame = ash). Meadow is the default and stays
## unbadged — absence reads as the easy road. The destination node's tag
## is looked up by position; legs too short for a clean dash run skip
## the badge rather than crowd the chevron.
func _stamp_terrain_glyph(tgt: CanvasItem, pts: PackedVector2Array,
		dest: Vector2) -> void:
	var terrain := ""
	for m in _nodes:
		if (m.pos as Vector2).distance_to(dest) < 2.0:
			terrain = String(m.get("terrain", ""))
			break
	if terrain == "" or terrain == "meadow":
		return
	var cum := PackedFloat32Array()
	cum.append(0.0)
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
		cum.append(total)
	if total < 80.0:
		return
	var c := _route_arc_point(pts, cum, total * 0.5)
	var ink := PLAYER_AMBER
	tgt.draw_circle(c, 10.5, Color(0.06, 0.045, 0.025, 0.92))
	tgt.draw_arc(c, 10.5, 0, TAU, 26,
		Color(ink.r, ink.g, ink.b, 0.9), 1.5, true)
	match terrain:
		"woods":
			tgt.draw_line(c + Vector2(0, -5.6), c + Vector2(-4.5, 3.2), ink, 1.8, true)
			tgt.draw_line(c + Vector2(0, -5.6), c + Vector2(4.5, 3.2), ink, 1.8, true)
			tgt.draw_line(c + Vector2(-4.5, 3.2), c + Vector2(4.5, 3.2), ink, 1.8, true)
			tgt.draw_line(c + Vector2(0, 3.2), c + Vector2(0, 5.8), ink, 1.8, true)
		"pass":
			tgt.draw_line(c + Vector2(-5.8, 4.2), c + Vector2(-1.0, -4.8), ink, 1.8, true)
			tgt.draw_line(c + Vector2(-1.0, -4.8), c + Vector2(2.0, 1.0), ink, 1.8, true)
			tgt.draw_line(c + Vector2(2.0, 1.0), c + Vector2(4.0, -2.0), ink, 1.8, true)
			tgt.draw_line(c + Vector2(4.0, -2.0), c + Vector2(6.1, 4.2), ink, 1.8, true)
		"ash":
			tgt.draw_line(c + Vector2(-3.0, 4.2), c + Vector2(-0.5, -5.2), ink, 1.8, true)
			tgt.draw_line(c + Vector2(3.0, 4.2), c + Vector2(-0.5, -5.2), ink, 1.8, true)
			tgt.draw_line(c + Vector2(-3.0, 4.2), c + Vector2(3.0, 4.2), ink, 1.8, true)
			tgt.draw_line(c + Vector2(2.2, -1.2), c + Vector2(3.7, -3.7), ink, 1.6, true)


## Point at arc-distance `d` along a polyline whose cumulative segment
## lengths are `cum` (same convention as MapPulseOverlay's march walk).
func _route_arc_point(pts: PackedVector2Array, cum: PackedFloat32Array,
		d: float) -> Vector2:
	d = clampf(d, 0.0, cum[cum.size() - 1])
	for i in range(1, pts.size()):
		if d <= cum[i]:
			var seg := cum[i] - cum[i - 1]
			var t := 0.0 if seg <= 0.0 else (d - cum[i - 1]) / seg
			return pts[i - 1].lerp(pts[i], t)
	return pts[pts.size() - 1]


func _draw_sea_segments(tgt: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	# Rule a line in short dashes, skipping every dash whose midpoint falls
	# on land (or off the pinned sheet) — cheap clipping for the graticule.
	var n := maxi(int(a.distance_to(b) / 22.0), 1)
	for k in range(n):
		var p0 := a.lerp(b, float(k) / float(n))
		var p1 := a.lerp(b, (float(k) + 0.8) / float(n))
		var mid := (p0 + p1) * 0.5
		var ci := _cell_at(mid)
		if ci >= 0 and not _land[ci] and _inside_sheet(mid, 12.0):
			tgt.draw_line(p0, p1, col, 1.0, true)


## Per-type chip dress: radius (fights are the road's milestones — bigger
## than waysides, so the skeleton's fight…stop…stop…fight rhythm is visible
## at a glance) + the dye the parchment disc is washed with.
# Node radii sized for legibility: open fights read ~5-6% of screen height
# (the readable band shipped maps use — base StS only gets away with smaller
# because it scrolls ~7 floors at once; we show the whole act). Hierarchy:
# General > fight > services > wayside.
const SITE_STYLE := {
	"combat": {"r": 20.0, "tint": Color(0.62, 0.15, 0.10), "wash": 0.12},
	"elite": {"r": 23.0, "tint": Color(0.62, 0.13, 0.09), "wash": 0.26},
	"rest": {"r": 18.0, "tint": Color(0.95, 0.55, 0.20), "wash": 0.18},
	"shop": {"r": 18.0, "tint": Color(0.74, 0.56, 0.16), "wash": 0.18},
	"event": {"r": 18.0, "tint": Color(0.44, 0.28, 0.56), "wash": 0.17},
	"treasure": {"r": 18.0, "tint": Color(0.88, 0.68, 0.18), "wash": 0.24},
	"recruit": {"r": 18.0, "tint": Color(0.22, 0.38, 0.55), "wash": 0.18},
	"wayside": {"r": 17.0, "tint": Color(0.42, 0.35, 0.24), "wash": 0.10},
	# Boss ("THE KEEP") is drawn as separate keep furniture on the plate, but the
	# legend looks its style up here — deep crimson so the legend chip reads as the
	# act climax rather than a dull wayside-fallback disc.
	"boss": {"r": 25.0, "tint": Color(0.55, 0.10, 0.08), "wash": 0.30},
}

# Per-type medallion materials — an enamel FACE, a metal BEZEL, and the icon
# INK (raised light metal on the enamel). This is the card kit's material
# vocabulary (aged bronze/silver/gold + enamel) brought to the chart so the
# stops read as struck campaign tokens, not flat coins. Lit top-left to match
# the plate's NW light. Locked stops are auto-dimmed by _draw_medallion.
# Distinct per-type colour wheel so "what is what" reads at a glance (the
# lesson from StS's confusable all-black icons): red=fight, red+gold=General,
# orange=rest, GREEN=shop, GOLD=treasure, violet=event, blue=recruit,
# tan=wayside. Shop was gold like treasure — split to green so they never
# confuse.
const SITE_MAT := {
	# FIGHT (the commonest stop) and wayside stay quiet; the DECISION stops
	# (rest/shop/event/treasure/recruit) wear brighter enamel — at chart zoom
	# the old dark faces all collapsed into identical dark coins, and it's
	# the rare stops popping that makes route-planning read at a glance.
	"combat":   {"face": Color(0.46, 0.16, 0.12), "bezel": Color(0.37, 0.33, 0.30), "ink": Color(0.97, 0.92, 0.82)},
	"elite":    {"face": Color(0.34, 0.10, 0.10), "bezel": Color(0.66, 0.49, 0.22), "ink": Color(1.00, 0.90, 0.58)},
	"rest":     {"face": Color(0.60, 0.31, 0.12), "bezel": Color(0.70, 0.48, 0.25), "ink": Color(1.00, 0.80, 0.46)},
	"shop":     {"face": Color(0.16, 0.42, 0.27), "bezel": Color(0.76, 0.59, 0.25), "ink": Color(0.84, 0.96, 0.80)},
	"event":    {"face": Color(0.42, 0.24, 0.60), "bezel": Color(0.49, 0.45, 0.55), "ink": Color(0.95, 0.88, 1.00)},
	"treasure": {"face": Color(0.50, 0.38, 0.11), "bezel": Color(0.88, 0.68, 0.28), "ink": Color(1.00, 0.92, 0.56)},
	"recruit":  {"face": Color(0.17, 0.33, 0.50), "bezel": Color(0.53, 0.60, 0.68), "ink": Color(0.90, 0.95, 1.00)},
	"wayside":  {"face": Color(0.34, 0.30, 0.22), "bezel": Color(0.59, 0.51, 0.38), "ink": Color(0.96, 0.91, 0.78)},
	"boss":     {"face": Color(0.35, 0.09, 0.08), "bezel": Color(0.64, 0.22, 0.15), "ink": Color(1.00, 0.86, 0.60)},
}

# Engraved site names printed at the tokens (antique charts label their own
# symbols). These REPLACED the bottom legend band (2026-07-07 — the band was
# one HUD too many): the key now sits at every unstruck stop, and the hover
# tooltip carries the deeper intel (encounter, mutator, terrain, bridge).
# "General" is the player-facing word for elite; waysides print their verb so
# a Drill Yard reads different from a Cache without a key.
const SITE_LABEL := {
	"combat": "FIGHT", "elite": "GENERAL", "rest": "REST", "shop": "SHOP",
	"event": "EVENT", "treasure": "TREASURE", "recruit": "RECRUIT",
}
const WAYSIDE_LABEL := {
	"drill_yard": "DRILL YARD", "standard_bearer": "BANNER",
	"supply_cache": "CACHE", "muster_scale": "SCALES",
}


func _site_label_text(typ: String, nd: Dictionary) -> String:
	if typ == "wayside":
		return String(WAYSIDE_LABEL.get(String(nd.get("wayside_id", "")),
			"WAYSIDE"))
	return String(SITE_LABEL.get(typ, ""))


func _site_label_visible(typ: String, nd: Dictionary, open_now: bool) -> bool:
	# The icons now carry most site identity, so labels become emphasis:
	# reachable choices, high-value route planning stops, and named waysides.
	# Hiding locked ordinary FIGHT/EVENT/RECRUIT text removes the map's worst
	# clutter while the hover tooltip keeps the deep intel.
	if open_now:
		return true
	if typ in ["elite", "rest", "shop", "treasure"]:
		return true
	if typ == "wayside":
		var wid := String(nd.get("wayside_id", ""))
		return wid in ["supply_cache", "drill_yard"]
	return false


func _draw_sites(tgt: CanvasItem) -> void:
	# Marker hierarchy — the cool of a campaign map is reading the campaign:
	#   conquered  → planted amber pennant (the land is yours)
	#   reachable  → light disc at full strength, amber ring + halo
	#   far future → same light disc, dimmed and ink-ringed
	# Discs are pale parchment with DARK ink glyphs — the value flip off the
	# olive terrain is what makes site types readable at chart zoom (the old
	# dark-coin chips with dark-gold glyphs all read as identical dots).
	for nd in _nodes:
		var p: Vector2 = nd.pos
		var typ: String = nd.type
		if typ == "boss":
			continue
		var visited: bool = nd.vis
		var open_now: bool = nd.avail
		if visited:
			# Claimed: a spent, dimmed medallion with the amber pennant planted
			# in it, so the marched road still reads as a chain of struck tokens.
			var vst: Dictionary = SITE_STYLE.get(typ, SITE_STYLE["wayside"])
			var vmat: Dictionary = SITE_MAT.get(typ, SITE_MAT["wayside"])
			_draw_medallion(tgt, p, float(vst.r) * 0.84, vmat, false)
			tgt.draw_line(p + Vector2(0, 1), p + Vector2(0, -22),
				Color(0.07, 0.06, 0.04), 2.2, true)
			tgt.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -22),
				p + Vector2(15, -17.5), p + Vector2(0, -13)]), PLAYER_AMBER)
			tgt.draw_line(p + Vector2(0, -22), p + Vector2(0, -13),
				Color(0.30, 0.16, 0.05), 1.0, true)
			continue
		var st: Dictionary = SITE_STYLE.get(typ, SITE_STYLE["wayside"])
		var mat: Dictionary = SITE_MAT.get(typ, SITE_MAT["wayside"])
		# Reachable stops sit a bigger medallion (+5) so the "where can I go
		# next" read is unmistakable; far-future stops stay at base, dimmed.
		var r: float = float(st.r) + (5.0 if open_now else 0.0)
		# Hearth glow under the rest medallion — a safe light on the road.
		if typ == "rest":
			tgt.draw_circle(p, r + 9.0, Color(1.0, 0.62, 0.25,
				0.16 if open_now else 0.09))
		# Reachable lamplight — a soft amber pool the locked stops don't get.
		if open_now:
			tgt.draw_circle(p, r + 16.0, Color(PLAYER_AMBER.r, PLAYER_AMBER.g,
				PLAYER_AMBER.b, 0.09))
			tgt.draw_circle(p, r + 9.5, Color(PLAYER_AMBER.r, PLAYER_AMBER.g,
				PLAYER_AMBER.b, 0.10))
		# The medallion: cast shadow, beveled metal bezel, recessed enamel face.
		_draw_medallion(tgt, p, r, mat, open_now)
		# Rim ring: Generals always wear the rival crimson; any other open stop
		# wears bright amber; locked plain stops let the bezel carry it.
		if typ == "elite":
			tgt.draw_arc(p, r + 0.6, 0, TAU, 36,
				Color(CRIMSON.r, CRIMSON.g, CRIMSON.b, 0.95),
				2.8 if open_now else 2.2, true)
		elif open_now:
			tgt.draw_arc(p, r + 0.6, 0, TAU, 36, PLAYER_AMBER, 2.8, true)
		# Colour-blind-safe reachability cue (shape, not just colour): an open
		# stop wears a "march here" chevron under it. Locked stops carry NO
		# stamp — the old per-node padlock repeated 15-20× per act was pure
		# noise; dimming + the missing ring/chevron already say "not yet".
		if open_now:
			var cy := p + Vector2(0, r + 11.0)
			for dy in [0.0, 4.0]:
				tgt.draw_polyline(PackedVector2Array([
					cy + Vector2(-6.2, 3.6 + dy), cy + Vector2(0, -1.8 + dy),
					cy + Vector2(6.2, 3.6 + dy)]),
					Color(0.10, 0.07, 0.05, 0.95), 2.1, true)
		# Type glyph as a bold outlined sticker, sized off the ACTUAL radius so
		# reachable (bigger) stops also get a bigger, more legible symbol. The
		# icon is the HERO — big and near-white so the SHAPE, not the frame,
		# is what the eye lands on.
		var ipx := r * 1.58
		var gink: Color = (mat.ink as Color).lerp(Color(1.0, 1.0, 1.0), 0.34)
		if not open_now:
			gink = gink.darkened(0.06)
			gink.a = 0.95
		var drew_glyph := _draw_core_site_glyph(tgt, p, ipx * 0.52, gink, typ)
		if typ == "wayside":
			# Per-verb glyph, embossed by a dark underdraw then the light ink.
			if not drew_glyph:
				_draw_wayside_glyph(tgt, p + Vector2(1.0, 1.2), ipx * 0.5,
					Color(0, 0, 0, 0.40), String(nd.get("wayside_id", "")))
				drew_glyph = _draw_wayside_glyph(tgt, p, ipx * 0.5, gink,
					String(nd.get("wayside_id", "")))
		elif typ == "recruit":
			# A "draft a card" glyph reads as a free draft far better than the
			# old flag (a flag says nothing about taking a card).
			_draw_card_glyph(tgt, p, ipx * 0.52, gink)
			drew_glyph = true
		elif typ == "event":
			# An open book reads as "a story happens here" — bolder and clearer
			# than the busy scroll silhouette, and on-theme with the chart.
			_draw_event_glyph(tgt, p, ipx * 0.52, gink)
			drew_glyph = true
		if not drew_glyph:
			var tex: Texture2D = _node_icon(typ)
			if tex != null:
				_draw_emboss_icon(tgt, tex, p, ipx, gink)
		if String(nd.get("mutator_id", "")) != "":
			# Mutator star — same signal as the old chart, on the chip's rim.
			_draw_star(tgt, p + Vector2(r * 0.78, -r * 0.78), 6.0,
				Color(1.0, 0.84, 0.30, 0.95))
		# Pursuit mark — once the rival's response is riding (2+ holds
		# broken), every unbroken hold wears a crimson outrider pennant
		# over its left shoulder: the road has hardened since you landed.
		if typ == "combat" and RunState.holds_broken_in_act >= 2:
			var fp := p + Vector2(-r * 0.95, -r * 0.62)
			tgt.draw_line(fp, fp + Vector2(0, -11.0),
				Color(0.10, 0.05, 0.03, 0.95), 1.8, true)
			tgt.draw_colored_polygon(PackedVector2Array([
				fp + Vector2(0, -11.0), fp + Vector2(-8.5, -8.2),
				fp + Vector2(0, -5.6)]),
				Color(0.85, 0.25, 0.18, 0.95))
		# The engraved site name under the token (see SITE_LABEL). Struck
		# stops stay quiet (skipped above) and the keep has its own plaque.
		# Deterministic — bakes into the plate ink like everything else here.
		var ltxt: String = _site_label_text(typ, nd)
		if ltxt != "" and _site_label_visible(typ, nd, open_now) \
				and GameTheme.font_display != null:
			var lsz := 11 if open_now else 10
			var lcol := Color(0.94, 0.86, 0.66, 1.0) if open_now \
				else Color(0.76, 0.68, 0.52, 0.92)
			# Below the token by default; lane scatter can pull the next lane's
			# stop within ~76px, so a crowded slot sets the name ABOVE instead
			# (the mutator star and pursuit pennant hug the rim — a baseline at
			# -(r+12) clears both).
			var crowd := false
			for qn in _nodes:
				var q: Vector2 = qn.pos
				# Window covers the 90px lane pitch + full scatter — a stack
				# that misses by a hair leaves two labels piled in the same
				# inter-node gap (the EVENT-over-CACHE read).
				if q != p and absf(q.x - p.x) < 48.0 \
						and q.y - p.y > 8.0 and q.y - p.y < 118.0:
					crowd = true
					break
			var lbase: Vector2
			if crowd:
				lbase = p + Vector2(0.0, -(r + 12.0))
			else:
				lbase = p + Vector2(0.0, r + (30.0 if open_now else 20.0))
			var lw := GameTheme.font_display.get_string_size(ltxt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, lsz).x
			var lpos := Vector2(lbase.x - lw * 0.5, lbase.y)
			tgt.draw_string_outline(GameTheme.font_display, lpos, ltxt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, lsz, 4,
				Color(0.03, 0.025, 0.02, 0.88))
			tgt.draw_string(GameTheme.font_display, lpos, ltxt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, lsz, lcol)


## A site marker as an enamel-and-metal medallion pressed into the chart: soft
## cast shadow, dark keyline, a beveled metal bezel (lit top-left per the
## plate's NW light), and a recessed enamel face with an ambient-occlusion rim
## and a soft specular. Locked stops are dimmed here so callers don't have to.
func _draw_medallion(tgt: CanvasItem, p: Vector2, r: float, mat: Dictionary,
		open_now: bool) -> void:
	var bezel: Color = mat.bezel
	var face: Color = mat.face
	# Pull the enamel chroma down a step so the tokens sit IN the sepia
	# chart world — hue keeps the type coding, the drop stops them reading
	# as candy stickers on the paper.
	var fg := (face.r + face.g + face.b) / 3.0
	face = Color(lerpf(face.r, fg, 0.16), lerpf(face.g, fg, 0.16),
		lerpf(face.b, fg, 0.16))
	if not open_now:
		bezel = bezel.darkened(0.28)
		face = face.darkened(0.20)
	# Soft cast shadow — two stacked discs read softer than one hard circle.
	tgt.draw_circle(p + Vector2(2.6, 4.2), r + 1.5, Color(0, 0, 0, 0.16))
	tgt.draw_circle(p + Vector2(1.8, 2.8), r + 0.4, Color(0, 0, 0, 0.22))
	# Dark keyline so the medallion crisps off the parchment.
	tgt.draw_circle(p, r + 1.3, Color(0.06, 0.05, 0.04, 0.88))
	# Bezel base, then the recessed enamel face. Bezel share thinned 0.19 →
	# 0.14: at node radii the fat rim ate the enamel and every token read as
	# a dark ring — the face (the type colour) is the payload, not the metal.
	tgt.draw_circle(p, r, bezel)
	var rf: float = r - maxf(2.2, r * 0.14)
	tgt.draw_circle(p, rf, face)
	# Ambient occlusion just inside the bezel (the face sits below the rim).
	tgt.draw_arc(p, rf - 0.8, 0, TAU, 32, face.darkened(0.52), 2.2, true)
	# Beveled rim: a bright lit arc top-left, a deep shadow arc bottom-right —
	# the bevel is what sells "struck metal" over "flat ring".
	var bw: float = maxf(2.0, r * 0.14)
	var rb: float = r - bw * 0.5
	tgt.draw_arc(p, rb, PI * 1.00, PI * 1.66, 24, bezel.lightened(0.58), bw, true)
	tgt.draw_arc(p, rb, PI * 0.00, PI * 0.60, 24, bezel.darkened(0.50), bw, true)
	# A tiny rivet of pure rim-light at the very top-left of the bezel.
	tgt.draw_arc(p, rb, PI * 1.18, PI * 1.40, 8, bezel.lightened(0.85),
		bw * 0.6, true)
	# Soft specular on the enamel, top-left.
	tgt.draw_circle(p + Vector2(-rf * 0.30, -rf * 0.30), rf * 0.36,
		Color(1.0, 0.98, 0.92, 0.10))


## Stamp a silhouette icon as a bold "sticker": a crisp dark contour (8-way
## offset) so the SHAPE reads at node size on any face colour, a bright fill,
## and a whisper of top-left rim-light to keep the struck-metal feel. A soft
## emboss blurred small icons into blobs — a hard outline is far more legible.
func _draw_emboss_icon(tgt: CanvasItem, tex: Texture2D, p: Vector2,
		ipx: float, ink: Color) -> void:
	var sz := Vector2(ipx, ipx)
	var base := p - sz * 0.5
	var oc := Color(0.05, 0.04, 0.03, 0.92)
	var ow: float = maxf(1.5, ipx * 0.07)
	for a in range(8):
		var ang := float(a) / 8.0 * TAU
		tgt.draw_texture_rect(tex,
			Rect2(base + Vector2(cos(ang), sin(ang)) * ow, sz), false, oc)
	tgt.draw_texture_rect(tex, Rect2(base, sz), false, ink)
	tgt.draw_texture_rect(tex, Rect2(base + Vector2(-0.9, -1.0), sz), false,
		Color(1.0, 1.0, 0.96, 0.16))


func _draw_core_site_glyph(tgt: CanvasItem, c: Vector2, s: float,
		ink: Color, typ: String) -> bool:
	if typ not in ["combat", "elite", "rest", "shop", "treasure"]:
		return false
	var shadow := Color(0.05, 0.04, 0.03, 0.92)
	_draw_core_site_glyph_shape(tgt, c + Vector2(1.2, 1.4), s, shadow, typ)
	_draw_core_site_glyph_shape(tgt, c, s, ink, typ)
	return true


func _draw_core_site_glyph_shape(tgt: CanvasItem, c: Vector2, s: float,
		ink: Color, typ: String) -> void:
	var lw: float = maxf(2.0, s * 0.18)
	match typ:
		"combat":
			# Crossed blades: one glance = fight, and much cleaner at 40px than
			# the old detailed SVG pair.
			for side in [-1.0, 1.0]:
				var a := c + Vector2(-s * 0.56 * side, s * 0.58)
				var b := c + Vector2(s * 0.54 * side, -s * 0.58)
				tgt.draw_line(a, b, ink, lw, true)
				var dir := (b - a).normalized()
				var n := dir.orthogonal()
				tgt.draw_line(a + dir * s * 0.30 - n * s * 0.20,
					a + dir * s * 0.30 + n * s * 0.20, ink, lw * 0.72, true)
				tgt.draw_circle(a - dir * s * 0.08, lw * 0.75, ink)
		"elite":
			# Crested war helm, not just another crossed-sword marker. Generals
			# now read as command figures before the label is parsed.
			var bowl := PackedVector2Array([
				c + Vector2(-s * 0.68, s * 0.05),
				c + Vector2(-s * 0.48, -s * 0.46),
				c + Vector2(0, -s * 0.66),
				c + Vector2(s * 0.48, -s * 0.46),
				c + Vector2(s * 0.68, s * 0.05),
				c + Vector2(s * 0.36, s * 0.50),
				c + Vector2(-s * 0.36, s * 0.50),
			])
			tgt.draw_colored_polygon(bowl, ink)
			tgt.draw_line(c + Vector2(0, -s * 0.74),
				c + Vector2(0, s * 0.42), ink.darkened(0.35), lw * 0.60, true)
			tgt.draw_line(c + Vector2(-s * 0.44, s * 0.03),
				c + Vector2(s * 0.44, s * 0.03), ink.darkened(0.35), lw * 0.60, true)
			tgt.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -s * 0.96), c + Vector2(s * 0.18, -s * 0.60),
				c + Vector2(0, -s * 0.70), c + Vector2(-s * 0.18, -s * 0.60),
			]), ink)
		"rest":
			# Fire over crossed logs.
			tgt.draw_line(c + Vector2(-s * 0.64, s * 0.56),
				c + Vector2(s * 0.58, s * 0.22), ink, lw, true)
			tgt.draw_line(c + Vector2(s * 0.64, s * 0.56),
				c + Vector2(-s * 0.58, s * 0.22), ink, lw, true)
			tgt.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -s * 0.78), c + Vector2(s * 0.44, -s * 0.05),
				c + Vector2(s * 0.20, s * 0.42), c + Vector2(0, s * 0.60),
				c + Vector2(-s * 0.22, s * 0.34), c + Vector2(-s * 0.38, -s * 0.08),
			]), ink)
			tgt.draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * 0.04, -s * 0.38), c + Vector2(s * 0.19, s * 0.04),
				c + Vector2(0, s * 0.34), c + Vector2(-s * 0.13, s * 0.04),
			]), ink.darkened(0.30))
		"shop":
			# Market awning + counter.
			var top := c + Vector2(0, -s * 0.42)
			tgt.draw_rect(Rect2(c + Vector2(-s * 0.60, -s * 0.10),
				Vector2(s * 1.20, s * 0.62)), ink, false, lw * 0.82)
			tgt.draw_line(c + Vector2(-s * 0.64, s * 0.22),
				c + Vector2(s * 0.64, s * 0.22), ink, lw * 0.82, true)
			for i in range(3):
				var x0 := -s * 0.60 + float(i) * s * 0.40
				var strip := PackedVector2Array([
					c + Vector2(x0, -s * 0.18), c + Vector2(x0 + s * 0.40, -s * 0.18),
					c + Vector2(x0 + s * 0.32, top.y - c.y),
					c + Vector2(x0 + s * 0.08, top.y - c.y),
				])
				tgt.draw_colored_polygon(strip, ink if i != 1 else ink.darkened(0.26))
			tgt.draw_circle(c + Vector2(0, s * 0.10), s * 0.12, ink)
		"treasure":
			# Chest with a crown of coins.
			var box := Rect2(c + Vector2(-s * 0.62, -s * 0.08),
				Vector2(s * 1.24, s * 0.66))
			tgt.draw_rect(box, ink, false, lw)
			tgt.draw_arc(c + Vector2(0, -s * 0.08), s * 0.62,
				PI, TAU, 18, ink, lw, true)
			tgt.draw_line(c + Vector2(0, -s * 0.58),
				c + Vector2(0, s * 0.58), ink, lw * 0.72, true)
			tgt.draw_rect(Rect2(c + Vector2(-s * 0.12, s * 0.08),
				Vector2(s * 0.24, s * 0.20)), ink)
			for dx in [-0.42, 0.0, 0.42]:
				tgt.draw_circle(c + Vector2(s * dx, -s * 0.66), s * 0.12, ink)


## A "draft a card" glyph for recruit stops — a small fan of two cards with a
## "+" on the front, dark-outlined so it reads at node size. Far clearer than
## a flag for a free draft. c = centre, s = half-extent, ink = bright fill.
func _draw_card_glyph(tgt: CanvasItem, c: Vector2, s: float, ink: Color) -> void:
	var oc := Color(0.05, 0.04, 0.03, 0.92)
	var hw := s * 0.52
	var hh := s * 0.78
	var ow := 2.0
	# Back card (offset up-right, dimmer) then the front card (offset down-left).
	var b := c + Vector2(s * 0.26, -s * 0.20)
	tgt.draw_rect(Rect2(b - Vector2(hw + ow, hh + ow),
		Vector2((hw + ow) * 2.0, (hh + ow) * 2.0)), oc)
	tgt.draw_rect(Rect2(b - Vector2(hw, hh), Vector2(hw * 2.0, hh * 2.0)),
		(ink as Color).darkened(0.26))
	var f := c + Vector2(-s * 0.12, s * 0.12)
	tgt.draw_rect(Rect2(f - Vector2(hw + ow, hh + ow),
		Vector2((hw + ow) * 2.0, (hh + ow) * 2.0)), oc)
	tgt.draw_rect(Rect2(f - Vector2(hw, hh), Vector2(hw * 2.0, hh * 2.0)), ink)
	# "+" on the front card = gain.
	var pl := s * 0.28
	var pw: float = maxf(2.2, s * 0.20)
	tgt.draw_line(f + Vector2(-pl, 0), f + Vector2(pl, 0), oc, pw, true)
	tgt.draw_line(f + Vector2(0, -pl), f + Vector2(0, pl), oc, pw, true)


## An open-book glyph for event stops — "a story happens here". Two pages
## meeting at a spine, dark-outlined with a few text lines; bolder and clearer
## at node size than the busy scroll silhouette. c centre, s half-extent.
func _draw_event_glyph(tgt: CanvasItem, c: Vector2, s: float, ink: Color) -> void:
	# A bold "?" — the genre signal every deckbuilder player already reads as
	# "unknown story here". The old open-book silhouette smeared into a blob
	# at node size; a single fat font glyph stays crisp. Dark outline first
	# so the shape pops on any enamel, same contract as the sticker icons.
	if GameTheme.font_display == null:
		return
	var fsz := int(round(s * 2.5))
	var sw := GameTheme.font_display.get_string_size(
		"?", HORIZONTAL_ALIGNMENT_CENTER, -1, fsz)
	var pos := c + Vector2(-sw.x * 0.5, sw.y * 0.34)
	tgt.draw_string_outline(GameTheme.font_display, pos, "?",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, int(maxf(3.0, s * 0.30)),
		Color(0.05, 0.04, 0.03, 0.92))
	tgt.draw_string(GameTheme.font_display, pos, "?",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, ink)


## The conquest, visible as light: every claimed stop (and the landing camp)
## holds a soft pool of your amber on the parchment, so the marched road
## reads as country brought into the lamplight — territory without a single
## political border. Ink-layer (per open): it follows the run, not the act.
func _draw_claimed_glow(tgt: CanvasItem) -> void:
	var pts: Array[Vector2] = [_camp_pos]
	for nd in _nodes:
		if bool(nd.vis):
			pts.append(nd.pos as Vector2)
	for p in pts:
		tgt.draw_circle(p, 64.0, Color(PLAYER_AMBER.r, PLAYER_AMBER.g,
			PLAYER_AMBER.b, 0.045))
		tgt.draw_circle(p, 36.0, Color(PLAYER_AMBER.r, PLAYER_AMBER.g,
			PLAYER_AMBER.b, 0.055))


## Quiet chart furniture for the war-table mode — a compass rose and a tiny
## fleet mark in the south-east sea (guaranteed open water: the coast hull
## can never reach past the last row's SE diagonal). Enough to say "chart",
## never enough to fight the campaign.
func _draw_simple_furniture(tgt: CanvasItem) -> void:
	var cp := Vector2(size.x * 0.945, size.y * 0.735)
	var fcol := Color(0.36, 0.28, 0.185, 0.55)
	tgt.draw_arc(cp, 24.0, 0, TAU, 40, fcol, 1.4, true)
	tgt.draw_arc(cp, 18.5, 0, TAU, 40,
		Color(fcol.r, fcol.g, fcol.b, 0.30), 1.0, true)
	for k in range(8):
		var ang := TAU * float(k) / 8.0
		var lng: float = 22.0 if k % 2 == 0 else 11.0
		tgt.draw_line(cp, cp + Vector2(cos(ang), sin(ang)) * lng,
			Color(fcol.r, fcol.g, fcol.b, 0.58 if k % 2 == 0 else 0.32),
			1.5 if k % 2 == 0 else 1.0, true)
	tgt.draw_colored_polygon(PackedVector2Array([cp + Vector2(0, -24),
		cp + Vector2(3.6, -7), cp + Vector2(-3.6, -7)]),
		Color(0.55, 0.20, 0.12, 0.70))
	if GameTheme.font_display != null:
		tgt.draw_string(GameTheme.font_display, cp + Vector2(-7, -29), "N",
			HORIZONTAL_ALIGNMENT_CENTER, 14, 12,
			Color(0.36, 0.28, 0.185, 0.70))
	# The landing fleet — two little inked sails riding the graticule.
	var scol := Color(0.36, 0.28, 0.185, 0.60)
	for sd in [[Vector2(size.x * 0.912, size.y * 0.880), 1.0],
			[Vector2(size.x * 0.958, size.y * 0.905), 0.78]]:
		var sp2: Vector2 = sd[0]
		var sc: float = sd[1]
		tgt.draw_arc(sp2, 9.0 * sc, 0.25, PI - 0.25, 12, scol, 1.6 * sc, true)
		tgt.draw_line(sp2 + Vector2(0, 2.0 * sc), sp2 + Vector2(0, -11.0 * sc),
			scol, 1.3 * sc, true)
		tgt.draw_colored_polygon(PackedVector2Array([
			sp2 + Vector2(0.8 * sc, -11.0 * sc),
			sp2 + Vector2(7.5 * sc, -2.5 * sc),
			sp2 + Vector2(0.8 * sc, -2.5 * sc)]),
			Color(scol.r, scol.g, scol.b, 0.42))


func _draw_etna(tgt: CanvasItem) -> void:
	# The volcano — the act's villain rendered as geography. A cone with lit
	# and shadowed faces, a glowing caldera, lava threads, and a smoke plume
	# drifting north-east on the strait wind. Sized to LOOM — it is the
	# campaign's destination and the largest landform on the chart.
	var apex := _etna_peak + Vector2(0, -42.0)
	var bw := 112.0
	var bh := 98.0
	var bl := _etna_peak + Vector2(-bw, bh * 0.52)
	var br_ := _etna_peak + Vector2(bw, bh * 0.58)
	# Ash skirt — scorched ground fanning out from the foot, so the mountain
	# grows out of burnt country instead of standing on clean parchment.
	# Many faint steps: three strong discs printed as concentric rings.
	for ai in range(7):
		var ar := lerpf(86.0, 22.0, float(ai) / 6.0)
		tgt.draw_circle(_etna_peak + Vector2(4.0, bh * 0.52), ar,
			Color(0.16, 0.10, 0.07, 0.032))
	var ink := Color(0.09, 0.065, 0.045, 0.92)
	# Concave flanks — a volcano's slope eases out at the foot and steepens
	# to the crater; the straight twin-triangle silhouette was the loudest
	# "programmer art" tell on the plate. Both flanks sampled off the same
	# power curve so the profile reads as one drawn line.
	var prof := PackedVector2Array()
	var steps := 8
	for si in range(steps + 1):
		var t := float(si) / float(steps)
		prof.append(Vector2(apex.x - pow(1.0 - t, 1.42) * bw,
			lerpf(bl.y, apex.y, t)))
	for si2 in range(1, steps + 1):
		var t2 := float(si2) / float(steps)
		prof.append(Vector2(apex.x + pow(t2, 1.42) * bw,
			lerpf(apex.y, br_.y, t2)))
	# Cast shadow (SE, matching the medallions), then the lit body.
	var shadow := PackedVector2Array()
	for v in prof:
		shadow.append(v + Vector2(6.0, 7.0))
	tgt.draw_colored_polygon(shadow, Color(0, 0, 0, 0.20))
	tgt.draw_colored_polygon(prof, Color(0.295, 0.225, 0.175))
	# Shadow face: the east half, split down from the crater to a point ON
	# the base chord (a free-floating split vertex poked below the outline).
	var base_mid := bl.lerp(br_, 0.55)
	var east := PackedVector2Array()
	east.append(apex)
	for si3 in range(1, steps + 1):
		var t3 := float(si3) / float(steps)
		east.append(Vector2(apex.x + pow(t3, 1.42) * bw,
			lerpf(apex.y, br_.y, t3)))
	east.append(base_mid)
	tgt.draw_colored_polygon(east, Color(0.165, 0.120, 0.098))
	# Engraved hatching down the shadow face — the chart's relief language.
	for hk in range(4):
		var ht := 0.22 + 0.19 * float(hk)
		var top := Vector2(apex.x + pow(ht, 1.42) * bw * 0.30,
			lerpf(apex.y, br_.y, ht) + 4.0)
		var bot := Vector2(apex.x + pow(minf(ht + 0.30, 1.0), 1.42) * bw * 0.92,
			lerpf(apex.y, br_.y, minf(ht + 0.34, 1.0)))
		tgt.draw_line(top, bot, Color(ink.r, ink.g, ink.b, 0.45), 1.2, true)
	# Ink outline over everything — the one line weight that makes the
	# landform sit in the same engraving as the coast and the medallions.
	var outline := prof.duplicate()
	outline.append(prof[0])
	tgt.draw_polyline(outline, ink, 2.2, true)
	# Foot contours easing the cone into the land.
	for fc in [[bw * 0.66, 0.30], [bw * 0.84, 0.18]]:
		tgt.draw_arc(_etna_peak + Vector2(4.0, bh * 0.54), float(fc[0]),
			PI + 0.5, TAU - 0.5, 20,
			Color(ink.r, ink.g, ink.b, float(fc[1])), 1.1, true)
	# Caldera: dark crater mouth ringed in ink, ember glow stacked soft.
	tgt.draw_circle(apex + Vector2(0, 3), 26.0, Color(1.0, 0.42, 0.10, 0.10))
	tgt.draw_circle(apex + Vector2(0, 2), 15.0, Color(1.0, 0.45, 0.12, 0.22))
	tgt.draw_circle(apex, 6.5, Color(0.07, 0.04, 0.03))
	tgt.draw_arc(apex, 6.5, 0, TAU, 20, ink, 1.4, true)
	tgt.draw_circle(apex, 4.0, Color(1.0, 0.52, 0.14, 0.95))
	# Lava threads in the route ink's casing convention: dark under, bright
	# over — the same stroke grammar as the campaign dashes.
	var lrng := RandomNumberGenerator.new()
	lrng.seed = 666
	for k in range(4):
		var dirx := lrng.randf_range(-0.8, 0.9)
		var run := PackedVector2Array()
		var lp := apex + Vector2(dirx * 6.0, 2.0)
		run.append(lp)
		for _st in range(4):
			lp += Vector2(dirx * lrng.randf_range(4.0, 9.0),
				lrng.randf_range(7.0, 12.0))
			run.append(lp)
		var la := 0.80 - float(k) * 0.12
		tgt.draw_polyline(run, Color(0.06, 0.03, 0.02, la * 0.8), 2.8, true)
		tgt.draw_polyline(run, Color(0.98, 0.40, 0.11, la), 1.4, true)
	# Smoke: outlined puffs drifting NE — drawn objects, not soft sprites.
	var puffs := [[10.0, -18.0, 6.0, 0.50], [22.0, -34.0, 9.0, 0.42],
		[37.0, -52.0, 12.5, 0.32], [55.0, -71.0, 16.5, 0.20]]
	for pf in puffs:
		var pc := apex + Vector2(float(pf[0]), float(pf[1]))
		var pr := float(pf[2])
		var pa := float(pf[3])
		tgt.draw_circle(pc, pr, Color(0.62, 0.58, 0.55, pa))
		tgt.draw_arc(pc, pr, PI * 0.55, PI * 2.35, 18,
			Color(ink.r, ink.g, ink.b, pa * 0.55), 1.2, true)


func _draw_keep(tgt: CanvasItem) -> void:
	var kp := _boss_pos if _boss_pos != Vector2.ZERO \
		else Vector2(size.x - MARGIN_R, size.y * 0.5)
	# Smaller than the procedural version — Etna looms behind it; the keep
	# is the gate, the mountain is the threat.
	var kw := 70.0
	var kh := 44.0
	var base_y := kp.y + kh * 0.5
	# Kit materials: lit stone / shaded stone / the engraving ink — the keep
	# is drawn with the same light and line as the medallions (its old flat
	# near-black rectangles sat a fidelity tier below them).
	var lit := Color(0.335, 0.290, 0.245)
	var shade := Color(0.200, 0.165, 0.140)
	var ink := Color(0.08, 0.06, 0.045)
	tgt.draw_circle(kp + Vector2(5, kh * 0.55), kw * 0.60, Color(0, 0, 0, 0.20))
	tgt.draw_circle(kp + Vector2(3, kh * 0.5), kw * 0.52, Color(0, 0, 0, 0.22))
	# Central tower first (tallest, behind the wall), then the flankers.
	for tdef in [[0.0, 1.45, 22.0], [-0.42, 0.92, 19.0], [0.42, 0.92, 19.0]]:
		var toff: float = tdef[0]
		var th: float = kh * float(tdef[1])
		var tw: float = tdef[2]
		var tower := Rect2(kp.x + kw * toff - tw * 0.5, base_y - th, tw, th)
		tgt.draw_rect(tower, lit)
		tgt.draw_rect(Rect2(tower.position.x + tower.size.x * 0.55,
			tower.position.y, tower.size.x * 0.45, tower.size.y), shade)
		# Tower cap crenellations.
		for ck in range(3):
			tgt.draw_rect(Rect2(tower.position.x + 1.0
				+ float(ck) * (tw - 2.0) / 3.0, tower.position.y - 5.0,
				(tw - 2.0) / 3.0 * 0.58, 5.0), lit if ck < 2 else shade)
		tgt.draw_rect(tower, ink, false, 1.8)
		# Arrow slit.
		tgt.draw_rect(Rect2(tower.position.x + tw * 0.42,
			tower.position.y + th * 0.30, 2.4, 7.0), ink)
	# Curtain wall in front, lit face west and shaded return east.
	var wall := Rect2(kp.x - kw * 0.5, base_y - kh * 0.62, kw, kh * 0.62)
	tgt.draw_rect(wall, lit)
	tgt.draw_rect(Rect2(wall.position.x + wall.size.x * 0.60, wall.position.y,
		wall.size.x * 0.40, wall.size.y), shade)
	var teeth := 6
	for i in range(teeth):
		var tx := wall.position.x + wall.size.x * float(i) / float(teeth)
		tgt.draw_rect(Rect2(tx, wall.position.y - 5.0,
			wall.size.x / float(teeth) * 0.55, 5.0),
			lit if i < 4 else shade)
	tgt.draw_rect(wall, ink, false, 2.0)
	tgt.draw_line(wall.position + Vector2(0, -5.0),
		wall.position + Vector2(wall.size.x, -5.0),
		Color(ink.r, ink.g, ink.b, 0.55), 1.0, true)
	# The gate — a barred arch dead centre; this is the door the campaign
	# marches to, so the keep should visibly HAVE one.
	var gx := kp.x
	var gw := 12.0
	var gb := base_y
	tgt.draw_rect(Rect2(gx - gw * 0.5, gb - 14.0, gw, 14.0),
		Color(0.055, 0.04, 0.03))
	tgt.draw_arc(Vector2(gx, gb - 14.0), gw * 0.5, PI, TAU, 12,
		Color(0.055, 0.04, 0.03), 4.5, false)
	tgt.draw_line(Vector2(gx, gb - 12.0), Vector2(gx, gb - 2.0),
		Color(0.30, 0.24, 0.16, 0.8), 1.2, true)
	# The pennant over the keep flies the rival lord's banner — the one spot
	# on the plate where his color shows at full cloth strength (the political
	# wash below is the same dye thinned). Crimson on legacy runs.
	var banner := _banner_color()
	var pole_top := Vector2(kp.x, base_y - kh * 1.45 - 26.0)
	tgt.draw_line(Vector2(kp.x, base_y - kh * 1.45), pole_top, ink, 2.0, true)
	tgt.draw_circle(pole_top, 1.6, Color(0.92, 0.78, 0.42))
	var flag := PackedVector2Array([pole_top,
		pole_top + Vector2(30, 3.5), pole_top + Vector2(20, 8.5),
		pole_top + Vector2(30, 13.5), pole_top + Vector2(0, 15)])
	tgt.draw_colored_polygon(flag, banner)
	var fol := flag.duplicate()
	fol.append(flag[0])
	tgt.draw_polyline(fol, Color(ink.r, ink.g, ink.b, 0.85), 1.2, true)
	tgt.draw_circle(Vector2(kp.x - kw * 0.34, base_y - 4.0), 3.2,
		Color(1.0, 0.55, 0.20, 0.85))
	if _boss_name != "" and GameTheme.font_display != null:
		# Each act's keep is a place before it is a fight: name the seat,
		# then the holder. Common-noun names only (lore rule), one per leg —
		# the passes, the grain country, the lava country.
		var keep_names := ["THE PASS GATE", "THE GRANARY KEEP",
			"THE CINDER SEAT"]
		# Plaque 17px lines; anchored slightly RIGHT of the keep so the rest-row
		# stops (which approach from the west) never land under it — but no
		# further east than the map's OPEN view can show. Both bounds are
		# tight: the row-10 chips reach x ≈ .743·w + jitter8 + r23, and at the
		# open zoom (1.10, MapView) the screen cuts the plate at size.x/1.10.
		var plaque := Rect2(kp.x - 54.0, base_y + 16.0, 224.0, 44.0)
		tgt.draw_rect(plaque, Color(0.05, 0.04, 0.035, 0.88))
		tgt.draw_rect(plaque, Color(banner.r, banner.g, banner.b, 0.85),
			false, 1.5)
		var keep_lbl: String = keep_names[clampi(_act - 1, 0, 2)]
		tgt.draw_string_outline(GameTheme.font_display,
			Vector2(plaque.position.x, base_y + 33.0), keep_lbl,
			HORIZONTAL_ALIGNMENT_CENTER, plaque.size.x, 17, 5,
			Color(0, 0, 0, 0.9))
		tgt.draw_string(GameTheme.font_display,
			Vector2(plaque.position.x, base_y + 33.0), keep_lbl,
			HORIZONTAL_ALIGNMENT_CENTER, plaque.size.x, 17,
			Color(0.83, 0.74, 0.58, 1.0))
		tgt.draw_string_outline(GameTheme.font_display,
			Vector2(plaque.position.x, base_y + 54.0), _boss_name,
			HORIZONTAL_ALIGNMENT_CENTER, plaque.size.x, 17, 5,
			Color(0, 0, 0, 0.9))
		tgt.draw_string(GameTheme.font_display,
			Vector2(plaque.position.x, base_y + 54.0), _boss_name,
			HORIZONTAL_ALIGNMENT_CENTER, plaque.size.x, 17,
			Color(0.95, 0.84, 0.66))


func _draw_camp(tgt: CanvasItem) -> void:
	# The landing camp: a main tent flanked by a smaller one and a cookfire —
	# a place the army lives in, not a bare survey triangle.
	var camp := _camp_pos
	var canvas_c := Color(0.38, 0.31, 0.21, 0.96)
	var ink := Color(0.05, 0.04, 0.03)
	# Ground shadow.
	tgt.draw_circle(camp + Vector2(2, 9), 20.0, Color(0, 0, 0, 0.14))
	# Main tent (lit face west, shaded face east — the plate's NW light).
	var apex := camp + Vector2(0, -15)
	tgt.draw_colored_polygon(PackedVector2Array([apex,
		camp + Vector2(-16, 10), camp + Vector2(2, 10)]), canvas_c)
	tgt.draw_colored_polygon(PackedVector2Array([apex,
		camp + Vector2(2, 10), camp + Vector2(16, 10)]),
		canvas_c.darkened(0.30))
	tgt.draw_polyline(PackedVector2Array([camp + Vector2(-16, 10), apex,
		camp + Vector2(16, 10), camp + Vector2(-16, 10)]), ink, 1.6, true)
	tgt.draw_line(apex, camp + Vector2(2, 10), ink, 1.0, true)
	# Door flap.
	tgt.draw_colored_polygon(PackedVector2Array([camp + Vector2(-4, 10),
		camp + Vector2(0, -1), camp + Vector2(4, 10)]),
		Color(0.10, 0.075, 0.05, 0.9))
	# Small tent behind-left.
	var s_apex := camp + Vector2(-22, -2)
	tgt.draw_colored_polygon(PackedVector2Array([s_apex,
		camp + Vector2(-31, 9), camp + Vector2(-13, 9)]),
		canvas_c.darkened(0.14))
	tgt.draw_polyline(PackedVector2Array([camp + Vector2(-31, 9), s_apex,
		camp + Vector2(-13, 9), camp + Vector2(-31, 9)]), ink, 1.3, true)
	# Cookfire east of the door — a warm ember the pulse overlay echoes.
	var fp := camp + Vector2(14, 3)
	tgt.draw_circle(fp, 5.0, Color(1.0, 0.55, 0.18, 0.22))
	tgt.draw_circle(fp, 2.2, Color(1.0, 0.62, 0.22, 0.85))
	tgt.draw_line(fp + Vector2(-3.4, 2.6), fp + Vector2(3.4, 1.4), ink, 1.2, true)
	tgt.draw_line(fp + Vector2(-3.0, 1.2), fp + Vector2(3.0, 2.8), ink, 1.2, true)
	if GameTheme.font_display != null:
		tgt.draw_string_outline(GameTheme.font_display, camp + Vector2(-75, 35),
			"YOUR CAMP", HORIZONTAL_ALIGNMENT_CENTER, 150, 17, 5,
			Color(0, 0, 0, 0.9))
		tgt.draw_string(GameTheme.font_display, camp + Vector2(-75, 35),
			"YOUR CAMP", HORIZONTAL_ALIGNMENT_CENTER, 150, 17,
			Color(0.92, 0.84, 0.68))
	# "YOU ARE HERE" — a labelled static marker at the army's position, baked
	# into the plate so it shows under BOTH the live overlay standard and the
	# sandbox fallback. The swaying amber banner alone read like the conquered-
	# keep pennants (same amber flag, no label); this ground-ring + named plate
	# is the unambiguous "this is you" cue the clarity audit asked for.
	if _has_player and GameTheme.font_display != null:
		var you := _player_pos
		# Twin ground-ring at the foot — a surveyed "mark" the bare pennants
		# never wear, so the eye separates you from a planted conquest flag.
		tgt.draw_circle(you + Vector2(0, 6), 11.0, Color(0, 0, 0, 0.30))
		tgt.draw_arc(you + Vector2(0, 5), 10.0, 0, TAU, 28,
			Color(0.05, 0.04, 0.03, 0.92), 2.6, true)
		tgt.draw_arc(you + Vector2(0, 5), 10.0, 0, TAU, 28, PLAYER_AMBER,
			1.5, true)
		# Named plate just below the foot (clear of the staff + flag above).
		# Bigger plate + 17px outlined text + brighter rim: this is the core
		# "where am I" cue, and at 15px with no outline it was easy to lose.
		var pw := 152.0
		var plate := Rect2(you.x - pw * 0.5, you.y + 16.0, pw, 27.0)
		tgt.draw_rect(plate, Color(0.05, 0.04, 0.03, 0.90))
		tgt.draw_rect(plate, Color(PLAYER_AMBER.r, PLAYER_AMBER.g,
			PLAYER_AMBER.b, 0.80), false, 1.5)
		tgt.draw_string_outline(GameTheme.font_display, Vector2(plate.position.x,
			plate.position.y + 19.0), "YOU ARE HERE",
			HORIZONTAL_ALIGNMENT_CENTER, pw, 17, 5, Color(0, 0, 0, 0.9))
		tgt.draw_string(GameTheme.font_display, Vector2(plate.position.x,
			plate.position.y + 19.0), "YOU ARE HERE",
			HORIZONTAL_ALIGNMENT_CENTER, pw, 17, Color(0.98, 0.89, 0.68))
	# The army standard at the player's position is normally drawn (and
	# animated) by MapView's pulse overlay; this static fallback keeps the
	# render-only sandbox (map_proto.tscn) showing a complete picture.
	if overlay_handles_standard:
		return
	var stand_p := _player_pos if _has_player else camp + Vector2(30, -4)
	tgt.draw_line(stand_p + Vector2(0, 4), stand_p + Vector2(0, -28),
		Color(0.05, 0.04, 0.03), 2.2, true)
	tgt.draw_colored_polygon(PackedVector2Array([stand_p + Vector2(0, -28),
		stand_p + Vector2(22, -22), stand_p + Vector2(0, -16)]), PLAYER_AMBER)


func _draw_ui() -> void:
	var w: float = size.x
	var h: float = size.y
	var title_font: Font = GameTheme.font_title \
		if GameTheme.font_title != null else GameTheme.font_display
	if title_font == null:
		return
	# Lamplight vignette — a LIVE full-rect radial falling to dark at the
	# corners (the bake path flattens alpha; the live path composites fine).
	# This is the Inscryption move: the table is lit by one lamp, and the
	# screen's value structure is designed around it. Drawn under the HUD
	# bands, over the plate + paper layers.
	if _vignette_tex == null:
		var vgrad := Gradient.new()
		vgrad.set_color(0, Color(0, 0, 0, 0.0))
		vgrad.set_color(1, Color(0, 0, 0, 0.30))
		vgrad.add_point(0.62, Color(0, 0, 0, 0.0))
		_vignette_tex = GradientTexture2D.new()
		_vignette_tex.gradient = vgrad
		_vignette_tex.width = 512
		_vignette_tex.height = 288
		_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
		_vignette_tex.fill_from = Vector2(0.5, 0.47)
		_vignette_tex.fill_to = Vector2(1.04, 0.47)
	draw_texture_rect(_vignette_tex, Rect2(Vector2.ZERO, size), false)
	var numerals := ["I", "II", "III"]
	var act_n: String = numerals[clampi(RunState.get_act() - 1, 0, 2)]
	if GameTheme.font_display == null:
		return
	# THE TITLE CARTOUCHE — docked in the NW sea corner, the way real charts
	# set their title box IN the water, not floated over the geography. The
	# old top-center stack (title band + sub-line + MapView's standing-order
	# chip + tally = four lines of floating text) pushed the top lane down
	# and read as clutter; one left-aligned corner panel now carries all of
	# it: act title, march line, and the standing order + province tally as
	# a single line. MapView's separate gate chip is retired.
	# The march label ("THE FIRST MARCH") duplicates the act line above it, so
	# when a rival faction is named the enemy IS the informative sub-line — drop
	# the redundant march prefix and just name who the army marches against.
	var marches := ["THE FIRST MARCH", "THE SECOND MARCH", "THE LAST MARCH"]
	var sub: String
	if _faction_name != "":
		sub = "AGAINST " + _faction_name
	else:
		sub = marches[clampi(RunState.get_act() - 1, 0, 2)]
	var sub_col := Color(0.92, 0.80, 0.58, 1.0)
	if _faction_name != "":
		var bn := _banner_color()
		sub_col = Color(bn.r, bn.g, bn.b, 1.0).lerp(sub_col, 0.40)
	# Standing order + tally, one line, urgency-tinted like the old chip.
	var holds_left: int = maxi(
		RunState.HOLDS_TO_OPEN_LORD - RunState.holds_broken_in_act, 0)
	var owned := 0
	for nd0 in _nodes:
		if bool(nd0.vis):
			owned += 1
	var order_txt: String
	var order_col: Color
	if RunState.is_lord_gate_open():
		order_txt = "The keep road is open — march on the lord"
		order_col = Color(0.96, 0.84, 0.46)
	else:
		order_txt = "Break %d more %s to open the keep road" % [holds_left,
			"hold" if holds_left == 1 else "holds"]
		order_col = Color(0.92, 0.55, 0.42)
	order_txt += "  ·  %d / %d provinces" % [owned, _nodes.size()]
	var title_txt := "ACT %s  ·  THE BURNING ISLE" % act_n
	var title_sz := 22
	var sub_sz := 13
	var order_sz := 15
	var sub_txt := _letterspace(sub)
	if GameTheme.font_display.get_string_size(sub_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sub_sz).x > 452.0:
		sub_txt = sub   # longest kingdom names drop the letterspacing
	var line_ws := [
		title_font.get_string_size(title_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, title_sz).x,
		GameTheme.font_display.get_string_size(sub_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sub_sz).x,
		GameTheme.font_display.get_string_size(order_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, order_sz).x]
	var inner_w := 0.0
	for lw in line_ws:
		inner_w = maxf(inner_w, float(lw))
	# x=118 docks the cartouche to the same left rail as MapView's resource
	# band above it (one aligned column in the corner); y=73 leaves the same
	# 8px breath under the band (bottom y=65) that spaces the row's elements.
	var band := Rect2(118.0, 73.0, clampf(inner_w + 32.0, 300.0, 520.0), 96.0)
	draw_rect(band, Color(0.045, 0.04, 0.035, 0.86))
	draw_rect(band, Color(PLAYER_AMBER.r, PLAYER_AMBER.g, PLAYER_AMBER.b,
		0.55), false, 1.5)
	draw_rect(band.grow(-4.0), Color(PLAYER_AMBER.r, PLAYER_AMBER.g,
		PLAYER_AMBER.b, 0.22), false, 1.0)
	var tx := band.position.x + 16.0
	draw_string(title_font, Vector2(tx, band.position.y + 30), title_txt,
		HORIZONTAL_ALIGNMENT_LEFT, band.size.x - 32.0, title_sz,
		Color(0.90, 0.80, 0.60))
	draw_string(GameTheme.font_display, Vector2(tx, band.position.y + 51),
		sub_txt, HORIZONTAL_ALIGNMENT_LEFT, band.size.x - 32.0, sub_sz, sub_col)
	# Hairline rule between the title block and the standing order.
	draw_line(Vector2(tx, band.position.y + 63),
		Vector2(band.position.x + band.size.x - 16.0, band.position.y + 63),
		Color(0.60, 0.51, 0.34, 0.40), 1.0, true)
	draw_string(GameTheme.font_display, Vector2(tx, band.position.y + 84),
		order_txt, HORIZONTAL_ALIGNMENT_LEFT, band.size.x - 32.0, order_sz,
		order_col)
	# The bottom legend band is GONE (2026-07-07): every unstruck token now
	# prints its own engraved name (SITE_LABEL in _draw_sites), hover carries
	# the deep intel, and the full key lives behind the "?" primer. One less
	# HUD band competing with the chart.


## "THE FIRST MARCH" → "T H E   F I R S T   M A R C H" — the chart's
## letterspaced small-caps convention for campaign furniture (one space
## between letters, three between words, same as the hand-set labels).
func _letterspace(s: String) -> String:
	var out := ""
	for i in range(s.length()):
		var ch := s[i]
		out += ch
		if ch == " ":
			out += " "
		elif i < s.length() - 1:
			out += " "
	return out


func _draw_star(tgt: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	tgt.draw_circle(c, r + 2.0, Color(0, 0, 0, 0.55))
	var pts := PackedVector2Array()
	for k in range(10):
		var ang := -PI / 2.0 + TAU * float(k) / 10.0
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	tgt.draw_colored_polygon(pts, col)


func _node_icon(typ: String) -> Texture2D:
	match typ:
		"combat": return GameTheme.tex_node_combat
		"elite": return GameTheme.tex_node_elite
		"rest": return GameTheme.tex_node_rest
		"shop": return GameTheme.tex_node_shop
		"event": return GameTheme.tex_node_event
		"boss": return GameTheme.tex_node_boss
		"treasure": return GameTheme.tex_node_treasure
		"recruit": return GameTheme.tex_node_recruit
		"wayside": return GameTheme.tex_node_wayside
	return null


## Per-verb wayside glyph, ink-drawn straight into the chart so the four
## roadside halts read as four DIFFERENT stops at chart zoom (the shared
## horned-helm SVG made Drill Yard / Scales / Standard-Bearer / Supply Cache
## pixel-identical, breaking route-planning). Same hand-inked vocabulary as
## the camp/keep/star furniture — `c` is the chip centre, `s` the half-extent
## (~ the icon's reach from centre), `ink` the chip's glyph colour. Returns
## true when it drew a known verb, so callers fall back to the SVG otherwise.
func _draw_wayside_glyph(tgt: CanvasItem, c: Vector2, s: float,
		ink: Color, wayside_id: String) -> bool:
	var lw := maxf(1.3, s * 0.16)   # stroke scales with the chip
	match wayside_id:
		"drill_yard":
			# Anvil — the drill yard where creatures are trained harder.
			var top_l := c + Vector2(-s * 0.78, -s * 0.30)
			var top_r := c + Vector2(s * 0.62, -s * 0.30)
			var face := PackedVector2Array([
				top_l, top_r,
				c + Vector2(s * 0.40, -s * 0.04),
				c + Vector2(-s * 0.46, -s * 0.04)])
			tgt.draw_colored_polygon(face, ink)
			# Horn — the pointed beak off the left of the face.
			tgt.draw_colored_polygon(PackedVector2Array([
				top_l, c + Vector2(-s * 0.96, -s * 0.18),
				c + Vector2(-s * 0.46, -s * 0.04)]), ink)
			# Waist + splayed base.
			tgt.draw_line(c + Vector2(-s * 0.16, -s * 0.04),
				c + Vector2(-s * 0.24, s * 0.40), ink, lw, true)
			tgt.draw_line(c + Vector2(s * 0.10, -s * 0.04),
				c + Vector2(s * 0.18, s * 0.40), ink, lw, true)
			tgt.draw_line(c + Vector2(-s * 0.50, s * 0.46),
				c + Vector2(s * 0.46, s * 0.46), ink, lw * 1.4, true)
			return true
		"muster_scale":
			# Balance scales — the quartermaster's one weighed trade.
			tgt.draw_line(c + Vector2(0, -s * 0.74), c + Vector2(0, s * 0.50),
				ink, lw, true)               # central post
			tgt.draw_line(c + Vector2(-s * 0.30, s * 0.62),
				c + Vector2(s * 0.30, s * 0.62), ink, lw, true)  # foot
			tgt.draw_circle(c + Vector2(0, -s * 0.74), lw * 0.9, ink)
			var beam_l := c + Vector2(-s * 0.66, -s * 0.58)
			var beam_r := c + Vector2(s * 0.66, -s * 0.58)
			tgt.draw_line(beam_l, beam_r, ink, lw, true)        # beam
			# Two hanging pans (open shallow bowls on cords).
			for bx in [beam_l, beam_r]:
				tgt.draw_line(bx, bx + Vector2(0, s * 0.30), ink, lw * 0.8, true)
				tgt.draw_arc(bx + Vector2(0, s * 0.30), s * 0.26,
					0.0, PI, 14, ink, lw, true)
			return true
		"standard_bearer":
			# A pennant on a staff — the banner the standard-bearer re-pins.
			# Inked (not amber) so it never reads as the live army standard.
			var pole_top := c + Vector2(-s * 0.34, -s * 0.78)
			tgt.draw_line(pole_top, c + Vector2(-s * 0.34, s * 0.74),
				ink, lw, true)
			tgt.draw_circle(pole_top, lw * 0.9, ink)
			# Swallowtail flag flying off the staff.
			tgt.draw_colored_polygon(PackedVector2Array([
				pole_top,
				c + Vector2(s * 0.74, -s * 0.58),
				c + Vector2(s * 0.40, -s * 0.34),
				c + Vector2(s * 0.74, -s * 0.10),
				c + Vector2(-s * 0.34, -s * 0.10)]), ink)
			return true
		"supply_cache":
			# A banded chest — the cache cracked open for spoils.
			var box := Rect2(c + Vector2(-s * 0.66, -s * 0.30),
				Vector2(s * 1.32, s * 0.78))
			tgt.draw_rect(box, ink, false, lw)
			# Domed lid as a capped arc across the top.
			tgt.draw_arc(c + Vector2(0, -s * 0.30), s * 0.66,
				PI, TAU, 18, ink, lw, true)
			tgt.draw_line(c + Vector2(-s * 0.66, -s * 0.30),
				c + Vector2(s * 0.66, -s * 0.30), ink, lw, true)
			# Centre band + clasp.
			tgt.draw_line(c + Vector2(0, -s * 0.78),
				c + Vector2(0, s * 0.48), ink, lw, true)
			tgt.draw_rect(Rect2(c + Vector2(-s * 0.12, -s * 0.16),
				Vector2(s * 0.24, s * 0.22)), ink)
			return true
	return false
